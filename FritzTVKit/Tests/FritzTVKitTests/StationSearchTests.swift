import XCTest
@testable import FritzTVKit

final class StationSearchTests: XCTestCase {

    func testEnvelopeUsesMediaServiceAndLowercaseMode() {
        let xml = FritzBoxStationSearch.envelope(action: "StationSearch",
                                                 arguments: ["NewStationSearchMode": "start"])
        XCTAssertTrue(xml.contains("<u:StationSearch xmlns:u=\"urn:dslforum-org:service:X_AVM-DE_Media:1\">"))
        XCTAssertTrue(xml.contains("<NewStationSearchMode>start</NewStationSearchMode>"))
        XCTAssertTrue(xml.contains("</u:StationSearch></s:Body></s:Envelope>"))
    }

    func testParsesProgressResponse() {
        let response = """
        <?xml version="1.0"?>
        <s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/"><s:Body>
        <u:GetSearchProgressResponse xmlns:u="urn:dslforum-org:service:X_AVM-DE_Media:1">
        <NewSearchProgress>42</NewSearchProgress>
        <NewStationSearchStatus>active</NewStationSearchStatus>
        </u:GetSearchProgressResponse></s:Body></s:Envelope>
        """
        XCTAssertEqual(FritzBoxStationSearch.parseStatus(response), StationSearchStatus(isActive: true, progress: 42))

        let done = "<NewSearchProgress>100</NewSearchProgress><NewStationSearchStatus>INACTIVE</NewStationSearchStatus>"
        XCTAssertEqual(FritzBoxStationSearch.parseStatus(done), StationSearchStatus(isActive: false, progress: 100))
    }
}
