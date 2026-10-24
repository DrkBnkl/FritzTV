import Foundation

// MARK: Modelle (Antworten von press2arr / „Lichtspiel“ auf der NAS)

/// Ein Spielfilm, der gerade in einer Mediathek läuft (`GET /api/mediathek`).
public struct MediathekMovie: Decodable, Identifiable, Hashable, Sendable {
    public let tmdbId: Int
    public let title: String
    public let originalTitle: String?
    public let year: Int?
    public let overview: String?
    public let posterPath: String?
    public let backdropPath: String?
    public let rating: Double?
    public let ratingSource: String?
    public let runtime: Int?
    public let tagline: String?
    public let mtSince: Int?
    public let bookmarked: Bool?
    private let channelList: [String]?
    private let genreList: [String]?
    private let makerList: [String]?
    /// Einträge aus Kinoprogrammen (Yorck, ASTOR, auch Archiv).
    public let nCinema: Int?
    /// Artikel aus der Presse (SPIEGEL, FAZ …).
    public let nPress: Int?
    private let pressSourceList: [String]?
    /// Urteil der jüngsten Kritik: positiv, gemischt oder negativ.
    public let pressVerdict: String?

    public var id: Int { tmdbId }
    public var channels: [String] { channelList ?? [] }
    public var genres: [String] { genreList ?? [] }
    public var makers: [String] { makerList ?? [] }
    public var pressSources: [String] { pressSourceList ?? [] }
    public var ranInCinema: Bool { (nCinema ?? 0) > 0 }
    public var reviewedInPress: Bool { (nPress ?? 0) > 0 }
    public var isBookmarked: Bool { bookmarked ?? false }

    public var posterURL: URL? { TMDbImage.url(posterPath, size: "w342") }
    public var backdropURL: URL? { TMDbImage.url(backdropPath, size: "w1280") }

    enum CodingKeys: String, CodingKey {
        case tmdbId, title, originalTitle, year, overview, posterPath, backdropPath, rating, ratingSource
        case runtime, tagline, mtSince, bookmarked, nCinema, nPress, pressVerdict
        case channelList = "channels"
        case genreList = "genres"
        case makerList = "makers"
        case pressSourceList = "pressSources"
    }
}

/// Detailseite eines Films (`GET /api/item/movie/<id>`).
public struct MovieDetail: Decodable, Sendable {
    public struct Details: Decodable, Sendable {
        public struct CastMember: Decodable, Hashable, Sendable {
            public let name: String
            public let character: String?
        }
        public let genres: [String]?
        public let runtime: Int?
        public let tagline: String?
        public let makers: [String]?
        public let cast: [CastMember]?
    }

    public struct Mention: Decodable, Hashable, Sendable {
        public let source: String?
        public let title: String?
        public let url: String?
        public let summary: String?
        public let date: String?
        public let verdict: String?
        /// 1 = Eintrag aus einem Kinoprogramm, sonst Presseartikel.
        public let cinema: Int?
        public var isCinema: Bool { cinema == 1 }
    }

    public struct Hit: Decodable, Hashable, Identifiable, Sendable {
        public let id: String?
        public let channel: String?
        public let title: String?
        public let topic: String?
        public let url: String?
        public let quality: String?
        public let timestamp: Int?
        public let duration: Int?
        public let ov: Bool?
        public let hardsub: Bool?

        public var streamURL: URL? { url.flatMap(URL.init(string:)) }
        public var isOriginalVersion: Bool { ov ?? false }
        public var hasBurnedSubtitles: Bool { hardsub ?? false }
    }

    public struct MediathekInfo: Decodable, Sendable {
        public let hits: [Hit]?
        public let checking: Bool?
    }

    public let tmdbId: Int
    public let title: String
    public let originalTitle: String?
    public let year: Int?
    public let overview: String?
    public let posterPath: String?
    public let backdropPath: String?
    public let details: Details?
    public let mentions: [Mention]?
    public let mediathek: MediathekInfo?
    public let bookmarked: Bool?

    public var reviews: [Mention] { (mentions ?? []).filter { !$0.isCinema } }
    public var cinemaEntries: [Mention] { (mentions ?? []).filter(\.isCinema) }
    public var playableHits: [Hit] { (mediathek?.hits ?? []).filter { $0.streamURL != nil } }
    public var backdropURL: URL? { TMDbImage.url(backdropPath, size: "w1280") }
    public var posterURL: URL? { TMDbImage.url(posterPath, size: "w342") }
}

public enum TMDbImage {
    public static func url(_ path: String?, size: String) -> URL? {
        guard let path, !path.isEmpty else { return nil }
        return URL(string: "https://image.tmdb.org/t/p/\(size)\(path)")
    }
}

// MARK: Client

/// Liest die Mediathek-Daten von press2arr (ohne Anmeldung, nur im Heimnetz bzw. über VPN).
public struct Press2arrClient: Sendable {
    public enum ClientError: Error {
        case badAddress
        case http(Int)
    }

    public let baseURL: URL
    let session: URLSession

    /// `address` z. B. „192.168.178.99:5056“ oder „http://nas:5056“.
    public init(address: String, session: URLSession = .shared) throws {
        var text = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw ClientError.badAddress }
        if !text.lowercased().hasPrefix("http") { text = "http://" + text }
        while text.hasSuffix("/") { text.removeLast() }
        guard let url = URL(string: text), url.host != nil else { throw ClientError.badAddress }
        baseURL = url
        self.session = session
    }

    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }()

    private struct MediathekResponse: Decodable {
        let items: [MediathekMovie]
    }

    /// Alle Spielfilme mit aktuellem Mediathek-Treffer, nach Bewertung sortiert.
    /// Reihen und Filter bildet die App selbst, so reicht ein Abruf.
    public func mediathekMovies(limit: Int = 2000) async throws -> [MediathekMovie] {
        let data = try await get("api/mediathek", query: [URLQueryItem(name: "limit", value: String(limit))])
        return try Self.decoder.decode(MediathekResponse.self, from: data).items
    }

    public func movie(id: Int) async throws -> MovieDetail {
        let data = try await get("api/item/movie/\(id)", query: [])
        return try Self.decoder.decode(MovieDetail.self, from: data)
    }

    /// Merkliste in press2arr setzen oder entfernen.
    public func setBookmark(id: Int, _ bookmarked: Bool) async throws {
        var request = URLRequest(url: baseURL.appendingPathComponent("api/item/movie/\(id)/bookmark"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["bookmarked": bookmarked])
        let (_, response) = try await session.data(for: request)
        try Self.check(response)
    }

    private func get(_ path: String, query: [URLQueryItem]) async throws -> Data {
        var components = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)
        if !query.isEmpty { components?.queryItems = query }
        guard let url = components?.url else { throw ClientError.badAddress }
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        let (data, response) = try await session.data(for: request)
        try Self.check(response)
        return data
    }

    private static func check(_ response: URLResponse) throws {
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw ClientError.http(http.statusCode)
        }
    }
}

// MARK: Reihen und Filter für die Übersicht

public enum MediathekSort: String, CaseIterable, Sendable {
    case rating, newest, year

    public var label: String {
        switch self {
        case .rating: return "Bewertung"
        case .newest: return "Neu in der Mediathek"
        case .year: return "Erscheinungsjahr"
        }
    }
}

public enum MediathekShelf {
    public static func sorted(_ movies: [MediathekMovie], by sort: MediathekSort) -> [MediathekMovie] {
        switch sort {
        case .rating:
            return movies.sorted { ($0.rating ?? 0, $0.year ?? 0) > ($1.rating ?? 0, $1.year ?? 0) }
        case .newest:
            return movies.sorted { ($0.mtSince ?? 0, $0.rating ?? 0) > ($1.mtSince ?? 0, $1.rating ?? 0) }
        case .year:
            return movies.sorted { ($0.year ?? 0, $0.rating ?? 0) > ($1.year ?? 0, $1.rating ?? 0) }
        }
    }

    /// Filter „lief im Kino“ und „in der Presse besprochen“ sind kombinierbar (beides muss gelten).
    public static func filtered(_ movies: [MediathekMovie], cinema: Bool, press: Bool) -> [MediathekMovie] {
        movies.filter { (!cinema || $0.ranInCinema) && (!press || $0.reviewedInPress) }
    }
}
