import Foundation

/// Eine einzelne Sendung im elektronischen Programmführer (EPG).
public struct EPGProgram: Identifiable, Hashable, Sendable, Codable {
    public var id: String { "\(serviceID):\(eventID)" }
    public let eventID: Int
    public let serviceID: Int
    public let title: String
    public let subtitle: String?
    public let description: String?
    public let startDate: Date
    public let duration: TimeInterval
    public let isRunningStatus: Bool

    public var endDate: Date {
        startDate.addingTimeInterval(duration)
    }

    /// Manche Sender füllen die Programmdaten nur mit einem Hinweistext statt einer Sendung
    /// (z. B. bigFM: „Leider keine Programminformationen vorhanden“).
    public static func isPlaceholderTitle(_ title: String) -> Bool {
        title.lowercased().contains("keine programminformation")
    }

    public init(
        eventID: Int,
        serviceID: Int,
        title: String,
        subtitle: String? = nil,
        description: String? = nil,
        startDate: Date,
        duration: TimeInterval,
        isRunningStatus: Bool = false
    ) {
        self.eventID = eventID
        self.serviceID = serviceID
        self.title = title
        self.subtitle = subtitle
        self.description = description
        self.startDate = startDate
        self.duration = duration
        self.isRunningStatus = isRunningStatus
    }

    /// Prüft, ob die Sendung zum angegebenen Zeitpunkt läuft.
    public func isLive(at date: Date = Date()) -> Bool {
        if isRunningStatus, startDate <= date, date < endDate.addingTimeInterval(EPGChannelSchedule.overrunGrace) {
            return true
        }
        return date >= startDate && date < endDate
    }

    /// Fortschritt der Sendung (0.0 bis 1.0) zu einem bestimmten Zeitpunkt.
    public func progress(at date: Date = Date()) -> Double {
        guard duration > 0 else { return 0 }
        let elapsed = date.timeIntervalSince(startDate)
        return min(max(elapsed / duration, 0.0), 1.0)
    }
}

/// Programm eines Senders, geordnet nach Startzeit.
public struct EPGChannelSchedule: Sendable, Hashable {
    public let serviceID: Int
    public let programs: [EPGProgram]

    public init(serviceID: Int, programs: [EPGProgram]) {
        self.serviceID = serviceID
        self.programs = programs.sorted(by: Self.startsEarlier)
    }

    /// Eindeutige Reihenfolge, auch bei gleicher Startzeit.
    static func startsEarlier(_ a: EPGProgram, _ b: EPGProgram) -> Bool {
        a.startDate != b.startDate ? a.startDate < b.startDate : a.eventID < b.eventID
    }

    /// Die aktuell laufende Sendung, unabhängig von der Reihenfolge der Eingabe. Überlappen sich
    /// Sendungen (z. B. eine verschobene neben ihrem alten Eintrag), gilt die zuletzt beginnende.
    static func current<S: Sequence>(in programs: S, at date: Date) -> EPGProgram? where S.Element == EPGProgram {
        var running: EPGProgram?
        var scheduled: EPGProgram?
        for program in programs where program.startDate <= date {
            if program.isRunningStatus, date < program.endDate.addingTimeInterval(overrunGrace),
               running.map({ startsEarlier($0, program) }) ?? true {
                running = program
            }
            if date < program.endDate, scheduled.map({ startsEarlier($0, program) }) ?? true {
                scheduled = program
            }
        }
        return running ?? scheduled
    }

    /// Wie lange eine als „läuft“ gemeldete Sendung über ihr geplantes Ende hinaus noch als
    /// aktuell gilt (Überziehen, z. B. bei Sport). Danach zählt nur noch die Uhrzeit.
    public static let overrunGrace: TimeInterval = 30 * 60

    /// Die aktuell laufende Sendung. Der Running Status aus der EIT hat Vorrang, aber nur,
    /// solange die Sendung nicht schon lange vorbei ist – sonst bliebe eine veraltete Meldung
    /// hängen, wenn keine neuen Daten mehr kommen.
    public func currentProgram(at date: Date = Date()) -> EPGProgram? {
        Self.current(in: programs, at: date)
    }

    /// Die danach folgende Sendung.
    public func nextProgram(at date: Date = Date()) -> EPGProgram? {
        guard let current = currentProgram(at: date) else {
            return programs.first { $0.startDate >= date }
        }
        return programs.first { $0.startDate >= current.endDate }
    }

    /// Sendung zu einer bestimmten Uhrzeit (z. B. 20:15).
    public func program(at date: Date) -> EPGProgram? {
        programs.first { date >= $0.startDate && date < $0.endDate }
    }
}
