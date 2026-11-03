import Foundation

/// Abschnitt der Radioliste.
public struct RadioListSection: Identifiable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let stations: [ChannelGroup]
}

/// Die Radiosender der Box. Sie stehen bewusst außerhalb von `ChannelLineup`: Radio bekommt keine
/// Senderplätze und taucht beim Umschalten, in der Direktwahl und im EPG nicht auf.
public struct RadioStations: Sendable {
    /// Maximale Länge der Liste „Zuletzt gehört“.
    public static let recentLimit = 3

    /// Alle Radiosender, nach Senderfamilien sortiert, darin in der Reihenfolge der Box.
    public let all: [ChannelGroup]

    public init(catalog: ChannelCatalog? = nil) {
        let merged = Self.merged(catalog?.radioGroups ?? [])
        all = Self.families.indices.flatMap { index in
            merged.filter { Self.familyIndex(of: $0.displayName) == index }
        }
    }

    /// Die Box führt denselben Sender oft mehrfach und verschieden geschrieben („BAYERN 3“/„Bayern 3“,
    /// „Antenne Brbg.“/„Antenne Brandenburg“), meist mit alter und neuer Frequenz. Zusammengefasst
    /// ist die Liste kürzer, und der Player probiert bei einem toten Eintrag die anderen.
    private static func merged(_ groups: [ChannelGroup]) -> [ChannelGroup] {
        var order: [String] = []
        var buckets: [String: [ChannelGroup]] = [:]
        for group in groups {
            let key = mergeKey(group.displayName)
            if buckets[key] == nil { order.append(key) }
            buckets[key, default: []].append(group)
        }
        return order.compactMap { key in
            guard let members = buckets[key], let first = members.first else { return nil }
            if members.count == 1 { return first }
            let names = members.map { $0.displayName.split(whereSeparator: \.isWhitespace).joined(separator: " ") }
            return ChannelGroup(key: first.key,
                                displayName: names.max { $0.count < $1.count } ?? first.displayName,
                                variants: members.flatMap(\.variants))
        }
    }

    private static func mergeKey(_ name: String) -> String {
        let plain = name.lowercased().filter { $0.isLetter || $0.isNumber }
        let aliases = ["antennebrbg": "antennebrandenburg", "swr4rheinhessen": "swr4rp"]
        return aliases[plain] ?? plain
    }

    // MARK: Senderfamilien

    /// Titel und Namensanfänge je Familie; was nirgends passt, kommt in den letzten Eintrag.
    private static let families: [(title: String, prefixes: [String])] = [
        ("WDR", ["1live", "cosmo", "die maus", "wdr"]),
        ("NDR", ["ndr", "n-joy"]),
        ("SWR", ["swr", "dasding"]),
        ("BR", ["bayern", "br24", "br-", "br ", "puls"]),
        ("hr", ["hr", "you fm"]),
        ("MDR", ["mdr"]),
        ("rbb", ["rbb", "antenne br", "radio3", "radioeins", "fritz"]),
        ("Radio Bremen", ["bremen"]),
        ("SR", ["sr ", "antennesaar", "unserding"]),
        ("Deutschlandradio", ["dlf", "dradio"]),
        ("Weitere Sender", [])
    ]

    private static func familyIndex(of name: String) -> Int {
        let lower = name.lowercased()
        return families.firstIndex { family in family.prefixes.contains { lower.hasPrefix($0) } }
            ?? families.count - 1
    }

    /// Name der Senderfamilie, z. B. für die Farbe einer Kachel ohne Logo.
    public static func familyTitle(of name: String) -> String {
        families[familyIndex(of: name)].title
    }

    // MARK: Liste

    /// Abschnitte der Radioliste: Favoriten und zuletzt gehörte Sender oben, dann die Familien,
    /// ganz unten Sender, die zuletzt keinen Ton lieferten. Leere Abschnitte entfallen.
    public func sections(favoriteKeys: [String], recentKeys: [String], deadIDs: Set<String>) -> [RadioListSection] {
        let working = all.filter { !$0.areAllVariantsDead(deadIDs: deadIDs) }
        var result = [
            RadioListSection(id: "favorites", title: "FAVORITEN", stations: stations(keys: favoriteKeys)),
            RadioListSection(id: "recent", title: "ZULETZT GEHÖRT", stations: recent(keys: recentKeys))
        ]
        for family in Self.families {
            result.append(RadioListSection(id: family.title, title: family.title.uppercased(),
                                           stations: working.filter { Self.familyTitle(of: $0.displayName) == family.title }))
        }
        result.append(RadioListSection(id: "dead", title: "ZULETZT OHNE EMPFANG",
                                       stations: all.filter { $0.areAllVariantsDead(deadIDs: deadIDs) }))
        return result.filter { !$0.stations.isEmpty }
    }

    private func stations(keys: [String]) -> [ChannelGroup] {
        keys.compactMap { key in all.first { $0.key == key } }
    }

    /// Zuletzt gehörte Sender, soweit es sie noch gibt.
    public func recent(keys: [String]) -> [ChannelGroup] {
        stations(keys: Array(keys.prefix(Self.recentLimit)))
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
