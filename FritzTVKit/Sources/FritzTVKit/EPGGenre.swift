import Foundation

/// Grobe Sparten für den Filter der Programmübersicht. Abgeleitet aus den (sehr feinen)
/// Kategorien der XMLTV-Daten, z. B. „Krimi“, „Fußball“, „Animation“.
public enum EPGGenre: String, CaseIterable, Sendable, Codable {
    case fiction, sport, news, documentary, kids, entertainment

    public var title: String {
        switch self {
        case .fiction: return "Filme & Serien"
        case .sport: return "Sport"
        case .news: return "Nachrichten"
        case .documentary: return "Doku"
        case .kids: return "Kinder"
        case .entertainment: return "Unterhaltung"
        }
    }

    /// Erste passende Sparte zu den Kategorien einer Sendung (Reihenfolge der Kategorien zählt).
    public static func from(categories: [String]) -> EPGGenre? {
        for category in categories {
            let c = category.lowercased()
            for (genre, words) in keywords where words.contains(where: { c.contains($0) }) {
                return genre
            }
        }
        return nil
    }

    // Reihenfolge wichtig: „Kinder“ vor „Animation“-Filmen, „Sportmagazin“ vor „Magazin“.
    private static let keywords: [(EPGGenre, [String])] = [
        (.kids, ["kinder", "animation", "zeichentrick", "children", "kids"]),
        (.sport, ["sport", "fußball", "fussball", "basketball", "eishockey", "football", "rugby",
                  "tennis", "handball", "golf", "radsport", "boxen"]),
        (.news, ["nachrichten", "news", "aktuelles", "politik", "regionalinfo", "regionalmagazin", "wetter"]),
        (.documentary, ["dokumentation", "doku", "wissen", "natur", "geschichte", "reportage", "reisen",
                        "documentary", "report"]),
        (.fiction, ["spielfilm", "film", "serie", "krimi", "drama", "action", "thriller", "komödie", "comedy",
                    "sitcom", "fantasy", "science", "abenteuer", "horror", "romantik", "western", "soap",
                    "telenovela", "biografie", "movie", "series"]),
        (.entertainment, ["unterhaltung", "show", "talk", "reality", "musik", "music", "quiz", "kochen",
                          "magazin", "lifestyle", "ratgeber", "gesellschaft"]),
    ]
}
