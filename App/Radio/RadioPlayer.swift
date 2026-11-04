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

    var volume: Int {
        get { Int(mediaPlayer.audio?.volume ?? 100) }
        set { mediaPlayer.audio?.volume = Int32(min(max(newValue, 0), 100)) }
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
        openedAt = Date()
        lastTime = 0
        lastTimeChange = Date()
        status = .connecting
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
