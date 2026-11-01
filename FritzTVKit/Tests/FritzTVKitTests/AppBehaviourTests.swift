import XCTest
@testable import FritzTVKit

final class AppBehaviourTests: XCTestCase {

    private func tuner(_ number: Int, name: String?, used: Bool = true) -> TunerInfo {
        TunerInfo(tunerNumber: number, isUsed: used, hasLock: used, signalPower: Double(number), channelName: name)
    }

    func testActiveTunerMatchesByChannelName() {
        let status = TunerStatus(totalTuners: 4, tuners: [tuner(0, name: "RTL"), tuner(1, name: "ZDF HD")])
        XCTAssertEqual(status.activeTuner(forChannelNames: ["ZDF HD", "ZDF"])?.tunerNumber, 1)
    }

    func testActiveTunerFallsBackToTheOnlyUsedOne() {
        let status = TunerStatus(totalTuners: 4, tuners: [tuner(0, name: nil, used: false), tuner(1, name: nil)])
        XCTAssertEqual(status.activeTuner(forChannelNames: ["ZDF HD"])?.tunerNumber, 1)
    }

    func testActiveTunerDoesNotGuessAmongForeignTuners() {
        let status = TunerStatus(totalTuners: 4, tuners: [tuner(0, name: "RTL"), tuner(1, name: "VOX")])
        XCTAssertNil(status.activeTuner(forChannelNames: ["ZDF HD"]))
    }

    func testEntryByGroupKeyAcceptsAliasesAndRejectsUnknownChannels() {
        let m3u = "#EXTM3U\n#EXTINF:0,ZDF HD\nrtsp://x/?freq=1&pids=0\n#EXTINF:0,ZDFneo HD\nrtsp://x/?freq=1&pids=1\n"
        let lineup = ChannelLineup(catalog: ChannelCatalog(channels: M3UParser.parse(m3u)),
                                   preferences: LineupPreferences(order: ["zdf", "zdf_neo"], hidden: []))
        XCTAssertEqual(lineup.entry(groupKey: "zdfneo")?.number, 2)
        XCTAssertEqual(lineup.entry(groupKey: "ZDF")?.number, 1)
        XCTAssertNil(lineup.entry(groupKey: "rbb berlin"))
    }
}
