import Foundation

/// Gespeicherte Wünsche des Nutzers: Reihenfolge und ausgeblendete Sender.
/// Codable, damit die App sie z. B. in UserDefaults ablegen kann.
public struct LineupPreferences: Codable, Equatable, Sendable {
    /// Gruppen-Schlüssel in gewünschter Reihenfolge (ohne `tv:`-Präfix).
    public var order: [String]
    public var hidden: Set<String>

    public init(order: [String], hidden: Set<String>) {
        self.order = order
        self.hidden = hidden
    }

    public static let standard = LineupPreferences(
        order: DefaultLineup.main + DefaultLineup.niche + DefaultLineup.hidden,
        hidden: Set(DefaultLineup.hidden)
    )

    /// Auf kanonische Schlüssel gebracht und ohne Dubletten. Ältere Versionen konnten denselben
    /// Sender unter zwei Schreibweisen speichern (z. B. „zdfneo“ und „zdf_neo“).
    public var normalized: LineupPreferences {
        var seen = Set<String>()
        let canonicalOrder = order.map(Channel.canonicalGroupKey(for:)).filter { seen.insert($0).inserted }
        return LineupPreferences(order: canonicalOrder, hidden: Set(hidden.map(Channel.canonicalGroupKey(for:))))
    }
}

/// Ein belegter Senderplatz.
public struct LineupEntry: Identifiable, Hashable, Sendable {
    public var id: String { group.id }
    /// Senderplatz, beginnend bei 1. Nur sichtbare Sender bekommen eine Nummer.
    public let number: Int
    public let group: ChannelGroup
    /// Sender, die die Box neu meldet und die noch nicht einsortiert sind.
    public let isNew: Bool
}

/// Die Senderplätze der App: Ergebnis aus Senderliste der Box und Nutzerwünschen.
public struct ChannelLineup: Sendable {
    /// Sichtbare Sender mit Platznummer, in Umschaltreihenfolge.
    public let entries: [LineupEntry]
    /// Ausgeblendete Sender (für die Einstellungen).
    public let hiddenGroups: [ChannelGroup]

    public init(catalog: ChannelCatalog, preferences: LineupPreferences = .standard) {
        let tv = catalog.tvGroups
        let byKey = Dictionary(tv.map { (Self.shortKey($0), $0) }, uniquingKeysWith: { first, _ in first })
        let preferences = preferences.normalized
        let known = Set(preferences.order)

        var visible: [(ChannelGroup, Bool)] = []
        var hidden: [ChannelGroup] = []

        for key in preferences.order {
            guard let group = byKey[key] else { continue }   // Sender nicht mehr empfangbar
            if preferences.hidden.contains(key) {
                hidden.append(group)
            } else {
                visible.append((group, false))
            }
        }
        // Neue Sender (z. B. nach einem Suchlauf) kommen ans Ende der sichtbaren Liste,
        // außer sie wurden schon ausgeblendet.
        for group in tv where !known.contains(Self.shortKey(group)) {
            if preferences.hidden.contains(Self.shortKey(group)) {
                hidden.append(group)
            } else {
                visible.append((group, true))
            }
        }

        entries = visible.enumerated().map { index, item in
            LineupEntry(number: index + 1, group: item.0, isNew: item.1)
        }
        hiddenGroups = hidden
    }

    public func entry(number: Int) -> LineupEntry? {
        entries.indices.contains(number - 1) ? entries[number - 1] : nil
    }

    /// Nächster bzw. vorheriger Platz, mit Umlauf am Listenende (wie beim Fernseher).
    public func entry(after number: Int, step: Int) -> LineupEntry? {
        guard !entries.isEmpty else { return nil }
        let count = entries.count
        let index = ((number - 1 + step) % count + count) % count
        return entries[index]
    }

    /// Schlüssel ohne Listenart, passend zu `DefaultLineup`.
    static func shortKey(_ group: ChannelGroup) -> String {
        group.variants[0].groupKey
    }
}
