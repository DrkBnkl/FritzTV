import Foundation
import FritzTVKit
import VLCKitSPM
#if canImport(TVVLCKit)
import TVVLCKit
#elseif canImport(MobileVLCKit)
import MobileVLCKit
#elseif canImport(VLCKit)
import VLCKit
#endif

/// Scannt im Hintergrund andere Multiplex-Frequenzen mit einer leisen VLC-Instanz ab,
/// um den EPG für alle Sender schnell und zuverlässig zu befüllen.
///
/// Sicherheit & Performance:
/// 1. Verwendet `epgOnlyStreamURL` (`pids=0,16,17,18,20`): Es fließen weder Bild- noch Tondaten
///    (nur ca. 150 kbit/s statt 15–20 Mbit/s), sodass Audio- und Videowiedergabe des Hauptplayers
///    völlig ungestört bleiben.
/// 2. Priorisiert die Senderliste des Nutzers (Plätze 1, 2, 3…), damit die Lieblingssender
///    innerhalb weniger Sekunden vollständig geladen sind.
/// 3. Überspringt die Frequenz des gerade laufenden Senders (dieser empfängt ohnehin live).
/// 4. Weicht sofort zurück (`yieldIfScanning`), wenn der Hauptplayer auf die gescannte Frequenz umschaltet.
/// 5. Sammelt pro Multiplex nur 5 Sekunden – ausreichend für EIT Schedule und Present/Following.
@MainActor
final class BackgroundEPGScanner: ObservableObject {
    @Published private(set) var isScanning = false
    @Published private(set) var currentScanningChannel: String?
    @Published private(set) var currentScanningFrequency: Int?

    private var scanTask: Task<Void, Never>?
    private var scannedFrequencies: Set<Int> = []
    private var lastScanTime: [Int: Date] = [:]
    private var scannerPlayer: VLCMediaPlayer?

    /// Bricht den aktuellen Frequenz-Scan sofort ab, falls der Hauptplayer auf dieselbe Frequenz umschaltet.
    func yieldIfScanning(frequency: Int) {
        if currentScanningFrequency == frequency {
            DebugLog.log("EPG-Scan weicht für Hauptplayer auf Frequenz \(frequency) MHz")
            scannerPlayer?.stop()
            scannerPlayer = nil
            currentScanningChannel = nil
            currentScanningFrequency = nil
        }
    }

    /// Startet den Hintergrund-Scan für alle Multiplexe, priorisiert nach der Senderliste des Nutzers.
    func startScanIfNeeded(
        lineup: ChannelLineup?,
        catalog: ChannelCatalog,
        epgStore: EPGStore,
        host: String,
        activeFrequency: Int? = nil,
        deadIDs: Set<String> = []
    ) {
        guard !isScanning else { return }

        let unscanned = findUnscannedChannels(
            lineup: lineup,
            catalog: catalog,
            activeFrequency: activeFrequency,
            deadIDs: deadIDs
        )
        guard !unscanned.isEmpty else {
            DebugLog.log("EPG-Hintergrundscan: Alle Frequenzen aktuell")
            return
        }

        isScanning = true
        scanTask = Task { [weak self] in
            guard let self else { return }
            DebugLog.log("Starte EPG-Hintergrundscan für \(unscanned.count) Multiplexe")

            for (freq, channel) in unscanned {
                if Task.isCancelled { break }

                // Überspringen, falls der Hauptplayer inzwischen auf diese Frequenz gewechselt hat
                if let active = activeFrequency, active == freq {
                    continue
                }

                // Prüfen, ob genügend Tuner der FRITZ!Box frei sind (mind. 2 bei Multi-Tuner-Boxen, damit andere Haushaltsmitglieder nicht blockiert werden)
                if let status = await FritzBoxTunerClient().fetchStatus(host: host) {
                    let requiredFree = status.totalTuners > 1 ? 2 : 1
                    if status.freeCount < requiredFree {
                        DebugLog.log("EPG-Hintergrundscan pausiert: nicht genügend freie Tuner (\(status.freeCount) frei, benötigt \(requiredFree) von \(status.totalTuners))")
                        break
                    }
                }

                await self.scanChannel(channel: channel, frequency: freq)

                // Kurze Pause zwischen den Frequenzen (250 ms)
                try? await Task.sleep(for: .milliseconds(250))
            }

            self.isScanning = false
            self.currentScanningChannel = nil
            self.currentScanningFrequency = nil
            DebugLog.log("EPG-Hintergrundscan beendet")
        }
    }

    func stop() {
        scanTask?.cancel()
        scanTask = nil
        scannerPlayer?.stop()
        scannerPlayer = nil
        isScanning = false
        currentScanningChannel = nil
        currentScanningFrequency = nil
    }

    private func findUnscannedChannels(
        lineup: ChannelLineup?,
        catalog: ChannelCatalog,
        activeFrequency: Int?,
        deadIDs: Set<String>
    ) -> [(frequency: Int, channel: Channel)] {
        var result: [(frequency: Int, channel: Channel)] = []
        var seenFreqs = Set<Int>()
        let now = Date()

        // 1. Zuerst die Sender aus der Senderliste des Nutzers (Favoriten / Plätze 1, 2, 3...)
        if let entries = lineup?.entries {
            for entry in entries {
                let preferred = entry.group.preferredChannel(preferHD: true)
                guard let freq = preferred.tuning?.frequencyMHz,
                      !deadIDs.contains(preferred.id) else { continue }

                if seenFreqs.contains(freq) { continue }
                seenFreqs.insert(freq)

                if let active = activeFrequency, active == freq { continue }
                if let last = lastScanTime[freq], now.timeIntervalSince(last) < 7200 { continue }

                result.append((freq, preferred))
            }
        }

        // 2. Anschließend alle übrigen Multiplexe aus dem Gesamtkatalog
        for group in catalog.groups {
            guard let channel = group.variants.first(where: { $0.tuning != nil && !deadIDs.contains($0.id) }),
                  let freq = channel.tuning?.frequencyMHz else { continue }

            if seenFreqs.contains(freq) { continue }
            seenFreqs.insert(freq)

            if let active = activeFrequency, active == freq { continue }
            if let last = lastScanTime[freq], now.timeIntervalSince(last) < 7200 { continue }

            result.append((freq, channel))
        }

        return result
    }

    private func scanChannel(channel: Channel, frequency: Int) async {
        self.currentScanningChannel = channel.name
        self.currentScanningFrequency = frequency
        DebugLog.log("EPG-Scan auf \(channel.name) (\(frequency) MHz)")

        let player = VLCMediaPlayer()
        let epgURL = channel.epgOnlyStreamURL
        let media = VLCMedia(url: epgURL)
        media.addOption(":no-video")
        media.addOption(":no-audio")
        media.addOption(":no-spu")
        media.addOption(":network-caching=300")
        player.media = media

        self.scannerPlayer = player
        player.play()

        // 5 Sekunden sammeln (reicht für EIT-Schedule und Present/Following des Multiplex)
        try? await Task.sleep(for: .seconds(5))

        player.stop()
        self.scannerPlayer = nil
        self.scannedFrequencies.insert(frequency)
        self.lastScanTime[frequency] = Date()
    }
}
