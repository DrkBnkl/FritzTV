import Foundation

/// Hält die EPG-Daten aller Sender und ordnet sie den Sendern der Senderliste zu.
///
/// Zuordnung: Die SDT im Stream nennt zu jeder Service-ID den Sendernamen. Die Senderlisten der
/// FRITZ!Box verwenden dieselben Namen (die Box übernimmt sie beim Sendersuchlauf aus der SDT).
/// Ein Sender der Senderliste wird deshalb über seine Namen (HD- und SD-Variante) gefunden.
/// Zusätzlich kann der Player eine Zuordnung lernen, wenn der von VLC gemeldete Titel der
/// laufenden Sendung eindeutig zu genau einem Dienst passt.
public final class EPGStore: @unchecked Sendable {
    private let lock = NSLock()
    private var programsByService: [Int: [Int: EPGProgram]] = [:]
    private var serviceIDByName: [String: Int] = [:]

    public init() {}

    /// Normalisierte Form eines Sendernamens für den Vergleich.
    public static func normalize(_ name: String) -> String {
        EITLogParser.cleanName(name)
            .folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
                     locale: Locale(identifier: "de_DE"))
            .components(separatedBy: .whitespaces).filter { !$0.isEmpty }.joined(separator: " ")
    }

    // MARK: Daten aufnehmen

    public func add(program: EPGProgram) {
        lock.lock()
        defer { lock.unlock() }
        programsByService[program.serviceID, default: [:]][program.eventID] = program
    }

    /// Zuordnung aus der SDT: Service-ID → Sendername.
    public func setServiceName(_ name: String, for serviceID: Int) {
        let key = Self.normalize(name)
        guard !key.isEmpty else { return }
        lock.lock()
        defer { lock.unlock() }
        serviceIDByName[key] = serviceID
    }

    /// Lernt eine Zuordnung, wenn genau ein Dienst gerade eine Sendung mit diesem Titel zeigt.
    /// `title` muss von VLC stammen (Metadaten des ausgewählten Programms), nicht aus diesem Speicher.
    @discardableResult
    public func learn(channelNames: [String], fromNowPlayingTitle title: String, at date: Date = Date()) -> Bool {
        let wanted = Self.normalize(title)
        guard !wanted.isEmpty else { return false }
        lock.lock()
        defer { lock.unlock() }
        if channelNames.contains(where: { serviceIDByName[Self.normalize($0)] != nil }) { return false }
        let matches = programsByService.compactMap { sid, map -> Int? in
            let schedule = EPGChannelSchedule(serviceID: sid, programs: Array(map.values))
            guard let current = schedule.currentProgram(at: date) else { return nil }
            return Self.normalize(current.title) == wanted ? sid : nil
        }
        guard matches.count == 1, let sid = matches.first else { return false }
        for name in channelNames {
            serviceIDByName[Self.normalize(name)] = sid
        }
        return true
    }

    // MARK: Abfragen

    /// Service-ID eines Senders über seine Namen (z. B. alle Varianten einer Sendergruppe).
    public func serviceID(forChannelNames names: [String]) -> Int? {
        lock.lock()
        defer { lock.unlock() }
        for name in names {
            if let sid = serviceIDByName[Self.normalize(name)] { return sid }
        }
        return nil
    }

    public func schedule(for serviceID: Int) -> EPGChannelSchedule? {
        lock.lock()
        defer { lock.unlock() }
        guard let map = programsByService[serviceID], !map.isEmpty else { return nil }
        return EPGChannelSchedule(serviceID: serviceID, programs: Array(map.values))
    }

    public func schedule(forChannelNames names: [String]) -> EPGChannelSchedule? {
        guard let sid = serviceID(forChannelNames: names) else { return nil }
        return schedule(for: sid)
    }

    public func currentProgram(forChannelNames names: [String], at date: Date = Date()) -> EPGProgram? {
        schedule(forChannelNames: names)?.currentProgram(at: date)
    }

    public func nextProgram(forChannelNames names: [String], at date: Date = Date()) -> EPGProgram? {
        schedule(forChannelNames: names)?.nextProgram(at: date)
    }

    /// Entfernt Sendungen, die vor mehr als 12 Stunden endeten.
    public func pruneExpired(before date: Date = Date().addingTimeInterval(-12 * 3600)) {
        lock.lock()
        defer { lock.unlock() }
        for (sid, map) in programsByService {
            programsByService[sid] = map.filter { $0.value.endDate > date }
        }
    }
}

public extension ChannelGroup {
    /// Alle Namen der Varianten, für die EPG-Zuordnung.
    var epgNames: [String] { variants.map(\.name) }
}
