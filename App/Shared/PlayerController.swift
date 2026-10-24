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
}

/// Kapselt VLCKit: Abspielen eines RTSP-Streams der FRITZ!Box, Timeshift-Prototyp,
/// automatisches Neuverbinden, Ton- und Untertitelspuren, „Läuft jetzt“ aus der EIT.
///
/// Statt der VLC-Delegate-Methoden wird der Zustand zweimal pro Sekunde abgefragt.
/// Das ist robuster gegenüber Unterschieden zwischen den VLCKit-Versionen.
@MainActor
final class PlayerController: ObservableObject {
    let mediaPlayer = VLCMediaPlayer()

    @Published private(set) var status: PlayerStatus = .idle
    @Published private(set) var nowPlaying: String?
    @Published private(set) var audioTrackName = "Standard"
    @Published private(set) var subtitleName = "Aus"
    /// Zeitversatz zum Live-Bild aus Sprüngen und beendeten Pausen.
    @Published private(set) var behindLive: TimeInterval = 0
    /// Gesetzt, solange das Bild angehalten ist.
    @Published private(set) var pausedSince: Date?

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
    func play(candidates list: [Channel], options: PlaybackOptions) {
        guard !list.isEmpty else { return }
        var ordered = list
        currentVariantKey = Self.variantKey(list)
        if let known = workingVariant[currentVariantKey], let index = ordered.firstIndex(where: { $0.id == known }) {
            ordered.insert(ordered.remove(at: index), at: 0)
        }
        candidates = ordered
        candidateIndex = 0
        failedCandidates = 0
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
        wasPlaying = false

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
                if let channel { workingVariant[currentVariantKey] = channel.id }
                DebugLog.log("Wiedergabe läuft (\(forceTCP || options?.rtspTCP == true ? "TCP" : "UDP")): Video \(mediaPlayer.videoSize), Tonspuren \(mediaPlayer.audioTrackNames ?? [])")
                selectPreferredAudioTrack()
                // Die Tonverzögerung greift erst, wenn eine Tonspur aktiv ist.
                mediaPlayer.currentAudioPlaybackDelay = (options?.audioDelayMs ?? 0) * 1000
            }
            status = .playing
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
            DebugLog.log("Läuft jetzt: \(title)")
        }
    }

    /// Schlüssel für die gemerkte Variante: Sender plus gewünschte Qualität.
    private static func variantKey(_ list: [Channel]) -> String {
        guard let first = list.first else { return "" }
        return "\(first.kind.rawValue):\(first.groupKey):\(first.isHD)"
    }

    /// Es kam weder Bild noch Ton. Reihenfolge: erst auf TCP wechseln, dann die nächste Variante
    /// des Senders probieren, nach einer vollen Runde wie gewohnt mit Countdown neu verbinden.
    private func handleNoData() {
        if fallBackToTCP() {
            scheduleReconnect(after: 1)
            return
        }
        failedCandidates += 1
        if candidates.count > 1, failedCandidates < candidates.count {
            candidateIndex = (candidateIndex + 1) % candidates.count
            channel = candidates[candidateIndex]
            DebugLog.log("Keine Daten – probiere Variante \(candidateIndex + 1)/\(candidates.count): \(channel?.streamURL.absoluteString ?? "")")
            scheduleReconnect(after: 1)
            return
        }
        failedCandidates = 0
        if candidates.count > 1 {
            candidateIndex = (candidateIndex + 1) % candidates.count
            channel = candidates[candidateIndex]
        }
        scheduleReconnect()
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
        audioTrackName = trackName(current: mediaPlayer.currentAudioTrackIndex,
                                   names: mediaPlayer.audioTrackNames,
                                   indexes: mediaPlayer.audioTrackIndexes) ?? "Standard"
        let subtitle = mediaPlayer.currentVideoSubTitleIndex
        subtitleName = subtitle < 0 ? "Aus" : (trackName(current: subtitle,
                                                         names: mediaPlayer.videoSubTitlesNames,
                                                         indexes: mediaPlayer.videoSubTitlesIndexes) ?? "An")
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
