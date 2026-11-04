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
        // Schlüssel wie in der Standardbelegung, damit der Top-Shelf-Link den Sender findet
        for channel in defaults {
            XCTAssertTrue(DefaultLineup.main.contains(channel.groupKey), channel.groupKey)
        }

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

    func testChannelLogoSlugNormalization() {
        // Beispiele für die Dateinamen-Normalisierung
        XCTAssertEqual(ChannelLogo.slug(for: "WDR"), "wdr")
        XCTAssertEqual(ChannelLogo.slug(for: "NDR FS HH"), "ndr_fs_hh")
        XCTAssertEqual(ChannelLogo.slug(for: "SWR Fernsehen BW"), "swr_fernsehen_bw")
        // Sonderzeichen entfernt, Umlaute umgeschrieben, Präfix/Suffix entfernt
        XCTAssertEqual(ChannelLogo.slug(for: "SAT.1"), "sat1")
        XCTAssertEqual(ChannelLogo.slug(for: "hr-fernsehen"), "hrfernsehen")
        XCTAssertEqual(ChannelLogo.slug(for: "BR Süd"), "br_sued")
        XCTAssertEqual(ChannelLogo.slug(for: "CNN (eng)"), "cnn")
        XCTAssertEqual(ChannelLogo.slug(for: "BBC News eng"), "bbc_news")
        XCTAssertEqual(ChannelLogo.slug(for: "Home & Garden TV"), "home_garden_tv")
    }

    func testChannelLogoCandidatesTryWithAndWithoutHD() {
        let urls = ChannelLogo.candidateURLs(for: "Das Erste HD").map(\.absoluteString)
        XCTAssertEqual(urls, ["http://tv.avm.de/tvapp/logos/das_erste_hd.png",
                              "http://tv.avm.de/tvapp/logos/das_erste.png"])
        XCTAssertEqual(ChannelLogo.candidateURLs(for: "ZDF").map(\.absoluteString),
                       ["http://tv.avm.de/tvapp/logos/zdf.png"])
    }

    func testPublicHLSLookupIsExactNotSubstring() {
        let zdf = PublicHLSChannels.streams["zdf"]
        XCTAssertEqual(PublicHLSChannels.hlsURL(for: "tv:zdf"), zdf)
        XCTAssertEqual(PublicHLSChannels.hlsURL(for: "tv:zdfinfo"), PublicHLSChannels.streams["zdfinfo"])
        XCTAssertEqual(PublicHLSChannels.hlsURL(for: "tv:zdfneo"), PublicHLSChannels.streams["zdfneo"])
        XCTAssertEqual(PublicHLSChannels.hlsURL(for: "tv:zdf_neo"), PublicHLSChannels.streams["zdfneo"])
        XCTAssertEqual(PublicHLSChannels.hlsURL(for: "tv:swr rp"), PublicHLSChannels.streams["swr rp"])
        XCTAssertEqual(PublicHLSChannels.hlsURL(for: "tv:ndr fs nds"), PublicHLSChannels.streams["ndr niedersachsen"])
        XCTAssertEqual(PublicHLSChannels.hlsURL(for: "Das Erste HD"), PublicHLSChannels.streams["das erste"])
        XCTAssertEqual(PublicHLSChannels.hlsURL(for: "hr-fernsehen"), PublicHLSChannels.streams["hr-fernsehen"])
        XCTAssertEqual(PublicHLSChannels.hlsURL(for: "hr fernsehen"), PublicHLSChannels.streams["hr-fernsehen"])
        XCTAssertEqual(PublicHLSChannels.hlsURL(for: "hr"), PublicHLSChannels.streams["hr-fernsehen"])
        // Präfix als ganzes Wort: „wdr koln“ hat einen eigenen Eintrag, „wdr duisburg“ fällt auf „wdr“
        XCTAssertEqual(PublicHLSChannels.hlsURL(for: "tv:wdr duisburg"), PublicHLSChannels.streams["wdr"])
        // Private Sender und zufällige Teilstrings ergeben nichts
        XCTAssertNil(PublicHLSChannels.hlsURL(for: "tv:rtl"))
        XCTAssertNil(PublicHLSChannels.hlsURL(for: "tv:disney channel"))
        XCTAssertNil(PublicHLSChannels.hlsURL(for: "   "))
    }
}
