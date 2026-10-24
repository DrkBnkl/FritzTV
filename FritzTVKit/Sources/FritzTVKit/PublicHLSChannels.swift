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
        "ard-alpha": URL(string: "https://mcdn.br.de/br/fs/ard_alpha/hls/de/master.m3u8")!,
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
        "swr": URL(string: "https://swrbwd-hls.akamaized.net/hls/live/2018672/swrbwd/master.m3u8")!,
        "swr bw": URL(string: "https://swrbwd-hls.akamaized.net/hls/live/2018672/swrbwd/master.m3u8")!,
        "swr rp": URL(string: "https://swrrpd-hls.akamaized.net/hls/live/2018676/swrrpd/master.m3u8")!,
        "hr-fernsehen": URL(string: "https://hrhls.akamaized.net/hls/live/2024525/hrhls/master.m3u8")!,
        "mdr": URL(string: "https://mdrtvsnhls.akamaized.net/hls/live/2016928/mdrtvsn/master.m3u8")!,
        "sr fernsehen": URL(string: "https://srfs.akamaized.net/hls/live/689649/srfsgeo/index.m3u8")!
    ]

    /// Prüft, ob für den angegebenen Sender ein HLS-Stream verfügbar ist.
    public static func hlsURL(for groupKey: String) -> URL? {
        let cleaned = groupKey.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "de_DE"))
        if let direct = streams[cleaned] {
            return direct
        }
        for (key, url) in streams {
            if cleaned.contains(key) || key.contains(cleaned) {
                return url
            }
        }
        return nil
    }
}
