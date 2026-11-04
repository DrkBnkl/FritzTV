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

    private func stations(_ names: [String]) -> RadioStations {
        let m3u = "#EXTM3U\n" + names.enumerated()
            .map { "#EXTINF:0,\($1)\nrtsp://x/?freq=\($0)&pids=0\n" }.joined()
        return RadioStations(catalog: ChannelCatalog(channels: M3UParser.parse(data: Data(m3u.utf8), kind: .radio)))
    }

    func testDuplicateSpellingsBecomeOneStationWithAllVariants() throws {
        let list = stations(["BAYERN 3", "Bayern 3", "Antenne Brbg.", "Antenne Brandenburg",
                             "Bremen Next", "Bremen NEXT", "WDR 2  Ostwestfalen/Lippe", "WDR 2 Ostwestfalen/Lippe"])
        XCTAssertEqual(list.all.count, 4)
        let antenne = try XCTUnwrap(list.all.first { $0.displayName == "Antenne Brandenburg" })
        XCTAssertEqual(antenne.variants.count, 2)
        XCTAssertTrue(list.all.contains { $0.displayName == "WDR 2 Ostwestfalen/Lippe" })
    }

    func testFamiliesAreSortedAndPrivateStationsComeLast() {
        let list = stations(["bigFM", "hr3", "SR 3 Saarlandwelle", "WDR 2", "SWR3", "Fritz", "Dlf"])
        let ids = list.sections(favoriteKeys: [], recentKeys: [], deadIDs: []).map(\.id)
        XCTAssertEqual(ids, ["WDR", "SWR", "hr", "rbb", "SR", "Deutschlandradio", "Weitere Sender"])
    }

    func testFavoritesAndRecentComeFirstAndEmptySectionsAreDropped() {
        let list = stations(["WDR 2", "bigFM"])
        let bigFM = list.all[1].key
        let sections = list.sections(favoriteKeys: [bigFM], recentKeys: [], deadIDs: [])
        XCTAssertEqual(sections.map(\.id), ["favorites", "WDR", "Weitere Sender"])
        XCTAssertEqual(sections[0].stations.map(\.displayName), ["bigFM"])
    }

    func testDeadStationsMoveToTheEndAndStayFavorites() {
        let list = stations(["WDR 2", "bigFM"])
        let dead = Set(list.all[1].variants.map(\.id))
        let sections = list.sections(favoriteKeys: [list.all[1].key], recentKeys: [], deadIDs: dead)
        XCTAssertEqual(sections.map(\.id), ["favorites", "WDR", "dead"])
        XCTAssertEqual(sections.last?.stations.map(\.displayName), ["bigFM"])
    }

    func testOneWorkingVariantKeepsStationInItsFamily() throws {
        let list = stations(["Bayern 3", "BAYERN 3"])
        let variants = try XCTUnwrap(list.all.first).variants
        let sections = list.sections(favoriteKeys: [], recentKeys: [], deadIDs: [variants[0].id])
        XCTAssertEqual(sections.map(\.id), ["BR"])
    }

    func testRadioLogosMatchTheSpellingsOfTheBox() {
        let spellings = [("BAYERN 3", "Bayern 3"), ("Antenne Brbg.", "Antenne Brandenburg"),
                         ("SWR1 BW", "SWR1 RP"), ("SWR4 BW", "SWR4 - Rheinhessen"),
                         ("Bremen Next", "Bremen NEXT"), ("ROCK ANTENNE", "Rock Antenne"),
                         ("SR 3 Saarlandwelle", "SR3")]
        for (one, other) in spellings {
            let urls = ChannelLogo.radioCandidateURLs(for: one)
            XCTAssertEqual(urls.first, ChannelLogo.radioCandidateURLs(for: other).first, one)
            XCTAssertEqual(urls.first?.scheme, "https", one)
        }
    }

    func testAllRadioLogoAddressesAreValidHTTPS() {
        for (key, address) in ChannelLogo.radioLogoAddresses {
            XCTAssertEqual(URL(string: address)?.scheme, "https", key)
        }
    }

    func testRadioStationWithoutOwnLogoFallsBackToAVM() {
        let urls = ChannelLogo.radioCandidateURLs(for: "WDR 2")
        XCTAssertEqual(urls.first?.absoluteString, "http://tv.avm.de/tvapp/logos/wdr_2.png")
    }

    func testTVLogosStayUnchanged() {
        XCTAssertEqual(ChannelLogo.candidateURLs(for: "1LIVE").first?.host, "tv.avm.de")
    }

    func testPlaceholderProgramIsRecognised() {
        XCTAssertTrue(EPGProgram.isPlaceholderTitle("Leider keine Programminformationen vorhanden"))
        XCTAssertFalse(EPGProgram.isPlaceholderTitle("WDR 2 Der Vormittag"))
    }

    func testRecordingMovesKeyToFrontWithoutDuplicates() {
        XCTAssertEqual(RadioStations.recording(key: "b", in: ["a", "b", "c"]), ["b", "a", "c"])
        XCTAssertEqual(RadioStations.recording(key: "d", in: ["a", "b", "c"]), ["d", "a", "b"])
    }
}
