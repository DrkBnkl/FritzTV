import Foundation

/// Tabelle offizieller HLS-Livestreams öffentlich-rechtlicher Sender
/// (z. B. für die Funktion „Von Anfang an“ oder Wiedergabe unterwegs).
public enum PublicHLSChannels {
    public static let streams: [String: URL] = [
        "das erste": URL(string: "https://daserste-live.ard-mcdn.de/daserste/live/hls/de/master.m3u8")!,
        "zdf": URL(string: "https://zdf-hls-15.akamaized.net/hls/live/2016498/de/high/master.m3u8")!,
        "zdfneo": URL(string: "https://zdf-hls-16.akamaized.net/hls/live/2016499/de/high/master.m3u8")!,
        "zdfinfo": URL(string: "https://zdf-hls-17.akamaized.net/hls/live/2016500/de/high/master.m3u8")!,
        "3sat": URL(string: "https://zdf-hls-18.akamaized.net/hls/live/2016501/dach/high/master.m3u8")!,
        "arte": URL(string: "https://artesimulcast.akamaized.net/hls/live/2030993/artelive_de/index.m3u8")!,
        "phoenix": URL(string: "https://zdf-hls-19.akamaized.net/hls/live/2016502/de/high/master.m3u8")!,
        "kika": URL(string: "https://kikageohls.akamaized.net/hls/live/2022693/livetvkika_de/master.m3u8")!,
        "one": URL(string: "https://mcdn-one.ard.de/ardone/hls/master.m3u8")!,
        "tagesschau24": URL(string: "https://tagesschau.akamaized.net/hls/live/2020115/tagesschau/tagesschau_1/master.m3u8")!,
        "ard alpha": URL(string: "https://mcdn.br.de/br/fs/ard_alpha/hls/de/master.m3u8")!,
        "rbb berlin": URL(string: "https://rbb-hls-berlin.akamaized.net/hls/live/2017824/rbb_berlin/master.m3u8")!,
        "rbb brandenburg": URL(string: "https://rbb-hls-brandenburg.akamaized.net/hls/live/2017825/rbb_brandenburg/master.m3u8")!,
        "wdr": URL(string: "https://wdrfs247.akamaized.net/hls/live/681509/wdr_msl4_fs247/index.m3u8")!,
        "wdr koln": URL(string: "https://wdrfs247.akamaized.net/hls/live/681509/wdr_msl4_fs247/index.m3u8")!,
        "br fernsehen": URL(string: "https://mcdn.br.de/br/fs/bfs_sued/hls/de/master.m3u8")!,
        "br sud": URL(string: "https://mcdn.br.de/br/fs/bfs_sued/hls/de/master.m3u8")!,
        "br nord": URL(string: "https://mcdn.br.de/br/fs/bfs_nord/hls/de/master.m3u8")!,
        "ndr": URL(string: "https://mcdn.ndr.de/ndr/hls/ndr_fs/ndr_hh/master.m3u8")!,
        "ndr hamburg": URL(string: "https://mcdn.ndr.de/ndr/hls/ndr_fs/ndr_hh/master.m3u8")!,
        "ndr niedersachsen": URL(string: "https://mcdn.ndr.de/ndr/hls/ndr_fs/ndr_nds/master.m3u8")!,
        "ndr fs nds": URL(string: "https://mcdn.ndr.de/ndr/hls/ndr_fs/ndr_nds/master.m3u8")!,
        "ndr fs hh": URL(string: "https://mcdn.ndr.de/ndr/hls/ndr_fs/ndr_hh/master.m3u8")!,
        "ndr fs sh": URL(string: "https://mcdn.ndr.de/ndr/hls/ndr_fs/ndr_sh/master.m3u8")!,
        "ndr fs mv": URL(string: "https://mcdn.ndr.de/ndr/hls/ndr_fs/ndr_mv/master.m3u8")!,
        "swr": URL(string: "https://swrbwd-hls.akamaized.net/hls/live/2018672/swrbwd/master.m3u8")!,
        "swr bw": URL(string: "https://swrbwd-hls.akamaized.net/hls/live/2018672/swrbwd/master.m3u8")!,
        "swr rp": URL(string: "https://swrrpd-hls.akamaized.net/hls/live/2018676/swrrpd/master.m3u8")!,
        "hr-fernsehen": URL(string: "https://hrhlsde.akamaized.net/hls/live/2024526/hrhlsde/master.m3u8")!,
        "hr fernsehen": URL(string: "https://hrhlsde.akamaized.net/hls/live/2024526/hrhlsde/master.m3u8")!,
        "hr": URL(string: "https://hrhlsde.akamaized.net/hls/live/2024526/hrhlsde/master.m3u8")!,
        "mdr": URL(string: "https://mdrtvsnhls.akamaized.net/hls/live/2016928/mdrtvsn/master.m3u8")!,
        "mdr sachsen": URL(string: "https://mdrtvsnhls.akamaized.net/hls/live/2016928/mdrtvsn/master.m3u8")!,
        "mdr sachsen-anhalt": URL(string: "https://mdrtvsahls.akamaized.net/hls/live/2016879/mdrtvsa/master.m3u8")!,
        "mdr s-anhalt": URL(string: "https://mdrtvsahls.akamaized.net/hls/live/2016879/mdrtvsa/master.m3u8")!,
        "mdr thuringen": URL(string: "https://mdrtvthhls.akamaized.net/hls/live/2016880/mdrtvth/master.m3u8")!,
        "sr fernsehen": URL(string: "https://srfs.akamaized.net/hls/live/689649/srfsgeo/index.m3u8")!
    ]

    /// Normalisiert einen Sendernamen oder Gruppenschlüssel: ohne Präfix „tv:“/„radio:“,
    /// ohne „HD“, klein, ohne Akzente, `_` als Leerzeichen („zdf_neo“ → „zdf neo“).
    static func normalize(_ raw: String) -> String {
        var s = raw.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "de_DE"))
        for prefix in ["tv:", "radio:"] where s.hasPrefix(prefix) { s.removeFirst(prefix.count) }
        s = s.replacingOccurrences(of: "_", with: " ").replacingOccurrences(of: "-", with: " ").trimmingCharacters(in: .whitespaces)
        if s.hasSuffix(" hd") { s.removeLast(3) }
        return s.components(separatedBy: .whitespaces).filter { !$0.isEmpty }.joined(separator: " ")
    }

    /// Internet-Stream zu einem Sender (Gruppenschlüssel oder Name).
    /// Erst exakter Treffer (auch ohne Leerzeichen, „zdf neo“ = „zdfneo“), sonst der längste
    /// Schlüssel, mit dem der Name als ganzes Wort beginnt („wdr koln“ → „wdr“). Kein loser
    /// Teilstring-Vergleich, damit z. B. ZDFinfo nicht den ZDF-Stream bekommt.
    public static func hlsURL(for groupKey: String) -> URL? {
        let name = normalize(groupKey)
        guard !name.isEmpty else { return nil }
        if let exact = normalizedStreams[name] { return exact }
        let compact = name.replacingOccurrences(of: " ", with: "")
        if let exact = normalizedStreams.first(where: { $0.key.replacingOccurrences(of: " ", with: "") == compact })?.value {
            return exact
        }
        let prefixMatches = normalizedStreams.filter { name.hasPrefix($0.key + " ") }
        return prefixMatches.max { $0.key.count < $1.key.count }?.value
    }

    /// `streams` mit normalisierten Schlüsseln: Gesuchte Namen sind normalisiert (`-` wird zum
    /// Leerzeichen), sonst fände „mdr sachsen anhalt“ nur den Präfix „mdr sachsen“.
    private static let normalizedStreams = Dictionary(
        streams.map { (normalize($0.key), $0.value) },
        uniquingKeysWith: { first, _ in first }
    )
}
