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
    var audioDelayAC3Ms: Int
    var timeshift: Bool
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

    init(epgStore: EPGStore = EPGStore(cacheURL: EPGStore.defaultCacheURL)) {
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
    private var lastPictureChangeAt = Date()

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
        if recordingActive {
            mediaPlayer.stopRecording()
            recordingActive = false
        }
        mediaPlayer.audio?.isMuted = true
        mediaPlayer.stop()
        recordingURL = nil
        recordingStartedAt = nil
        TimeshiftBufferManager.shared.cleanup()
        status = .idle
    }

    func setFailed(title: String, message: String, hint: String? = nil) {
        monitorTask?.cancel()
        reconnectTask?.cancel()
        reconnectTask = nil
        wasPlaying = false
        stopReplay()
        if recordingActive {
            mediaPlayer.stopRecording()
            recordingActive = false
        }
        mediaPlayer.audio?.isMuted = true
        mediaPlayer.stop()
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
        if recordingActive {
            mediaPlayer.stopRecording()
            recordingActive = false
        }
        wasPlaying = false
        stopReplay()
        mediaPlayer.audio?.isMuted = true
        mediaPlayer.stop()
        recordingURL = nil
        recordingStartedAt = nil
        recordingLimit = 0
        nowPlaying = nil
        vlcTitle = nil
        currentProgram = nil
        nextProgram = nil
        stats = PlaybackStatistics()
        refreshEPGPrograms()

        let media = VLCMedia(url: pidOverrides[channel.id] ?? channel.streamURL)
        media.addOption(":network-caching=\(options.networkCachingMs)")
        if options.rtspTCP || forceTCP {
            media.addOption(":rtsp-tcp")
        }
        media.addOption(":input-fast-seek")
        media.addOption(":sout-mux-caching=0")
        media.addOption(":avcodec-hurry-up=1")
        DebugLog.log("Öffne Stream per \(options.rtspTCP || forceTCP ? "TCP" : "UDP"), Puffer \(options.networkCachingMs) ms")
        if options.timeshift {
            prepareRecording()
        }
        mediaPlayer.media = media
        mediaPlayer.setDeinterlaceFilter(options.deinterlace && !channel.isHD ? "yadif" : nil)
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
                if let channel {
                    workingVariant[currentVariantKey] = channel.id
                    onVariantSuccess?(currentVariantKey, channel.id, failedInThisSessionForCurrent)
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
            status = (isReplaying && replayAnchor.paused) ? .paused : .playing
            updatePlaybackStats()
            refreshTrackNames()
            checkStreamHealth()
        } else if !wasPlaying {
            // Solange noch keine sauberen Daten laufen, Audio stummhalten
            mediaPlayer.audio?.isMuted = true
        } else if state == .paused || (isReplaying && replayAnchor.paused) {
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

    /// Überwacht, ob der Live-Stream tatsächlich weiterläuft oder eingefroren ist.
    /// Steht die Anzahl angezeigter Frames bei laufendem Player länger als 3.5 s still,
    /// wird der Stream automatisch und schnell neu verbunden.
    private func checkStreamHealth() {
        guard wasPlaying, status == .playing, !isReplaying, !(replayAnchor.paused) else {
            lastPictureChangeAt = Date()
            return
        }

        // Nicht in den ersten 3 Sekunden nach Verbindungsaufbau prüfen
        guard Date().timeIntervalSince(openedAt) > 3.0 else {
            lastPictureChangeAt = Date()
            return
        }

        if let vlcStats = mediaPlayer.media?.statistics {
            let currentPictures = Int(vlcStats.displayedPictures)
            if currentPictures > lastDisplayedPictures {
                lastDisplayedPictures = currentPictures
                lastPictureChangeAt = Date()
            } else if Date().timeIntervalSince(lastPictureChangeAt) > 3.5 {
                DebugLog.log("Stream eingefroren (keine neuen Bilder seit 3.5 s, Stand: \(currentPictures)) – Reconnect")
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
        if recordingActive {
            mediaPlayer.stopRecording()
            recordingActive = false
        }
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
            self?.start()
        }
    }

    // MARK: Timeshift über Mitschnitt in eine Datei
    //
    // Der Live-Player zeigt das Bild im normalen Dekodiermodus (ohne `:sout`, damit nur eine
    // Tonspur dekodiert wird) und schreibt den Strom gleichzeitig per libVLC-Mitschnitt in eine
    // TS-Datei (eine RTSP-Sitzung, ein Tuner). Anhalten oder Zurückspulen startet den zweiten
    // Player auf dieser Datei; der Live-Player läuft stumm weiter und schreibt mit. „Live“ oder
    // Aufholen bis zum Dateiende schaltet zurück.

    private func prepareRecording() {
        let manager = TimeshiftBufferManager.shared
        manager.cleanup()
        try? FileManager.default.createDirectory(at: manager.bufferDirectory, withIntermediateDirectories: true)
        let limit = manager.recordingLimitBytes()
        guard limit >= 500 * 1024 * 1024 else {
            recordingLimit = 0
            DebugLog.log("Timeshift aus: zu wenig freier Speicher (\(limit / 1_048_576) MB nutzbar)")
            return
        }
        recordingLimit = limit
        lastRecordingCheck = Date()
    }

    private func beginNativeRecording() {
        let manager = TimeshiftBufferManager.shared
        try? FileManager.default.createDirectory(at: manager.bufferDirectory, withIntermediateDirectories: true)
        _ = mediaPlayer.startRecording(atPath: manager.bufferDirectory.path)
        recordingActive = true
        recordingStartedAt = Date()
        lastRecordingCheck = Date()
        DebugLog.log("Timeshift-Mitschnitt gestartet in \(manager.bufferDirectory.lastPathComponent), höchstens \(recordingLimit / 1_048_576) MB")
    }

    var canTimeshift: Bool {
        guard options?.timeshift == true, recordingStartedAt != nil,
              status == .playing || status == .paused else { return false }
        if recordingURL == nil {
            recordingURL = TimeshiftBufferManager.shared.latestRecordingURL()
        }
        guard let url = recordingURL else { return false }
        return TimeshiftBufferManager.shared.fileSize(at: url) > 65_536
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
        }
    }

    // MARK: Progressive Jump
    private var lastJumpPressAt = Date.distantPast
    private var lastJumpForward = true
    private var jumpPressCount = 0
    @Published public private(set) var jumpFeedback: String?
    private var jumpFeedbackTask: Task<Void, Never>?

    public func jumpProgressive(forward: Bool) {
        let step = ProgressiveJump.nextStep(
            forward: forward,
            lastPressAt: &lastJumpPressAt,
            lastDirectionForward: &lastJumpForward,
            pressCount: &jumpPressCount
        )
        jump(seconds: Int(step.stepDelta))
        jumpFeedback = step.displayText
        jumpFeedbackTask?.cancel()
        jumpFeedbackTask = Task {
            try? await Task.sleep(for: .milliseconds(900))
            if !Task.isCancelled {
                await MainActor.run { [weak self] in
                    self?.jumpFeedback = nil
                }
            }
        }
    }

    func jump(seconds: Int) {
        let step = Double(seconds)
        if seconds < 0 {
            if isReplaying {
                let target = max(0, replayPosition + step)
                if replaySeekPending != nil {
                    replaySeekPending = target
                } else {
                    replayPlayer.jumpBackward(Int32(replayPosition - target))
                }
                replayAnchor = (target, Date(), replayAnchor.paused)
            } else if canTimeshift {
                startReplay(behind: -step, paused: false)
            }
        } else if isReplaying {
            if currentBehind <= step + 1 {
                goLive()
            } else {
                let target = replayPosition + step
                if replaySeekPending != nil {
                    replaySeekPending = target
                } else {
                    replayPlayer.jumpForward(Int32(seconds))
                }
                replayAnchor = (target, Date(), replayAnchor.paused)
            }
        }
    }

    func goLive() {
        guard isReplaying else { return }
        DebugLog.log("Timeshift: zurück zu Live")
        stopReplay()
    }

    private func startReplay(behind: Double, paused: Bool) {
        if recordingURL == nil {
            recordingURL = TimeshiftBufferManager.shared.latestRecordingURL()
        }
        guard let url = recordingURL, let options else { return }
        // 1 s Abstand zum Dateiende: VLC puffert, die Datei hinkt dem Bild leicht hinterher.
        let position = max(0, recordedSeconds - behind - 1)
        let media = VLCMedia(url: url)
        media.addOption(":file-caching=300")
        media.addOption(":input-fast-seek")
        replayPlayer.media = media
        replayPlayer.setDeinterlaceFilter(options.deinterlace && channel?.isHD == false ? "yadif" : nil)
        mediaPlayer.audio?.isMuted = true
        replayPlayer.audio?.isMuted = paused
        replayPlayer.play()
        replayAnchor = (position, Date(), paused)
        replaySeekPending = position > 0.5 ? position : nil
        replayPausePending = paused
        replayTracksSynced = false
        replayOpenedAt = Date()
        pausedSince = paused ? Date() : nil
        isReplaying = true
        status = paused ? .paused : .playing
        DebugLog.log("Timeshift: Wiedergabe aus dem Mitschnitt ab \(Int(position)) s (\(Int(behind)) s hinter Live), angehalten=\(paused)")
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
        if wasPlaying {
            mediaPlayer.audio?.isMuted = false
            status = .playing
        }
    }

    /// Läuft mit der Überwachung zweimal pro Sekunde.
    private func pollTimeshift() {
        if recordingActive && recordingURL == nil {
            if let url = TimeshiftBufferManager.shared.latestRecordingURL(),
               TimeshiftBufferManager.shared.fileSize(at: url) > 0 {
                recordingURL = url
                DebugLog.log("Timeshift-Mitschnittdatei erkannt: \(url.lastPathComponent)")
            }
        }

        if isReplaying {
            mediaPlayer.audio?.isMuted = true
            let hasReplayVideo = replayPlayer.hasVideoOut || replayPlayer.videoSize.width > 0
            let hasReplayMedia = hasReplayVideo || replayPlayer.numberOfAudioTracks > 0

            if replayPlayer.isPlaying && hasReplayMedia {
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

            // Bis zum Dateiende aufgeholt: zurück zum Live-Bild.
            let state = replayPlayer.state
            let openingGrace = Date().timeIntervalSince(replayOpenedAt) < 1.5
            if state == .ended || state == .error || (!replayAnchor.paused && !openingGrace && currentBehind < 1) {
                goLive()
            }
        }

        // Größe des Mitschnitts prüfen (alle 10 s).
        guard let url = recordingURL, recordingLimit > 0,
              Date().timeIntervalSince(lastRecordingCheck) > 10 else { return }
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
        var tracks = indexes(mediaPlayer.videoSubTitlesIndexes)
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
