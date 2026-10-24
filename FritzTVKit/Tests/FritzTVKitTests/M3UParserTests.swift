import XCTest
@testable import FritzTVKit

/// Tests gegen die echte Senderliste der FRITZ!Box (Vodafone Kabel, Berlin, Okt. 2026).
final class M3UParserTests: XCTestCase {

    private func fixtureChannels() throws -> [Channel] {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "tv", withExtension: "m3u", subdirectory: "Fixtures"))
        return M3UParser.parse(data: try Data(contentsOf: url))
    }

    func testParsesAllRealChannelsAndDropsPlaceholders() throws {
        let channels = try fixtureChannels()
        // 95 Einträge, davon 3 Platzhalter („...“, „.“, „..“).
        XCTAssertEqual(channels.count, 92)
        XCTAssertFalse(channels.contains { channel in channel.name.allSatisfy { $0 == "." } })
    }

    func testReadsTuningParameters() throws {
        let zdf = try XCTUnwrap(try fixtureChannels().first { $0.name == "ZDF HD" })
        let tuning = try XCTUnwrap(zdf.tuning)
        XCTAssertEqual(tuning.frequencyMHz, 450)
        XCTAssertEqual(tuning.modulation, "256qam")
        XCTAssertEqual(tuning.symbolRate, 6900)
        XCTAssertEqual(tuning.spectralInversion, 1)
        XCTAssertTrue(tuning.includesEIT)
        XCTAssertEqual(zdf.networkCachingMilliseconds, 1000)
        XCTAssertEqual(zdf.streamURL.host, "192.168.178.1")
        XCTAssertEqual(zdf.streamURL.port, 554)
    }

    func testSplitsHDAndLanguage() throws {
        let channels = try fixtureChannels()
        let wdr = try XCTUnwrap(channels.first { $0.name == "WDR HD Köln" })
        XCTAssertTrue(wdr.isHD)
        XCTAssertEqual(wdr.displayName, "WDR Köln")

        let cnn = try XCTUnwrap(channels.first { $0.name == "CNN (eng)" })
        XCTAssertFalse(cnn.isHD)
        XCTAssertEqual(cnn.displayName, "CNN")
        XCTAssertEqual(cnn.languageTag, "eng")
    }

    func testGroupsHDAndSDVariants() throws {
        let catalog = ChannelCatalog(channels: try fixtureChannels())
        XCTAssertEqual(catalog.groups.count, 81)
        XCTAssertEqual(catalog.groups.filter { $0.hd != nil && $0.sd != nil }.count, 11)

        let zdf = try XCTUnwrap(catalog.groups.first { $0.displayName == "ZDF" })
        XCTAssertEqual(zdf.preferredChannel(preferHD: true).name, "ZDF HD")
        XCTAssertEqual(zdf.preferredChannel(preferHD: false).name, "ZDF")

        // Unterschiedliche Schreibweise wird zusammengeführt.
        let hseExtra = try XCTUnwrap(catalog.groups.first { $0.key == "tv:hse extra" })
        XCTAssertEqual(hseExtra.variants.count, 2)

        // Nur-SD-Sender fallen auf SD zurück.
        let rtl = try XCTUnwrap(catalog.groups.first { $0.displayName == "RTL" })
        XCTAssertEqual(rtl.preferredChannel(preferHD: true).name, "RTL")
    }

    func testGroupsByMultiplex() throws {
        let catalog = ChannelCatalog(channels: try fixtureChannels())
        XCTAssertEqual(catalog.channelsByFrequency.count, 18)
        XCTAssertEqual(catalog.channelsByFrequency[370]?.count, 12)
    }

    func testStripsDVBEmphasisMarkers() {
        let text = """
        #EXTM3U
        #EXTINF:0,\u{86}RTL\u{87} Television
        rtsp://192.168.178.1:554/?freq=330&pids=0,16,17,18,20
        #EXTINF:0,†DELUXE‡ MUSIC
        rtsp://192.168.178.1:554/?freq=346&pids=0,16,17,18,20
        """
        let names = M3UParser.parse(text).map(\.name)
        XCTAssertEqual(names, ["RTL Television", "DELUXE MUSIC"])
    }

    /// Nach einem Sendersuchlauf führt die Box Das Erste & Co. doppelt: neue Frequenz (386) vorne,
    /// alte (330) hinten. Beide Varianten müssen als Ausweichlinks erhalten bleiben.
    func testCandidatesAfterChannelScan() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "tv-nach-suchlauf", withExtension: "m3u", subdirectory: "Fixtures"))
        let catalog = ChannelCatalog(channels: M3UParser.parse(data: try Data(contentsOf: url)))

        let ard = try XCTUnwrap(catalog.groups.first { $0.displayName == "Das Erste" })
        let frequencies = ard.candidates(preferHD: true).compactMap { $0.tuning?.frequencyMHz }
        XCTAssertEqual(frequencies, [386, 330])
        XCTAssertEqual(ard.preferredChannel(preferHD: true).tuning?.frequencyMHz, 386)

        let br = try XCTUnwrap(catalog.groups.first { $0.displayName == "BR Süd" })
        XCTAssertEqual(br.candidates(preferHD: true).compactMap { $0.tuning?.frequencyMHz }, [402, 338])

        // SD-Varianten kommen nach allen HD-Varianten.
        let zdf = try XCTUnwrap(catalog.groups.first { $0.displayName == "ZDF" })
        let zdfCandidates = zdf.candidates(preferHD: true)
        XCTAssertTrue(zdfCandidates.first?.isHD == true)
        XCTAssertFalse(zdfCandidates.last?.isHD == true)
    }
}
