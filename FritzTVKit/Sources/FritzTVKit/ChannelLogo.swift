import Foundation

/// Senderlogos vom AVM-Logoserver (`http://tv.avm.de/tvapp/logos/<name>.png`).
///
/// Dateiname nach AVM-Schema: kleingeschrieben, Zeichen `\/:<|>"'?*+-.,@()!%&`
/// entfernt, Präfix `alt_` und Suffix ` eng` entfernt, Leerzeichen → `_`, Umlaute → ae/oe/ue, ß → ss,
/// Akzente vereinfacht, mehrfache `_` zusammengefasst. Beispiele: `wdr.png`, `ndr_fs_hh.png`.
///
/// Ob AVM für HD-Sender eigene Dateien führt, ist nicht bekannt. Deshalb liefert
/// `candidateURLs` den Namen mit und ohne „HD“; die Ansicht probiert sie der Reihe nach.
public enum ChannelLogo {
    public static let baseURL = URL(string: "http://tv.avm.de/tvapp/logos/")!

    public static func slug(for channelName: String) -> String {
        var s = channelName.lowercased()
        s.removeAll { "\\/:<|>\"'?*+-.,@()!%&".contains($0) }
        if s.hasPrefix("alt_") { s.removeFirst(4) }
        if s.hasSuffix(" eng") { s.removeLast(4) }
        s = s.trimmingCharacters(in: .whitespaces)
        s = s.replacingOccurrences(of: " ", with: "_").replacingOccurrences(of: "\u{00A0}", with: "_")
        for (from, to) in [("ü", "ue"), ("ä", "ae"), ("ö", "oe"), ("ß", "ss")] {
            s = s.replacingOccurrences(of: from, with: to)
        }
        // Übrige Akzente vereinfachen (é → e, ç → c …)
        s = s.folding(options: .diacriticInsensitive, locale: Locale(identifier: "en_US_POSIX"))
        while s.contains("__") { s = s.replacingOccurrences(of: "__", with: "_") }
        return s
    }

    /// Mögliche Logo-Adressen, die wahrscheinlichste zuerst.
    public static func candidateURLs(for channelName: String) -> [URL] {
        var names = [channelName]
        let lower = channelName.lowercased()
        if lower.hasSuffix(" hd") {
            names.append(String(channelName.dropLast(3)))
        }
        let canonical = Channel.canonicalGroupKey(for: channelName)
        if !names.contains(canonical) {
            names.append(canonical)
        }
        var seen = Set<String>()
        return names.map(slug(for:)).filter { !$0.isEmpty && seen.insert($0).inserted }
            .compactMap { URL(string: "\($0).png", relativeTo: baseURL)?.absoluteURL }
    }

    public static func url(for channelName: String) -> URL? {
        candidateURLs(for: channelName).first
    }
}
