import Foundation

/// Verwaltet die EPG-Daten aller Sender, hält das aktuelle Programm vor und ordnet
/// Programme den Sendern zu.
public final class EPGStore: @unchecked Sendable {
    private let lock = NSLock()
    private var programsByService: [Int: [String: EPGProgram]] = [:]
    private var serviceIDByChannelKey: [String: Int] = [:]
    private var channelKeyByServiceID: [Int: String] = [:]

    public init() {}

    /// Speichert ein EPG-Programm.
    public func add(program: EPGProgram) {
        lock.lock()
        defer { lock.unlock() }
        var map = programsByService[program.serviceID, default: [:]]
        map[program.id] = program
        programsByService[program.serviceID] = map
    }

    /// Verknüpft einen Sender-Schlüssel mit einer DVB Service-ID.
    public func associate(channelKey: String, serviceID: Int) {
        lock.lock()
        defer { lock.unlock() }
        serviceIDByChannelKey[channelKey] = serviceID
        channelKeyByServiceID[serviceID] = channelKey
    }

    /// Sucht die Service-ID für einen Sender.
    public func serviceID(for channelKey: String) -> Int? {
        lock.lock()
        defer { lock.unlock() }
        return serviceIDByChannelKey[channelKey]
    }

    /// Liefert den Programmablauf für eine Service-ID.
    public func schedule(for serviceID: Int) -> EPGChannelSchedule? {
        lock.lock()
        defer { lock.unlock() }
        guard let map = programsByService[serviceID], !map.isEmpty else { return nil }
        return EPGChannelSchedule(serviceID: serviceID, programs: Array(map.values))
    }

    /// Liefert den Programmablauf für einen Sender-Schlüssel (falls verknüpft).
    public func schedule(forChannelKey key: String) -> EPGChannelSchedule? {
        lock.lock()
        let sid = serviceIDByChannelKey[key]
        lock.unlock()
        guard let sid else { return nil }
        return schedule(for: sid)
    }

    /// Liefert die aktuell laufende Sendung für einen Sender.
    public func currentProgram(forChannelKey key: String, at date: Date = Date()) -> EPGProgram? {
        schedule(forChannelKey: key)?.currentProgram(at: date)
    }

    /// Liefert die nächste Sendung für einen Sender.
    public func nextProgram(forChannelKey key: String, at date: Date = Date()) -> EPGProgram? {
        schedule(forChannelKey: key)?.nextProgram(at: date)
    }

    /// Bereinigt alte Programme, die vor mehr als 12 Stunden beendet wurden.
    public func pruneExpired(before date: Date = Date().addingTimeInterval(-12 * 3600)) {
        lock.lock()
        defer { lock.unlock() }
        for (sid, map) in programsByService {
            let active = map.filter { $0.value.endDate > date }
            programsByService[sid] = active
        }
    }
}
