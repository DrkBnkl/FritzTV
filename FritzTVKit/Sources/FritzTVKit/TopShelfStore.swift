import Foundation

/// Ein kompakter Sendereintrag für die Apple TV Top Shelf Erweiterung.
public struct TopShelfChannel: Codable, Sendable, Identifiable, Hashable {
    public let number: Int
    public let name: String
    public let groupKey: String
    public let isHD: Bool

    public var id: Int { number }

    public init(number: Int, name: String, groupKey: String, isHD: Bool) {
        self.number = number
        self.name = name
        self.groupKey = groupKey
        self.isHD = isHD
    }

    /// URL zum Senderlogo auf dem AVM-Server als Vorschau für Top Shelf.
    public var logoURL: URL? { ChannelLogo.url(for: name) }
}

/// Verwaltet die Ablage der Favoriten / Top-Sender für tvOS Top Shelf.
public struct TopShelfStore: Sendable {
    public static let sharedSuiteName = "group.de.home.fritztv"
    public static let userDefaultsKey = "FritzTV.TopShelfChannels"

    /// Standardliste der wichtigsten öffentlich-rechtlichen Sender als sicherer Rückfall.
    public static let defaultChannels: [TopShelfChannel] = [
        TopShelfChannel(number: 1, name: "Das Erste HD", groupKey: "das-erste", isHD: true),
        TopShelfChannel(number: 2, name: "ZDF HD", groupKey: "zdf", isHD: true),
        TopShelfChannel(number: 3, name: "rbb Berlin HD", groupKey: "rbb-berlin", isHD: true),
        TopShelfChannel(number: 4, name: "arte HD", groupKey: "arte", isHD: true),
        TopShelfChannel(number: 5, name: "3sat HD", groupKey: "3sat", isHD: true),
        TopShelfChannel(number: 6, name: "KiKA HD", groupKey: "kika", isHD: true),
        TopShelfChannel(number: 7, name: "phoenix HD", groupKey: "phoenix", isHD: true),
        TopShelfChannel(number: 8, name: "ZDFneo HD", groupKey: "zdfneo", isHD: true)
    ]

    public static func save(channels: [TopShelfChannel]) {
        guard let data = try? JSONEncoder().encode(channels) else { return }
        UserDefaults.standard.set(data, forKey: userDefaultsKey)
        if let groupDefaults = UserDefaults(suiteName: sharedSuiteName) {
            groupDefaults.set(data, forKey: userDefaultsKey)
        }
    }

    public static func load() -> [TopShelfChannel] {
        if let groupDefaults = UserDefaults(suiteName: sharedSuiteName),
           let data = groupDefaults.data(forKey: userDefaultsKey),
           let channels = try? JSONDecoder().decode([TopShelfChannel].self, from: data),
           !channels.isEmpty {
            return channels
        }
        if let data = UserDefaults.standard.data(forKey: userDefaultsKey),
           let channels = try? JSONDecoder().decode([TopShelfChannel].self, from: data),
           !channels.isEmpty {
            return channels
        }
        return defaultChannels
    }
}
