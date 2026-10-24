import XCTest
@testable import FritzTVKit

final class TunerAndCandidatesTests: XCTestCase {

    private func fixtureChannels() throws -> [Channel] {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "tv-nach-suchlauf", withExtension: "m3u", subdirectory: "Fixtures"))
        return M3UParser.parse(data: try Data(contentsOf: url))
    }

    func testDeadVariantsSortedToEnd() throws {
        let catalog = ChannelCatalog(channels: try fixtureChannels())
        let ard = try XCTUnwrap(catalog.groups.first { $0.displayName == "Das Erste" })

        // Ohne deadIDs: Frequenzen [386, 330]
        let original = ard.candidates(preferHD: true)
        XCTAssertEqual(original.compactMap { $0.tuning?.frequencyMHz }, [386, 330])

        // Wenn 386 als tot markiert ist: 330 wandert nach vorne!
        let dead386 = Set([original[0].id])
        let reprioritized = ard.candidates(preferHD: true, deadIDs: dead386)
        XCTAssertEqual(reprioritized.compactMap { $0.tuning?.frequencyMHz }, [330, 386])

        // Wenn alle Varianten tot sind: areAllVariantsDead gibt true
        let allDead = Set(original.map(\.id))
        XCTAssertTrue(ard.areAllVariantsDead(deadIDs: allDead))
        XCTAssertFalse(ard.areAllVariantsDead(deadIDs: dead386))
    }

    func testTunerStatusAllBusyCalculation() {
        let freeStatus = TunerStatus(
            totalTuners: 4,
            tuners: [
                TunerInfo(tunerNumber: 0, isUsed: true, hasLock: true, channelName: "ZDF"),
                TunerInfo(tunerNumber: 1, isUsed: false, hasLock: false),
                TunerInfo(tunerNumber: 2, isUsed: false, hasLock: false),
                TunerInfo(tunerNumber: 3, isUsed: false, hasLock: false)
            ]
        )
        XCTAssertEqual(freeStatus.usedCount, 1)
        XCTAssertEqual(freeStatus.freeCount, 3)
        XCTAssertFalse(freeStatus.allTunersBusy)

        let busyStatus = TunerStatus(
            totalTuners: 4,
            tuners: [
                TunerInfo(tunerNumber: 0, isUsed: true, hasLock: true, channelName: "ZDF"),
                TunerInfo(tunerNumber: 1, isUsed: true, hasLock: true, channelName: "Das Erste"),
                TunerInfo(tunerNumber: 2, isUsed: true, hasLock: true, channelName: "RTL"),
                TunerInfo(tunerNumber: 3, isUsed: true, hasLock: true, channelName: "SAT.1")
            ]
        )
        XCTAssertEqual(busyStatus.usedCount, 4)
        XCTAssertEqual(busyStatus.freeCount, 0)
        XCTAssertTrue(busyStatus.allTunersBusy)
    }
}
