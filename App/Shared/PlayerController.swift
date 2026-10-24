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
    @Published private(set) var audioTrackName = "Standard"
    @Published private(set) var subtitleName = "Aus"
    @Published private(set) var hasSubtitles = false
    @Published private(set) var stats = PlaybackStatistics()
    /// Zeitversatz zum Live-Bild aus Sprüngen und beendeten Pausen.
    @Published private(set) var behindLive: TimeInterval = 0
    /// Gesetzt, solange das Bild angehalten ist.
    @Published private(set) var pausedSince: Date?

    var onVariantSuccess: ((_ variantKey: String, _ channelID: String, _ failedEarlierIDs: [String]) -> Void)?
    var onAllCandidatesFailed: ((_ channelName: String) -> Void)?

    init(epgStore: EPGStore = EPGStore()) {
        self.epgStore = epgStore
        let parser = EITLogParser()
        self.epgParser = parser

        parser.onProgramParsed = { [weak self] program in
            Task { @MainActor in
                self?.handleParsedProgram(program)
            }
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
    /// Variante, die in dieser Sitzung zuletzt Bild geliefert hat, je Sender.
    private var workingVariant: [String: String] = [:]
    private var currentVariantKey = ""

    private var timeshiftDirectory: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Timeshift", isDirectory: true)
    }

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
        reconnectTask?.cancel()
        reconnectTask = nil
        start()
    }

    func stop() {
        monitorTask?.cancel()
        reconnectTask?.cancel()
        reconnectTask = nil
        mediaPlayer.stop()
        status = .idle
        wasPlaying = false
    }

    func setFailed(title: String, message: String, hint: String? = nil) {
        monitorTask?.cancel()
        reconnectTask?.cancel()
        reconnectTask = nil
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
        behindLive = 0
        pausedSince = nil
        nowPlaying = nil
        currentProgram = nil
        nextProgram = nil
        wasPlaying = false
        stats = PlaybackStatistics()
        refreshEPGPrograms()

        let media = VLCMedia(url: channel.streamURL)
        media.addOption(":network-caching=\(options.networkCachingMs)")
        if options.rtspTCP || forceTCP {
            media.addOption(":rtsp-tcp")
        }
        DebugLog.log("Öffne Stream per \(options.rtspTCP || forceTCP ? "TCP" : "UDP"), Puffer \(options.networkCachingMs) ms")
        if options.timeshift {
            try? FileManager.default.createDirectory(at: timeshiftDirectory, withIntermediateDirectories: true)
            media.addOption(":input-timeshift-path=\(timeshiftDirectory.path)")
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
           !title.isEmpty, title != nowPlaying {
            nowPlaying = title
            refreshEPGPrograms()
            DebugLog.log("Läuft jetzt: \(title)")
        }
    }

    private func handleParsedProgram(_ program: EPGProgram) {
        epgStore.add(program: program)
        if let current = channel {
            if program.isRunningStatus || (nowPlaying != nil && program.title.localizedCaseInsensitiveContains(nowPlaying!)) {
                epgStore.associate(channelKey: current.groupKey, serviceID: program.serviceID)
            }
            if epgStore.serviceID(for: current.groupKey) == program.serviceID {
                refreshEPGPrograms()
            }
        }
    }

    func refreshEPGPrograms() {
        guard let current = channel else { return }
        currentProgram = epgStore.currentProgram(forChannelKey: current.groupKey)
        nextProgram = epgStore.nextProgram(forChannelKey: current.groupKey)
        if let current = currentProgram, nowPlaying == nil {
            nowPlaying = current.title
        }
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
        
        // Alle Varianten wurden erfolglos probiert
        let channelName = channel?.displayName ?? "Sender"
        DebugLog.log("Keine Variante von \(channelName) liefert Bild.")
        onAllCandidatesFailed?(channelName)
        setFailed(
            title: "Kein Bild für \(channelName)",
            message: "Senderliste veraltet – Suchlauf starten",
            hint: "Bitte in der FRITZ!Box-Oberfläche unter DVB-C einen Sendersuchlauf starten."
        )
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

    // MARK: Timeshift (Prototyp mit dem eingebauten Timeshift von VLC)

    var canTimeshift: Bool {
        options?.timeshift == true && (status == .playing || status == .paused)
    }

    /// Aktueller Rückstand zum Live-Bild in Sekunden.
    var currentBehind: TimeInterval {
        behindLive + (pausedSince.map { Date().timeIntervalSince($0) } ?? 0)
    }

    var isTimeshifted: Bool { pausedSince != nil || behindLive > 0.5 }

    func togglePause() {
        guard canTimeshift else { return }
        if let since = pausedSince {
            behindLive += Date().timeIntervalSince(since)
            pausedSince = nil
            mediaPlayer.play()
        } else {
            pausedSince = Date()
            mediaPlayer.pause()
        }
    }

    func jump(seconds: Int) {
        guard canTimeshift else { return }
        if seconds < 0 {
            mediaPlayer.jumpBackward(Int32(-seconds))
            behindLive += Double(-seconds)
        } else if currentBehind <= Double(seconds) {
            goLive()
        } else {
            mediaPlayer.jumpForward(Int32(seconds))
            behindLive -= Double(seconds)
        }
    }

    func goLive() {
        guard isTimeshifted else { return }
        restart()
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
            newStats.inputBitrateMbps = (Double(vlcStats.inputBitrate) * 8.0) / 1_000_000.0
            newStats.demuxBitrateMbps = (Double(vlcStats.demuxBitrate) * 8.0) / 1_000_000.0
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
