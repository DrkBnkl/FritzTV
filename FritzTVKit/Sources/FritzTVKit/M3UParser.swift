import Foundation

/// Liest die M3U-Listen der FRITZ!Box (`/dvb/m3u/tvhd.m3u`, `tvsd.m3u`, `radio.m3u`).
///
/// Format pro Sender:
/// ```
/// #EXTINF:0,ZDF HD
/// #EXTVLCOPT:network-caching=1000
/// rtsp://192.168.178.1:554/?avm=1&freq=450&…
/// ```
public enum M3UParser {

    /// Zerlegt Rohdaten. Die Box liefert UTF-8; Latin-1 dient als Rückfall.
    public static func parse(data: Data, kind: ChannelKind = .tv) -> [Channel] {
        let text = String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .isoLatin1)
            ?? ""
        return parse(text, kind: kind)
    }

    public static func parse(_ text: String, kind: ChannelKind = .tv) -> [Channel] {
        var channels: [Channel] = []
        var pendingName: String?
        var pendingCaching: Int?

        for rawLine in text.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line == "#EXTM3U" { continue }

            if line.hasPrefix("#EXTINF:") {
                // Alles nach dem ersten Komma ist der Name.
                if let comma = line.firstIndex(of: ",") {
                    pendingName = String(line[line.index(after: comma)...])
                } else {
                    pendingName = nil
                }
                pendingCaching = nil
            } else if line.hasPrefix("#EXTVLCOPT:") {
                let option = line.dropFirst("#EXTVLCOPT:".count)
                if option.hasPrefix("network-caching=") {
                    pendingCaching = Int(option.dropFirst("network-caching=".count))
                }
            } else if line.hasPrefix("#") {
                continue
            } else if let url = URL(string: line), url.scheme?.lowercased() == "rtsp" {
                defer { pendingName = nil; pendingCaching = nil }
                guard let rawName = pendingName else { continue }
                let cleaned = ChannelName.clean(rawName)
                // Platzhalter wie „.“, „..“ oder „...“ überspringen.
                guard ChannelName.isMeaningful(cleaned) else { continue }
                let parts = ChannelName.split(cleaned)
                channels.append(Channel(
                    name: cleaned,
                    displayName: parts.base,
                    isHD: parts.isHD,
                    languageTag: parts.language,
                    kind: kind,
                    position: channels.count,
                    streamURL: url,
                    tuning: TuningParameters(url: url),
                    networkCachingMilliseconds: pendingCaching
                ))
            }
        }
        return channels
    }
}

/// Aufbereitung der Sendernamen.
enum ChannelName {

    /// Entfernt DVB-Hervorhebungszeichen (0x86/0x87, je nach Dekodierung auch als „†“/„‡“
    /// sichtbar, z. B. „†RTL‡ Television“) und doppelte Leerzeichen.
    static func clean(_ name: String) -> String {
        let markers: Set<Character> = ["\u{86}", "\u{87}", "†", "‡"]
        let stripped = String(name.filter { !markers.contains($0) })
        return stripped
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }

    /// Ein Name braucht mindestens einen Buchstaben oder eine Ziffer.
    static func isMeaningful(_ name: String) -> Bool {
        name.unicodeScalars.contains { CharacterSet.alphanumerics.contains($0) }
    }

    /// Trennt „HD“ und eine Sprachkennung wie „(eng)“ vom Namen.
    /// „WDR HD Köln“ → („WDR Köln“, HD), „CNN (eng)“ → („CNN“, SD, „eng“).
    static func split(_ name: String) -> (base: String, isHD: Bool, language: String?) {
        var working = name
        var language: String?

        if working.hasSuffix(")"), let open = working.lastIndex(of: "(") {
            let inner = working[working.index(after: open)..<working.index(before: working.endIndex)]
            if (2...3).contains(inner.count), inner.allSatisfy(\.isLetter) {
                language = inner.lowercased()
                working = String(working[..<open]).trimmingCharacters(in: .whitespaces)
            }
        }

        let tokens = working.split(separator: " ")
        let isHD = tokens.contains("HD")
        let base = tokens.filter { $0 != "HD" }.joined(separator: " ")
        return (base.isEmpty ? working : base, isHD, language)
    }
}
