import XCTest
@testable import FritzTVKit

final class EITLogParserTests: XCTestCase {

    func testParsesStandardVLCLogLines() {
        var parsedPrograms: [EPGProgram] = []
        let parser = EITLogParser { program in
            parsedPrograms.append(program)
        }

        let sampleLines = [
            "new EIT service_id=11110 version=12 current_next=1 ts_id=10 network_id=1 segment_last_section_number=1 last_table_id=78",
            "  * event id=45120 start_time:1729760400 duration:3600 running=4 free_ca=0",
            "    - short event lang=deu 'Sportschau' : 'Bundesliga am Samstag'",
            "    - extended event lang=deu [1/2]",
            "       - text='Moderation: Esther Sedlaczek. Berichte von den Spielen.'",
            "    - extended event lang=deu [2/2]",
            "       - text='Zusammenfassungen der Nachmittagsbegegnungen.'",
            "  * event id=45121 start_time:1729764000 duration:1800 running=1 free_ca=0",
            "    - short event lang=deu 'Tagesschau' : 'Nachrichten'",
            "       - text='Hauptausgabe mit Wetter.'"
        ]

        for line in sampleLines {
            parser.processLine(line)
        }
        parser.flush()

        XCTAssertEqual(parsedPrograms.count, 2)

        let sportschau = parsedPrograms[0]
        XCTAssertEqual(sportschau.serviceID, 11110)
        XCTAssertEqual(sportschau.eventID, 45120)
        XCTAssertEqual(sportschau.title, "Sportschau")
        XCTAssertEqual(sportschau.subtitle, "Bundesliga am Samstag")
        XCTAssertTrue(sportschau.description?.contains("Moderation: Esther Sedlaczek") == true)
        XCTAssertTrue(sportschau.description?.contains("Zusammenfassungen der Nachmittagsbegegnungen") == true)
        XCTAssertEqual(sportschau.startDate, Date(timeIntervalSince1970: 1729760400))
        XCTAssertEqual(sportschau.duration, 3600)
        XCTAssertTrue(sportschau.isRunningStatus)

        let tagesschau = parsedPrograms[1]
        XCTAssertEqual(tagesschau.title, "Tagesschau")
        XCTAssertEqual(tagesschau.subtitle, "Nachrichten")
        XCTAssertEqual(tagesschau.duration, 1800)
        XCTAssertFalse(tagesschau.isRunningStatus)
    }

    func testEPGStoreAndScheduleLookups() throws {
        let store = EPGStore()
        let now = Date()
        let p1 = EPGProgram(
            eventID: 1,
            serviceID: 100,
            title: "Laufende Sendung",
            startDate: now.addingTimeInterval(-1800),
            duration: 3600,
            isRunningStatus: true
        )
        let p2 = EPGProgram(
            eventID: 2,
            serviceID: 100,
            title: "Folgende Sendung",
            startDate: now.addingTimeInterval(1800),
            duration: 3600,
            isRunningStatus: false
        )

        store.add(program: p1)
        store.add(program: p2)
        store.associate(channelKey: "daserste", serviceID: 100)

        let current = try XCTUnwrap(store.currentProgram(forChannelKey: "daserste", at: now))
        XCTAssertEqual(current.title, "Laufende Sendung")
        XCTAssertEqual(current.progress(at: now), 0.5, accuracy: 0.05)

        let next = store.nextProgram(forChannelKey: "daserste", at: now)
        XCTAssertEqual(next?.title, "Folgende Sendung")
    }
}
