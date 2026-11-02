import Foundation

/// Die Radiosender der Box. Sie stehen bewusst außerhalb von `ChannelLineup`: Radio bekommt keine
/// Senderplätze und taucht beim Umschalten, in der Direktwahl und im EPG nicht auf.
public struct RadioStations: Sendable {
    /// Maximale Länge der Liste „Zuletzt gehört“.
    public static let recentLimit = 3

    /// Alle Radiosender in der Reihenfolge der Box.
    public let all: [ChannelGroup]

    public init(catalog: ChannelCatalog? = nil) {
        all = catalog?.radioGroups ?? []
    }

    /// Zuletzt gehörte Sender, soweit es sie noch gibt.
    public func recent(keys: [String]) -> [ChannelGroup] {
        keys.prefix(Self.recentLimit).compactMap { key in all.first { $0.key == key } }
    }

    /// Nächster Sender in Umschaltrichtung, am Listenende geht es von vorn weiter.
    public func station(after current: ChannelGroup, step: Int) -> ChannelGroup? {
        guard !all.isEmpty else { return nil }
        let index = all.firstIndex(of: current) ?? 0
        return all[(index + step % all.count + all.count) % all.count]
    }

    /// Neue Liste „Zuletzt gehört“ mit `key` an erster Stelle, ohne Dubletten.
    public static func recording(key: String, in keys: [String]) -> [String] {
        Array(([key] + keys.filter { $0 != key }).prefix(recentLimit))
    }
}
