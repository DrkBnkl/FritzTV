import Foundation

/// Hilfsklasse zur Ermittlung der Senderlogo-URLs vom AVM-Server.
public struct ChannelLogo: Sendable {
    public static func slug(for channelName: String) -> String {
        var s = channelName.lowercased()
        s = s.replacingOccurrences(of: "ä", with: "ae")
        s = s.replacingOccurrences(of: "ö", with: "oe")
        s = s.replacingOccurrences(of: "ü", with: "ue")
        s = s.replacingOccurrences(of: "ß", with: "ss")
        s = s.replacingOccurrences(of: " hd", with: "")
        s = s.replacingOccurrences(of: "alt_", with: "")
        s = s.replacingOccurrences(of: " eng", with: "")
        s = s.trimmingCharacters(in: .whitespacesAndNewlines)
        s = s.replacingOccurrences(of: " ", with: "_")
        s = s.filter { $0.isLetter || $0.isNumber || $0 == "_" || $0 == "." }
        return s
    }

    public static func url(for channelName: String) -> URL? {
        let name = slug(for: channelName)
        guard !name.isEmpty else { return nil }
        return URL(string: "http://tv.avm.de/tvapp/logos/\(name).png")
    }
}
