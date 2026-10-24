import Foundation
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
    var audioDelayMs: Int
    var timeshift: Bool
}

enum PlayerStatus: Equatable {
    case idle
    case connecting
    case playing
    case paused
    case reconnecting(seconds: Int)
    case failed(title: String, message: String, hint: String?)
}

/// Kapselt VLCKit: Abspielen eines RTSP-Streams der FRITZ!Box, Timeshift-Prototyp,
/// automatisches Neuverbinden, Ton- und Untertitelspuren, „Läuft jetzt“ aus der EIT.
///
/// Statt der VLC-Delegate-Methoden wird der Zustand zweimal pro Sekunde abgefragt.
/// Das ist robuster gegenüber Unterschieden zwischen den VLCKit-Versionen.
@MainActor
final class PlayerController: ObservableObject {
    let mediaPlayer = VLCMediaPlayer()
    let epgStore: EPGStore
    let epgParser: EITLogParser
    private var logReceiver: EPGLogReceiver?

    @Published private(set) var status: PlayerStatus = .idle
    @Published private(set) var nowPlaying: String?
    @Published private(set) var currentProgram: EPGProgram?
    @Published private(set) var nextProgram: EPGProgram?
    /// Zählt hoch, sobald neue EPG-Daten eingetroffen sind (auch für andere Sender).
    @Published private(set) var epgRevision = 0
    @Published private(set) var audioTrackName = "Standard"
    @Published private(set) var subtitleName = "Aus"
    @Published private(set) var hasSubtitles = false
    @Published private(set) var stats = PlaybackStatistics()
    /// Zeitversatz zum Live-Bild aus Sprüngen und beendeten Pausen.
    /// Gesetzt, solange das Bild angehalten ist.
    @Published private(set) var pausedSince: Date?
    /// Zweiter Player für Timeshift: spielt die Mitschnittdatei, solange nicht live geschaut wird.
    let replayPlayer = VLCMediaPlayer()
    /// Gesetzt, solange der Mitschnitt statt des Live-Bilds zu sehen ist.
    @Published private(set) var isReplaying = false

    var onVariantSuccess: ((_ variantKey: String, _ channelID: String, _ failedEarlierIDs: [String]) -> Void)?
    var onAllCandidatesFailed: ((_ channelName: String) -> Void)?

    init(epgStore: EPGStore = EPGStore()) {
        self.epgStore = epgStore
        let parser = EITLogParser()
        self.epgParser = parser

        // Der Speicher ist threadsicher; die Rückrufe kommen aus VLC-Threads (Wiedergabe und
        // Hintergrund-Abruf teilen sich die Bibliothek und damit diesen Parser).
        let store = epgStore
        parser.onServiceName = { [weak self] serviceID, name in
            store.setServiceName(name, for: serviceID)
            Task { @MainActor in self?.scheduleEPGRefresh() }
        }
        parser.onProgramParsed = { [weak self] program in
            store.add(program: program)
            Task { @MainActor in self?.handleParsedProgram(program) }
        }
        let receiver = EPGLogReceiver(parser: parser)
        self.logReceiver = receiver
        VLCLibrary.shared().loggers = [receiver]
    }

    private(set) var channel: Channel?
    private(set) var options: PlaybackOptions?
    private var monitorTask: Task<Void, Never>?
    private var reconnectTask: Task<Void, Never>?
    private var openedAt = Date()
    private var wasPlaying = false
    /// Kommt per UDP kein Bild an (z. B. über VPN oder eine Firewall), wird für den Rest der Sitzung
    /// RTP über TCP verwendet.
    private var forceTCP = false
    /// Varianten des aktuellen Senders (z. B. alte und neue Frequenz nach einem Sendersuchlauf).
    private var candidates: [Channel] = []
    private var candidateIndex = 0
    /// Wie viele Varianten seit dem letzten Bild ohne Erfolg probiert wurden.
    private var failedCandidates = 0
    /// Fehlgeschlagene Varianten in der aktuellen Sitzung vor einem erfolgreichen Bild.
    private var failedInThisSessionForCurrent: [String] = []
    private var retryTask: Task<Void, Never>?

    // Timeshift über Mitschnitt in eine Datei (Vorbild dream Player)
    /// Datei, in die der Live-Player gerade mitschreibt.
    private var recordingURL: URL?
    /// Beginn des Mitschnitts (erste Daten); Grundlage für die Position in der Datei.
    private var recordingStartedAt: Date?
    private var recordingLimit: Int64 = 0
    private var lastRecordingCheck = Date.distantPast
    /// Mitschreiben verhindert die Wiedergabe (z. B. fehlt das sout-Modul): für diese Sitzung aus.
    private var recordingDisabledForSession = false
    /// Nach dem Fehlschlag aller Varianten ein letzter Versuch ohne Mitschnitt.
    private var triedWithoutRecording = false
    /// Position im Mitschnitt in Sekunden ab Dateianfang, gemessen mit eigener Uhr
    /// (unabhängig von den Zeitstempeln im TS-Strom).
    private var replayAnchor: (fileSeconds: Double, at: Date, paused: Bool) = (0, .distantPast, true)
    private var replayPausePending = false

    /// Ergänzte RTSP-Links nach PID-Änderungen, je Variante (Sitzung).
    private var pidOverrides: [String: URL] = [:]
    /// Varianten, für die in dieser Sitzung schon PIDs ergänzt wurden (nur ein Versuch je Variante).
    private var pidCheckDone: Set<String> = []
    /// Variante, die in dieser Sitzung zuletzt Bild geliefert hat, je Sender.
    private var workingVariant: [String: String] = [:]
    private var currentVariantKey = ""

    // MARK: Abspielen

    func play(channel: Channel, options: PlaybackOptions) {
        play(candidates: [channel], options: options)
    }

    /// Spielt die erste Variante. Kommt darüber nichts an, werden die übrigen der Reihe nach probiert.
    func play(candidates list: [Channel], options: PlaybackOptions, preferredVariantID: String? = nil) {
        guard !list.isEmpty else { return }
        var ordered = list
        currentVariantKey = Self.variantKey(list)
        let savedVariant = preferredVariantID ?? workingVariant[currentVariantKey]
        if let known = savedVariant, let index = ordered.firstIndex(where: { $0.id == known }) {
            ordered.insert(ordered.remove(at: index), at: 0)
        }
        candidates = ordered
        candidateIndex = 0
        failedCandidates = 0
        failedInThisSessionForCurrent = []
        triedWithoutRecording = false
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
        stopReplay()
        mediaPlayer.stop()
        recordingURL = nil
        recordingStartedAt = nil
        TimeshiftBufferManager.shared.cleanup()
        status = .idle
        wasPlaying = false
    }

    func setFailed(title: String, message: String, hint: String? = nil) {
        monitorTask?.cancel()
        reconnectTask?.cancel()
        reconnectTask = nil
        stopReplay()
        mediaPlayer.stop()
        wasPlaying = false
        status = .failed(title: title, message: message, hint: hint)
    }

    /// Startet den Stream neu, z. B. nach geänderten Einstellungen oder für „zurück zu Live“.
    func restart() {
        guard channel != nil else { return }
        reconnectTask?.cancel()
        reconnectTask = nil
        start()
    }

    private func start() {
        guard let channel, let options else { return }
        monitorTask?.cancel()
        mediaPlayer.stop()
        stopReplay()
        recordingURL = nil
        recordingStartedAt = nil
        nowPlaying = nil
        vlcTitle = nil
        currentProgram = nil
        nextProgram = nil
        wasPlaying = false
        stats = PlaybackStatistics()
        refreshEPGPrograms()

        let media = VLCMedia(url: pidOverrides[channel.id] ?? channel.streamURL)
        media.addOption(":network-caching=\(options.networkCachingMs)")
        if options.rtspTCP || forceTCP {
            media.addOption(":rtsp-tcp")
        }
        DebugLog.log("Öffne Stream per \(options.rtspTCP || forceTCP ? "TCP" : "UDP"), Puffer \(options.networkCachingMs) ms")
        if options.timeshift && !recordingDisabledForSession && !triedWithoutRecording {
            startRecording(on: media, channel: channel)
        }
        mediaPlayer.media = media
        mediaPlayer.setDeinterlaceFilter(options.deinterlace && !channel.isHD ? "yadif" : nil)
        mediaPlayer.play()

        status = .connecting
        openedAt = Date()
        startMonitor()
    }

    // MARK: Überwachung

    private func startMonitor() {
        monitorTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(500))
                guard let self, !Task.isCancelled else { return }
                self.poll()
            }
        }
    }

    private var lastLoggedState: Int = -1

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

        if mediaPlayer.isPlaying && hasMedia {
            if !wasPlaying {
                wasPlaying = true
                failedCandidates = 0
                if recordingURL != nil {
                    recordingStartedAt = Date()
                } else if triedWithoutRecording && options?.timeshift == true && !recordingDisabledForSession {
                    // Erst ohne Mitschnitt kam Bild: das Mitschreiben war schuld.
                    recordingDisabledForSession = true
                    DebugLog.log("Timeshift-Mitschnitt verhindert die Wiedergabe – für diese Sitzung abgeschaltet")
                }
                if let channel {
                    workingVariant[currentVariantKey] = channel.id
                    onVariantSuccess?(currentVariantKey, channel.id, failedInThisSessionForCurrent)
                }
                failedInThisSessionForCurrent = []
                DebugLog.log("Wiedergabe läuft (\(forceTCP || options?.rtspTCP == true ? "TCP" : "UDP")): Video \(mediaPlayer.videoSize), Tonspuren \(mediaPlayer.audioTrackNames as? [String] ?? [])")
                selectPreferredAudioTrack()
                // Die Tonverzögerung greift erst, wenn eine Tonspur aktiv ist.
                mediaPlayer.currentAudioPlaybackDelay = (options?.audioDelayMs ?? 0) * 1000
            }
            status = .playing
            updatePlaybackStats()
            refreshTrackNames()
        } else if state == .paused {
            status = .paused
        } else if !wasPlaying, Date().timeIntervalSince(openedAt) > 12 {
            // Nach 12 Sekunden ohne Bild und Ton neu versuchen.
            DebugLog.log("Neu verbinden: nach 12 s keine Daten (Zustand \(state.rawValue))")
            handleNoData()
            return
        }

        if let title = mediaPlayer.media?.metadata(forKey: VLCMetaInformationNowPlaying),
           !title.isEmpty, title != vlcTitle {
            vlcTitle = title
            nowPlaying = title
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
                        + indexes(mediaPlayer.videoSubTitlesIndexes)).map(Int.init)
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

    /// Titel der laufenden Sendung, wie VLC ihn für das ausgewählte Programm meldet.
    /// Unabhängig vom EPG-Speicher, daher als Anker für das Lernen einer Zuordnung geeignet.
    private var vlcTitle: String?
    private var lastEPGRefresh = Date.distantPast
    private var epgRefreshPending = false

    /// Namen aller Varianten des aktuellen Senders (HD/SD, alte/neue Frequenz).
    private var currentEPGNames: [String] {
        let names = candidates.map(\.name)
        return names.isEmpty ? (channel.map { [$0.name] } ?? []) : names
    }

    private func handleParsedProgram(_ program: EPGProgram) {
        if channel != nil, epgStore.serviceID(forChannelNames: currentEPGNames) == nil,
           let title = vlcTitle,
           epgStore.learn(channelNames: currentEPGNames, fromNowPlayingTitle: title) {
            DebugLog.log("EPG-Zuordnung über Titel gelernt: \(currentEPGNames.first ?? "")")
        }
        scheduleEPGRefresh()
    }

    /// Fasst viele Aktualisierungen in kurzer Folge zusammen (eine EIT bringt Dutzende Sendungen)
    /// und meldet Ansichten wie der Programmübersicht über `epgRevision`, dass neue Daten da sind.
    private func scheduleEPGRefresh() {
        guard !epgRefreshPending else { return }
        epgRefreshPending = true
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard let self else { return }
            self.epgRefreshPending = false
            self.epgRevision &+= 1
            self.refreshEPGPrograms()
        }
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

    /// Schlüssel für die gemerkte Variante: Sender plus gewünschte Qualität.
    private static func variantKey(_ list: [Channel]) -> String {
        guard let first = list.first else { return "" }
        return "\(first.kind.rawValue):\(first.groupKey):\(first.isHD)"
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
        
        // Alle Varianten wurden erfolglos probiert. Lief der Mitschnitt mit, einmal ohne ihn
        // versuchen: Fehlt VLC das Modul zum Mitschreiben, käme sonst nie ein Bild.
        if recordingURL != nil && !triedWithoutRecording {
            triedWithoutRecording = true
            failedCandidates = 0
            candidateIndex = 0
            channel = candidates.first
            DebugLog.log("Keine Variante liefert Bild – letzter Versuch ohne Timeshift-Mitschnitt")
            scheduleReconnect(after: 1)
            return
        }
        let channelName = channel?.displayName ?? "Sender"
        DebugLog.log("Keine Variante von \(channelName) liefert Bild.")
        setFailed(
            title: "Kein Bild für \(channelName)",
            message: "Senderliste veraltet – Suchlauf starten",
            hint: "Sendersuchlauf starten: Einstellungen › Sendersuchlauf (mit Box-Kennwort) oder in der FRITZ!Box-Oberfläche unter DVB-C."
        )
        // Kann die Meldung präzisieren (z. B. „Alle Tuner belegt“).
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

    /// Kommen per UDP keine Daten an (VPN, Firewall), für den Rest der Sitzung RTP über TCP nutzen.
    /// Gibt `true` zurück, wenn gerade umgeschaltet wurde.
    @discardableResult
    private func fallBackToTCP() -> Bool {
        guard options?.rtspTCP == false, !forceTCP else { return false }
        forceTCP = true
        DebugLog.log("Keine Daten per UDP – Wechsel auf RTP über TCP für diese Sitzung")
        return true
    }

    private func scheduleReconnect(after seconds: Int = 3) {
        guard reconnectTask == nil else { return }
        monitorTask?.cancel()
        mediaPlayer.stop()
        wasPlaying = false
        reconnectTask = Task { [weak self] in
            for remaining in stride(from: seconds, through: 1, by: -1) {
                self?.status = .reconnecting(seconds: remaining)
                try? await Task.sleep(for: .seconds(1))
                if Task.isCancelled { return }
            }
            self?.reconnectTask = nil
            self?.start()
        }
    }

    // MARK: Timeshift über Mitschnitt in eine Datei
    //
    // Der Live-Player zeigt das Bild und schreibt den Strom gleichzeitig in eine TS-Datei
    // (eine RTSP-Sitzung, ein Tuner). Anhalten oder Zurückspulen startet den zweiten Player auf
    // dieser Datei; der Live-Player läuft stumm weiter und schreibt mit. „Live“ oder Aufholen bis
    // zum Dateiende schaltet zurück.

    private func startRecording(on media: VLCMedia, channel: Channel) {
        let manager = TimeshiftBufferManager.shared
        manager.cleanup()
        try? FileManager.default.createDirectory(at: manager.bufferDirectory, withIntermediateDirectories: true)
        let limit = manager.recordingLimitBytes()
        guard limit >= 500 * 1024 * 1024 else {
            DebugLog.log("Timeshift aus: zu wenig freier Speicher (\(limit / 1_048_576) MB nutzbar)")
            return
        }
        let url = manager.newSegmentURL(channelKey: channel.groupKey)
        media.addOption(TimeshiftBufferManager.soutDisplayAndRecordOption(destination: url))
        recordingURL = url
        recordingLimit = limit
        lastRecordingCheck = Date()
        DebugLog.log("Timeshift-Mitschnitt nach \(url.lastPathComponent), höchstens \(limit / 1_048_576) MB")
    }

    var canTimeshift: Bool {
        options?.timeshift == true && recordingURL != nil && recordingStartedAt != nil && status == .playing
    }

    /// Länge des bisherigen Mitschnitts in Sekunden.
    private var recordedSeconds: Double {
        recordingStartedAt.map { Date().timeIntervalSince($0) } ?? 0
    }

    /// Aktuelle Position im Mitschnitt in Sekunden ab Dateianfang.
    private var replayPosition: Double {
        replayAnchor.paused ? replayAnchor.fileSeconds
                            : replayAnchor.fileSeconds + Date().timeIntervalSince(replayAnchor.at)
    }

    /// Aktueller Rückstand zum Live-Bild in Sekunden.
    var currentBehind: TimeInterval {
        isReplaying ? max(0, recordedSeconds - replayPosition) : 0
    }

    var isTimeshifted: Bool { isReplaying }

    func togglePause() {
        if isReplaying {
            if replayAnchor.paused {
                replayAnchor = (replayPosition, Date(), false)
                pausedSince = nil
                replayPausePending = false
                replayPlayer.play()
            } else {
                replayAnchor = (replayPosition, Date(), true)
                pausedSince = Date()
                replayPlayer.pause()
            }
        } else if canTimeshift {
            startReplay(behind: 0, paused: true)
        }
    }

    func jump(seconds: Int) {
        let step = Double(seconds)
        if seconds < 0 {
            if isReplaying {
                let target = max(0, replayPosition + step)
                replayPlayer.jumpBackward(Int32(replayPosition - target))
                replayAnchor = (target, Date(), replayAnchor.paused)
            } else if canTimeshift {
                startReplay(behind: -step, paused: false)
            }
        } else if isReplaying {
            if currentBehind <= step + 1 {
                goLive()
            } else {
                replayPlayer.jumpForward(Int32(seconds))
                replayAnchor = (replayPosition + step, Date(), replayAnchor.paused)
            }
        }
    }

    func goLive() {
        guard isReplaying else { return }
        DebugLog.log("Timeshift: zurück zu Live")
        stopReplay()
    }

    private func startReplay(behind: Double, paused: Bool) {
        guard let url = recordingURL, let options else { return }
        // 1 s Abstand zum Dateiende: VLC puffert, die Datei hinkt dem Bild leicht hinterher.
        let position = max(0, recordedSeconds - behind - 1)
        let media = VLCMedia(url: url)
        media.addOption(":start-time=\(String(format: "%.1f", position))")
        media.addOption(":file-caching=300")
        replayPlayer.media = media
        replayPlayer.setDeinterlaceFilter(options.deinterlace && channel?.isHD == false ? "yadif" : nil)
        replayPlayer.play()
        replayAnchor = (position, Date(), paused)
        replayPausePending = paused
        pausedSince = paused ? Date() : nil
        mediaPlayer.audio?.isMuted = true
        isReplaying = true
        DebugLog.log("Timeshift: Wiedergabe aus dem Mitschnitt ab \(Int(position)) s (\(Int(behind)) s hinter Live)")
    }

    private func stopReplay() {
        replayPausePending = false
        pausedSince = nil
        if isReplaying || replayPlayer.media != nil {
            replayPlayer.stop()
        }
        mediaPlayer.audio?.isMuted = false
        isReplaying = false
    }

    /// Läuft mit der Überwachung zweimal pro Sekunde.
    private func pollTimeshift() {
        if isReplaying {
            // Angehalten starten: erst pausieren, wenn VLC wirklich spielt.
            if replayPausePending && replayPlayer.isPlaying {
                replayPausePending = false
                replayPlayer.pause()
            }
            // Bis zum Dateiende aufgeholt: zurück zum Live-Bild.
            let state = replayPlayer.state
            if state == .ended || state == .error || (!replayAnchor.paused && currentBehind < 1) {
                goLive()
            }
        }

        // Größe des Mitschnitts prüfen (alle 10 s).
        guard let url = recordingURL, Date().timeIntervalSince(lastRecordingCheck) > 10 else { return }
        lastRecordingCheck = Date()
        if TimeshiftBufferManager.shared.fileSize(at: url) > recordingLimit {
            DebugLog.log("Timeshift-Mitschnitt hat die Grenze von \(recordingLimit / 1_048_576) MB erreicht – Puffer wird neu begonnen")
            restart()
        }
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
        mediaPlayer.currentAudioTrackIndex = tracks[(position + 1) % tracks.count]
        refreshTrackNames()
    }

    func cycleSubtitle() {
        var tracks = indexes(mediaPlayer.videoSubTitlesIndexes)
        if !tracks.contains(-1) { tracks.insert(-1, at: 0) }
        guard tracks.count > 1 else { return }
        let position = tracks.firstIndex(of: mediaPlayer.currentVideoSubTitleIndex) ?? 0
        mediaPlayer.currentVideoSubTitleIndex = tracks[(position + 1) % tracks.count]
        refreshTrackNames()
    }

    private func refreshTrackNames() {
        let subIndexes = indexes(mediaPlayer.videoSubTitlesIndexes).filter { $0 >= 0 }
        hasSubtitles = !subIndexes.isEmpty
        let rawAudio = trackName(current: mediaPlayer.currentAudioTrackIndex,
                                 names: mediaPlayer.audioTrackNames,
                                 indexes: mediaPlayer.audioTrackIndexes) ?? "Standard"
        audioTrackName = cleanAudioName(rawAudio)

        let subtitle = mediaPlayer.currentVideoSubTitleIndex
        if subtitle < 0 {
            subtitleName = hasSubtitles ? "Aus" : "Aus (keine vorhanden)"
        } else {
            let rawSub = trackName(current: subtitle,
                                  names: mediaPlayer.videoSubTitlesNames,
                                  indexes: mediaPlayer.videoSubTitlesIndexes) ?? "An"
            subtitleName = cleanSubtitleName(rawSub)
        }
    }

    private func cleanSubtitleName(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.localizedCaseInsensitiveContains("disable") {
            return "Aus"
        }
        var cleaned = trimmed
        if let regex = try? NSRegularExpression(pattern: #"Track\s*\d+\s*-\s*\[(.*?)\]"#) {
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
        if let regex = try? NSRegularExpression(pattern: #"Track\s*\d+\s*-\s*\[(.*?)\]"#) {
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
