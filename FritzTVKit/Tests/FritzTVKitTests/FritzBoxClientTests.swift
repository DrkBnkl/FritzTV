import XCTest
@testable import FritzTVKit

final class FritzBoxClientTests: XCTestCase {
    private static let playlist = """
    #EXTM3U
    #EXTINF:0,Das Erste HD
    #EXTVLCOPT:network-caching=1000
    rtsp://192.168.178.1:554/?avm=1&freq=386&bw=8&msys=dvbc&mtype=256qam&sr=6900&specinv=1&pids=0,16,17,18,20,5100
    """

    override func tearDown() {
        StubProtocol.responses = [:]
        super.tearDown()
    }

    func testRecognizesPlaylist() {
        XCTAssertTrue(FritzBoxClient.isPlaylist(Data("#EXTM3U\n".utf8)))
        XCTAssertTrue(FritzBoxClient.isPlaylist(Data("\u{FEFF}\n#EXTM3U\n".utf8)))
        XCTAssertFalse(FritzBoxClient.isPlaylist(Data("<!DOCTYPE html><html>FRITZ!Box</html>".utf8)))
        XCTAssertFalse(FritzBoxClient.isPlaylist(Data()))
    }

    /// Liefert `fritz.box` etwas anderes als eine Liste (Login-Seite nach Umleitung, fremder Server),
    /// kommt die Standard-IP dran statt „keine Sender“.
    func testFallsBackWhenHostAnswersWithoutPlaylist() async throws {
        for path in ["tvhd", "tvsd", "radio"] {
            StubProtocol.responses["http://fritz.box/dvb/m3u/\(path).m3u"] = (200, "<html>Anmeldung</html>")
        }
        StubProtocol.responses["http://192.168.178.1/dvb/m3u/tvhd.m3u"] = (200, Self.playlist)
        let result = try await FritzBoxClient(session: Self.session).loadCatalog()
        XCTAssertEqual(result.host, "192.168.178.1")
        XCTAssertEqual(result.catalog.tvGroups.count, 1)
    }

    /// Fehlt nur eine Liste (404), gilt die Box trotzdem als gefunden.
    func testMissingSinglePlaylistKeepsHost() async throws {
        StubProtocol.responses["http://fritz.box/dvb/m3u/tvhd.m3u"] = (200, Self.playlist)
        let result = try await FritzBoxClient(session: Self.session).loadCatalog()
        XCTAssertEqual(result.host, "fritz.box")
    }

    private static var session: URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubProtocol.self]
        return URLSession(configuration: configuration)
    }
}

/// Antwortet aus einer festen Tabelle; unbekannte Adressen bekommen 404.
private final class StubProtocol: URLProtocol {
    nonisolated(unsafe) static var responses: [String: (status: Int, body: String)] = [:]

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url else { return }
        let entry = Self.responses[url.absoluteString] ?? (404, "")
        let response = HTTPURLResponse(url: url, statusCode: entry.status, httpVersion: "HTTP/1.1", headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(entry.body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
