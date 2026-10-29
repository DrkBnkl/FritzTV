import Foundation

/// Standardbelegung der Senderplätze für deutsches DVB-C-Kabelfernsehen.
/// Schlüssel = `Channel.groupKey`: Name ohne „HD“/Sprachkennung, klein, ohne Umlaute.
public enum DefaultLineup {

    /// Plätze 1 bis 47: Öffentlich-Rechtliche, dann Dritte, dann Private.
    public static let main: [String] = [
        // Öffentlich-rechtliche Hauptsender
        "das erste", "zdf", "rbb berlin", "arte", "3sat", "phoenix",
        "zdf_neo", "zdfinfo", "one", "tagesschau24", "kika", "ard alpha",
        // Dritte Programme
        "rbb brandenburg", "ndr fs nds", "mdr sachsen", "wdr koln",
        "br sud", "hr-fernsehen", "swr rp", "sr fernsehen",
        // Private
        "rtl", "sat.1", "prosieben", "vox", "kabel eins", "rtlzwei",
        "super rtl", "ntv", "welt", "nitro", "sixx", "tele 5", "dmax", "tlc",
        "sport1", "eurosport 1", "prosieben maxx", "sat.1 gold",
        "kabel eins doku", "n24 doku", "rtlup", "voxup", "comedy central",
        "mtv", "disney channel", "nick", "toggo plus"
    ]

    /// Plätze ab 48: Nischen, Lokales, fremdsprachige Nachrichten, Musik.
    public static let niche: [String] = [
        "parlamentsfernsehen", "alex berlin", "tv berlin", "spreekanal",
        "euronews", "bbc news", "cnn", "cnbc europe", "al jazeera int", "cgtn",
        "deluxe music", "schlager deluxe", "dmf", "dokusat", "anixe+",
        "home & garden tv", "df1", "nicetv"
    ]

    /// Standardmäßig ausgeblendet: Shopping und religiöse Sender.
    /// Lassen sich in den Einstellungen wieder einblenden.
    public static let hidden: [String] = [
        "qvc", "qvc2", "qvc style", "hse", "hse extra", "hse trend",
        "1-2-3.tv", "juwelo tv", "channel21", "shop lc", "sonnenklar.tv",
        "bibel tv", "k-tv", "hope tv", "sonlife", "die neue zeit tv"
    ]
}
