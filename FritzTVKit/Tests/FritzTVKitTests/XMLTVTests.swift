import XCTest
@testable import FritzTVKit

final class XMLTVTests: XCTestCase {

    func testKeysMatchFritzBoxAndXMLTVNames() {
        XCTAssertEqual(XMLTV.key("rbb Berlin HD"), XMLTV.key("DE - rbb Berlin"))
        XCTAssertEqual(XMLTV.key("Das Erste HD"), XMLTV.key("DE - Das Erste"))
        XCTAssertEqual(XMLTV.key("zdf_neo"), XMLTV.key("DE - ZDFneo"))
        XCTAssertEqual(XMLTV.key("hr-fernsehen HD"), XMLTV.key("DE - hr"))
        XCTAssertEqual(XMLTV.key("BR Süd HD"), XMLTV.key("DE - BR Fernsehen Süd"))
        XCTAssertEqual(XMLTV.key("NDR FS NDS HD"), XMLTV.key("DE - NDR Fernsehen Niedersachsen"))
        XCTAssertEqual(XMLTV.key("WDR HD Köln"), XMLTV.key("DE - WDR Fernsehen Köln"))
        XCTAssertEqual(XMLTV.key("CNN International (eng)"), XMLTV.key("DE - CNN International"))
        XCTAssertNotEqual(XMLTV.key("ZDF HD"), XMLTV.key("DE - ZDFinfo"))
    }

    func testParseKeepsWantedChannelsInWindow() throws {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <tv>
          <channel id="rbbBerlin.de"><display-name lang="de">DE - rbb Berlin</display-name></channel>
          <channel id="Other.de"><display-name lang="de">DE - Anderer Sender</display-name></channel>
          <programme start="20261027180000 +0000" stop="20261027183000 +0000" channel="rbbBerlin.de">
            <title lang="de">rbb24</title>
            <sub-title lang="de">Nachrichten</sub-title>
            <desc lang="de">Aus Berlin &amp; Brandenburg</desc>
          </programme>
          <programme start="20261027183000 +0000" stop="20261027190000 +0000" channel="Other.de">
            <title lang="de">Woanders</title>
          </programme>
          <programme start="20261101180000 +0000" stop="20261101183000 +0000" channel="rbbBerlin.de">
            <title lang="de">Zu spät</title>
          </programme>
        </tv>
        """
        let from = try XCTUnwrap(XMLTV.date("20261027000000 +0000"))
        let to = try XCTUnwrap(XMLTV.date("20261029000000 +0000"))
        let result = try XCTUnwrap(XMLTV.parse(data: Data(xml.utf8),
                                               wantedKeys: [XMLTV.key("rbb Berlin HD")],
                                               from: from, to: to))
        XCTAssertEqual(result.channelCount, 2)
        let programs = try XCTUnwrap(result.programsByKey[XMLTV.key("rbb Berlin HD")])
        XCTAssertEqual(programs.count, 1)
        XCTAssertEqual(programs[0].title, "rbb24")
        XCTAssertEqual(programs[0].subtitle, "Nachrichten")
        XCTAssertEqual(programs[0].description, "Aus Berlin & Brandenburg")
        XCTAssertEqual(programs[0].duration, 1800)
        XCTAssertLessThan(programs[0].serviceID, 0)
    }

    func testDateWithOffset() throws {
        let utc = try XCTUnwrap(XMLTV.date("20261027180000 +0000"))
        let local = try XCTUnwrap(XMLTV.date("20261027190000 +0100"))
        XCTAssertEqual(utc, local)
    }

    func testStoreFillsGapsFromExternalData() {
        let store = EPGStore()
        let start = Date().addingTimeInterval(-600)
        // Stream (DVB): nur die laufende Sendung
        store.setServiceName("rbb Berlin HD", for: 100)
        store.add(program: EPGProgram(eventID: 1, serviceID: 100, title: "Live aus dem Stream",
                                      startDate: start, duration: 1800))
        // Internet: dieselbe Zeit (abweichend) und die Sendung danach
        store.setExternal([XMLTV.key("rbb Berlin HD"): [
            EPGProgram(eventID: 10, serviceID: -1, title: "Doppelt", startDate: start, duration: 1800),
            EPGProgram(eventID: 11, serviceID: -1, title: "Danach", startDate: start.addingTimeInterval(1800), duration: 1800)
        ]])
        let titles = store.schedule(forChannelNames: ["rbb Berlin HD"])?.programs.map(\.title)
        XCTAssertEqual(titles, ["Live aus dem Stream", "Danach"])
        // Sender ohne Stream-Daten bekommt die Internet-Daten
        store.setExternal([XMLTV.key("ZDF HD"): [
            EPGProgram(eventID: 12, serviceID: -2, title: "heute", startDate: start, duration: 900)
        ]])
        XCTAssertEqual(store.schedule(forChannelNames: ["ZDF HD"])?.programs.first?.title, "heute")
    }
}
