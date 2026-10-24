import Foundation

/// Liest EIT-Programminformationen (EPG) aus den libVLC-Debug-Meldungen des Demuxers (`ts_psip.c`).
///
/// libVLC gibt bei Debug-Stufe Zeilen wie folgende aus:
/// ```
/// new EIT service_id=11110 version=12 current_next=1 ts_id=10 network_id=1 ...
///   * event id=45120 start_time:1729760400 duration:3600 running=4 free_ca=0
///     - short event lang=deu 'Sportschau' : 'Bundesliga am Samstag'
///     - extended event lang=deu [1/2]
///        - text='Moderation: Esther Sedlaczek. Berichte von den Spielen...'
/// ```
public final class EITLogParser: @unchecked Sendable {
    private let lock = NSLock()

    private var activeServiceID: Int?
    private var pendingEventID: Int?
    private var pendingStartTime: Date?
    private var pendingDuration: TimeInterval?
    private var pendingRunning: Bool = false
    private var pendingTitle: String?
    private var pendingSubtitle: String?
    private var pendingDescriptions: [String] = []

    /// Callback, der aufgerufen wird, sobald eine Sendung vollständig erkannt wurde.
    public var onProgramParsed: ((EPGProgram) -> Void)?

    public init(onProgramParsed: ((EPGProgram) -> Void)? = nil) {
        self.onProgramParsed = onProgramParsed
    }

    /// Verarbeitet eine einzelne Protokollzeile.
    public func processLine(_ rawLine: String) {
        lock.lock()
        defer { lock.unlock() }

        let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
        if line.isEmpty { return }

        // 1. Neuer EIT-Abschnitt für einen Sender
        if line.contains("new EIT") {
            finalizeCurrentEventLocked()
            if let serviceID = extractInt(after: "service_id", in: line) {
                activeServiceID = serviceID
            }
            return
        }

        // 2. Neues Event innerhalb des EIT-Abschnitts
        if line.contains("event id") {
            finalizeCurrentEventLocked()
            guard let eventID = extractInt(after: "event id", in: line) else { return }
            pendingEventID = eventID

            if let startTimeSeconds = extractInt64(after: "start_time", in: line) {
                // start_time ist ein UNIX-Zeitstempel (UTC)
                pendingStartTime = Date(timeIntervalSince1970: TimeInterval(startTimeSeconds))
            }
            if let durationSeconds = extractInt(after: "duration", in: line) {
                pendingDuration = TimeInterval(durationSeconds)
            }
            if let running = extractInt(after: "running", in: line) {
                // Status 4 = läuft jetzt (running)
                pendingRunning = (running == 4)
            }
            return
        }

        // 3. Kurztitel und Untertitel (Short Event Descriptor)
        if line.contains("- short event lang=") {
            if let (title, subtitle) = parseShortEvent(line) {
                pendingTitle = title
                pendingSubtitle = subtitle.isEmpty ? nil : subtitle
            }
            return
        }

        // 4. Ausführlicher Beschreibungstext (Extended Event Descriptor)
        if line.contains("- text='") || line.contains("text='") {
            if let text = extractQuoted(after: "text='", in: line) {
                if !text.isEmpty {
                    pendingDescriptions.append(text)
                }
            }
            return
        }
    }

    /// Schließt das aktuelle Event ab, falls vorhanden.
    public func flush() {
        lock.lock()
        defer { lock.unlock() }
        finalizeCurrentEventLocked()
    }

    private func finalizeCurrentEventLocked() {
        guard let serviceID = activeServiceID,
              let eventID = pendingEventID,
              let title = pendingTitle, !title.isEmpty,
              let startTime = pendingStartTime,
              let duration = pendingDuration else {
            resetPendingLocked()
            return
        }

        let fullDesc = pendingDescriptions.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        let program = EPGProgram(
            eventID: eventID,
            serviceID: serviceID,
            title: title,
            subtitle: pendingSubtitle,
            description: fullDesc.isEmpty ? nil : fullDesc,
            startDate: startTime,
            duration: duration,
            isRunningStatus: pendingRunning
        )

        resetPendingLocked()
        onProgramParsed?(program)
    }

    private func resetPendingLocked() {
        pendingEventID = nil
        pendingStartTime = nil
        pendingDuration = nil
        pendingRunning = false
        pendingTitle = nil
        pendingSubtitle = nil
        pendingDescriptions.removeAll()
    }

    // MARK: Parsing-Hilfen

    private func extractInt(after prefix: String, in text: String) -> Int? {
        guard let range = text.range(of: prefix) else { return nil }
        let after = text[range.upperBound...].drop(while: { $0 == " " || $0 == "=" || $0 == ":" })
        let digits = after.prefix { $0.isNumber }
        return Int(digits)
    }

    private func extractInt64(after prefix: String, in text: String) -> Int64? {
        guard let range = text.range(of: prefix) else { return nil }
        let after = text[range.upperBound...].drop(while: { $0 == " " || $0 == "=" || $0 == ":" })
        let digits = after.prefix { $0.isNumber }
        return Int64(digits)
    }

    private func parseShortEvent(_ line: String) -> (String, String)? {
        // Format: "- short event lang=deu 'Titel' : 'Untertitel'"
        guard let firstQuote = line.firstIndex(of: "'") else { return nil }
        let rest1 = line[line.index(after: firstQuote)...]
        guard let secondQuote = rest1.firstIndex(of: "'") else { return nil }
        let title = String(rest1[..<secondQuote])

        let rest2 = rest1[rest1.index(after: secondQuote)...]
        guard let thirdQuote = rest2.firstIndex(of: "'") else {
            return (title, "")
        }
        let rest3 = rest2[rest2.index(after: thirdQuote)...]
        guard let fourthQuote = rest3.firstIndex(of: "'") else {
            return (title, "")
        }
        let subtitle = String(rest3[..<fourthQuote])
        return (title, subtitle)
    }

    private func extractQuoted(after prefix: String, in text: String) -> String? {
        guard let range = text.range(of: prefix) else { return nil }
        let after = text[range.upperBound...]
        guard let endQuote = after.lastIndex(of: "'") else {
            return String(after)
        }
        return String(after[..<endQuote])
    }
}
