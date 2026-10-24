import Foundation
import FritzTVKit
#if os(tvOS)
import TVVLCKit
#else
import VLCKit
#endif

/// Scannt im Hintergrund andere Multiplex-Frequenzen mit einer unsichtbaren VLC-Instanz ab,
/// um den EPG für alle Sender zu befüllen (Vorbild dream Player TV).
///
/// Läuft nur, wenn mindestens ein freier Tuner an der FRITZ!Box verfügbar ist.
@MainActor
final class BackgroundEPGScanner: ObservableObject {
    @Published private(set) var isScanning = false
    @Published private(set) var currentScanningChannel: String?

    private var scanTask: Task<Void, Never>?
    private var scannedFrequencies: Set<Int> = []
    private var lastScanTime: [Int: Date] = [:]
    private var scannerPlayer: VLCMediaPlayer?

    /// Startet den Hintergrund-Scan für alle Multiplexe, die noch keine Daten haben.
    func startScanIfNeeded(catalog: ChannelCatalog, epgStore: EPGStore, host: String) {
        guard !isScanning else { return }

        // Finde alle Frequenzen, für deren Sender noch kein EPG vorliegt
        let unscanned = findUnscannedChannels(catalog: catalog, epgStore: epgStore)
        guard !unscanned.isEmpty else { return }

        isScanning = true
        scanTask = Task { [weak self] in
            guard let self else { return }
            for (freq, channel) in unscanned {
                if Task.isCancelled { break }

                // Prüfen, ob Tuner frei sind
                if let status = await FritzBoxTunerClient().fetchStatus(host: host) {
                    // Mindestens 1 Tuner muss für Live-TV frei bleiben
                    if status.freeCount < 1 {
                        DebugLog.log("EPG-Hintergrundscan pausiert: keine freien Tuner")
                        break
                    }
                }

                await self.scanChannel(channel: channel, frequency: freq)

                // Kurze Pause zwischen Frequenzwechseln
                try? await Task.sleep(for: .seconds(3))
            }
            self.isScanning = false
            self.currentScanningChannel = nil
        }
    }

    func stop() {
        scanTask?.cancel()
        scanTask = nil
        scannerPlayer?.stop()
        scannerPlayer = nil
        isScanning = false
        currentScanningChannel = nil
    }

    private func findUnscannedChannels(catalog: ChannelCatalog, epgStore: EPGStore) -> [(frequency: Int, channel: Channel)] {
        var result: [(frequency: Int, channel: Channel)] = []
        var seenFreqs = Set<Int>()

        let now = Date()
        for group in catalog.groups {
            guard let channel = group.variants.first(where: { $0.tuning?.frequencyMHz != nil }) ?? group.variants.first,
                  let freq = channel.tuning?.frequencyMHz else { continue }

            if seenFreqs.contains(freq) { continue }
            seenFreqs.insert(freq)

            // Prüfen, ob vor kurzem (< 2 Stunden) bereits gescannt
            if let last = lastScanTime[freq], now.timeIntervalSince(last) < 7200 {
                continue
            }

            // Prüfen, ob bereits EPG für diesen Service/Kanal vorliegt
            if let serviceID = epgStore.serviceID(for: group.key),
               epgStore.schedule(for: serviceID)?.currentProgram(at: now) != nil {
                continue
            }

            result.append((freq, channel))
        }
        return result
    }

    private func scanChannel(channel: Channel, frequency: Int) async {
        self.currentScanningChannel = channel.name
        DebugLog.log("Starte EPG-Hintergrundscan auf \(channel.name) (\(frequency) MHz)")

        let player = VLCMediaPlayer()
        let media = VLCMedia(url: channel.streamURL)
        media.addOption(":no-video")
        media.addOption(":no-audio")
        media.addOption(":no-spu")
        media.addOption(":codec=none")
        media.addOption(":network-caching=500")
        player.media = media

        self.scannerPlayer = player
        player.play()

        // 12 Sekunden sammeln
        try? await Task.sleep(for: .seconds(12))

        player.stop()
        self.scannerPlayer = nil
        self.scannedFrequencies.insert(frequency)
        self.lastScanTime[frequency] = Date()
        DebugLog.log("EPG-Hintergrundscan für \(channel.name) beendet")
    }
}
