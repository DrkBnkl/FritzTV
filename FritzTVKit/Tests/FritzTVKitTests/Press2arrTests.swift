import XCTest
@testable import FritzTVKit

/// Prüft das Lesen der press2arr-Antworten (Beispiele aus dem press2arr-Mock, Oktober 2026).
final class Press2arrTests: XCTestCase {

    private let listJSON = """
    {"items": [
      {"backdrop_path": "/b124.jpg", "bookmarked": false, "channels": ["ARD"], "genres": ["Drama", "Komödie"],
       "makers": ["Anna Berger"], "media_type": "movie", "mt_since": 1792000000, "n_cinema": 0, "n_press": 0,
       "original_title": "The Whale", "overview": "Ein Literaturdozent will seine Tochter zurückgewinnen.",
       "poster_path": "/p124.jpg", "press_sources": [], "press_verdict": null, "rating": 7.7,
       "rating_source": "IMDb", "runtime": 118, "tagline": "", "title": "The Whale", "tmdb_id": 124, "year": 2022},
      {"tmdb_id": 101, "title": "Der Sturm", "year": 2026, "rating": 7.1, "mt_since": 1792500000,
       "channels": ["3Sat", "ARD"], "n_cinema": 2, "n_press": 3,
       "press_sources": ["FAZ Kino", "Spiegel Kino", "Zeit Film"], "press_verdict": "positiv"}
    ], "channels": [["ARD", 2]], "genres": [["Drama", 2]]}
    """

    private let detailJSON = """
    {"tmdb_id": 101, "title": "Der Sturm", "year": 2026, "bookmarked": true,
     "details": {"cast": [{"character": "Marie", "name": "Sandra Hüller", "profile_path": null}],
                 "genres": ["Drama", "Thriller"], "makers": ["Anna Berger"], "runtime": 118,
                 "tagline": "Manche Stürme kommen von innen.", "providers": [], "votes": 300},
     "mentions": [
       {"cinema": null, "date": "2026-10-16T10:00:00+00:00", "source": "Spiegel Kino",
        "summary": "Das Ereignis des Herbstes.", "title": "Kinostart „Der Sturm“", "url": "http://spiegel/1",
        "verdict": "positiv"},
       {"cinema": 1, "source": "Yorck", "summary": "Delphi Filmpalast · OmU", "title": "Der Sturm", "verdict": "keins"}],
     "mediathek": {"checking": false, "hits": [
       {"channel": "ARD", "duration": 7020, "hardsub": false, "id": "mvw1", "ov": false, "quality": "HD",
        "timestamp": 1792000000, "title": "Der Sturm", "url": "http://mediathek-video/1_hd.mp4"},
       {"channel": "ARTE.DE", "id": "mvw2", "ov": true, "quality": null, "title": "Der Sturm (OV)", "url": null}]}}
    """

    func testDecodesMediathekList() throws {
        let data = Data(listJSON.utf8)
        struct Wrapper: Decodable { let items: [MediathekMovie] }
        let movies = try Press2arrClient.decoder.decode(Wrapper.self, from: data).items
        XCTAssertEqual(movies.count, 2)
        XCTAssertEqual(movies[0].title, "The Whale")
        XCTAssertEqual(movies[0].posterURL?.absoluteString, "https://image.tmdb.org/t/p/w342/p124.jpg")
        XCTAssertFalse(movies[0].ranInCinema)
        XCTAssertTrue(movies[1].ranInCinema)
        XCTAssertTrue(movies[1].reviewedInPress)
        XCTAssertEqual(movies[1].pressSources.count, 3)
        XCTAssertEqual(movies[1].pressVerdict, "positiv")
        XCTAssertEqual(movies[1].genres, [])          // fehlende Felder sind kein Fehler
    }

    func testFilterAndSort() throws {
        struct Wrapper: Decodable { let items: [MediathekMovie] }
        let movies = try Press2arrClient.decoder.decode(Wrapper.self, from: Data(listJSON.utf8)).items
        XCTAssertEqual(MediathekShelf.filtered(movies, cinema: true, press: false).map(\.tmdbId), [101])
        XCTAssertEqual(MediathekShelf.filtered(movies, cinema: false, press: true).map(\.tmdbId), [101])
        XCTAssertEqual(MediathekShelf.filtered(movies, cinema: false, press: false).count, 2)
        XCTAssertEqual(MediathekShelf.sorted(movies, by: .rating).map(\.tmdbId), [124, 101])
        XCTAssertEqual(MediathekShelf.sorted(movies, by: .newest).map(\.tmdbId), [101, 124])
        XCTAssertEqual(MediathekShelf.sorted(movies, by: .year).map(\.tmdbId), [101, 124])
    }

    func testDecodesDetail() throws {
        let detail = try Press2arrClient.decoder.decode(MovieDetail.self, from: Data(detailJSON.utf8))
        XCTAssertEqual(detail.details?.makers, ["Anna Berger"])
        XCTAssertEqual(detail.details?.cast?.first?.name, "Sandra Hüller")
        XCTAssertEqual(detail.reviews.map(\.source), ["Spiegel Kino"])
        XCTAssertEqual(detail.cinemaEntries.map(\.source), ["Yorck"])
        XCTAssertEqual(detail.playableHits.count, 1)   // Treffer ohne Link fällt weg
        XCTAssertEqual(detail.playableHits.first?.streamURL?.absoluteString, "http://mediathek-video/1_hd.mp4")
        XCTAssertEqual(detail.bookmarked, true)
    }

    func testAddressParsing() throws {
        XCTAssertEqual(try Press2arrClient(address: "192.168.178.99:5056").baseURL.absoluteString, "http://192.168.178.99:5056")
        XCTAssertEqual(try Press2arrClient(address: "http://nas.local:5056/").baseURL.absoluteString, "http://nas.local:5056")
        XCTAssertThrowsError(try Press2arrClient(address: "  "))
    }
}
