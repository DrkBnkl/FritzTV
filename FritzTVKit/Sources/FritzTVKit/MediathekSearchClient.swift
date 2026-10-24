import Foundation

/// Suchergebnis aus der MediathekViewWeb-API.
public struct MediathekSearchResult: Identifiable, Sendable, Codable, Hashable {
    public let id: String
    public let channel: String
    public let topic: String
    public let title: String
    public let description: String
    public let timestamp: Int
    public let duration: Int
    public let urlVideo: String
    public let urlVideoHD: String?
    /// Untertitel (meist TTML), falls der Sender welche anbietet.
    public let urlSubtitle: String?

    public var subtitleURL: URL? {
        urlSubtitle.flatMap { $0.isEmpty ? nil : URL(string: $0) }
    }

    public var bestPlaybackURL: URL? {
        if let hd = urlVideoHD, !hd.isEmpty, let url = URL(string: hd) {
            return url
        }
        return URL(string: urlVideo)
    }

    enum CodingKeys: String, CodingKey {
        case id
        case channel
        case topic
        case title
        case description
        case timestamp
        case duration
        case urlVideo = "url_video"
        case urlVideoHD = "url_video_hd"
        case urlSubtitle = "url_subtitle"
    }

    public init(id: String, channel: String, topic: String, title: String, description: String,
                timestamp: Int, duration: Int, urlVideo: String, urlVideoHD: String?, urlSubtitle: String? = nil) {
        self.id = id
        self.channel = channel
        self.topic = topic
        self.title = title
        self.description = description
        self.timestamp = timestamp
        self.duration = duration
        self.urlVideo = urlVideo
        self.urlVideoHD = urlVideoHD
        self.urlSubtitle = urlSubtitle
    }

    /// Nachsichtig: Fehlt ein Nebenfeld (Beschreibung, Thema, Dauer), bleibt der Treffer erhalten.
    /// Nur ohne Titel oder Video-Link wird er verworfen.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func string(_ key: CodingKeys) -> String? { try? c.decodeIfPresent(String.self, forKey: key) }
        func number(_ key: CodingKeys) -> Int {
            if let value = try? c.decodeIfPresent(Int.self, forKey: key) { return value }
            if let value = try? c.decodeIfPresent(Double.self, forKey: key) { return Int(value) }
            return string(key).flatMap { Int($0) } ?? 0
        }
        guard let title = string(.title), let urlVideo = string(.urlVideo), !urlVideo.isEmpty else {
            throw DecodingError.dataCorruptedError(forKey: .urlVideo, in: c, debugDescription: "Titel oder Video fehlt")
        }
        self.title = title
        self.urlVideo = urlVideo
        self.id = string(.id) ?? urlVideo
        self.channel = string(.channel) ?? ""
        self.topic = string(.topic) ?? ""
        self.description = string(.description) ?? ""
        self.timestamp = number(.timestamp)
        self.duration = number(.duration)
        self.urlVideoHD = string(.urlVideoHD)
        self.urlSubtitle = string(.urlSubtitle)
    }

    /// Sendername, wie MediathekViewWeb ihn führt, zu einem Sender der Senderliste.
    /// `nil` für Sender, die MediathekViewWeb nicht kennt (Private): dann nur nach Titel suchen.
    public static func mediathekChannel(for channelName: String) -> String? {
        let name = channelName.folding(options: [.caseInsensitive, .diacriticInsensitive],
                                       locale: Locale(identifier: "de_DE"))
        let table: [(prefix: String, channel: String)] = [
            ("das erste", "ARD"), ("tagesschau24", "ARD"), ("one", "ARD"), ("ard alpha", "ARD-alpha"),
            ("zdf", "ZDF"), ("3sat", "3Sat"), ("arte", "ARTE.DE"), ("phoenix", "PHOENIX"),
            ("kika", "KiKA"), ("rbb", "RBB"), ("ndr", "NDR"), ("wdr", "WDR"), ("br ", "BR"),
            ("mdr", "MDR"), ("swr", "SWR"), ("hr", "HR"), ("sr ", "SR"), ("radio bremen", "Radio Bremen TV")
        ]
        return table.first { name == $0.prefix.trimmingCharacters(in: .whitespaces) || name.hasPrefix($0.prefix) }?.channel
    }
}

/// Fragt die MediathekViewWeb-API (`/api/query`) ab, um vergangene Sendungen
/// („Sendung verpasst“) direkt als MP4-Video abspielen zu können.
public struct MediathekSearchClient: Sendable {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func search(title: String, channel: String? = nil, limit: Int = 10) async -> [MediathekSearchResult] {
        guard let url = URL(string: "https://mediathekviewweb.de/api/query") else { return [] }

        var queries: [[String: Any]] = [
            ["fields": ["title"], "query": title]
        ]
        if let channel, let mvwChannel = MediathekSearchResult.mediathekChannel(for: channel) {
            queries.append(["fields": ["channel"], "query": mvwChannel])
        }

        let payload: [String: Any] = [
            "queries": queries,
            "sortBy": "timestamp",
            "sortOrder": "desc",
            "size": limit
        ]

        guard let bodyData = try? JSONSerialization.data(withJSONObject: payload) else { return [] }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 6
        request.setValue("text/plain", forHTTPHeaderField: "Content-Type")
        request.httpBody = bodyData

        guard let (data, response) = try? await session.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200 else {
            return []
        }

        return Self.decodeResults(from: data)
    }

    /// Untertitel zu einem Mediathek-Video suchen (z. B. für Filme aus press2arr, die nur den
    /// Video-Link kennen): Treffer mit demselben Video-Link.
    public func subtitleURL(forVideo videoURL: URL, title: String, channel: String? = nil) async -> URL? {
        let results = await search(title: title, channel: channel, limit: 25)
        let wanted = videoURL.absoluteString
        return results.first { [$0.urlVideo, $0.urlVideoHD].contains(wanted) }?.subtitleURL
    }

    /// Wertet die Antwort aus; unvollständige Einträge werden einzeln übersprungen.
    static func decodeResults(from data: Data) -> [MediathekSearchResult] {
        struct Lenient: Decodable {
            let value: MediathekSearchResult?
            init(from decoder: Decoder) throws {
                value = try? MediathekSearchResult(from: decoder)
            }
        }
        struct ResponseEnvelope: Decodable {
            struct ResultContainer: Decodable {
                let results: [Lenient]
            }
            let result: ResultContainer?
        }
        guard let envelope = try? JSONDecoder().decode(ResponseEnvelope.self, from: data) else {
            return []
        }
        return envelope.result?.results.compactMap(\.value) ?? []
    }
}
