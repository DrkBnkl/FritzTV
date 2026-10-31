import XCTest
@testable import FritzTVKit

final class ReviewRegressionTests: XCTestCase {

    private func catalog(_ names: [String]) -> ChannelCatalog {
        let m3u = names.enumerated()
            .map { "#EXTINF:0,\($1)\nrtsp://192.168.178.1:554/?avm=1&freq=450&pids=0,\($0 + 100)\n" }
            .joined()
        return ChannelCatalog(channels: M3UParser.parse("#EXTM3U\n" + m3u))
    }

    // MARK: Anmeldung

    func testOnlyDigestReceivesCredentials() {
        XCTAssertTrue(DigestDelegate.acceptsCredentials(forAuthenticationMethod: NSURLAuthenticationMethodHTTPDigest))
        XCTAssertFalse(DigestDelegate.acceptsCredentials(forAuthenticationMethod: NSURLAuthenticationMethodHTTPBasic))
    }

    // MARK: Senderplätze

    func testHidingAChannelMissingFromOrderTakesEffect() {
        let prefs = LineupPreferences(order: ["zdf"], hidden: ["neuer sender"])
        let lineup = ChannelLineup(catalog: catalog(["ZDF HD", "Neuer Sender"]), preferences: prefs)
        XCTAssertEqual(lineup.entries.map(\.group.displayName), ["ZDF"])
        XCTAssertEqual(lineup.hiddenGroups.map(\.displayName), ["Neuer Sender"])
    }

    func testAliasKeysInOrderDoNotDuplicateAChannel() {
        let prefs = LineupPreferences(order: ["zdf", "zdfneo", "zdf_neo"], hidden: [])
        let lineup = ChannelLineup(catalog: catalog(["ZDF HD", "ZDFneo HD"]), preferences: prefs)
        XCTAssertEqual(lineup.entries.map(\.number), [1, 2])
        XCTAssertEqual(lineup.entries.map(\.group.displayName), ["ZDF", "ZDFneo"])
    }

    func testNormalizedPreferencesUseCanonicalKeys() {
        let prefs = LineupPreferences(order: ["zdfneo", "zdf_neo", "rtl"], hidden: ["zdf neo"]).normalized
        XCTAssertEqual(prefs.order, ["zdf_neo", "rtl"])
        XCTAssertEqual(prefs.hidden, ["zdf_neo"])
    }

    // MARK: SD-Filter

    func testPublicChannelWithoutHDVariantStays() {
        let groups = catalog(["WDR Aachen", "RTL Television"]).groups
        XCTAssertEqual(groups.map(\.displayName), ["WDR Aachen", "RTL Television"])
    }

    func testPublicSDIsDroppedWhenHDExists() throws {
        let group = try XCTUnwrap(catalog(["ZDF HD", "ZDF"]).groups.first)
        XCTAssertTrue(group.variants.allSatisfy(\.isHD))
    }

    // MARK: HLS

    func testMDRSachsenAnhaltGetsItsOwnStream() throws {
        let anhalt = try XCTUnwrap(PublicHLSChannels.streams["mdr sachsen-anhalt"])
        XCTAssertEqual(PublicHLSChannels.hlsURL(for: "tv:mdr sachsen-anhalt"), anhalt)
        XCTAssertEqual(PublicHLSChannels.hlsURL(for: "tv:mdr s-anhalt"), anhalt)
        XCTAssertEqual(PublicHLSChannels.hlsURL(for: "tv:mdr sachsen"), PublicHLSChannels.streams["mdr sachsen"])
    }

    // MARK: EPG

    func testStoreAndScheduleAgreeOnOverlappingPrograms() throws {
        let store = EPGStore()
        let now = Date()
        store.setServiceName("Test", for: 1)
        for id in 0..<40 {
            store.add(program: EPGProgram(eventID: id, serviceID: 1, title: "Sendung \(id)",
                                          startDate: now.addingTimeInterval(-600), duration: 3600,
                                          isRunningStatus: true))
        }
        let schedule = try XCTUnwrap(store.schedule(for: 1))
        XCTAssertEqual(schedule.currentProgram(at: now)?.title, "Sendung 39")
        XCTAssertEqual(store.currentProgram(forChannelNames: ["Test"], at: now)?.title, "Sendung 39")
    }

    func testRescheduledProgramWinsOverItsStaleEntry() {
        let now = Date()
        let stale = EPGProgram(eventID: 1, serviceID: 1, title: "Alt", startDate: now.addingTimeInterval(-3000), duration: 3600)
        let fresh = EPGProgram(eventID: 2, serviceID: 1, title: "Neu", startDate: now.addingTimeInterval(-600), duration: 1800)
        XCTAssertEqual(EPGChannelSchedule(serviceID: 1, programs: [fresh, stale]).currentProgram(at: now)?.title, "Neu")
    }
}
