import Foundation

/// Verwaltet den Ringpuffer für das Timeshift auf dem Speicher (tvOS Cache / macOS).
/// Vorbild dream Player TV: Überwachung des freien Speichers (mind. 200 MB Reserve, max. 50% des freien Platzes),
/// Aufteilung bei Bedarf und automatisches Bereinigen beim Senderwechsel.
public final class TimeshiftBufferManager: @unchecked Sendable {
    public static let shared = TimeshiftBufferManager()

    /// Mindestreserve an freiem Speicher in Bytes (200 MB wie im dream Player).
    public static let minFreeSpaceReserveBytes: Int64 = 200 * 1024 * 1024
    /// Maximale Dateigröße für ein TS-Segment (4 GB FAT32-Grenze).
    public static let maxSegmentSizeBytes: Int64 = 4 * 1024 * 1024 * 1024

    public var bufferDirectory: URL {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        return caches.appendingPathComponent("Timeshift", isDirectory: true)
    }

    public init() {
        try? FileManager.default.createDirectory(at: bufferDirectory, withIntermediateDirectories: true)
    }

    /// Prüft, ob genügend freier Speicher vorhanden ist, um Timeshift sicher zu betreiben.
    public func checkStorageSafety() -> (isSafe: Bool, availableMB: Int, reason: String?) {
        guard let values = try? bufferDirectory.resourceValues(forKeys: [.volumeAvailableCapacityKey, .volumeTotalCapacityKey]),
              let available = values.volumeAvailableCapacity else {
            return (true, 1000, nil)
        }

        let availableBytes = Int64(available)
        let availableMB = Int(availableBytes / (1024 * 1024))

        if availableBytes < Self.minFreeSpaceReserveBytes {
            return (false, availableMB, "Zu wenig Speicher frei (\(availableMB) MB verfügbar, mind. 200 MB Reserve erforderlich).")
        }

        return (true, availableMB, nil)
    }

    /// Berechnet die aktuelle Größe aller Timeshift-Aufnahmedateien im Puffer.
    public func currentBufferSizeInBytes() -> Int64 {
        guard let files = try? FileManager.default.contentsOfDirectory(at: bufferDirectory, includingPropertiesForKeys: [.fileSizeKey]) else {
            return 0
        }
        var total: Int64 = 0
        for file in files {
            if let size = (try? file.resourceValues(forKeys: [.fileSizeKey]))?.fileSize {
                total += Int64(size)
            }
        }
        return total
    }

    /// Neuer Pfad für eine Timeshift-Aufnahmedatei eines Senders.
    public func newSegmentURL(channelKey: String) -> URL {
        let timestamp = Int(Date().timeIntervalSince1970)
        let filename = "timeshift_\(channelKey)_\(timestamp).ts"
        return bufferDirectory.appendingPathComponent(filename)
    }

    /// Erzeugt die libVLC-Option für das Speichern des Rohstreams in eine TS-Datei.
    public static func soutOption(destination: URL) -> String {
        ":sout=#duplicate{dst=std{access=file,mux=ts,dst=\(destination.path)}}"
    }

    /// Bereinigt alte Timeshift-Dateien beim Senderwechsel oder Beenden.
    public func cleanup() {
        guard let files = try? FileManager.default.contentsOfDirectory(at: bufferDirectory, includingPropertiesForKeys: nil) else {
            return
        }
        for file in files {
            try? FileManager.default.removeItem(at: file)
        }
    }
}
