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
        // Nur unkritische Zeichen im Dateinamen (er landet ungeschützt in der sout-Option).
        let safeKey = String(channelKey.map { $0.isLetter || $0.isNumber || $0 == "-" ? $0 : "_" })
        let filename = "timeshift_\(safeKey)_\(timestamp).ts"
        return bufferDirectory.appendingPathComponent(filename)
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

    /// libVLC-Option: Bild anzeigen und gleichzeitig den Rohstream in eine TS-Datei schreiben
    /// (eine RTSP-Sitzung, ein Tuner).
    public static func soutDisplayAndRecordOption(destination: URL) -> String {
        ":sout=#duplicate{dst=display,dst=std{access=file,mux=ts,dst=\(destination.path)}}"
    }

    /// Erzeugt die libVLC-Option für das Speichern des Rohstreams in eine TS-Datei.
    public static func soutOption(destination: URL) -> String {
        ":sout=#duplicate{dst=std{access=file,mux=ts,dst=\(destination.path)}}"
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
