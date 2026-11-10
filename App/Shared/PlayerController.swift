import Foundation
#if os(macOS)
import AppKit
#endif
import VLCKitSPM
#if canImport(TVVLCKit)
import TVVLCKit
#elseif canImport(MobileVLCKit)
import MobileVLCKit
#elseif canImport(VLCKit)
import VLCKit
#endif
import FritzTVKit

struct PlaybackOptions: Equatable {
    var networkCachingMs: Int
    var rtspTCP: Bool
    var deinterlace: Bool
    /// Nur macOS: SD-Bild vor dem Hochskalieren nachschärfen (VLC-Filter `sharpen`).
    var sharpenSD: Bool
    var audioDelayMs: Int
    var audioDelayAC3Ms: Int
    var timeshift: Bool
    /// Pufferlänge für Timeshift in Minuten.
    var timeshiftMinutes: Int
}

enum PlayerStatus: Equatable {
    case idle
    case connecting
    case playing
    case paused
    case reconnecting(seconds: Int)
    case failed(title: String, message: String, hint: String?)

    var isTransitioning: Bool {
        switch self {
        case .connecting, .reconnecting, .idle:
            return true
        case .playing, .paused, .failed:
            return false
        }
    }
}

/// Kapselt VLCKit: Abspielen eines RTSP-Streams der FRITZ!Box, Timeshift,
/// automatisches Neuverbinden, Ton- und Untertitelspuren, „Läuft jetzt“ aus der EIT.
///
/// Statt der VLC-Delegate-Methoden wird der Zustand zweimal pro Sekunde abgefragt.
/// Das ist robuster gegenüber Unterschieden zwischen den VLCKit-Versionen.
@MainActor
final class PlayerController: ObservableObject {
    /// libVLC-Bibliothek mit Optionen zur Unterdrückung störender OSD-Einblendungen
    /// (z. B. Miniatur-Vorschau und Dateipfad bei Screenshots für das macOS-Dock-Icon).
    private static let vlcLibrary = VLCLibrary(options: [
        "--no-snapshot-preview",
        "--no-osd"
    ])

    /// Stärke des Nachschärfens (VLC-Standard 0,05, Bereich 0–2). Wirkt auf das 576er-Bild vor dem
    /// Hochskalieren, deshalb zurückhaltend gewählt, damit MPEG-2-Blockartefakte nicht hervortreten.
    private static let sharpenSigma = "0.1"

    /// SD-Sender senden 576i. `yadif2x` erzeugt aus jedem Halbbild ein Vollbild (50 statt 25 Bilder
    /// pro Sekunde); das erhält die Bewegungsauflösung und passt zur 50-Hz-Ausgabe auf dem Apple TV.
    private static func deinterlaceFilter(options: PlaybackOptions, isSD: Bool) -> String? {
        options.deinterlace && isSD ? "yadif2x" : nil
    }

    /// Bildfilter je Medium. `sharpen` ist nur in VLCKit für macOS enthalten, nicht in TVVLCKit.
    private static func addPictureOptions(to media: VLCMedia, options: PlaybackOptions, isSD: Bool) {
        #if os(macOS)
        if options.sharpenSD && isSD {
            media.addOption(":video-filter=sharpen")
            media.addOption(":sharpen-sigma=\(sharpenSigma)")
        }
        #endif
    }

    let mediaPlayer = VLCMediaPlayer(library: vlcLibrary)
    let epgStore: EPGStore
    let epgParser: EITLogParser
    private var logReceiver: EPGLogReceiver?

    @Published private(set) var status: PlayerStatus = .idle
    /// Nach dem Umschalten noch kein Bild des neuen Senders zu sehen. Die Bildfläche zeigt bis dahin
    /// womöglich noch das letzte Bild des vorherigen Senders (VLC meldet „läuft“ schon, wenn nur der
    /// Ton da ist) – solange wird sie schwarz abgedeckt.
    @Published private(set) var awaitingFirstPicture = false
    @Published private(set) var nowPlaying: String?
    @Published private(set) var currentProgram: EPGProgram?
    @Published private(set) var nextProgram: EPGProgram?
    /// Zählt hoch, sobald neue EPG-Daten eingetroffen sind (auch für andere Sender).
    @Published private(set) var epgRevision = 0
    @Published private(set) var audioTrackName = "Standard"
    @Published private(set) var subtitleName = "Aus"
    @Published private(set) var hasSubtitles = false
    @Published private(set) var stats = PlaybackStatistics()
    /// Statistiken nur sammeln, solange sie zu sehen sind (Sendungsinfo). Sonst würde jede
    /// Aktualisierung zweimal pro Sekunde alle Ansichten neu zeichnen, die den Player beobachten.
    var collectStats = false {
        didSet { if collectStats && !oldValue { updatePlaybackStats() } }
    }
    /// Zeitversatz zum Live-Bild aus Sprüngen und beendeten Pausen.
    /// Gesetzt, solange das Bild angehalten ist.
    @Published private(set) var pausedSince: Date?
    /// Zweiter Player für Timeshift: spielt die Mitschnittdatei, solange nicht live geschaut wird.
    let replayPlayer = VLCMediaPlayer(library: vlcLibrary)
    /// Gesetzt, solange der Mitschnitt statt des Live-Bilds zu sehen ist.
    @Published private(set) var isReplaying = false

    /// Eigene Lautstärke der App (0–100), unabhängig von der Systemlautstärke.
    /// Gilt für Live-Bild und Mitschnitt; stumm geschaltet wird über die Lautstärke 0, damit sich
    /// das nicht mit dem Stummschalten beim Wechsel zwischen Live-Bild und Mitschnitt überschneidet.
    var volume = 100 {
        didSet { applyVolume() }
    }

    /// Bild ist da. `channelID`: zu merkende Variante (nur bei gewünschter Qualität, sonst `nil`);
    /// `staleIDs`: vorher fehlgeschlagene Varianten auf einer anderen Frequenz (veraltete Einträge).
    var onVariantSuccess: ((_ variantKey: String, _ channelID: String?, _ staleIDs: [String]) -> Void)?
    var onAllCandidatesFailed: ((_ channelName: String) -> Void)?

    init(epgStore: EPGStore = EPGStore(cacheURL: EPGStore.defaultCacheURL)) {
        self.epgStore = epgStore
        let parser = EITLogParser()
        self.epgParser = parser

        // Der Speicher ist threadsicher; die Rückrufe kommen aus VLC-Threads (Wiedergabe und
        // Hintergrund-Abruf teilen sich die Bibliothek und damit diesen Parser).
        //
        // Die EIT wiederholt sich alle paar Sekunden und bringt Tausende Sendungen. Früher startete
        // jede einzelne Sendung eine Aufgabe auf dem Hauptthread (samt teurem Abgleich über den
        // ganzen Speicher) – nach einem Suchlauf über alle Frequenzen war der Hauptthread damit
        // dauerhaft ausgelastet und die App reagierte nur noch zäh. Jetzt: nur Änderungen zählen,
        // und höchstens einmal pro Sekunde ein Signal an den Hauptthread.
        let store = epgStore
        let signal = EPGChangeSignal()
        parser.onServiceName = { [weak self] serviceID, name in
            if store.setServiceName(name, for: serviceID) {
                signal.fire { self?.epgDataChanged() }
            }
        }
        parser.onProgramParsed = { [weak self] program in
            if store.add(program: program) {
                signal.fire { self?.epgDataChanged() }
            }
        }
        let receiver = EPGLogReceiver(parser: parser)
        self.logReceiver = receiver
        Self.vlcLibrary.loggers = [receiver]
        VLCLibrary.shared().loggers = [receiver]
    }

    private(set) var channel: Channel?
    private(set) var options: PlaybackOptions?
    private var monitorTask: Task<Void, Never>?
    private var reconnectTask: Task<Void, Never>?
    private var openedAt = Date()
    private var wasPlaying = false
    /// Kommt per UDP kein Bild an (z. B. über VPN oder eine Firewall), wird auf RTP über TCP gewechselt.
    private var forceTCP = false
    /// Wann TCP erstmals Daten geliefert hat. Ohne diesen Beleg lag der Ausfall nicht an UDP
    /// (z. B. Tuner belegt): Dann gilt der Wechsel nur bis zum nächsten Sender oder zur Fehlermeldung.
    private var tcpConfirmedAt: Date?
    /// Auch ein bestätigter Wechsel gilt nur so lange: Das Netz kann sich inzwischen geändert haben.
    private static let tcpFallbackDuration: TimeInterval = 30 * 60
    /// Varianten des aktuellen Senders (z. B. alte und neue Frequenz nach einem Sendersuchlauf).
    private var candidates: [Channel] = []
    private var candidateIndex = 0
    /// Wie viele Varianten seit dem letzten Bild ohne Erfolg probiert wurden.
    private var failedCandidates = 0
    /// Fehlgeschlagene Varianten in der aktuellen Sitzung vor einem erfolgreichen Bild.
    private var failedInThisSessionForCurrent: [String] = []
    private var retryTask: Task<Void, Never>?

    // Timeshift über Mitschnitt in eine Datei (Ringpuffer)
    /// Datei, in die der Live-Player gerade mitschreibt.
    private var recordingURL: URL?
    /// Beginn des Mitschnitts (erste Daten); Grundlage für die Position in der Datei.
    private var recordingStartedAt: Date?
    private var recordingLimit: Int64 = 0
    private var recordingActive = false
    private var lastRecordingCheck = Date.distantPast
    /// Position im Mitschnitt in Sekunden ab Dateianfang, gemessen mit eigener Uhr
    /// (unabhängig von den Zeitstempeln im TS-Strom).
    private var replayAnchor: (fileSeconds: Double, at: Date, paused: Bool) = (0, .distantPast, true)
    private var replaySeekPending: Double?
    private var replayPausePending = false
    private var replayTracksSynced = false
    private var replayOpenedAt = Date.distantPast

    /// Ergänzte RTSP-Links nach PID-Änderungen, je Variante (Sitzung).
    private var pidOverrides: [String: URL] = [:]
    /// Varianten, für die in dieser Sitzung schon PIDs ergänzt wurden (nur ein Versuch je Variante).
    private var pidCheckDone: Set<String> = []
    /// Variante, die in dieser Sitzung zuletzt Bild geliefert hat, je Sender.
    private var workingVariant: [String: String] = [:]
    private var currentVariantKey = ""

    // Watchdog gegen eingefrorene Streams
    private var lastDisplayedPictures: Int = 0
    #if DEBUG
    private var lastStatsLog = Date.distantPast
    #endif
    private var lastPictureChangeAt = Date()

    // MARK: Abspielen

    func play(channel: Channel, options: PlaybackOptions) {
        play(candidates: [channel], options: options)
    }

    /// Spielt die erste Variante. Kommt darüber nichts an, werden die übrigen der Reihe nach probiert.
    func play(candidates list: [Channel], options: PlaybackOptions, preferredVariantID: String? = nil) {
        guard !list.isEmpty else { return }
        if let confirmed = tcpConfirmedAt, Date().timeIntervalSince(confirmed) > Self.tcpFallbackDuration {
            tcpConfirmedAt = nil
        }
        resetUnconfirmedTCP()
        var ordered = list
        currentVariantKey = list.variantKey
        let savedVariant = preferredVariantID ?? workingVariant[currentVariantKey]
        // Gemerkte Variante nur vorziehen, wenn sie die gewünschte Qualität hat: Sonst bliebe ein Sender
        // nach einem einzigen HD-Aussetzer dauerhaft auf SD.
        if let known = savedVariant,
           let index = ordered.firstIndex(where: { $0.id == known && $0.isHD == ordered[0].isHD }) {
            ordered.insert(ordered.remove(at: index), at: 0)
        }
        candidates = ordered
        candidateIndex = 0
        failedCandidates = 0
        failedInThisSessionForCurrent = []
        self.channel = ordered[0]
        self.options = options
        retryTask?.cancel()
        reconnectTask?.cancel()
        reconnectTask = nil
        start()
    }

    func stop() {
        monitorTask?.cancel()
        retryTask?.cancel()
        reconnectTask?.cancel()
        reconnectTask = nil
        wasPlaying = false
        stopReplay()
        endLiveRecording()
        mediaPlayer.audio?.isMuted = true
        mediaPlayer.stop()
        discardBuffer()
        status = .idle
    }

    func setFailed(title: String, message: String, hint: String? = nil) {
        monitorTask?.cancel()
        reconnectTask?.cancel()
        reconnectTask = nil
        wasPlaying = false
        stopReplay()
        endLiveRecording()
        mediaPlayer.audio?.isMuted = true
        mediaPlayer.stop()
        discardBuffer()
        status = .failed(title: title, message: message, hint: hint)
    }

    /// Startet den Stream neu (leert den Timeshift-Puffer).
    func restart() {
        guard channel != nil else { return }
        reconnectTask?.cancel()
        reconnectTask = nil
        start()
    }

    /// Öffnet den Stream. `preserveTimeshift`: Neuverbinden desselben Senders nach einem Abriss –
    /// bisheriger Puffer und eine laufende Wiedergabe daraus bleiben erhalten.
    private func start(preserveTimeshift: Bool = false) {
        guard let channel, let options else { return }
        monitorTask?.cancel()
        endLiveRecording()
        wasPlaying = false
        if !(preserveTimeshift && isReplaying) {
            stopReplay()
        }
        mediaPlayer.audio?.isMuted = true
        mediaPlayer.stop()
        lastDisplayedPictures = 0
        lastPictureChangeAt = Date()
        if !awaitingFirstPicture { awaitingFirstPicture = true }
        recordingLimit = 0
        nowPlaying = nil
        vlcTitle = nil
        currentProgram = nil
        nextProgram = nil
        stats = PlaybackStatistics()
        refreshEPGPrograms()

        let media = VLCMedia(url: pidOverrides[channel.id] ?? channel.streamURL)
        media.addOption(":network-caching=\(options.networkCachingMs)")
        // Videotext-Untertitel durchsichtig über dem Bild statt als schwarze Videotext-Tafel.
        media.addOption(":vbi-opaque=0")
        if options.rtspTCP || forceTCP {
            media.addOption(":rtsp-tcp")
        }
        Self.addPictureOptions(to: media, options: options, isSD: !channel.isHD)
        DebugLog.log("Öffne Stream per \(options.rtspTCP || forceTCP ? "TCP" : "UDP"), Puffer \(options.networkCachingMs) ms")
        if options.timeshift {
            prepareRecording(keepHistory: preserveTimeshift)
        } else {
            discardBuffer()
        }
        resetCrop(for: mediaPlayer, isSD: !channel.isHD)
        mediaPlayer.media = media
        mediaPlayer.setDeinterlaceFilter(Self.deinterlaceFilter(options: options, isSD: !channel.isHD))
        mediaPlayer.audio?.isMuted = true
        mediaPlayer.play()

        status = .connecting
        openedAt = Date()
        startMonitor()
    }

    // MARK: Überwachung

    private func startMonitor() {
        monitorTask = Task { [weak self] in
            while !Task.isCancelled {
                // Bis das erste Bild da ist, öfter nachsehen: Die schwarze Abdeckung soll ohne
                // Verzögerung verschwinden.
                let interval = (self?.needsFastPolling ?? false) ? 100 : 500
                try? await Task.sleep(for: .milliseconds(interval))
                guard let self, !Task.isCancelled else { return }
                self.poll()
            }
        }
    }

    /// Kurzer Takt, bis das erste Bild da ist, und in den ersten Sekunden eines Mitschnitts: Dessen
    /// Tonausgabe beginnt mit voller Lautstärke, die eigene Lautstärke soll sofort wieder gelten.
    private var needsFastPolling: Bool {
        awaitingFirstPicture || (isReplaying && volume < 100 && Date().timeIntervalSince(replayOpenedAt) < 2)
    }

    private var lastLoggedState: Int = -1
    /// Gesetzter Bildbeschnitt je Player (`nil` = keiner).
    private var appliedCrop: [ObjectIdentifier: String] = [:]

    /// Prüft die Videospur und setzt bei SD-Sendern den Bildausschnitt (Overscan, Standardformat;
    /// `PictureCrop`), auch wenn das Format mitten in der Sendung wechselt.
    private func updateCrop(for player: VLCMediaPlayer, isSD: Bool) {
        guard isSD, let tracks = player.media?.tracksInformation as? [[String: Any]],
              let video = tracks.first(where: { ($0[VLCMediaTracksInformationType] as? String) == VLCMediaTracksInformationTypeVideo })
        else { return }
        func value(_ key: String) -> Double { (video[key] as? NSNumber)?.doubleValue ?? 0 }
        let width = value(VLCMediaTracksInformationVideoWidth)
        let height = value(VLCMediaTracksInformationVideoHeight)
        let den = value(VLCMediaTracksInformationSourceAspectRatioDenominator)
        // Spur noch ohne Format: beim Öffnen gesetzten Beschnitt beibehalten.
        guard width > 0, height > 0, den > 0 else { return }
        let crop = PictureCrop.geometry(width: Int(width), height: Int(height),
                                        sampleAspect: value(VLCMediaTracksInformationSourceAspectRatio) / den)
        let key = ObjectIdentifier(player)
        guard appliedCrop[key] != crop else { return }
        appliedCrop[key] = crop
        Self.setCrop(crop, on: player)
        DebugLog.log("Bildbeschnitt: \(crop ?? "aus") (\(Int(width))×\(Int(height)))")
    }

    private static func setCrop(_ crop: String?, on player: VLCMediaPlayer) {
        if let crop {
            crop.withCString { player.videoCropGeometry = UnsafeMutablePointer(mutating: $0) }
        } else {
            player.videoCropGeometry = nil
        }
    }

    /// Vor dem Öffnen eines Mediums: Der Beschnitt hängt am Player und gälte sonst weiter. SD-Sender
    /// bekommen gleich den Ausschnitt für 720 × 576 (16:9), damit er ab dem ersten Bild gilt. Er muss
    /// am Player gesetzt werden: Die Videoausgabe von VLC hängt am Player, nicht am Medium, und erbt
    /// eine Medienoption `:crop=…` deshalb nicht. Weicht die Videospur ab, korrigiert `updateCrop`.
    private func resetCrop(for player: VLCMediaPlayer, isSD: Bool) {
        let crop = isSD ? PictureCrop.defaultSDGeometry : nil
        appliedCrop[ObjectIdentifier(player)] = crop
        Self.setCrop(crop, on: player)
    }

    private func poll() {
        let state = mediaPlayer.state
        if state.rawValue != lastLoggedState {
            lastLoggedState = state.rawValue
            DebugLog.log("VLC-Zustand \(state.rawValue) (0 stopped, 1 opening, 2 buffering, 3 ended, 4 error, 5 playing, 6 paused, 7 esAdded), isPlaying=\(mediaPlayer.isPlaying)")
        }

        // VLC meldet „playing“ schon vor den ersten Daten. Als laufend gilt die Wiedergabe erst,
        // wenn wirklich Bild oder Ton ankommt.
        let hasMedia = mediaPlayer.hasVideoOut || mediaPlayer.videoSize.width > 0 || mediaPlayer.numberOfAudioTracks > 0

        if state == .error || state == .ended || (state == .stopped && Date().timeIntervalSince(openedAt) > 2) {
            DebugLog.log("Neu verbinden: Zustand \(state.rawValue), Daten empfangen: \(wasPlaying)")
            if wasPlaying { scheduleReconnect() } else { handleNoData() }
            return
        }

        // VLC legt die Tonausgabe je Sendung neu an und beginnt dann wieder mit voller Lautstärke.
        applyVolume()

        if mediaPlayer.isPlaying && hasMedia {
            if !wasPlaying {
                wasPlaying = true
                failedCandidates = 0
                if forceTCP, tcpConfirmedAt == nil { tcpConfirmedAt = Date() }
                if let channel {
                    let preferredQuality = channel.isHD == candidates.first?.isHD
                    if preferredQuality { workingVariant[currentVariantKey] = channel.id }
                    // Als tot gelten nur Varianten auf einer anderen Frequenz (alte Einträge nach einem
                    // Suchlauf). Scheitert eine Variante auf derselben Frequenz, war es ein Aussetzer
                    // (Tuner belegt, langsamer Start) – sie wird beim nächsten Mal wieder zuerst probiert.
                    let workingFrequency = channel.tuning?.frequencyMHz
                    let staleIDs = candidates
                        .filter { failedInThisSessionForCurrent.contains($0.id) && $0.tuning?.frequencyMHz != workingFrequency }
                        .map(\.id)
                    onVariantSuccess?(currentVariantKey, preferredQuality ? channel.id : nil, staleIDs)
                }
                failedInThisSessionForCurrent = []
                DebugLog.log("Wiedergabe läuft (\(forceTCP || options?.rtspTCP == true ? "TCP" : "UDP")): Video \(mediaPlayer.videoSize), Tonspuren \(mediaPlayer.audioTrackNames as? [String] ?? [])")
                selectPreferredAudioTrack()
                // Die Tonverzögerung greift erst, wenn eine Tonspur aktiv ist (getrennt für AC3/Stereo).
                applyAudioDelay()
                if !isReplaying {
                    // Entmuten erst nach Spurwahl und einer kurzen Einpendelzeit (200 ms),
                    // damit unvollständige Audio-Frames zu Beginn und der Spurwechsel nicht krächzen/knacken.
                    Task { @MainActor [weak self] in
                        try? await Task.sleep(for: .milliseconds(200))
                        guard let self, self.wasPlaying, !self.isReplaying else { return }
                        self.mediaPlayer.audio?.isMuted = false
                    }
                }
                if options?.timeshift == true && recordingLimit >= 500 * 1024 * 1024 {
                    beginNativeRecording()
                }
            }
            setStatus((isReplaying && replayAnchor.paused) ? .paused : .playing)
            updateFirstPicture()
            updateCrop(for: mediaPlayer, isSD: channel?.isHD == false)
            if collectStats { updatePlaybackStats() }
            refreshTrackNames()
            checkStreamHealth()
        } else if !wasPlaying {
            // Solange noch keine sauberen Daten laufen, Audio stummhalten
            mediaPlayer.audio?.isMuted = true
            if Date().timeIntervalSince(openedAt) > 12 {
                // Nach 12 Sekunden ohne Bild und Ton: TCP, nächste Variante oder Fehlermeldung.
                DebugLog.log("Neu verbinden: nach 12 s keine Daten (Zustand \(state.rawValue))")
                handleNoData()
                return
            }
        } else if state == .paused || (isReplaying && replayAnchor.paused) {
            setStatus(.paused)
        }

        if let title = mediaPlayer.media?.metaData.nowPlaying,
           !title.isEmpty, title != vlcTitle {
            vlcTitle = title
            nowPlaying = title
            if channel != nil, epgStore.serviceID(forChannelNames: currentEPGNames) == nil {
                if epgStore.learn(channelNames: currentEPGNames, fromNowPlayingTitle: title) {
                    DebugLog.log("EPG-Zuordnung über Titel gelernt: \(currentEPGNames.first ?? "")")
                }
            }
            refreshEPGPrograms()
            DebugLog.log("Läuft jetzt: \(title)")
        }
        // Jetzt/Danach wechseln auch ohne neue Daten, wenn eine Sendung endet.
        if Date().timeIntervalSince(lastEPGRefresh) > 15 {
            refreshEPGPrograms()
        }
        pollTimeshift()
        checkForChangedPIDs()
    }

    /// Kommt nach einigen Sekunden kein Bild (oder gar nichts), prüfen, ob die PMT Spuren nennt,
    /// die der RTSP-Link nicht anfordert, und den Sender einmal mit ergänzten PIDs neu öffnen.
    private func checkForChangedPIDs() {
        guard let channel, channel.kind == .tv, !pidCheckDone.contains(channel.id) else { return }
        let elapsed = Date().timeIntervalSince(openedAt)
        let noPicture = mediaPlayer.videoSize.width == 0 && !mediaPlayer.hasVideoOut
        guard elapsed > 6, noPicture else { return }

        let trackIDs = (indexes(mediaPlayer.videoTrackIndexes)
                        + indexes(mediaPlayer.audioTrackIndexes)
                        + indexes(mediaPlayer.videoSubTitlesIndexes)).map { Int($0) }
        let missing = channel.missingPIDs(trackIDs: trackIDs)
        guard !missing.isEmpty else {
            if elapsed > 11 { pidCheckDone.insert(channel.id) }
            return
        }
        pidCheckDone.insert(channel.id)
        guard let url = channel.streamURL(addingPIDs: missing) else { return }
        pidOverrides[channel.id] = url
        DebugLog.log("PIDs geändert bei \(channel.name): ergänze \(missing) und verbinde neu")
        scheduleReconnect(after: 1)
    }

    /// Überwacht, ob der Live-Stream tatsächlich weiterläuft oder eingefroren ist.
    /// Steht die Anzahl angezeigter Frames bei laufendem Player länger als 3.5 s still,
    /// wird der Stream automatisch und schnell neu verbunden.
    private func checkStreamHealth() {
        // Nur live prüfen. (Früher stand hier zusätzlich `!replayAnchor.paused` – das ist zu Beginn
        // `true` und schaltete die Überwachung im Live-Betrieb komplett ab.)
        guard wasPlaying, status == .playing, !isReplaying else {
            lastPictureChangeAt = Date()
            return
        }

        #if os(macOS)
        // Im Dock minimiert oder ohne sichtbares Fenster ist die Videofläche ausgeblendet;
        // macOS drosselt dann das Zeichnen, sodass `displayedPictures` stehen bleiben kann,
        // ohne dass der Stream tatsächlich eingefroren ist.
        if let view = mediaPlayer.drawable as? NSView,
           view.window == nil || view.window?.isMiniaturized == true || view.isHidden {
            lastPictureChangeAt = Date()
            return
        }
        #endif

        // Nicht in den ersten 4 Sekunden nach Verbindungsaufbau prüfen
        guard Date().timeIntervalSince(openedAt) > 4.0 else {
            lastPictureChangeAt = Date()
            return
        }

        if let vlcStats = mediaPlayer.media?.statistics {
            let currentPictures = Int(vlcStats.displayedPictures)
            #if DEBUG
            if Date().timeIntervalSince(lastStatsLog) > 3 {
                lastStatsLog = Date()
                DebugLog.log("Bilder: dekodiert \(vlcStats.decodedVideo), angezeigt \(currentPictures), verloren \(vlcStats.lostPictures)")
            }
            #endif
            // Erst prüfen, wenn überhaupt schon Bilder empfangen und angezeigt wurden
            guard currentPictures > 0 else { return }

            if currentPictures > lastDisplayedPictures {
                lastDisplayedPictures = currentPictures
                lastPictureChangeAt = Date()
            } else if Date().timeIntervalSince(lastPictureChangeAt) > 4.0 {
                DebugLog.log("Stream eingefroren (keine neuen Bilder seit 4.0 s, Stand: \(currentPictures)) – Reconnect")
                lastPictureChangeAt = Date()
                lastDisplayedPictures = 0
                scheduleReconnect(after: 1)
            }
        }
    }

    /// Titel der laufenden Sendung, wie VLC ihn für das ausgewählte Programm meldet.
    /// Unabhängig vom EPG-Speicher, daher als Anker für das Lernen einer Zuordnung geeignet.
    private var vlcTitle: String?
    private var lastEPGRefresh = Date.distantPast
    /// Abgleich über den Titel ist teuer (geht über alle gespeicherten Sendungen): höchstens alle 30 s.
    private var lastLearnAttempt = Date.distantPast

    /// Namen aller Varianten des aktuellen Senders (HD/SD, alte/neue Frequenz).
    private var currentEPGNames: [String] {
        let names = candidates.map(\.name)
        return names.isEmpty ? (channel.map { [$0.name] } ?? []) : names
    }

    /// Neue oder geänderte Programmdaten (höchstens einmal pro Sekunde, siehe `EPGChangeSignal`).
    /// Meldet Ansichten wie der Programmübersicht über `epgRevision`, dass neue Daten da sind.
    private func epgDataChanged() {
        if channel != nil, let title = vlcTitle,
           Date().timeIntervalSince(lastLearnAttempt) > 30,
           epgStore.serviceID(forChannelNames: currentEPGNames) == nil {
            lastLearnAttempt = Date()
            if epgStore.learn(channelNames: currentEPGNames, fromNowPlayingTitle: title) {
                DebugLog.log("EPG-Zuordnung über Titel gelernt: \(currentEPGNames.first ?? "")")
            }
        }
        epgRevision &+= 1
        refreshEPGPrograms()
    }

    /// Neue Programmdaten aus dem Internet.
    func externalEPGUpdated() {
        epgRevision &+= 1
        refreshEPGPrograms()
    }

    func refreshEPGPrograms() {
        lastEPGRefresh = Date()
        guard channel != nil else { return }
        let names = currentEPGNames
        let current = epgStore.currentProgram(forChannelNames: names)
        let next = epgStore.nextProgram(forChannelNames: names)
        if current != currentProgram { currentProgram = current }
        if next != nextProgram { nextProgram = next }
        if nowPlaying == nil, let current { nowPlaying = current.title }
    }

    /// Setzt den Status nur bei einer Änderung: Jede Zuweisung an eine `@Published`-Eigenschaft
    /// löst ein Neuzeichnen aus, auch wenn der Wert gleich bleibt.
    /// Gibt die Bildfläche frei, sobald der neue Sender ein Bild zeigt. Radio (kein Bild) sofort;
    /// kommt trotz Ton nach 4 s kein Bild, ebenfalls – sonst bliebe der Bildschirm dauerhaft schwarz.
    private func updateFirstPicture() {
        guard awaitingFirstPicture else { return }
        let shown = Int(mediaPlayer.media?.statistics.displayedPictures ?? 0)
        let isRadio = channel?.kind == .radio
        if shown > 0 || isRadio || Date().timeIntervalSince(openedAt) > 4 {
            DebugLog.log("Erstes Bild nach \(Int(Date().timeIntervalSince(openedAt) * 1000)) ms (\(shown) Bilder)")
            awaitingFirstPicture = false
        }
    }

    private func setStatus(_ newStatus: PlayerStatus) {
        if status != newStatus { status = newStatus }
    }

    /// Es kam weder Bild noch Ton. Reihenfolge: erst auf TCP wechseln, dann die nächste Variante
    /// des Senders probieren. Wenn alle Varianten fehlschlagen, Meldung anzeigen.
    private func handleNoData() {
        if fallBackToTCP() {
            scheduleReconnect(after: 1)
            return
        }
        if let current = channel {
            failedInThisSessionForCurrent.append(current.id)
        }
        failedCandidates += 1
        if candidates.count > 1, failedCandidates < candidates.count {
            candidateIndex = (candidateIndex + 1) % candidates.count
            channel = candidates[candidateIndex]
            DebugLog.log("Keine Daten – probiere Variante \(candidateIndex + 1)/\(candidates.count): \(channel?.streamURL.absoluteString ?? "")")
            scheduleReconnect(after: 1)
            return
        }

        resetUnconfirmedTCP()
        // Schaut man zeitversetzt, bleibt der Puffer sehenswert, auch wenn live nichts mehr ankommt:
        // Wiedergabe und Puffer behalten und den Live-Empfang im Hintergrund weiter versuchen.
        if isReplaying, !candidates.isEmpty {
            DebugLog.log("Live-Empfang gestört, Timeshift-Wiedergabe läuft weiter")
            failedCandidates = 0
            failedInThisSessionForCurrent = []
            candidateIndex = 0
            channel = candidates[0]
            scheduleReconnect(after: 5)
            return
        }

        let channelName = channel?.displayName ?? "Sender"
        DebugLog.log("Keine Variante von \(channelName) liefert Bild.")
        setFailed(
            title: "Kein Bild für \(channelName)",
            message: "Der Sender liefert keine Daten.",
            hint: "Die Ursache wird geprüft. Ein neuer Versuch läuft automatisch."
        )
        // Präzisiert die Meldung nach Abfrage der Box (Tuner belegt, Box nicht erreichbar, Suchlauf nötig).
        onAllCandidatesFailed?(channelName)
        scheduleRetryAfterFailure()
    }

    /// Nach einer Fehlermeldung in größerem Abstand still weiter probieren: Ein belegter Tuner wird
    /// frei, ein kurzer Netzaussetzer geht vorbei. Endet mit jedem Senderwechsel oder Stopp.
    private func scheduleRetryAfterFailure() {
        retryTask?.cancel()
        let failedChannelKey = currentVariantKey
        retryTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(30))
            guard let self, !Task.isCancelled, case .failed = self.status,
                  self.currentVariantKey == failedChannelKey, !self.candidates.isEmpty else { return }
            DebugLog.log("Neuer Versuch nach Fehlermeldung")
            self.failedCandidates = 0
            self.candidateIndex = 0
            self.channel = self.candidates[0]
            self.start()
        }
    }

    /// Kommen per UDP keine Daten an (VPN, Firewall), RTP über TCP probieren.
    /// Gibt `true` zurück, wenn gerade umgeschaltet wurde.
    @discardableResult
    private func fallBackToTCP() -> Bool {
        guard options?.rtspTCP == false, !forceTCP else { return false }
        forceTCP = true
        DebugLog.log("Keine Daten per UDP – Wechsel auf RTP über TCP")
        return true
    }

    /// Nimmt einen TCP-Wechsel zurück, der keine Daten gebracht hat.
    private func resetUnconfirmedTCP() {
        guard forceTCP, tcpConfirmedAt == nil else { return }
        forceTCP = false
        DebugLog.log("Zurück zu UDP")
    }

    /// Verbindet denselben Sender neu. Der Timeshift-Puffer bleibt erhalten; schaut man gerade
    /// zeitversetzt, läuft diese Wiedergabe weiter.
    private func scheduleReconnect(after seconds: Int = 3) {
        guard reconnectTask == nil else { return }
        monitorTask?.cancel()
        endLiveRecording()
        mediaPlayer.audio?.isMuted = true
        mediaPlayer.stop()
        wasPlaying = false
        reconnectTask = Task { [weak self] in
            for remaining in stride(from: seconds, through: 1, by: -1) {
                self?.status = .reconnecting(seconds: remaining)
                try? await Task.sleep(for: .seconds(1))
                if Task.isCancelled { return }
            }
            self?.reconnectTask = nil
            self?.start(preserveTimeshift: true)
        }
    }

    // MARK: Timeshift über Mitschnitt in Dateien (Ringpuffer aus Abschnitten)
    //
    // Der Live-Player zeigt das Bild im normalen Dekodiermodus (ohne `:sout`, damit nur eine
    // Tonspur dekodiert wird) und schreibt den Strom gleichzeitig per libVLC-Mitschnitt in eine
    // TS-Datei (eine RTSP-Sitzung, ein Tuner). Anhalten oder Zurückspulen startet den zweiten
    // Player auf diesen Dateien; der Live-Player läuft stumm weiter und schreibt mit. „Live“ oder
    // Aufholen bis zum Ende schaltet zurück.
    //
    // Ringpuffer: Alle 15 Minuten (oder bei 4 GB) beginnt eine neue Datei. Abgeschlossene Abschnitte
    // bleiben erhalten, bis sie älter als die eingestellte Pufferlänge sind oder der Platz knapp
    // wird. Ein Abriss der Verbindung beendet nur den laufenden Abschnitt; der bisherige Puffer und
    // eine laufende Wiedergabe daraus bleiben erhalten. Nur ein Senderwechsel leert den Puffer.

    private struct RecordingSegment: Equatable {
        let url: URL
        let startedAt: Date
        var endedAt: Date?

        /// Länge in Sekunden (wächst, solange der Abschnitt noch beschrieben wird).
        var seconds: Double { (endedAt ?? Date()).timeIntervalSince(startedAt) }
    }

    /// Länge eines Abschnitts, bevor eine neue Datei beginnt.
    private static let segmentSeconds: Double = 15 * 60
    /// Mindestgröße einer Datei, bevor sie abgespielt wird.
    private static let minimumPlayableBytes: Int64 = 65_536

    /// Abgeschlossene Abschnitte, älteste zuerst.
    private var endedSegments: [RecordingSegment] = []
    /// Dateien, in die nicht mehr geschrieben wird (zum Erkennen der neuen Mitschnittdatei).
    private var retiredPaths: Set<String> = []
    /// Abschnitt, aus dem gerade wiedergegeben wird.
    private var replaySegment: RecordingSegment?
    /// Höchstgröße des gesamten Puffers.
    private var bufferLimit: Int64 = 0

    /// Laufender Abschnitt, sobald seine Datei erkannt ist.
    private var liveSegment: RecordingSegment? {
        guard let url = recordingURL, let started = recordingStartedAt else { return nil }
        return RecordingSegment(url: url, startedAt: started, endedAt: nil)
    }

    /// Alle abspielbaren Abschnitte in zeitlicher Reihenfolge.
    private var availableSegments: [RecordingSegment] {
        var all = endedSegments
        if let live = liveSegment,
           TimeshiftBufferManager.shared.fileSize(at: live.url) > Self.minimumPlayableBytes {
            all.append(live)
        }
        return all
    }

    /// Bereitet den Mitschnitt vor. `keepHistory`: bisherige Abschnitte behalten (Neuverbinden
    /// desselben Senders), sonst wird der Puffer geleert (Senderwechsel).
    private func prepareRecording(keepHistory: Bool) {
        let manager = TimeshiftBufferManager.shared
        if keepHistory {
            pruneSegments()
        } else {
            discardBuffer()
        }
        try? FileManager.default.createDirectory(at: manager.bufferDirectory, withIntermediateDirectories: true)
        let limit = manager.recordingLimitBytes()
        guard limit >= 500 * 1024 * 1024 else {
            recordingLimit = 0
            DebugLog.log("Timeshift aus: zu wenig freier Speicher (\(limit / 1_048_576) MB nutzbar)")
            return
        }
        recordingLimit = limit
        // Bereits belegter Puffer zählt mit, sonst schrumpft die Grenze bei jedem Neuverbinden.
        bufferLimit = manager.bufferLimitBytes() + manager.currentBufferSizeInBytes()
        lastRecordingCheck = Date()
    }

    /// Leert den Puffer vollständig (Senderwechsel, Timeshift aus, Stopp).
    private func discardBuffer() {
        endedSegments = []
        retiredPaths = []
        TimeshiftBufferManager.shared.cleanup(keeping: replaySegment.map { [$0.url.path] } ?? [])
    }

    private func beginNativeRecording() {
        let manager = TimeshiftBufferManager.shared
        try? FileManager.default.createDirectory(at: manager.bufferDirectory, withIntermediateDirectories: true)
        // Alle vorhandenen Dateien sind ältere Abschnitte; die neue erkennt `pollTimeshift`.
        retiredPaths.formUnion(manager.recordingFiles().map(\.path))
        _ = mediaPlayer.startRecording(atPath: manager.bufferDirectory.path)
        recordingActive = true
        recordingURL = nil
        recordingStartedAt = Date()
        lastRecordingCheck = Date()
        DebugLog.log("Timeshift-Mitschnitt gestartet in \(manager.bufferDirectory.lastPathComponent), Abschnitt höchstens \(recordingLimit / 1_048_576) MB, Puffer höchstens \(bufferLimit / 1_048_576) MB")
    }

    /// Beendet den laufenden Abschnitt. Die Datei bleibt als abgeschlossener Abschnitt erhalten.
    private func endLiveRecording() {
        if recordingActive {
            mediaPlayer.stopRecording()
            recordingActive = false
        }
        let manager = TimeshiftBufferManager.shared
        let now = Date()
        if let url = recordingURL, let started = recordingStartedAt,
           manager.fileSize(at: url) > Self.minimumPlayableBytes {
            endedSegments.append(RecordingSegment(url: url, startedAt: started, endedAt: now))
        }
        if let replay = replaySegment, replay.endedAt == nil, replay.url == recordingURL {
            replaySegment?.endedAt = now
        }
        retiredPaths.formUnion(manager.recordingFiles().map(\.path))
        recordingURL = nil
        recordingStartedAt = nil
    }

    /// Neue Datei beginnen, ohne den Live-Empfang zu unterbrechen.
    private func rotateRecording() {
        DebugLog.log("Timeshift: neuer Abschnitt")
        endLiveRecording()
        beginNativeRecording()
    }

    /// Entfernt Abschnitte, die älter als die Pufferlänge sind oder über die Größengrenze gehen.
    /// Der Abschnitt, aus dem gerade wiedergegeben wird, bleibt immer erhalten.
    private func pruneSegments() {
        let manager = TimeshiftBufferManager.shared
        let minutes = max(options?.timeshiftMinutes ?? 90, 1)
        let keepAfter = Date().addingTimeInterval(-Double(minutes) * 60)
        let replayURL = replaySegment?.url
        endedSegments.removeAll { segment in
            (segment.endedAt ?? Date()) < keepAfter && segment.url != replayURL
        }
        if bufferLimit > 0 {
            var total = endedSegments.reduce(Int64(0)) { $0 + manager.fileSize(at: $1.url) }
                + (recordingURL.map { manager.fileSize(at: $0) } ?? 0)
            while total > bufferLimit,
                  let index = endedSegments.firstIndex(where: { $0.url != replayURL }) {
                let removed = endedSegments.remove(at: index)
                total -= manager.fileSize(at: removed.url)
            }
        }
        // Dateien löschen, die zu keinem Abschnitt mehr gehören.
        var keep = Set(endedSegments.map(\.url.path))
        if let replayURL { keep.insert(replayURL.path) }
        if let recordingURL { keep.insert(recordingURL.path) }
        for file in manager.recordingFiles() where retiredPaths.contains(file.path) && !keep.contains(file.path) {
            manager.remove(file)
            retiredPaths.remove(file.path)
        }
    }

    /// Erkennt die Datei des laufenden Mitschnitts (VLC wählt den Namen selbst).
    private func detectRecordingFile() {
        guard recordingActive, recordingURL == nil else { return }
        let manager = TimeshiftBufferManager.shared
        if let url = manager.latestRecordingURL(excluding: retiredPaths), manager.fileSize(at: url) > 0 {
            recordingURL = url
            DebugLog.log("Timeshift-Mitschnittdatei erkannt: \(url.lastPathComponent)")
        }
    }

    var canTimeshift: Bool {
        guard options?.timeshift == true, status == .playing || status == .paused else { return false }
        detectRecordingFile()
        return !availableSegments.isEmpty
    }

    /// Aktuelle Position im wiedergegebenen Abschnitt in Sekunden ab Dateianfang.
    private var replayPosition: Double {
        replayAnchor.paused ? replayAnchor.fileSeconds
                            : replayAnchor.fileSeconds + Date().timeIntervalSince(replayAnchor.at)
    }

    /// Aktueller Rückstand zum Live-Bild in Sekunden (Uhrzeit der Position bis jetzt).
    var currentBehind: TimeInterval {
        guard isReplaying, let segment = replaySegment else { return 0 }
        return max(0, Date().timeIntervalSince(segment.startedAt) - replayPosition)
    }

    var isTimeshifted: Bool { isReplaying }

    /// Sendung, die gerade zu sehen ist: im Timeshift die Sendung an der zeitversetzten Stelle.
    var displayedProgram: EPGProgram? {
        guard isReplaying else { return currentProgram }
        let at = Date().addingTimeInterval(-currentBehind)
        return epgStore.currentProgram(forChannelNames: currentEPGNames, at: at) ?? currentProgram
    }

    /// Sendung nach der gerade zu sehenden.
    var displayedNextProgram: EPGProgram? {
        guard isReplaying else { return nextProgram }
        let at = Date().addingTimeInterval(-currentBehind)
        return epgStore.nextProgram(forChannelNames: currentEPGNames, at: at) ?? nextProgram
    }

    func togglePause() {
        if isReplaying {
            if replayAnchor.paused {
                replayAnchor = (replayPosition, Date(), false)
                pausedSince = nil
                replayPausePending = false
                replayPlayer.audio?.isMuted = false
                replayPlayer.play()
                status = .playing
            } else {
                replayAnchor = (replayPosition, Date(), true)
                pausedSince = Date()
                replayPlayer.audio?.isMuted = true
                if replayPlayer.isPlaying {
                    replayPlayer.pause()
                } else {
                    replayPausePending = true
                }
                status = .paused
            }
        } else if canTimeshift {
            startReplay(behind: 0, paused: true)
        } else if status != .playing || !mediaPlayer.isPlaying {
            start()
        } else {
            // Läuft, aber (noch) kein Mitschnitt: sichtbar machen statt stumm nichts zu tun.
            showFeedback(options?.timeshift == true ? "Timeshift startet gleich …" : "Timeshift ist ausgeschaltet")
        }
    }

    // MARK: Progressive Jump
    private var lastJumpPressAt = Date.distantPast
    private var lastJumpForward = true
    private var jumpPressCount = 0
    /// Kurzer Hinweis in der Bildmitte (Sprungweite, Timeshift-Hinweise).
    @Published private(set) var jumpFeedback: String?
    private var jumpFeedbackTask: Task<Void, Never>?

    func jumpProgressive(forward: Bool) {
        let step = ProgressiveJump.nextStep(
            forward: forward,
            lastPressAt: &lastJumpPressAt,
            lastDirectionForward: &lastJumpForward,
            pressCount: &jumpPressCount
        )
        // Im Live-Bild gibt es nichts vorzuspulen: dann auch keine Sprungweite anzeigen.
        let jumps = isReplaying || (!forward && canTimeshift)
        jump(seconds: Int(step.stepDelta))
        if jumps {
            showFeedback(step.displayText)
        } else if !forward {
            showFeedback(options?.timeshift == true ? "Timeshift startet gleich …" : "Timeshift ist ausgeschaltet")
        }
    }

    func showFeedback(_ text: String) {
        jumpFeedback = text
        jumpFeedbackTask?.cancel()
        jumpFeedbackTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(900))
            guard !Task.isCancelled else { return }
            self?.jumpFeedback = nil
        }
    }

    func jump(seconds: Int) {
        let step = Double(seconds)
        if isReplaying, let segment = replaySegment {
            let target = segment.startedAt.addingTimeInterval(replayPosition + step)
            if step > 0, target >= Date().addingTimeInterval(-1) {
                goLive()
                return
            }
            replay(atWallClock: target, paused: replayAnchor.paused)
        } else if seconds < 0, canTimeshift {
            startReplay(behind: -step, paused: false)
        }
    }

    func goLive() {
        guard isReplaying else { return }
        DebugLog.log("Timeshift: zurück zu Live")
        stopReplay()
    }

    /// Springt direkt zu einem bestimmten Rückstand hinter dem Live-Bild (z. B. per Mausklick in der Timeshift-Leiste).
    func seekToBehind(seconds: TimeInterval) {
        if seconds <= 2 {
            goLive()
            return
        }
        let target = Date().addingTimeInterval(-seconds)
        replay(atWallClock: target, paused: isReplaying ? replayAnchor.paused : false)
    }

    private func startReplay(behind: Double, paused: Bool) {
        // 1 s Abstand zum Ende: VLC puffert, die Datei hinkt dem Bild leicht hinterher.
        replay(atWallClock: Date().addingTimeInterval(-behind - 1), paused: paused)
    }

    /// Spielt den Puffer ab der angegebenen Uhrzeit. Liegt sie vor dem Puffer, beginnt die
    /// Wiedergabe am Anfang; liegt sie in einer Lücke (Verbindungsabriss), am nächsten Abschnitt.
    @discardableResult
    private func replay(atWallClock target: Date, paused: Bool) -> Bool {
        detectRecordingFile()
        let all = availableSegments
        var chosen: (segment: RecordingSegment, offset: Double)?
        for segment in all {
            let end = segment.endedAt ?? Date()
            if target < segment.startedAt {
                chosen = (segment, 0)
                break
            }
            if target <= end {
                chosen = (segment, target.timeIntervalSince(segment.startedAt))
                break
            }
        }
        if chosen == nil, let last = all.last {
            chosen = (last, max(0, last.seconds - 1))
        }
        guard let chosen else { return false }
        if isReplaying, replaySegment?.url == chosen.segment.url {
            seekWithinReplay(to: chosen.offset)
        } else {
            openReplay(segment: chosen.segment, position: chosen.offset, paused: paused)
        }
        return true
    }

    private func seekWithinReplay(to target: Double) {
        if replaySeekPending != nil {
            replaySeekPending = target
        } else {
            let delta = target - replayPosition
            if delta < 0 {
                replayPlayer.jumpBackward(Int32((-delta).rounded()))
            } else if delta > 0 {
                replayPlayer.jumpForward(Int32(delta.rounded()))
            }
        }
        replayAnchor = (target, Date(), replayAnchor.paused)
    }

    private func openReplay(segment: RecordingSegment, position: Double, paused: Bool) {
        guard let options else { return }
        if isReplaying {
            replayPlayer.stop()
        }
        let media = VLCMedia(url: segment.url)
        media.addOption(":file-caching=300")
        media.addOption(":input-fast-seek")
        media.addOption(":vbi-opaque=0")
        Self.addPictureOptions(to: media, options: options, isSD: channel?.isHD == false)
        resetCrop(for: replayPlayer, isSD: channel?.isHD == false)
        replayPlayer.media = media
        replayPlayer.setDeinterlaceFilter(Self.deinterlaceFilter(options: options, isSD: channel?.isHD == false))
        mediaPlayer.audio?.isMuted = true
        replayPlayer.audio?.isMuted = paused
        replayPlayer.play()
        applyVolume()
        replaySegment = segment
        replayAnchor = (position, Date(), paused)
        replaySeekPending = position > 0.5 ? position : nil
        replayPausePending = paused
        replayTracksSynced = false
        replayOpenedAt = Date()
        pausedSince = paused ? (pausedSince ?? Date()) : nil
        isReplaying = true
        status = paused ? .paused : .playing
        DebugLog.log("Timeshift: Wiedergabe aus \(segment.url.lastPathComponent) ab \(Int(position)) s (\(Int(currentBehind)) s hinter Live), angehalten=\(paused)")
    }

    /// Ende eines Abschnitts erreicht: im nächsten Abschnitt weiter oder zurück zu Live.
    private func continueAfter(_ segment: RecordingSegment) {
        detectRecordingFile()
        if let end = segment.endedAt,
           let next = availableSegments.first(where: { $0.url != segment.url && $0.startedAt >= segment.startedAt }) {
            // Lücke durch einen Verbindungsabriss überspringen.
            openReplay(segment: next, position: max(0, end.timeIntervalSince(next.startedAt)), paused: false)
            return
        }
        goLive()
    }

    private func stopReplay() {
        replaySeekPending = nil
        replayPausePending = false
        replayTracksSynced = false
        pausedSince = nil
        if isReplaying || replayPlayer.media != nil {
            replayPlayer.stop()
        }
        replayPlayer.audio?.isMuted = false
        isReplaying = false
        replaySegment = nil
        pruneSegments()
        if wasPlaying {
            mediaPlayer.audio?.isMuted = false
            status = .playing
        }
    }

    /// Läuft mit der Überwachung zweimal pro Sekunde.
    private func pollTimeshift() {
        detectRecordingFile()

        if isReplaying {
            mediaPlayer.audio?.isMuted = true
            let hasReplayVideo = replayPlayer.hasVideoOut || replayPlayer.videoSize.width > 0
            let hasReplayMedia = hasReplayVideo || replayPlayer.numberOfAudioTracks > 0

            if replayPlayer.isPlaying && hasReplayMedia {
                updateCrop(for: replayPlayer, isSD: channel?.isHD == false)
                if !replayTracksSynced {
                    replayTracksSynced = true
                    if mediaPlayer.currentAudioTrackIndex >= 0 {
                        replayPlayer.currentAudioTrackIndex = mediaPlayer.currentAudioTrackIndex
                    }
                    if mediaPlayer.currentVideoSubTitleIndex >= 0 {
                        replayPlayer.currentVideoSubTitleIndex = mediaPlayer.currentVideoSubTitleIndex
                    }
                    applyAudioDelay()
                }
                // Bei MPEG-TS greift ein Sprung erst, nachdem VLC PMT und PCR-PID gelesen hat.
                if let targetSeconds = replaySeekPending {
                    replaySeekPending = nil
                    var targetMs = Int32(targetSeconds * 1000)
                    let knownLengthMs = replayPlayer.media?.length.intValue ?? 0
                    if knownLengthMs > 500 {
                        targetMs = min(targetMs, knownLengthMs - 500)
                    }
                    if targetMs > 0 {
                        replayPlayer.time = VLCTime(int: targetMs)
                    }
                }
                // Angehalten starten: erst pausieren, wenn wirklich Bild (bzw. bei Radio Ton) anliegt.
                let readyToPause = channel?.kind == .radio ? hasReplayMedia : hasReplayVideo
                if replayPausePending && readyToPause {
                    replayPausePending = false
                    replayPlayer.audio?.isMuted = true
                    replayPlayer.pause()
                } else if replayAnchor.paused && !replayPausePending && readyToPause {
                    replayPlayer.audio?.isMuted = true
                    replayPlayer.pause()
                }
            }

            // Ende des Abschnitts erreicht: nächster Abschnitt bzw. zurück zum Live-Bild.
            let state = replayPlayer.state
            let openingGrace = Date().timeIntervalSince(replayOpenedAt) < 1.5
            if state == .error {
                goLive()
            } else if let segment = replaySegment {
                let remaining = segment.seconds - replayPosition
                if state == .ended || (!replayAnchor.paused && !openingGrace && remaining < 1) {
                    continueAfter(segment)
                }
            }
        }

        // Abschnitte wechseln und alten Puffer aufräumen (alle 10 s).
        guard recordingActive, recordingLimit > 0,
              Date().timeIntervalSince(lastRecordingCheck) > 10 else { return }
        lastRecordingCheck = Date()
        if let url = recordingURL, let started = recordingStartedAt {
            let tooLong = Date().timeIntervalSince(started) >= Self.segmentSeconds
            let tooBig = TimeshiftBufferManager.shared.fileSize(at: url) >= recordingLimit
            if tooLong || tooBig {
                rotateRecording()
            }
        }
        pruneSegments()
    }

    // MARK: Ton und Untertitel

    /// Bevorzugt die deutsche Hauptspur und übergeht Audiodeskription und „Clean Audio“.
    private func selectPreferredAudioTrack() {
        guard let names = mediaPlayer.audioTrackNames as? [String] else { return }
        let tracks = Array(zip(names, indexes(mediaPlayer.audioTrackIndexes))).filter { $0.1 >= 0 }
        let special = ["audio description", "visually impaired", "audiodeskription", "clean audio",
                       "hearing impaired", "hörfilm"]
        let normal = tracks.filter { track in !special.contains { track.0.lowercased().contains($0) } }
        let german = normal.first { $0.0.lowercased().contains("german") || $0.0.lowercased().contains("deutsch") }
        guard let choice = german ?? normal.first, choice.1 != mediaPlayer.currentAudioTrackIndex else { return }
        mediaPlayer.currentAudioTrackIndex = choice.1
        DebugLog.log("Tonspur gewählt: \(choice.0)")
    }

    func cycleAudioTrack() {
        let tracks = indexes(mediaPlayer.audioTrackIndexes).filter { $0 >= 0 }
        guard tracks.count > 1 else { return }
        let position = tracks.firstIndex(of: mediaPlayer.currentAudioTrackIndex) ?? -1
        let nextTrack = tracks[(position + 1) % tracks.count]
        mediaPlayer.currentAudioTrackIndex = nextTrack
        if isReplaying {
            replayPlayer.currentAudioTrackIndex = nextTrack
        }
        applyAudioDelay()
        refreshTrackNames()
    }

    // MARK: Tonverzögerung

    /// Ermittelt die passende Tonverzögerung (in ms) anhand der aktuell gewählten Tonspur (AC3 vs. Stereo/PCM).
    private func currentTargetAudioDelay() -> Int {
        guard let options else { return 0 }
        let rawAudio = trackName(current: mediaPlayer.currentAudioTrackIndex,
                                 names: mediaPlayer.audioTrackNames,
                                 indexes: mediaPlayer.audioTrackIndexes) ?? ""
        let isAC3 = rawAudio.localizedCaseInsensitiveContains("ac3")
            || rawAudio.localizedCaseInsensitiveContains("dolby")
            || rawAudio.localizedCaseInsensitiveContains("a52")
            || rawAudio.localizedCaseInsensitiveContains("eac3")
        return isAC3 ? options.audioDelayAC3Ms : options.audioDelayMs
    }

    /// Setzt die Tonverzögerung für den Haupt- und Replay-Player.
    func applyAudioDelay() {
        let delayMicroseconds = currentTargetAudioDelay() * 1000
        mediaPlayer.currentAudioPlaybackDelay = delayMicroseconds
        if isReplaying {
            replayPlayer.currentAudioPlaybackDelay = delayMicroseconds
        }
    }

    func cycleSubtitle() {
        var tracks = subtitleTrackIDs()
        if !tracks.contains(-1) { tracks.insert(-1, at: 0) }
        guard tracks.count > 1 else { return }
        let position = tracks.firstIndex(of: mediaPlayer.currentVideoSubTitleIndex) ?? 0
        let nextSub = tracks[(position + 1) % tracks.count]
        mediaPlayer.currentVideoSubTitleIndex = nextSub
        if isReplaying {
            replayPlayer.currentVideoSubTitleIndex = nextSub
        }
        refreshTrackNames()
    }

    private func refreshTrackNames() {
        // Läuft zweimal pro Sekunde: nur bei Änderungen zuweisen (siehe `setStatus`).
        let subIndexes = subtitleTrackIDs().filter { $0 >= 0 }
        let newHasSubtitles = !subIndexes.isEmpty
        if hasSubtitles != newHasSubtitles { hasSubtitles = newHasSubtitles }
        let rawAudio = trackName(current: mediaPlayer.currentAudioTrackIndex,
                                 names: mediaPlayer.audioTrackNames,
                                 indexes: mediaPlayer.audioTrackIndexes) ?? "Standard"
        let newAudioName = cleanAudioName(rawAudio)
        if audioTrackName != newAudioName { audioTrackName = newAudioName }

        let subtitle = mediaPlayer.currentVideoSubTitleIndex
        let newSubtitleName: String
        if subtitle < 0 {
            newSubtitleName = newHasSubtitles ? "Aus" : "Aus (keine vorhanden)"
        } else {
            let rawSub = trackName(current: subtitle,
                                  names: mediaPlayer.videoSubTitlesNames,
                                  indexes: mediaPlayer.videoSubTitlesIndexes) ?? "An"
            newSubtitleName = cleanSubtitleName(rawSub)
        }
        if subtitleName != newSubtitleName { subtitleName = newSubtitleName }
    }

    /// Untertitelspuren ohne die vollständige Videotext-Ansicht: VLC bietet bei DVB neben den
    /// Untertitel-Tafeln (z. B. 150, 777) auch den normalen Videotext als „Untertitel“ an.
    private func subtitleTrackIDs() -> [Int32] {
        let ids = indexes(mediaPlayer.videoSubTitlesIndexes)
        let names = (mediaPlayer.videoSubTitlesNames as? [String]) ?? []
        guard ids.count == names.count else { return ids }
        let joined = names.joined(separator: " | ")
        if joined != lastLoggedSubtitleNames {
            lastLoggedSubtitleNames = joined
            DebugLog.log("Untertitelspuren: \(joined)")
        }
        return zip(ids, names).compactMap { id, name in
            id < 0 || !Self.isFullTeletext(name) ? id : nil
        }
    }

    private var lastLoggedSubtitleNames = ""

    /// Volle Videotext-Seite (keine Untertitel-Tafel)?
    static func isFullTeletext(_ name: String) -> Bool {
        let lower = name.lowercased()
        guard lower.contains("teletext") || lower.contains("videotext") else { return false }
        let subtitleHints = ["subtitle", "untertitel", "150", "777", "888", "149", "hearing"]
        return !subtitleHints.contains { lower.contains($0) }
    }

    private static let trackRegex = try? NSRegularExpression(pattern: #"Track\s*\d+\s*-\s*\[(.*?)\]"#)

    private func cleanSubtitleName(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.localizedCaseInsensitiveContains("disable") {
            return "Aus"
        }
        var cleaned = trimmed
        if let regex = Self.trackRegex {
            let ns = cleaned as NSString
            if let match = regex.firstMatch(in: cleaned, range: NSRange(location: 0, length: ns.length)) {
                cleaned = ns.substring(with: match.range(at: 1))
            }
        }
        if cleaned.localizedCaseInsensitiveContains("deu") || cleaned.localizedCaseInsensitiveContains("ger") {
            cleaned = "Deutsch"
        }
        if raw.localizedCaseInsensitiveContains("teletext") {
            if raw.contains("150") {
                cleaned += " (Tafel 150)"
            } else if raw.contains("777") {
                cleaned += " (Tafel 777)"
            } else {
                cleaned += " (Videotext)"
            }
        }
        return cleaned
    }

    private func cleanAudioName(_ raw: String) -> String {
        var cleaned = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let regex = Self.trackRegex {
            let ns = cleaned as NSString
            if let match = regex.firstMatch(in: cleaned, range: NSRange(location: 0, length: ns.length)) {
                cleaned = ns.substring(with: match.range(at: 1))
            }
        }
        if cleaned.localizedCaseInsensitiveContains("deu") || cleaned.localizedCaseInsensitiveContains("ger") {
            cleaned = "Deutsch"
        } else if cleaned.localizedCaseInsensitiveContains("eng") {
            cleaned = "Englisch"
        } else if cleaned.localizedCaseInsensitiveContains("fra") || cleaned.localizedCaseInsensitiveContains("fre") {
            cleaned = "Französisch"
        }
        if raw.localizedCaseInsensitiveContains("ac3") || raw.localizedCaseInsensitiveContains("dolby") {
            cleaned += " (Dolby Digital)"
        }
        return cleaned
    }

    private func updatePlaybackStats() {
        var newStats = PlaybackStatistics()
        newStats.videoSize = mediaPlayer.videoSize
        if let vlcStats = mediaPlayer.media?.statistics {
            // libVLC liefert Byte pro Mikrosekunde (die VLC-Oberfläche rechnet mit × 8000 in kbit/s),
            // × 8 ergibt also Mbit/s.
            newStats.inputBitrateMbps = Double(vlcStats.inputBitrate) * 8.0
            newStats.demuxBitrateMbps = Double(vlcStats.demuxBitrate) * 8.0
            newStats.displayedPictures = Int(vlcStats.displayedPictures)
            newStats.lostPictures = Int(vlcStats.lostPictures)
            newStats.demuxDiscontinuities = Int(vlcStats.demuxDiscontinuity)
        }
        newStats.signalPowerDB = stats.signalPowerDB
        newStats.signalNoiseRatioDB = stats.signalNoiseRatioDB
        newStats.tunerUsage = stats.tunerUsage
        self.stats = newStats
    }

    func updateTunerStats(signalPower: Double?, snr: Double?, tunerUsage: (used: Int, total: Int)?) {
        stats.signalPowerDB = signalPower
        stats.signalNoiseRatioDB = snr
        stats.tunerUsage = tunerUsage
    }

    private func indexes(_ raw: [Any]?) -> [Int32] {
        (raw as? [NSNumber])?.map(\.int32Value) ?? []
    }

    private func trackName(current: Int32, names: [Any]?, indexes raw: [Any]?) -> String? {
        guard let names = names as? [String] else { return nil }
        for (name, index) in zip(names, indexes(raw)) where index == current {
            return name
        }
        return nil
    }
}


// MARK: Lautstärke, Puffer, Spurauswahl (Mac-Steuerleiste und Menüs)

/// Eine wählbare Ton- oder Untertitelspur. `id` ist die VLC-Spurnummer, −1 = aus.
struct TrackOption: Identifiable, Hashable {
    let id: Int32
    let name: String
}

extension PlayerController {
    fileprivate func applyVolume() {
        let level = Int32(min(max(volume, 0), 100))
        if let audio = mediaPlayer.audio, audio.volume != level { audio.volume = level }
        if let audio = replayPlayer.audio, audio.volume != level { audio.volume = level }
    }

    /// Wie weit der Puffer zurückreicht (Sekunden bis jetzt), 0 ohne Mitschnitt.
    var bufferedSeconds: TimeInterval {
        guard options?.timeshift == true, let first = availableSegments.first else { return 0 }
        return max(0, Date().timeIntervalSince(first.startedAt))
    }

    var audioTrackOptions: [TrackOption] {
        let names = (mediaPlayer.audioTrackNames as? [String]) ?? []
        let tracks = zip(names, indexes(mediaPlayer.audioTrackIndexes)).filter { $0.1 >= 0 }
        let cleaned = tracks.map { track -> String in
            let raw = track.0.lowercased()
            let base = cleanAudioName(track.0)
            if raw.contains("audio description") || raw.contains("visually impaired") || raw.contains("audiodeskription") {
                return "\(base.replacingOccurrences(of: " (Dolby Digital)", with: "")) · Audiodeskription"
            }
            if raw.contains("clean audio") || raw.contains("hearing impaired") {
                return "Klare Sprache"
            }
            return base
        }
        return tracks.enumerated().map { offset, track in
            // Gleich lautende Spuren (z. B. zweimal „Deutsch“, eine mit Audiodeskription) unterscheidbar halten.
            let name = cleaned.filter { $0 == cleaned[offset] }.count > 1 ? track.0 : cleaned[offset]
            return TrackOption(id: track.1, name: name)
        }
    }

    var currentAudioTrackID: Int32 { mediaPlayer.currentAudioTrackIndex }

    func selectAudioTrack(_ id: Int32) {
        guard id != mediaPlayer.currentAudioTrackIndex else { return }
        mediaPlayer.currentAudioTrackIndex = id
        if isReplaying { replayPlayer.currentAudioTrackIndex = id }
        applyAudioDelay()
        refreshTrackNames()
    }

    /// Untertitel einschließlich „Aus“ (−1).
    var subtitleOptions: [TrackOption] {
        let names = (mediaPlayer.videoSubTitlesNames as? [String]) ?? []
        let ids = indexes(mediaPlayer.videoSubTitlesIndexes)
        let allowed = Set(subtitleTrackIDs())
        var options = [TrackOption(id: -1, name: "Aus")]
        for (name, id) in zip(names, ids) where id >= 0 && allowed.contains(id) {
            options.append(TrackOption(id: id, name: cleanSubtitleName(name)))
        }
        return options
    }

    var currentSubtitleID: Int32 { mediaPlayer.currentVideoSubTitleIndex }

    func selectSubtitle(_ id: Int32) {
        guard id != mediaPlayer.currentVideoSubTitleIndex else { return }
        mediaPlayer.currentVideoSubTitleIndex = id
        if isReplaying { replayPlayer.currentVideoSubTitleIndex = id }
        refreshTrackNames()
    }
}

/// Fasst Meldungen aus VLC-Threads zusammen: höchstens ein Aufruf pro Sekunde auf dem Hauptthread.
final class EPGChangeSignal: @unchecked Sendable {
    private let lock = NSLock()
    private var pending = false

    func fire(_ action: @escaping @MainActor () -> Void) {
        lock.lock()
        if pending {
            lock.unlock()
            return
        }
        pending = true
        lock.unlock()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [self] in
            lock.lock()
            pending = false
            lock.unlock()
            MainActor.assumeIsolated { action() }
        }
    }
}
