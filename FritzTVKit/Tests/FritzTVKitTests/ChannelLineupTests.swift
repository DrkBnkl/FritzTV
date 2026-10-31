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

    func testPublicBroadcasterIdentification() {
        let publicNames = [
            "Das Erste", "Das Erste HD", "ARD", "ZDF", "ZDF HD",
            "ZDFneo", "zdf_neo", "zdf neo", "ZDFinfo", "3sat",
            "arte", "phoenix", "KiKa", "ONE", "tagesschau24",
            "ARD alpha", "ARD-alpha", "rbb Berlin", "rbb Brandenburg",
            "WDR Köln", "BR Süd", "hr-fernsehen", "hr fernsehen",
            "NDR FS NDS", "MDR Sachsen", "SWR RP", "SR Fernsehen",
            "Radio Bremen TV", "Parlamentsfernsehen"
        ]
        for name in publicNames {
            XCTAssertTrue(Channel.isPublicBroadcaster(name: name), "\(name) sollte als ÖRR erkannt werden")
        }

        let privateNames = [
            "RTL", "SAT.1", "ProSieben", "VOX", "kabel eins", "RTLZWEI",
            "SUPER RTL", "ntv", "WELT", "NITRO", "sixx", "TELE 5",
            "DMAX", "TLC", "SPORT1", "Eurosport 1", "Disney Channel",
            "QVC", "HSE", "1-2-3.tv", "DELUXE MUSIC", "CNN", "DF1"
        ]
        for name in privateNames {
            XCTAssertFalse(Channel.isPublicBroadcaster(name: name), "\(name) sollte NICHT als ÖRR erkannt werden")
        }
    }

    func testZDFneoHDReplacesSDAndAssignedSlot7() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "tv-nach-suchlauf", withExtension: "m3u", subdirectory: "Fixtures"))
        let rawChannels = M3UParser.parse(data: try Data(contentsOf: url))
        
        // Die Rohdaten enthalten sowohl "ZDFneo HD" als auch das alte tote "zdf_neo" SD
        XCTAssertTrue(rawChannels.contains { $0.name == "ZDFneo HD" && $0.isHD })
        XCTAssertTrue(rawChannels.contains { $0.name == "zdf_neo" && !$0.isHD })

        // ChannelCatalog filtert die tote SD-Variante heraus
        let catalog = ChannelCatalog(channels: rawChannels)
        let zdfneoGroup = try XCTUnwrap(catalog.groups.first { $0.key == "tv:zdf_neo" })
        XCTAssertEqual(zdfneoGroup.displayName, "ZDFneo")
        XCTAssertTrue(zdfneoGroup.variants.allSatisfy(\.isHD))
        XCTAssertNil(zdfneoGroup.sd)

        // Lineup ordnet ZDFneo HD auf Platz 7 zu (entsprechend DefaultLineup "zdf_neo")
        let lineup = ChannelLineup(catalog: catalog)
        let slot7 = try XCTUnwrap(lineup.entry(number: 7))
        XCTAssertEqual(slot7.group.displayName, "ZDFneo")
        XCTAssertFalse(slot7.isNew)
        XCTAssertTrue(slot7.group.variants.allSatisfy(\.isHD))
    }
}
