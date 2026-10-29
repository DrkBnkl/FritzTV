import XCTest
@testable import FritzTVKit

final class ChannelLineupTests: XCTestCase {

    private func catalog() throws -> ChannelCatalog {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "tv", withExtension: "m3u", subdirectory: "Fixtures"))
        return ChannelCatalog(channels: M3UParser.parse(data: try Data(contentsOf: url)))
    }

    func testDefaultLineupCoversEveryChannelOfTheBox() throws {
        let lineup = ChannelLineup(catalog: try catalog())
        XCTAssertEqual(lineup.entries.count, 65)         // 47 Haupt- + 18 Nischensender
        XCTAssertEqual(lineup.hiddenGroups.count, 16)    // Shopping und Religion
        XCTAssertFalse(lineup.entries.contains { $0.isNew })
    }

    func testFirstPlacesFollowTheClassicOrder() throws {
        let lineup = ChannelLineup(catalog: try catalog())
        let firstFour = (1...4).compactMap { lineup.entry(number: $0)?.group.displayName }
        XCTAssertEqual(firstFour, ["Das Erste", "ZDF", "rbb Berlin", "arte"])
        XCTAssertEqual(lineup.entry(number: 21)?.group.displayName, "RTL")
    }

    func testZappingWrapsAround() throws {
        let lineup = ChannelLineup(catalog: try catalog())
        XCTAssertEqual(lineup.entry(after: 1, step: -1)?.number, 65)
        XCTAssertEqual(lineup.entry(after: 65, step: 1)?.number, 1)
    }

    func testCustomOrderHiddenAndNewChannels() throws {
        var prefs = LineupPreferences.standard
        prefs.order.removeAll { $0 == "arte" }
        prefs.order.insert("arte", at: 0)
        prefs.hidden.insert("rtl")
        prefs.order.removeAll { $0 == "welt" }           // simuliert einen neu gefundenen Sender

        let lineup = ChannelLineup(catalog: try catalog(), preferences: prefs)
        XCTAssertEqual(lineup.entry(number: 1)?.group.displayName, "arte")
        XCTAssertFalse(lineup.entries.contains { $0.group.displayName == "RTL" })
        XCTAssertEqual(lineup.entries.last?.group.displayName, "WELT")
        XCTAssertEqual(lineup.entries.last?.isNew, true)
    }

    func testPreferencesRoundTripThroughJSON() throws {
        let data = try JSONEncoder().encode(LineupPreferences.standard)
        XCTAssertEqual(try JSONDecoder().decode(LineupPreferences.self, from: data), .standard)
    }
}
