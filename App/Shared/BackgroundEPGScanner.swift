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

/// Scannt im Hintergrund andere Multiplex-Frequenzen mit einer unsichtbaren VLC-Instanz ab,
/// um den EPG für alle Sender zu befüllen (Vorbild dream Player TV).
///
/// Läuft nur, wenn danach noch mindestens ein Tuner der FRITZ!Box frei bleibt.
/// Der Abruf nutzt die gemeinsame VLC-Bibliothek; ihr Log-Empfänger trennt die Zeilen
/// je VLC-Objekt, und die SDT jeder Frequenz ordnet die Sendungen allen Sendern darauf zu.
@MainActor
final class BackgroundEPGScanner: ObservableObject {
    @Published private(set) var isScanning = false
    @Published private(set) var currentScanningChannel: String?

    private var scanTask: Task<Void, Never>?
    private var scannedFrequencies: Set<Int> = []
    private var lastScanTime: [Int: Date] = [:]
    private var scannerPlayer: VLCMediaPlayer?

    /// Startet den Hintergrund-Scan für alle Multiplexe, die noch keine Daten haben.
    func startScanIfNeeded(catalog: ChannelCatalog, epgStore: EPGStore, host: String, deadIDs: Set<String> = []) {
        guard !isScanning else { return }

        // Finde alle Frequenzen, für deren Sender noch kein EPG vorliegt
        let unscanned = findUnscannedChannels(catalog: catalog, epgStore: epgStore, deadIDs: deadIDs)
        guard !unscanned.isEmpty else { return }

        isScanning = true
        scanTask = Task { [weak self] in
            guard let self else { return }
            for (freq, channel) in unscanned {
                if Task.isCancelled { break }

                // Prüfen, ob Tuner frei sind
                if let status = await FritzBoxTunerClient().fetchStatus(host: host) {
                    // Der Abruf belegt selbst einen Tuner; danach muss noch einer frei sein
                    // (für andere Geräte im Heimnetz oder einen Senderwechsel).
                    if status.freeCount < 2 {
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

    private func findUnscannedChannels(catalog: ChannelCatalog, epgStore: EPGStore, deadIDs: Set<String>) -> [(frequency: Int, channel: Channel)] {
        var result: [(frequency: Int, channel: Channel)] = []
        var seenFreqs = Set<Int>()

        let now = Date()
        for group in catalog.groups {
            // Varianten ohne Bild (z. B. alte Frequenz nach einem Suchlauf) nicht abrufen.
            guard let channel = group.variants.first(where: { $0.tuning != nil && !deadIDs.contains($0.id) }),
                  let freq = channel.tuning?.frequencyMHz else { continue }

            if seenFreqs.contains(freq) { continue }
            seenFreqs.insert(freq)

            // Prüfen, ob vor kurzem (< 2 Stunden) bereits gescannt
            if let last = lastScanTime[freq], now.timeIntervalSince(last) < 7200 {
                continue
            }

            // Prüfen, ob bereits EPG für diesen Service/Kanal vorliegt
            if epgStore.currentProgram(forChannelNames: group.epgNames, at: now) != nil {
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
