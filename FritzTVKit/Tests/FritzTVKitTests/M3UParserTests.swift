import XCTest
@testable import FritzTVKit

/// Tests gegen eine echte DVB-C-Senderliste der FRITZ!Box.
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
        // Standard: Öffentlich-rechtliche SD-Sender werden herausgefiltert
        let catalog = ChannelCatalog(channels: try fixtureChannels())
        XCTAssertEqual(catalog.groups.count, 81)
        // Nur private Sender behalten beide Varianten (z. B. HSE, QVC, Shop LC, Sonnenklar, Channel21)
        XCTAssertEqual(catalog.groups.filter { $0.hd != nil && $0.sd != nil }.count, 6)

        // ÖRR-Sender wie ZDF haben nur noch die HD-Variante (kein SD-Fallback mit schwarzem Bild)
        let zdf = try XCTUnwrap(catalog.groups.first { $0.displayName == "ZDF" })
        XCTAssertEqual(zdf.preferredChannel(preferHD: true).name, "ZDF HD")
        XCTAssertEqual(zdf.preferredChannel(preferHD: false).name, "ZDF HD")
        XCTAssertNil(zdf.sd)

        // Unterschiedliche Schreibweise bei Privaten wird zusammengeführt.
        let hseExtra = try XCTUnwrap(catalog.groups.first { $0.key == "tv:hse extra" })
        XCTAssertEqual(hseExtra.variants.count, 2)
        XCTAssertNotNil(hseExtra.hd)
        XCTAssertNotNil(hseExtra.sd)

        // Nur-SD-Sender fallen auf SD zurück.
        let rtl = try XCTUnwrap(catalog.groups.first { $0.displayName == "RTL" })
        XCTAssertEqual(rtl.preferredChannel(preferHD: true).name, "RTL")

        // Ohne Filterung: alle 11 Gruppen behalten HD und SD (historische Rohdaten)
        let unfiltered = ChannelCatalog(channels: try fixtureChannels(), filterPublicSD: false)
        XCTAssertEqual(unfiltered.groups.filter { $0.hd != nil && $0.sd != nil }.count, 11)
        let unfilteredZDF = try XCTUnwrap(unfiltered.groups.first { $0.displayName == "ZDF" })
        XCTAssertEqual(unfilteredZDF.preferredChannel(preferHD: false).name, "ZDF")
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

        // Öffentlich-rechtliche Sender wie ZDF haben nur noch funktionierende HD-Varianten.
        let zdf = try XCTUnwrap(catalog.groups.first { $0.displayName == "ZDF" })
        let zdfCandidates = zdf.candidates(preferHD: true)
        XCTAssertTrue(zdfCandidates.allSatisfy(\.isHD))

        // Bei Privatsendern mit HD und SD kommen SD-Varianten nach allen HD-Varianten.
        let qvc = try XCTUnwrap(catalog.groups.first { $0.displayName == "QVC" })
        let qvcCandidates = qvc.candidates(preferHD: true)
        XCTAssertTrue(qvcCandidates.first?.isHD == true)
        XCTAssertFalse(qvcCandidates.last?.isHD == true)

        // ZDFneo HD wird trotz unterschiedlicher Schreibweise ("ZDFneo HD" vs DefaultLineup "zdf_neo")
        // richtig zugeordnet und belegt Platz 7 in der Standardbelegung ohne tote SD-Variante.
        let lineup = ChannelLineup(catalog: catalog)
        let slot7 = try XCTUnwrap(lineup.entry(number: 7))
        XCTAssertEqual(slot7.group.displayName, "ZDFneo")
        XCTAssertTrue(slot7.group.variants.allSatisfy(\.isHD))
        XCTAssertFalse(slot7.isNew)
    }
}
