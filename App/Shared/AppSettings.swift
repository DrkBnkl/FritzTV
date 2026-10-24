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
    /// Benutzername für die TR-064-Anmeldung (Sendersuchlauf). Das Kennwort liegt im Schlüsselbund.
    @Published var boxUsername: String { didSet { defaults.set(boxUsername, forKey: Keys.boxUsername) } }
    /// Zuletzt gesehene Sender (maximal 3 Schlüssel).
    @Published var recentKeys: [String] { didSet { defaults.set(recentKeys, forKey: Keys.recentKeys) } }
    /// Sender-Varianten (RTSP-URLs), die nachweislich keine Daten liefern.
    @Published var deadChannelIDs: Set<String> { didSet { defaults.set(Array(deadChannelIDs), forKey: Keys.deadChannels) } }
    /// Zuletzt funktionierende Variante je Sender (Variant-Key -> Channel ID).
    @Published var workingVariantIDs: [String: String] { didSet { defaults.set(workingVariantIDs, forKey: Keys.workingVariants) } }

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
            Keys.bannerSeconds: 15,
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
        let storedBanner = defaults.integer(forKey: Keys.bannerSeconds)
        bannerSeconds = storedBanner >= 15 ? storedBanner : 15
        match50Hz = defaults.bool(forKey: Keys.match50Hz)
        press2arrAddress = defaults.string(forKey: Keys.press2arr) ?? ""
        boxUsername = defaults.string(forKey: Keys.boxUsername) ?? ""
        recentKeys = defaults.stringArray(forKey: Keys.recentKeys) ?? []
        deadChannelIDs = Set(defaults.stringArray(forKey: Keys.deadChannels) ?? [])
        workingVariantIDs = defaults.dictionary(forKey: Keys.workingVariants) as? [String: String] ?? [:]
    }

    /// Fügt einen Sender zur Liste der zuletzt gesehenen Sender hinzu (max. 3, ohne Duplikate und ohne den aktuellen).
    func recordRecent(key: String, currentKey: String? = nil) {
        var updated = recentKeys.filter { $0 != key && $0 != currentKey }
        updated.insert(key, at: 0)
        recentKeys = Array(updated.prefix(3))
    }

    func markVariantWorking(variantKey: String, channelID: String) {
        workingVariantIDs[variantKey] = channelID
        deadChannelIDs.remove(channelID)
    }

    func markVariantDead(channelID: String) {
        deadChannelIDs.insert(channelID)
    }

    func resetDeadVariants() {
        deadChannelIDs.removeAll()
        workingVariantIDs.removeAll()
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
        static let boxUsername = "boxUsername"
        static let lastChannel = "lastChannelKey"
        static let lineup = "lineupPreferences"
        static let recentKeys = "recentKeys"
        static let deadChannels = "deadChannels"
        static let workingVariants = "workingVariants"
    }
}

