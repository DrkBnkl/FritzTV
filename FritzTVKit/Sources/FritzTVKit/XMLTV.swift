import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif

/// Programmdaten aus einer XMLTV-Datei (Internet-Quelle) für Sender, deren Daten nicht über den
/// laufenden Stream kommen. Die FRITZ!Box liefert einem Gerät nur einen Stream gleichzeitig, ein
/// Abruf der anderen Frequenzen unterbräche das Live-Bild.
public enum XMLTV {
    /// Vergleichsschlüssel für Sendernamen aus FRITZ!Box-Liste und XMLTV-Datei:
    /// ohne „DE - “, „HD“, Sprachzusatz, Sonderzeichen und Akzente; bekannte Abweichungen über Aliasse.
    public static func key(_ name: String) -> String {
        var n = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if n.hasPrefix("DE - ") { n.removeFirst(5) }
        n = n.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "de_DE"))
            .replacingOccurrences(of: "ß", with: "ss")
            .lowercased()
        for suffix in ["(eng)", "(ger)", "(de)"] {
            n = n.replacingOccurrences(of: suffix, with: "")
        }
        n = n.replacingOccurrences(of: #"\bhd\b"#, with: "", options: .regularExpression)
        n = n.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) || $0 == "+" }
            .map(String.init).joined()
        return aliases[n] ?? n
    }

    /// FRITZ!Box-Name → Name in der XMLTV-Datei (beide bereits als Schlüssel).
    static let aliases: [String: String] = [
        "hrfernsehen": "hr",
        "ndrfsnds": "ndrfernsehenniedersachsen",
        "ndrfsmv": "ndrmecklenburgvorpommern",
        "ndrfssh": "ndrschleswigholstein",
        "ndrfshh": "ndrhamburg",
        "wdrkoln": "wdrfernsehenkoln",
        "brsud": "brfernsehensud",
        "brnord": "brfernsehennord",
        "aljazeerainternational": "aljazeeraenglish",
        "cnn": "cnninternational",
        "juwelotv": "juwelo",
        "n24doku": "weltdoku",
    ]

    public struct Channel: Sendable {
        public let id: String
        public let names: [String]
    }

    /// Ergebnis: Sendungen je Schlüssel (siehe `key`).
    public struct Result: Sendable {
        public var programsByKey: [String: [EPGProgram]] = [:]
        public var channelCount = 0
        public var programCount = 0
    }

    /// Liest eine XMLTV-Datei. Nur Sender, deren Schlüssel in `wantedKeys` vorkommt, und nur
    /// Sendungen im Zeitfenster werden behalten (die Datei enthält Hunderte Sender über 10 Tage).
    public static func parse(fileURL: URL, wantedKeys: Set<String>,
                             from start: Date = Date().addingTimeInterval(-6 * 3600),
                             to end: Date = Date().addingTimeInterval(4 * 24 * 3600)) -> Result? {
        guard let parser = XMLParser(contentsOf: fileURL) else { return nil }
        return run(parser, wantedKeys: wantedKeys, from: start, to: end)
    }

    public static func parse(data: Data, wantedKeys: Set<String>,
                             from start: Date = Date().addingTimeInterval(-6 * 3600),
                             to end: Date = Date().addingTimeInterval(4 * 24 * 3600)) -> Result? {
        run(XMLParser(data: data), wantedKeys: wantedKeys, from: start, to: end)
    }

    private static func run(_ parser: XMLParser, wantedKeys: Set<String>, from start: Date, to end: Date) -> Result? {
        let delegate = Delegate(wantedKeys: wantedKeys, windowStart: start, windowEnd: end)
        parser.delegate = delegate
        guard parser.parse() || !delegate.result.programsByKey.isEmpty else { return nil }
        return delegate.result
    }

    /// „20261026083000 +0000“
    static func date(_ value: String) -> Date? {
        let parts = value.split(separator: " ")
        guard let stamp = parts.first, stamp.count >= 14 else { return nil }
        let digits = Array(stamp)
        func num(_ from: Int, _ len: Int) -> Int? { Int(String(digits[from..<from + len])) }
        guard let y = num(0, 4), let mo = num(4, 2), let d = num(6, 2),
              let h = num(8, 2), let mi = num(10, 2), let s = num(12, 2) else { return nil }
        var offset = 0
        if parts.count > 1, parts[1].count == 5, let raw = Int(parts[1].dropFirst()) {
            offset = (raw / 100 * 3600 + raw % 100 * 60) * (parts[1].hasPrefix("-") ? -1 : 1)
        }
        var comps = DateComponents()
        comps.year = y; comps.month = mo; comps.day = d
        comps.hour = h; comps.minute = mi; comps.second = s
        comps.timeZone = TimeZone(secondsFromGMT: offset)
        return Calendar(identifier: .gregorian).date(from: comps)
    }

    private final class Delegate: NSObject, XMLParserDelegate {
        let wantedKeys: Set<String>
        let windowStart: Date
        let windowEnd: Date
        var result = Result()

        /// Kanal-ID der Datei → Schlüssel (nur gewünschte Sender).
        private var keyByChannelID: [String: String] = [:]
        private var serviceIDByKey: [String: Int] = [:]

        private var channelID: String?
        private var channelNames: [String] = []
        private var programme: (channel: String, start: Date, stop: Date)?
        private var title: String?
        private var subtitle: String?
        private var desc: String?
        private var categories: [String] = []
        private var text = ""
        private var collecting = false

        init(wantedKeys: Set<String>, windowStart: Date, windowEnd: Date) {
            self.wantedKeys = wantedKeys
            self.windowStart = windowStart
            self.windowEnd = windowEnd
        }

        func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?,
                    qualifiedName: String?, attributes: [String: String] = [:]) {
            switch name {
            case "channel":
                channelID = attributes["id"]
                channelNames = []
            case "display-name", "title", "sub-title", "desc", "category":
                text = ""
                collecting = true
            case "programme":
                guard let channel = attributes["channel"], keyByChannelID[channel] != nil,
                      let start = attributes["start"].flatMap(XMLTV.date),
                      let stop = attributes["stop"].flatMap(XMLTV.date),
                      stop > windowStart, start < windowEnd, stop > start else {
                    programme = nil
                    return
                }
                programme = (channel, start, stop)
                title = nil; subtitle = nil; desc = nil; categories = []
            default:
                break
            }
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            if collecting { text += string }
        }

        func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
            switch name {
            case "display-name":
                collecting = false
                if channelID != nil { channelNames.append(text) }
            case "channel":
                if let id = channelID {
                    result.channelCount += 1
                    if let key = channelNames.map(XMLTV.key).first(where: wantedKeys.contains) {
                        keyByChannelID[id] = key
                    }
                }
                channelID = nil
            case "title":
                collecting = false
                if programme != nil, title == nil { title = text }
            case "sub-title":
                collecting = false
                if programme != nil, subtitle == nil { subtitle = text }
            case "desc":
                collecting = false
                if programme != nil, desc == nil { desc = text }
            case "category":
                collecting = false
                if programme != nil { categories.append(text) }
            case "programme":
                guard let p = programme, let key = keyByChannelID[p.channel],
                      let title, !title.isEmpty else { return }
                let sid = serviceIDByKey[key] ?? {
                    let new = -(serviceIDByKey.count + 1)   // negativ: keine DVB-Service-ID
                    serviceIDByKey[key] = new
                    return new
                }()
                let program = EPGProgram(
                    eventID: Int(p.start.timeIntervalSince1970),
                    serviceID: sid,
                    title: title,
                    subtitle: subtitle.flatMap { $0.isEmpty ? nil : $0 },
                    description: desc.flatMap { $0.isEmpty ? nil : $0 },
                    startDate: p.start,
                    duration: p.stop.timeIntervalSince(p.start),
                    genre: EPGGenre.from(categories: categories)?.rawValue)
                result.programsByKey[key, default: []].append(program)
                result.programCount += 1
                programme = nil
            default:
                break
            }
        }
    }
}
