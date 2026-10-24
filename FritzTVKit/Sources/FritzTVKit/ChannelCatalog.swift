import Foundation

/// Ein Sender aus Sicht der Bedienung: HD- und SD-Variante zusammengefasst.
public struct ChannelGroup: Identifiable, Hashable, Sendable {
    public var id: String { key }
    public let key: String
    public let displayName: String
    /// Alle Varianten, HD zuerst.
    public let variants: [Channel]

    public var hd: Channel? { variants.first { $0.isHD } }
    public var sd: Channel? { variants.first { !$0.isHD } }

    /// Stream, der abgespielt wird. Fällt auf die andere Variante zurück,
    /// wenn die bevorzugte fehlt.
    public func preferredChannel(preferHD: Bool) -> Channel {
        (preferHD ? (hd ?? sd) : (sd ?? hd)) ?? variants[0]
    }

    /// Alle abspielbaren Varianten in der Reihenfolge, in der sie probiert werden:
    /// bevorzugte Qualität zuerst, darin nach Position in der Liste der Box.
    /// Nach einem Sendersuchlauf führt die Box einen Sender oft doppelt, mit alter und neuer
    /// Frequenz. Liefert eine Variante keine Daten, probiert der Player die nächste.
    /// Gleiche Links kommen nur einmal vor.
    public func candidates(preferHD: Bool) -> [Channel] {
        let first = variants.filter { $0.isHD == preferHD }.sorted { $0.position < $1.position }
        let second = variants.filter { $0.isHD != preferHD }.sorted { $0.position < $1.position }
        var seen = Set<String>()
        return (first + second).filter { seen.insert($0.id).inserted }
    }
}

/// Senderliste der App, gebaut aus den M3U-Listen der Box.
public struct ChannelCatalog: Sendable {
    public let groups: [ChannelGroup]

    /// Fasst Einträge mit gleichem `groupKey` zusammen. Die Reihenfolge folgt dem
    /// ersten Auftreten in der Liste der Box, die wiederum HD vor SD sortiert.
    public init(channels: [Channel]) {
        var order: [String] = []
        var buckets: [String: [Channel]] = [:]
        for channel in channels {
            let key = "\(channel.kind.rawValue):\(channel.groupKey)"
            if buckets[key] == nil { order.append(key) }
            buckets[key, default: []].append(channel)
        }
        groups = order.compactMap { key in
            guard let members = buckets[key], let first = members.first else { return nil }
            let sorted = members.sorted { lhs, rhs in
                if lhs.isHD != rhs.isHD { return lhs.isHD }
                return lhs.position < rhs.position
            }
            return ChannelGroup(key: key, displayName: first.displayName, variants: sorted)
        }
    }

    public var tvGroups: [ChannelGroup] { groups.filter { $0.variants[0].kind == .tv } }
    public var radioGroups: [ChannelGroup] { groups.filter { $0.variants[0].kind == .radio } }

    /// Sender je Frequenz. Ein Multiplex kann für den EPG-Abruf mit einem
    /// einzigen Tuner-Zugriff gelesen werden.
    public var channelsByFrequency: [Int: [Channel]] {
        Dictionary(grouping: groups.flatMap(\.variants).filter { $0.tuning != nil }) {
            $0.tuning!.frequencyMHz
        }
    }
}
