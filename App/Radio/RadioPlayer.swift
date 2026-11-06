import Foundation
import VLCKitSPM
#if canImport(VLCKit)
import VLCKit
#endif
import FritzTVKit
import os

/// Spielt einen Radiosender der FRITZ!Box über VLCKit. Liefert eine Variante keinen Ton,
/// kommt die nächste dran; reißt der Ton ab, wird neu verbunden. Programminformationen
/// liest der `EITLogParser` aus den Debug-Meldungen von libVLC.
///
/// Wie in FritzTV wird der Zustand zweimal pro Sekunde abgefragt statt über VLC-Delegates.
/// Protokoll in der Konsole (Subsystem `de.home.fritzradio`), z. B. `log stream --predicate 'subsystem == "de.home.fritzradio"'`.
let radioLog = Logger(subsystem: "de.home.fritzradio", category: "Radio")

@MainActor
final class RadioPlayer: ObservableObject {
    enum Status: Equatable {
        case idle
        case connecting
        case playing
        case failed
    }

    private static let library = VLCLibrary(options: ["--no-video", "--no-osd"])

    /// Ohne Ton nach dieser Zeit gilt eine Variante als tot.
    private static let connectTimeout: TimeInterval = 10
    /// Läuft die Wiedergabezeit so lange nicht weiter, wird neu verbunden.
    private static let stallTimeout: TimeInterval = 8
    /// Neue Verbindungsversuche nach einem Abriss, bevor der Sender als gestört gilt.
    private static let maxReconnects = 3

    private let mediaPlayer = VLCMediaPlayer(library: library)
    let epgStore: EPGStore
    private let logReceiver: EITLogReceiver

    @Published private(set) var status: Status = .idle
    /// Zählt hoch, sobald neue Programmdaten eingetroffen sind.
    @Published private(set) var epgRevision = 0
    /// Tonformat des laufenden Senders, sobald libVLC es kennt.
    @Published private(set) var audioFormat: RadioAudioFormat?

    /// Erste Variante mit Ton: `variant` und die vorher gescheiterten Varianten.
    var onVariantSuccess: ((_ variant: Channel, _ failed: [Channel]) -> Void)?
    /// Keine Variante liefert Ton. `silent`: Varianten, die die Box annahm, die aber stumm blieben
    /// (veraltete Einträge). Lehnt die Box ab, sind meist alle Tuner belegt.
    var onAllVariantsFailed: ((_ failed: [Channel], _ silent: [Channel]) -> Void)?

    private(set) var channel: Channel?
    private var candidates: [Channel] = []
    private var failed: [Channel] = []
    private var silent: [Channel] = []
    private var reconnects = 0
    private var openedAt = Date()
    private var lastTime: Int32 = 0
    private var lastTimeChange = Date()
    private var monitorTask: Task<Void, Never>?
    /// Gelesene Bytes über die letzten Sekunden, für die geschätzte Bitrate.
    private var byteSamples: [(date: Date, bytes: Int)] = []

    /// Gewünschte Lautstärke (0–100). Sie wird bei jeder neuen Verbindung erneut gesetzt:
    /// Solange libVLC noch keine Tonausgabe geöffnet hat, geht ein gesetzter Wert sonst verloren.
    var volume = 100 {
        didSet { applyVolume() }
    }

    private func applyVolume() {
        mediaPlayer.audio?.volume = Int32(min(max(volume, 0), 100))
    }

    init(epgCacheURL: URL?) {
        epgStore = EPGStore(cacheURL: epgCacheURL)
        let store = epgStore
        let parser = EITLogParser()
        logReceiver = EITLogReceiver(parser: parser)
        Self.library.loggers = [logReceiver]
        let signal = EPGChangeSignal()
        parser.onServiceName = { [weak self] serviceID, name in
            if store.setServiceName(name, for: serviceID) {
                signal.fire { self?.epgRevision += 1 }
            }
        }
        parser.onProgramParsed = { [weak self] program in
            if store.add(program: program) {
                signal.fire { self?.epgRevision += 1 }
            }
        }
    }

    /// Spielt die Varianten eines Senders der Reihe nach, bis eine Ton liefert.
    func play(candidates list: [Channel]) {
        candidates = list
        failed = []
        silent = []
        reconnects = 0
        startNext()
    }

    func stop() {
        monitorTask?.cancel()
        monitorTask = nil
        mediaPlayer.stop()
        channel = nil
        candidates = []
        status = .idle
        audioFormat = nil
        epgStore.saveToFile()
    }

    private func startNext() {
        guard !candidates.isEmpty else {
            radioLog.notice("Keine Variante liefert Ton (\(self.failed.count) versucht)")
            monitorTask?.cancel()
            monitorTask = nil
            mediaPlayer.stop()
            channel = nil
            status = .failed
            onAllVariantsFailed?(failed, silent)
            return
        }
        open(candidates.removeFirst())
    }

    private func open(_ variant: Channel) {
        channel = variant
        radioLog.notice("Verbinde \(variant.name, privacy: .public): \(variant.streamURL.absoluteString, privacy: .public)")
        let media = VLCMedia(url: variant.streamURL)
        media.addOption(":network-caching=\(variant.networkCachingMilliseconds ?? 1000)")
        mediaPlayer.media = media
        mediaPlayer.play()
        applyVolume()
        openedAt = Date()
        lastTime = 0
        lastTimeChange = Date()
        status = .connecting
        audioFormat = nil
        byteSamples = []
        monitorTask?.cancel()
        monitorTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(500))
                guard !Task.isCancelled else { return }
                self?.check()
            }
        }
    }

    private func check() {
        guard let channel else { return }
        let state = mediaPlayer.state
        let broken = state == .error || state == .ended || state == .stopped
        let now = Date()
        let time = mediaPlayer.time.intValue
        if time != lastTime {
            lastTime = time
            lastTimeChange = now
        }

        switch status {
        case .connecting:
            if mediaPlayer.isPlaying, mediaPlayer.numberOfAudioTracks > 0, time > 0 {
                status = .playing
                applyVolume()
                radioLog.notice("Ton da nach \(now.timeIntervalSince(self.openedAt), format: .fixed(precision: 1)) s")
                reconnects = 0
                onVariantSuccess?(channel, failed)
                failed = []
                silent = []
            } else if broken || now.timeIntervalSince(openedAt) > Self.connectTimeout {
                failed.append(channel)
                if !broken { silent.append(channel) }
                startNext()
            }
        case .playing:
            updateAudioFormat(now: now)
            guard broken || now.timeIntervalSince(lastTimeChange) > Self.stallTimeout else { return }
            // Abriss (Box neu gestartet, WLAN weg, Tuner entzogen): dieselbe Variante erneut, dann aufgeben.
            reconnects += 1
            radioLog.notice("Ton abgerissen, Versuch \(self.reconnects)")
            if reconnects > Self.maxReconnects {
                failed.append(channel)
                startNext()
            } else {
                open(channel)
            }
        case .idle, .failed:
            break
        }
    }
}

extension RadioPlayer {
    /// Codec, Abtastrate und Kanäle aus den Spurinformationen. Die Bitrate meldet libVLC bei
    /// DVB meist nicht, dann wird sie aus den gelesenen Bytes geschätzt.
    private func updateAudioFormat(now: Date) {
        guard let media = mediaPlayer.media else { return }
        let bytes = Int(media.statistics.demuxReadBytes)
        if let last = byteSamples.last, bytes < last.bytes { byteSamples = [] }
        byteSamples.append((now, bytes))
        byteSamples.removeAll { now.timeIntervalSince($0.date) > Self.bitrateWindow }

        let tracks = (media.tracksInformation as? [[String: Any]]) ?? []
        guard let track = tracks.first(where: { $0[VLCMediaTracksInformationType] as? String == VLCMediaTracksInformationTypeAudio }),
              let fourcc = (track[VLCMediaTracksInformationCodec] as? NSNumber)?.uint32Value
        else { return }
        let sampleRate = (track[VLCMediaTracksInformationAudioRate] as? NSNumber)?.intValue ?? 0
        let channels = (track[VLCMediaTracksInformationAudioChannelsNumber] as? NSNumber)?.intValue ?? 0
        var kbps = ((track[VLCMediaTracksInformationBitrate] as? NSNumber)?.intValue ?? 0) / 1000
        var estimated = false
        if kbps <= 0, let first = byteSamples.first, let last = byteSamples.last {
            let seconds = last.date.timeIntervalSince(first.date)
            if seconds >= 3 {
                // Die Demux-Bytes sind die Nutzdaten des Tons (mit ffprobe abgeglichen).
                kbps = Int(Double(last.bytes - first.bytes) * 8 / seconds / 1000)
                estimated = true
            }
        }
        var shown = kbps > 0 ? Self.rounded(kbps) : nil
        // Kleine Schwankungen der Schätzung nicht anzeigen.
        if estimated, let shown0 = shown, let previous = audioFormat?.kilobitsPerSecond, abs(shown0 - previous) <= 8 {
            shown = previous
        }
        let format = RadioAudioFormat(codec: RadioAudioFormat.codecName(fourcc: fourcc), sampleRate: sampleRate,
                                      channels: channels, kilobitsPerSecond: shown, isEstimate: estimated)
        if format != audioFormat {
            audioFormat = format
            radioLog.debug("Tonformat \(format.summary, privacy: .public) (roh \(kbps) kbit/s)")
        }
    }

    private static let bitrateWindow: TimeInterval = 20

    /// Auf 8 kbit/s runden, damit die Anzeige nicht ständig springt.
    private static func rounded(_ kbps: Int) -> Int {
        Int((Double(kbps) / 8).rounded()) * 8
    }
}

/// Tonformat eines Senders, z. B. „AAC · 48 kHz · Stereo · ≈ 256 kbit/s“.
struct RadioAudioFormat: Equatable {
    var codec: String
    var sampleRate: Int
    var channels: Int
    var kilobitsPerSecond: Int?
    var isEstimate: Bool

    var summary: String {
        var parts = [codec]
        if sampleRate > 0 {
            let khz = Double(sampleRate) / 1000
            parts.append(khz == khz.rounded() ? "\(Int(khz)) kHz" : String(format: "%.1f kHz", khz))
        }
        switch channels {
        case 1: parts.append("Mono")
        case 2: parts.append("Stereo")
        case let n where n > 2: parts.append("\(n) Kanäle")
        default: break
        }
        if let kbps = kilobitsPerSecond {
            parts.append("\(isEstimate ? "≈ " : "")\(kbps) kbit/s")
        }
        return parts.joined(separator: " · ")
    }

    /// VLC-FourCC (z. B. `mp4a`, `mpga`) in einen gängigen Namen.
    static func codecName(fourcc: UInt32) -> String {
        let bytes = (0..<4).map { UInt8(truncatingIfNeeded: fourcc >> ($0 * 8)) }
        let code = String(decoding: bytes, as: UTF8.self)
        switch code {
        case "mp4a", "mp4l": return "AAC"
        case "mpga", "mp2a", "mp2 ": return "MP2"
        case "mp3 ": return "MP3"
        case "a52 ": return "AC-3"
        case "eac3": return "E-AC-3"
        case "opus": return "Opus"
        default: return code.trimmingCharacters(in: .whitespaces).uppercased()
        }
    }
}

/// Leitet SDT-/EIT-Meldungen von libVLC an den `EITLogParser` weiter, getrennt je Absender.
private final class EITLogReceiver: NSObject, VLCLogging, @unchecked Sendable {
    var level: VLCLogLevel = .debug
    private let parser: EITLogParser

    init(parser: EITLogParser) {
        self.parser = parser
        super.init()
    }

    func handleMessage(_ message: String, logLevel level: VLCLogLevel, context: VLCLogContext?) {
        guard EITLogParser.isRelevant(message) else { return }
        let source = context.map { Int(truncatingIfNeeded: $0.objectId) } ?? 0
        parser.processLine(message, source: source)
    }
}

/// Die EIT wiederholt sich alle paar Sekunden: höchstens ein Signal pro Sekunde an den Hauptthread.
private final class EPGChangeSignal: @unchecked Sendable {
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
