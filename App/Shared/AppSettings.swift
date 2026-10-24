import Foundation

/// Einstellungen der App, gespeichert in UserDefaults.
final class AppSettings: ObservableObject {
    private let defaults: UserDefaults

    /// Leer = automatisch (fritz.box, dann 192.168.178.1).
    @Published var host: String { didSet { defaults.set(host, forKey: Keys.host) } }
    @Published var preferHD: Bool { didSet { defaults.set(preferHD, forKey: Keys.preferHD) } }
    /// Netzwerkpuffer in ms, 0 = automatisch (LAN 500, sonst 1000).
    @Published var networkCaching: Int { didSet { defaults.set(networkCaching, forKey: Keys.networkCaching) } }
    @Published var rtspTCP: Bool { didSet { defaults.set(rtspTCP, forKey: Keys.rtspTCP) } }
    @Published var deinterlaceSD: Bool { didSet { defaults.set(deinterlaceSD, forKey: Keys.deinterlaceSD) } }
    @Published var audioDelayMs: Int { didSet { defaults.set(audioDelayMs, forKey: Keys.audioDelayMs) } }
    @Published var timeshift: Bool { didSet { defaults.set(timeshift, forKey: Keys.timeshift) } }
    @Published var bannerSeconds: Int { didSet { defaults.set(bannerSeconds, forKey: Keys.bannerSeconds) } }
    /// Adresse von press2arr („Lichtspiel“) auf der NAS für die Mediathek-Seite.
    @Published var press2arrAddress: String { didSet { defaults.set(press2arrAddress, forKey: Keys.press2arr) } }
    /// Nur Apple TV: Bildwiederholrate auf 50 Hz umschalten.
    @Published var match50Hz: Bool { didSet { defaults.set(match50Hz, forKey: Keys.match50Hz) } }

    var lastChannelKey: String? {
        get { defaults.string(forKey: Keys.lastChannel) }
        set { defaults.set(newValue, forKey: Keys.lastChannel) }
    }

    var lineupData: Data? {
        get { defaults.data(forKey: Keys.lineup) }
        set { defaults.set(newValue, forKey: Keys.lineup) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [
            Keys.preferHD: true,
            Keys.networkCaching: 0,
            Keys.rtspTCP: false,
            Keys.deinterlaceSD: true,
            Keys.audioDelayMs: -125,
            Keys.timeshift: true,
            Keys.bannerSeconds: 7,
            Keys.match50Hz: true,
            Keys.press2arr: "192.168.178.99:5056"
        ])
        host = defaults.string(forKey: Keys.host) ?? ""
        preferHD = defaults.bool(forKey: Keys.preferHD)
        networkCaching = defaults.integer(forKey: Keys.networkCaching)
        rtspTCP = defaults.bool(forKey: Keys.rtspTCP)
        deinterlaceSD = defaults.bool(forKey: Keys.deinterlaceSD)
        audioDelayMs = defaults.integer(forKey: Keys.audioDelayMs)
        timeshift = defaults.bool(forKey: Keys.timeshift)
        bannerSeconds = defaults.integer(forKey: Keys.bannerSeconds)
        match50Hz = defaults.bool(forKey: Keys.match50Hz)
        press2arrAddress = defaults.string(forKey: Keys.press2arr) ?? ""
    }

    private enum Keys {
        static let host = "host"
        static let preferHD = "preferHD"
        static let networkCaching = "networkCaching"
        static let rtspTCP = "rtspTCP"
        static let deinterlaceSD = "deinterlaceSD"
        static let audioDelayMs = "audioDelayMs"
        static let timeshift = "timeshift"
        static let bannerSeconds = "bannerSeconds"
        static let match50Hz = "match50Hz"
        static let press2arr = "press2arrAddress"
        static let lastChannel = "lastChannelKey"
        static let lineup = "lineupPreferences"
    }
}

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
