import Foundation

/// Verwaltet den Ringpuffer für das Timeshift auf dem Speicher (tvOS Cache / macOS).
/// Überwachung des freien Speichers (mind. 200 MB Reserve, max. 50% des freien Platzes),
/// Aufteilung bei Bedarf und automatisches Bereinigen beim Senderwechsel.
public final class TimeshiftBufferManager: @unchecked Sendable {
    public static let shared = TimeshiftBufferManager()

    /// Mindestreserve an freiem Speicher in Bytes (200 MB).
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

    /// Höchstgröße der Mitschnittdatei: 4 GB (FAT32-Grenze), höchstens die
    /// Hälfte des freien Speichers und immer mit 200 MB Reserve. 0 = Timeshift nicht möglich.
    public func recordingLimitBytes() -> Int64 {
        guard let values = try? bufferDirectory.resourceValues(forKeys: [.volumeAvailableCapacityKey]),
              let available = values.volumeAvailableCapacity else {
            return Self.maxSegmentSizeBytes
        }
        return Self.recordingLimit(availableBytes: Int64(available))
    }

    /// Rechenregel für `recordingLimitBytes`, getrennt testbar.
    public static func recordingLimit(availableBytes: Int64) -> Int64 {
        let usable = min(availableBytes / 2, availableBytes - minFreeSpaceReserveBytes)
        return max(0, min(maxSegmentSizeBytes, usable))
    }

    /// Höchstgröße des gesamten Puffers (alle Abschnitte zusammen): höchstens die Hälfte des
    /// freien Speichers und immer mit 200 MB Reserve, ohne 4-GB-Grenze (die gilt je Datei).
    public func bufferLimitBytes() -> Int64 {
        guard let values = try? bufferDirectory.resourceValues(forKeys: [.volumeAvailableCapacityKey]),
              let available = values.volumeAvailableCapacity else {
            return Self.maxSegmentSizeBytes
        }
        return Self.bufferLimit(availableBytes: Int64(available))
    }

    /// Rechenregel für `bufferLimitBytes`, getrennt testbar.
    public static func bufferLimit(availableBytes: Int64) -> Int64 {
        max(0, min(availableBytes / 2, availableBytes - minFreeSpaceReserveBytes))
    }

    /// Größe einer Datei im Puffer (0, wenn es sie nicht gibt).
    public func fileSize(at url: URL) -> Int64 {
        guard let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize else { return 0 }
        return Int64(size)
    }

    /// Liefert die neueste Mitschnittdatei im Pufferverzeichnis (z. B. von `startRecording(atPath:)` angelegt).
    /// `excluding`: Pfade älterer Abschnitte, die nicht mehr beschrieben werden.
    public func latestRecordingURL(excluding: Set<String> = []) -> URL? {
        recordingFiles()
            .filter { !excluding.contains($0.path) }
            .max { a, b in
                let dateA = (try? a.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                let dateB = (try? b.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                return dateA < dateB
            }
    }

    /// Alle Mitschnittdateien (.ts) im Pufferverzeichnis.
    public func recordingFiles() -> [URL] {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: bufferDirectory,
            includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }
        return files.filter { $0.pathExtension.lowercased() == "ts" }
    }

    /// Bereinigt alte Timeshift-Dateien beim Senderwechsel oder Beenden.
    /// `keeping`: Dateien, die erhalten bleiben (z. B. der Abschnitt, der gerade wiedergegeben wird).
    public func cleanup(keeping: Set<String> = []) {
        guard let files = try? FileManager.default.contentsOfDirectory(at: bufferDirectory, includingPropertiesForKeys: nil) else {
            return
        }
        for file in files where !keeping.contains(file.path) {
            try? FileManager.default.removeItem(at: file)
        }
    }

    /// Löscht eine einzelne Datei des Puffers.
    public func remove(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }
}
