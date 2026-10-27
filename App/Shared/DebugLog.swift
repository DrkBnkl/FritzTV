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
        #elseif targetEnvironment(simulator) && DEBUG
        // Apple-TV-Simulator: ins Projektverzeichnis auf dem Mac schreiben (für UI-Tests).
        guard let home = ProcessInfo.processInfo.environment["SIMULATOR_HOST_HOME"] else { return nil }
        let folder = URL(fileURLWithPath: home).appendingPathComponent("coding/FritzTV", isDirectory: true)
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

#if DEBUG
/// Nur Debug-Builds: meldet im Log, wenn der Hauptthread länger als eine Sekunde nicht reagiert.
/// Hilft bei eingefrorenem Bild (VLC braucht den Hauptthread für die Bildausgabe).
enum MainThreadWatchdog {
    private static var started = false

    static func start() {
        guard !started else { return }
        started = true
        let thread = Thread {
            var stalledSince: Date?
            while true {
                let answered = DispatchSemaphore(value: 0)
                DispatchQueue.main.async { answered.signal() }
                if answered.wait(timeout: .now() + 1.0) == .timedOut {
                    let since = stalledSince ?? Date().addingTimeInterval(-1)
                    stalledSince = since
                    DebugLog.log("Hauptthread blockiert seit \(String(format: "%.0f", Date().timeIntervalSince(since))) s")
                    answered.wait()
                    DebugLog.log("Hauptthread wieder frei nach \(String(format: "%.1f", Date().timeIntervalSince(since))) s")
                    stalledSince = nil
                }
                Thread.sleep(forTimeInterval: 0.5)
            }
        }
        thread.name = "MainThreadWatchdog"
        thread.start()
    }
}
#endif
