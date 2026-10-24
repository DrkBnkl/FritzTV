import Foundation

/// Liest Programminformationen (EIT) und Sendernamen (SDT) aus den libVLC-Debug-Meldungen
/// des TS-Demuxers (VLC 3, `modules/demux/mpeg/ts_si.c`).
///
/// libVLC gibt bei Debug-Stufe Zeilen wie folgende aus:
/// ```
/// new SDT ts_id=10 version=3 current_next=1 network_id=61441
///   * service id=28106 eit schedule=1 present=1 running=4 free_ca=0
///     - type=25 provider=ARD name=Das Erste HD
/// new EIT service_id=28106 version=12 current_next=1 ts_id=10 network_id=61441 ...
///   * event id=45120 start_time:1729760400 duration=3600 running=4 free_ca=0
///     - short event lang=deu 'Sportschau' : 'Bundesliga am Samstag'
///     - extended event lang=deu [1/2]
///        - text='Moderation: Esther Sedlaczek. Berichte von den Spielen...'
/// ```
///
/// Die SDT liefert die eindeutige Zuordnung Service-ID → Sendername. Nur darüber lassen sich
/// die Sendungen einem Sender zuordnen, denn die EIT eines Multiplex enthält die Sendungen
/// aller Sender auf dieser Frequenz.
///
/// Laufen mehrere VLC-Instanzen gleichzeitig (Wiedergabe und Hintergrund-Abruf), kommen ihre
/// Zeilen vermischt an. Deshalb führt der Parser den Lesezustand getrennt je Quelle
/// (`source`, z. B. die Objekt-ID aus dem VLC-Protokollkontext).
public final class EITLogParser: @unchecked Sendable {
    private struct SourceState {
        // EIT
        var serviceID: Int?
        var eventID: Int?
        var startTime: Date?
        var duration: TimeInterval?
        var running = false
        var title: String?
        var subtitle: String?
        var descriptions: [String] = []
        // SDT
        var sdtServiceID: Int?

        mutating func resetEvent() {
            eventID = nil
            startTime = nil
            duration = nil
            running = false
            title = nil
            subtitle = nil
            descriptions.removeAll()
        }
    }

    private let lock = NSLock()
    private var states: [Int: SourceState] = [:]

    /// Wird aufgerufen, sobald eine Sendung vollständig erkannt wurde.
    public var onProgramParsed: ((EPGProgram) -> Void)?
    /// Wird für jeden Eintrag der SDT aufgerufen: Service-ID und Sendername.
    public var onServiceName: ((_ serviceID: Int, _ name: String) -> Void)?

    public init(onProgramParsed: ((EPGProgram) -> Void)? = nil,
                onServiceName: ((_ serviceID: Int, _ name: String) -> Void)? = nil) {
        self.onProgramParsed = onProgramParsed
        self.onServiceName = onServiceName
    }

    /// Schneller Vorfilter für den Log-Empfänger: nur Zeilen, die der Parser auswertet.
    public static func isRelevant(_ message: String) -> Bool {
        message.contains("EIT") || message.contains("SDT") || message.contains("event id")
            || message.contains("short event") || message.contains("text='")
            || message.contains("service id") || message.contains("name=")
    }

    /// Verarbeitet eine einzelne Protokollzeile einer Quelle.
    public func processLine(_ rawLine: String, source: Int = 0) {
        let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
        if line.isEmpty { return }

        var finished: EPGProgram?
        var serviceName: (Int, String)?

        lock.lock()
        var state = states[source] ?? SourceState()

        if line.hasPrefix("new SDT") {
            finished = finalize(&state)
            state.serviceID = nil
            state.sdtServiceID = nil
        } else if line.hasPrefix("new EIT") {
            finished = finalize(&state)
            state.sdtServiceID = nil
            state.serviceID = Self.int(after: "service_id", in: line)
        } else if line.hasPrefix("* service id") {
            finished = finalize(&state)
            state.serviceID = nil
            state.sdtServiceID = Self.int(after: "service id", in: line)
        } else if line.hasPrefix("- type="), let sid = state.sdtServiceID,
                  let range = line.range(of: " name=") {
            let name = Self.cleanName(String(line[range.upperBound...]))
            if !name.isEmpty { serviceName = (sid, name) }
        } else if line.hasPrefix("* event id") {
            finished = finalize(&state)
            if state.serviceID != nil, let eventID = Self.int(after: "event id", in: line) {
                state.eventID = eventID
                if let start = Self.int64(after: "start_time", in: line) {
                    state.startTime = Date(timeIntervalSince1970: TimeInterval(start))
                }
                if let duration = Self.int(after: "duration", in: line) {
                    state.duration = TimeInterval(duration)
                }
                // Running Status 4 = läuft gerade
                state.running = Self.int(after: "running", in: line) == 4
            }
        } else if line.hasPrefix("- short event"), state.eventID != nil {
            if let (title, subtitle) = Self.parseShortEvent(line) {
                state.title = title
                state.subtitle = subtitle.isEmpty ? nil : subtitle
            }
        } else if line.hasPrefix("- text='"), state.eventID != nil {
            if let text = Self.quoted(after: "text='", in: line), !text.isEmpty {
                state.descriptions.append(text)
            }
        }

        states[source] = state
        lock.unlock()

        // Rückrufe außerhalb der Sperre, damit sie den Parser wieder aufrufen dürfen.
        if let (sid, name) = serviceName { onServiceName?(sid, name) }
        if let finished { onProgramParsed?(finished) }
    }

    /// Schließt die offene Sendung einer Quelle ab, z. B. wenn eine VLC-Instanz endet.
    public func flush(source: Int = 0) {
        lock.lock()
        var state = states[source] ?? SourceState()
        let finished = finalize(&state)
        states[source] = nil
        lock.unlock()
        if let finished { onProgramParsed?(finished) }
    }

    /// Schließt alle offenen Sendungen ab.
    public func flushAll() {
        lock.lock()
        let sources = Array(states.keys)
        lock.unlock()
        sources.forEach { flush(source: $0) }
    }

    private func finalize(_ state: inout SourceState) -> EPGProgram? {
        defer { state.resetEvent() }
        guard let serviceID = state.serviceID,
              let eventID = state.eventID,
              let title = state.title, !title.isEmpty,
              let startTime = state.startTime,
              let duration = state.duration else {
            return nil
        }
        let description = state.descriptions.joined(separator: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return EPGProgram(
            eventID: eventID,
            serviceID: serviceID,
            title: title,
            subtitle: state.subtitle,
            description: description.isEmpty ? nil : description,
            startDate: startTime,
            duration: duration,
            isRunningStatus: state.running
        )
    }

    // MARK: Parsing-Hilfen

    /// Entfernt DVB-Steuerzeichen (Hervorhebung 0x86/0x87 und deren Unicode-Entsprechungen).
    static func cleanName(_ raw: String) -> String {
        let removed = raw.unicodeScalars.filter { scalar in
            !(0x80...0x9F).contains(scalar.value) && scalar.value != 0xE086 && scalar.value != 0xE087
        }
        return String(String.UnicodeScalarView(removed)).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func int(after prefix: String, in text: String) -> Int? {
        int64(after: prefix, in: text).map { Int($0) }
    }

    static func int64(after prefix: String, in text: String) -> Int64? {
        guard let range = text.range(of: prefix) else { return nil }
        let after = text[range.upperBound...].drop(while: { $0 == " " || $0 == "=" || $0 == ":" })
        let digits = after.prefix { $0.isNumber || $0 == "-" }
        return Int64(digits)
    }

    /// Format: `- short event lang=deu 'Titel' : 'Untertitel'`. Titel und Untertitel dürfen selbst
    /// Apostrophe enthalten (z. B. „Grey's Anatomy“), daher wird am Trenner `' : '` geteilt.
    static func parseShortEvent(_ line: String) -> (String, String)? {
        guard let firstQuote = line.firstIndex(of: "'") else { return nil }
        let body = line[line.index(after: firstQuote)...]
        if let separator = body.range(of: "' : '") {
            let title = String(body[..<separator.lowerBound])
            var subtitle = body[separator.upperBound...]
            if subtitle.hasSuffix("'") { subtitle = subtitle.dropLast() }
            return (title, String(subtitle))
        }
        guard let lastQuote = body.lastIndex(of: "'") else { return (String(body), "") }
        return (String(body[..<lastQuote]), "")
    }

    static func quoted(after prefix: String, in text: String) -> String? {
        guard let range = text.range(of: prefix) else { return nil }
        let after = text[range.upperBound...]
        guard let endQuote = after.lastIndex(of: "'") else { return String(after) }
        return String(after[..<endQuote])
    }
}
