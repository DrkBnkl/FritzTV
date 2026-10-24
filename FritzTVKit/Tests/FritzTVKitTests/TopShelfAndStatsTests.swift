import XCTest
import CoreGraphics
@testable import FritzTVKit

final class TopShelfAndStatsTests: XCTestCase {

    func testPlaybackStatisticsLabels() {
        var stats = PlaybackStatistics()
        XCTAssertEqual(stats.resolutionLabel, "")
        XCTAssertEqual(stats.bitrateLabel, "")
        XCTAssertEqual(stats.lossLabel, "0 Bildfehler")

        stats.videoSize = CGSize(width: 1920, height: 1080)
        stats.inputBitrateMbps = 11.52
        stats.lostPictures = 3
        stats.demuxDiscontinuities = 1
        stats.signalPowerDB = -4.0
        stats.signalNoiseRatioDB = 33.0
        stats.tunerUsage = (used: 2, total: 4)

        XCTAssertTrue(stats.resolutionLabel.contains("1080p"))
        XCTAssertEqual(stats.bitrateLabel, "11.5 Mbit/s")
        XCTAssertEqual(stats.lossLabel, "3 verloren, 1 Abrisse")
        XCTAssertEqual(stats.signalLabel, "Signal: -4 dB · SNR: 33 dB")
        XCTAssertEqual(stats.tunerLabel, "Tuner 2/4")
    }

    func testTopShelfStoreDefaultsAndSave() {
        let defaults = TopShelfStore.defaultChannels
        XCTAssertFalse(defaults.isEmpty)
        XCTAssertEqual(defaults.first?.name, "Das Erste HD")

        let custom = [
            TopShelfChannel(number: 42, name: "Test Sender HD", groupKey: "test", isHD: true)
        ]
        TopShelfStore.save(channels: custom)
        let loaded = TopShelfStore.load()
        XCTAssertEqual(loaded.first?.number, 42)
        XCTAssertEqual(loaded.first?.name, "Test Sender HD")

        // Restore defaults
        TopShelfStore.save(channels: defaults)
    }
}
