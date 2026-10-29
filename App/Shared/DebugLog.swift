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

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()

    static func log(_ message: String) {
        let line = "\(timeFormatter.string(from: Date())) \(message)\n"
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

/// Meldet im Log, wenn der Hauptthread (Fernbedienung, Oberfläche) länger als 0,2 s nicht
/// reagiert. Nur in Debug-Builds aktiv, damit im Release-Betrieb der Hauptthread nicht
/// 10× pro Sekunde aufgeweckt wird.
enum MainThreadWatchdog {
    #if DEBUG
    private static var started = false
    #endif

    static func start() {
        #if DEBUG
        guard !started else { return }
        started = true
        let thread = Thread {
            while true {
                let answered = DispatchSemaphore(value: 0)
                let sent = Date()
                DispatchQueue.main.async { answered.signal() }
                if answered.wait(timeout: .now() + 0.2) == .timedOut {
                    answered.wait()
                    let ms = Int(Date().timeIntervalSince(sent) * 1000)
                    DebugLog.log("Hauptthread blockiert: \(ms) ms")
                }
                Thread.sleep(forTimeInterval: 0.1)
            }
        }
        thread.name = "MainThreadWatchdog"
        thread.qualityOfService = .utility
        thread.start()
        #endif
    }
}
