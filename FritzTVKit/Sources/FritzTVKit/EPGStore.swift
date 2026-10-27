import Foundation

/// Hält die EPG-Daten aller Sender und ordnet sie den Sendern der Senderliste zu.
///
/// Zuordnung: Die SDT im Stream nennt zu jeder Service-ID den Sendernamen. Die Senderlisten der
/// FRITZ!Box verwenden dieselben Namen (die Box übernimmt sie beim Sendersuchlauf aus der SDT).
/// Ein Sender der Senderliste wird deshalb über seine Namen (HD- und SD-Variante) gefunden.
/// Zusätzlich kann der Player eine Zuordnung lernen, wenn der von VLC gemeldete Titel der
/// laufenden Sendung eindeutig zu genau einem Dienst passt.
public final class EPGStore: @unchecked Sendable {
    private struct StorageData: Codable {
        var programsByService: [Int: [Int: EPGProgram]]
        var serviceIDByName: [String: Int]
    }

    private let lock = NSLock()
    private var programsByService: [Int: [Int: EPGProgram]] = [:]
    private var serviceIDByName: [String: Int] = [:]
    /// Programmdaten aus dem Internet (XMLTV), je Schlüssel `XMLTV.key(Sendername)`.
    /// Ergänzen die Daten aus dem Stream dort, wo diese fehlen.
    private var externalByKey: [String: [EPGProgram]] = [:]
    private let cacheURL: URL?
    /// Gesetzt, solange ein Speichervorgang geplant ist (geschützt durch `lock`).
    private var savePending = false

    public static var defaultCacheURL: URL? {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent("epg_cache.json")
    }

    public init(cacheURL: URL? = nil) {
        self.cacheURL = cacheURL
        if let cacheURL, let data = try? Data(contentsOf: cacheURL),
           let decoded = try? JSONDecoder().decode(StorageData.self, from: data) {
            self.programsByService = decoded.programsByService
            self.serviceIDByName = decoded.serviceIDByName
            pruneExpired()
        }
    }

    /// Normalisierte Form eines Sendernamens für den Vergleich.
    public static func normalize(_ name: String) -> String {
        EITLogParser.cleanName(name)
            .folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
                     locale: Locale(identifier: "de_DE"))
            .components(separatedBy: .whitespaces).filter { !$0.isEmpty }.joined(separator: " ")
    }

    // MARK: Speichern und Laden

    /// Fasst viele Änderungen zu einem Speichervorgang nach 10 Sekunden zusammen.
    /// Wird aus VLC-Threads aufgerufen, daher nur unter der Sperre (und nie, während sie gehalten wird).
    private func scheduleSave() {
        guard let url = cacheURL else { return }
        lock.lock()
        let alreadyPending = savePending
        savePending = true
        lock.unlock()
        guard !alreadyPending else { return }
        DispatchQueue.global(qos: .background).asyncAfter(deadline: .now() + 10) { [weak self] in
            guard let self else { return }
            self.lock.lock()
            self.savePending = false
            self.lock.unlock()
            self.pruneExpired()
            self.saveToFile(url)
        }
    }

    public func saveToFile(_ url: URL? = nil) {
        guard let targetURL = url ?? cacheURL else { return }
        lock.lock()
        let snapshot = StorageData(programsByService: programsByService, serviceIDByName: serviceIDByName)
        lock.unlock()
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        try? data.write(to: targetURL, options: .atomic)
    }

    // MARK: Daten aufnehmen

    /// Nimmt eine Sendung auf. Gibt `true` zurück, wenn sie neu ist oder sich geändert hat.
    /// (Die EIT wiederholt dieselben Sendungen alle paar Sekunden; Wiederholungen lösen weder
    /// Speichern noch Neuzeichnen aus.)
    @discardableResult
    public func add(program: EPGProgram) -> Bool {
        lock.lock()
        let changed = programsByService[program.serviceID]?[program.eventID] != program
        if changed {
            programsByService[program.serviceID, default: [:]][program.eventID] = program
        }
        lock.unlock()
        if changed { scheduleSave() }
        return changed
    }

    /// Zuordnung aus der SDT: Service-ID → Sendername. `true`, wenn sie neu ist.
    @discardableResult
    public func setServiceName(_ name: String, for serviceID: Int) -> Bool {
        let key = Self.normalize(name)
        guard !key.isEmpty else { return false }
        lock.lock()
        let changed = serviceIDByName[key] != serviceID
        if changed { serviceIDByName[key] = serviceID }
        lock.unlock()
        if changed { scheduleSave() }
        return changed
    }

    /// Lernt eine Zuordnung, wenn genau ein Dienst gerade eine Sendung mit diesem Titel zeigt.
    /// `title` muss von VLC stammen (Metadaten des ausgewählten Programms), nicht aus diesem Speicher.
    @discardableResult
    public func learn(channelNames: [String], fromNowPlayingTitle title: String, at date: Date = Date()) -> Bool {
        let wanted = Self.normalize(title)
        guard !wanted.isEmpty else { return false }
        lock.lock()
        if channelNames.contains(where: { serviceIDByName[Self.normalize($0)] != nil }) {
            lock.unlock()
            return false
        }
        let matches = programsByService.compactMap { sid, map -> Int? in
            let schedule = EPGChannelSchedule(serviceID: sid, programs: Array(map.values))
            guard let current = schedule.currentProgram(at: date) else { return nil }
            return Self.normalize(current.title) == wanted ? sid : nil
        }
        guard matches.count == 1, let sid = matches.first else {
            lock.unlock()
            return false
        }
        for name in channelNames {
            serviceIDByName[Self.normalize(name)] = sid
        }
        lock.unlock()
        // Erst nach dem Freigeben der Sperre: scheduleSave sperrt selbst.
        scheduleSave()
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

    /// Programm eines Senders: Daten aus dem Stream (DVB-EIT), ergänzt um Sendungen aus der
    /// Internet-Quelle in Zeiträumen, die der Stream nicht abdeckt.
    public func schedule(forChannelNames names: [String]) -> EPGChannelSchedule? {
        let dvb = serviceID(forChannelNames: names).flatMap { schedule(for: $0) }
        let external = externalPrograms(forChannelNames: names)
        guard !external.isEmpty else { return dvb }
        guard let dvb, !dvb.programs.isEmpty else {
            return EPGChannelSchedule(serviceID: external[0].serviceID, programs: external)
        }
        // Sparte aus der Internet-Quelle übernehmen (der Stream liefert keine), wenn eine Sendung
        // dort fast zur selben Zeit beginnt.
        let covered = dvb.programs.map { program -> EPGProgram in
            guard program.genre == nil,
                  let match = external.first(where: { abs($0.startDate.timeIntervalSince(program.startDate)) < 600 })
            else { return program }
            return program.withGenre(match.genre)
        }
        // Lücken füllen: externe Sendungen nur, wo keine DVB-Sendung liegt.
        let extra = external.filter { ext in
            !covered.contains { $0.startDate < ext.endDate && ext.startDate < $0.endDate }
        }
        return EPGChannelSchedule(serviceID: dvb.serviceID, programs: covered + extra)
    }

    private func externalPrograms(forChannelNames names: [String]) -> [EPGProgram] {
        lock.lock()
        defer { lock.unlock() }
        guard !externalByKey.isEmpty else { return [] }
        for name in names {
            if let programs = externalByKey[XMLTV.key(name)], !programs.isEmpty { return programs }
        }
        return []
    }

    /// Ersetzt die Programmdaten aus dem Internet.
    public func setExternal(_ programsByKey: [String: [EPGProgram]]) {
        lock.lock()
        externalByKey = programsByKey
        lock.unlock()
    }

    public var hasExternalData: Bool {
        lock.lock()
        defer { lock.unlock() }
        return !externalByKey.isEmpty
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
