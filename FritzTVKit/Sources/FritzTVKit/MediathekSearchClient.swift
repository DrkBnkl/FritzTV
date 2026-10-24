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
        if let channel, !channel.isEmpty {
            queries.append(["fields": ["channel"], "query": channel])
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

        struct ResponseEnvelope: Decodable {
            struct ResultContainer: Decodable {
                let results: [MediathekSearchResult]
            }
            let result: ResultContainer?
        }

        guard let envelope = try? JSONDecoder().decode(ResponseEnvelope.self, from: data) else {
            return []
        }
        return envelope.result?.results ?? []
    }
}
