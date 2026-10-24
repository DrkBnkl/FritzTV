import Foundation

/// Ein Untertitel mit Anzeigezeitraum in Sekunden ab Videobeginn.
public struct SubtitleCue: Equatable, Sendable {
    public let start: TimeInterval
    public let end: TimeInterval
    public let text: String

    public init(start: TimeInterval, end: TimeInterval, text: String) {
        self.start = start
        self.end = end
        self.text = text
    }
}

/// Untertitel der Mediatheken. ARD und ZDF liefern TTML/EBU-TT-D (`url_subtitle` bei
/// MediathekViewWeb), manche Sender WebVTT. AVPlayer kann zu einer MP4-Datei keine externen
/// Untertitel laden, deshalb zeigt die App sie selbst an.
public enum SubtitleParser {
    /// Erkennt das Format am Inhalt.
    public static func parse(_ data: Data) -> [SubtitleCue] {
        let head = String(decoding: data.prefix(64), as: UTF8.self)
        let cues = head.contains("WEBVTT") ? parseWebVTT(String(decoding: data, as: UTF8.self))
                                           : parseTTML(data)
        return normalizeBroadcastOffset(cues.sorted { $0.start < $1.start })
    }

    /// Fernseh-Untertitel beginnen oft bei Zeitcode 10:00:00:00. Liegen alle Einträge dahinter,
    /// werden 10 Stunden abgezogen.
    static func normalizeBroadcastOffset(_ cues: [SubtitleCue]) -> [SubtitleCue] {
        let offset: TimeInterval = 10 * 3600
        guard let first = cues.first, first.start >= offset else { return cues }
        return cues.map { SubtitleCue(start: $0.start - offset, end: $0.end - offset, text: $0.text) }
    }

    /// Text, der zum Zeitpunkt `time` angezeigt wird (mehrere gleichzeitige Einträge untereinander).
    public static func text(at time: TimeInterval, in cues: [SubtitleCue]) -> String? {
        let active = cues.filter { $0.start <= time && time < $0.end }.map(\.text)
        return active.isEmpty ? nil : active.joined(separator: "\n")
    }

    // MARK: TTML / EBU-TT-D

    public static func parseTTML(_ data: Data) -> [SubtitleCue] {
        let delegate = TTMLDelegate()
        let parser = XMLParser(data: data)
        parser.shouldProcessNamespaces = true
        parser.delegate = delegate
        parser.parse()
        return delegate.cues
    }

    /// Zeitangaben in TTML: `HH:MM:SS(.mmm)`, `HH:MM:SS:FF` (Bilder), `12.5s`, `1200ms`, `9000t` (Ticks).
    static func ttmlTime(_ raw: String, frameRate: Double, tickRate: Double) -> TimeInterval? {
        let value = raw.trimmingCharacters(in: .whitespaces)
        for (suffix, factor) in [("ms", 0.001), ("s", 1.0), ("m", 60.0), ("h", 3600.0)] where value.hasSuffix(suffix) {
            return Double(value.dropLast(suffix.count)).map { $0 * factor }
        }
        if value.hasSuffix("t") {
            return Double(value.dropLast()).map { $0 / tickRate }
        }
        if value.hasSuffix("f") {
            return Double(value.dropLast()).map { $0 / frameRate }
        }
        let parts = value.split(separator: ":").map(String.init)
        guard parts.count >= 3, let h = Double(parts[0]), let m = Double(parts[1]),
              let s = Double(parts[2]) else { return nil }
        var seconds = h * 3600 + m * 60 + s
        if parts.count == 4, let frames = Double(parts[3]) {
            seconds += frames / frameRate
        }
        return seconds
    }

    private final class TTMLDelegate: NSObject, XMLParserDelegate {
        var cues: [SubtitleCue] = []
        private var frameRate = 25.0
        private var tickRate = 10_000_000.0
        private var current: (begin: TimeInterval, end: TimeInterval)?
        private var text = ""

        func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                    qualifiedName qName: String?, attributes: [String: String] = [:]) {
            switch elementName {
            case "tt":
                if let rate = attribute("frameRate", in: attributes).flatMap(Double.init) { frameRate = rate }
                if let rate = attribute("tickRate", in: attributes).flatMap(Double.init) { tickRate = rate }
            case "p":
                let begin = attribute("begin", in: attributes)
                    .flatMap { SubtitleParser.ttmlTime($0, frameRate: frameRate, tickRate: tickRate) }
                var end = attribute("end", in: attributes)
                    .flatMap { SubtitleParser.ttmlTime($0, frameRate: frameRate, tickRate: tickRate) }
                if end == nil, let begin,
                   let duration = attribute("dur", in: attributes)
                    .flatMap({ SubtitleParser.ttmlTime($0, frameRate: frameRate, tickRate: tickRate) }) {
                    end = begin + duration
                }
                if let begin, let end { current = (begin, end) }
                text = ""
            case "br":
                if current != nil { text += "\n" }
            default:
                break
            }
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            guard current != nil else { return }
            text += string
        }

        func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?,
                    qualifiedName qName: String?) {
            guard elementName == "p", let span = current else { return }
            let lines = text.components(separatedBy: "\n")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            if !lines.isEmpty {
                cues.append(SubtitleCue(start: span.begin, end: span.end, text: lines.joined(separator: "\n")))
            }
            current = nil
            text = ""
        }

        /// Attribut ohne Rücksicht auf das Namensraum-Präfix (`ttp:frameRate`, `frameRate`).
        private func attribute(_ name: String, in attributes: [String: String]) -> String? {
            if let value = attributes[name] { return value }
            return attributes.first { $0.key.hasSuffix(":" + name) }?.value
        }
    }

    // MARK: WebVTT

    public static func parseWebVTT(_ content: String) -> [SubtitleCue] {
        var cues: [SubtitleCue] = []
        let blocks = content.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n\n")
        for block in blocks {
            let lines = block.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
            guard let timeIndex = lines.firstIndex(where: { $0.contains("-->") }) else { continue }
            let times = lines[timeIndex].components(separatedBy: "-->")
            guard times.count == 2,
                  let start = vttTime(times[0]),
                  let end = vttTime(times[1].trimmingCharacters(in: .whitespaces).components(separatedBy: " ").first ?? "")
            else { continue }
            let text = lines[(timeIndex + 1)...]
                .map { $0.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression) }
                .joined(separator: "\n")
            if !text.isEmpty { cues.append(SubtitleCue(start: start, end: end, text: text)) }
        }
        return cues
    }

    /// `MM:SS.mmm` oder `HH:MM:SS.mmm`.
    static func vttTime(_ raw: String) -> TimeInterval? {
        let parts = raw.trimmingCharacters(in: .whitespaces).split(separator: ":").map(String.init)
        let numbers = parts.compactMap(Double.init)
        guard numbers.count == parts.count, (2...3).contains(numbers.count) else { return nil }
        return numbers.reduce(0) { $0 * 60 + $1 }
    }
}
