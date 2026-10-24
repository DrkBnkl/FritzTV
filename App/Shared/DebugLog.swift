import Foundation

/// Einfaches Protokoll für Tests. Schreibt in die Xcode-Konsole und – nur in Debug-Builds auf dem Mac –
/// zusätzlich nach ~/coding/FritzTV/debug.log (wird bei jedem Start geleert).
enum DebugLog {
    private static let queue = DispatchQueue(label: "fritztv.debuglog")

    private static let fileURL: URL? = {
        #if os(macOS) && DEBUG
        let folder = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("coding/FritzTV", isDirectory: true)
        guard FileManager.default.fileExists(atPath: folder.path) else { return nil }
        let url = folder.appendingPathComponent("debug.log")
        try? Data().write(to: url)
        return url
        #else
        return nil
        #endif
    }()

    static func log(_ message: String) {
        let line = "\(Date().formatted(date: .omitted, time: .standard)) \(message)\n"
        print(line, terminator: "")
        guard let url = fileURL else { return }
        queue.async {
            guard let handle = try? FileHandle(forWritingTo: url) else { return }
            handle.seekToEndOfFile()
            handle.write(Data(line.utf8))
            try? handle.close()
        }
    }
}
