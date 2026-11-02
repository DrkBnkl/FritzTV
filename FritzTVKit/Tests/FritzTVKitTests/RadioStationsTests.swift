import XCTest
@testable import FritzTVKit

final class RadioStationsTests: XCTestCase {

    private func catalog() -> ChannelCatalog {
        let tv = "#EXTM3U\n#EXTINF:0,ZDF HD\nrtsp://x/?freq=1&pids=0\n#EXTINF:0,RTL\nrtsp://x/?freq=1&pids=1\n"
        let radio = "#EXTM3U\n#EXTINF:0,1LIVE\nrtsp://x/?freq=2&pids=0\n#EXTINF:0,WDR 2\nrtsp://x/?freq=2&pids=1\n"
            + "#EXTINF:0,COSMO\nrtsp://x/?freq=2&pids=2\n#EXTINF:0,WDR 5\nrtsp://x/?freq=2&pids=3\n"
        return ChannelCatalog(channels: M3UParser.parse(tv) + M3UParser.parse(data: Data(radio.utf8), kind: .radio))
    }

    func testRadioStaysOutOfTheTVLineup() {
        let catalog = catalog()
        let lineup = ChannelLineup(catalog: catalog)
        XCTAssertEqual(RadioStations(catalog: catalog).all.count, 4)
        XCTAssertFalse(lineup.entries.contains { $0.group.variants[0].kind == .radio })
        XCTAssertFalse(lineup.hiddenGroups.contains { $0.variants[0].kind == .radio })
    }

    func testStationsKeepTheOrderOfTheBox() {
        let names = RadioStations(catalog: catalog()).all.map(\.displayName)
        XCTAssertEqual(names, ["1LIVE", "WDR 2", "COSMO", "WDR 5"])
    }

    func testZappingWrapsAround() throws {
        let stations = RadioStations(catalog: catalog())
        let first = try XCTUnwrap(stations.all.first)
        let last = try XCTUnwrap(stations.all.last)
        XCTAssertEqual(stations.station(after: first, step: -1), last)
        XCTAssertEqual(stations.station(after: last, step: 1), first)
        XCTAssertEqual(stations.station(after: first, step: 1), stations.all[1])
    }

    func testNoNextStationWithoutRadio() throws {
        let group = try XCTUnwrap(RadioStations(catalog: catalog()).all.first)
        XCTAssertNil(RadioStations().station(after: group, step: 1))
    }

    func testRecentSkipsStationsThatNoLongerExist() {
        let stations = RadioStations(catalog: catalog())
        let keys = [stations.all[2].key, "radio:gibtesnicht", stations.all[0].key]
        XCTAssertEqual(stations.recent(keys: keys).map(\.displayName), ["COSMO", "1LIVE"])
    }

    func testRecordingMovesKeyToFrontWithoutDuplicates() {
        XCTAssertEqual(RadioStations.recording(key: "b", in: ["a", "b", "c"]), ["b", "a", "c"])
        XCTAssertEqual(RadioStations.recording(key: "d", in: ["a", "b", "c"]), ["d", "a", "b"])
    }
}
