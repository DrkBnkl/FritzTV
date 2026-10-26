import XCTest
@testable import FritzTVKit

final class EITLogParserTests: XCTestCase {

    /// Zeilen im Format von VLC 3 (`modules/demux/mpeg/ts_si.c`). Noch durch echte Zeilen aus
    /// VLCKit zu ersetzen, sobald sie am Mac mitgeschnitten sind.
    private let multiplexLines = [
        "new SDT ts_id=10 version=3 current_next=1 network_id=61441",
        "  * service id=28106 eit schedule=1 present=1 running=4 free_ca=0",
        "    - type=25 provider=ARD name=Das Erste HD",
        "  * service id=28111 eit schedule=1 present=1 running=4 free_ca=0",
        "    - type=25 provider=ARD name=WDR HD Köln",
        "new EIT service_id=28111 version=4 current_next=1 ts_id=10 network_id=61441 segment_last_section_number=1 last_table_id=78",
        "  * event id=900 start_time:1729760400 duration=3600 running=4 free_ca=0",
        "    - short event lang=deu 'Lokalzeit' : ''",
        "new EIT service_id=28106 version=12 current_next=1 ts_id=10 network_id=61441 segment_last_section_number=1 last_table_id=78",
        "  * event id=45120 start_time:1729760400 duration=3600 running=4 free_ca=0",
        "    - short event lang=deu 'Sportschau' : 'Bundesliga am Samstag'",
        "    - extended event lang=deu [0/1]",
        "       - text='Moderation: Esther Sedlaczek. '",
        "    - extended event lang=deu [1/1]",
        "       - text='Berichte von den Spielen.'",
        "  * event id=45121 start_time:1729764000 duration=900 running=1 free_ca=0",
        "    - short event lang=deu 'Tagesschau' : 'Nachrichten'"
    ]

    func testParsesEventsAndServiceNames() {
        var programs: [EPGProgram] = []
        var names: [Int: String] = [:]
        let parser = EITLogParser(onProgramParsed: { programs.append($0) },
                                  onServiceName: { names[$0] = $1 })
        multiplexLines.forEach { parser.processLine($0) }
        parser.flush()

        XCTAssertEqual(names, [28106: "Das Erste HD", 28111: "WDR HD Köln"])
        XCTAssertEqual(programs.map(\.title), ["Lokalzeit", "Sportschau", "Tagesschau"])

        let sportschau = programs[1]
        XCTAssertEqual(sportschau.serviceID, 28106)
        XCTAssertEqual(sportschau.eventID, 45120)
        XCTAssertEqual(sportschau.subtitle, "Bundesliga am Samstag")
        XCTAssertEqual(sportschau.description, "Moderation: Esther Sedlaczek. Berichte von den Spielen.")
        XCTAssertEqual(sportschau.startDate, Date(timeIntervalSince1970: 1729760400))
        XCTAssertEqual(sportschau.duration, 3600)
        XCTAssertTrue(sportschau.isRunningStatus)

        XCTAssertEqual(programs[0].serviceID, 28111)
        XCTAssertNil(programs[0].subtitle)
        XCTAssertFalse(programs[2].isRunningStatus)
    }

    func testTitleWithApostrophe() {
        var programs: [EPGProgram] = []
        let parser = EITLogParser(onProgramParsed: { programs.append($0) })
        [
            "new EIT service_id=1 version=1 current_next=1",
            "  * event id=7 start_time:1729760400 duration=2700 running=4 free_ca=0",
            "    - short event lang=deu 'Grey's Anatomy' : 'Die jungen Ärzte – Folge 'Neubeginn''",
            "  * event id=8 start_time:1729763100 duration=2700 running=1 free_ca=0",
            "    - short event lang=deu 'Rock'n'Roll'"
        ].forEach { parser.processLine($0) }
        parser.flush()

        XCTAssertEqual(programs.first?.title, "Grey's Anatomy")
        XCTAssertEqual(programs.first?.subtitle, "Die jungen Ärzte – Folge 'Neubeginn'")
        XCTAssertEqual(programs.last?.title, "Rock'n'Roll")
    }

    /// Wiedergabe und Hintergrund-Abruf liefern gleichzeitig Zeilen; je Quelle getrennt gelesen,
    /// landet keine Sendung beim falschen Dienst.
    func testInterleavedSourcesDoNotMix() {
        var programs: [EPGProgram] = []
        let parser = EITLogParser(onProgramParsed: { programs.append($0) })
        let a = 1, b = 2
        parser.processLine("new EIT service_id=100 version=1", source: a)
        parser.processLine("new EIT service_id=200 version=1", source: b)
        parser.processLine("  * event id=1 start_time:1729760400 duration=600 running=4", source: a)
        parser.processLine("  * event id=2 start_time:1729760400 duration=600 running=4", source: b)
        parser.processLine("    - short event lang=deu 'Sendung A' : ''", source: a)
        parser.processLine("    - short event lang=deu 'Sendung B' : ''", source: b)
        parser.flushAll()

        let bySID = Dictionary(uniqueKeysWithValues: programs.map { ($0.serviceID, $0.title) })
        XCTAssertEqual(bySID, [100: "Sendung A", 200: "Sendung B"])
    }

    func testStoreMapsChannelsBySDTNameNotByRunningStatus() throws {
        let store = EPGStore()
        let parser = EITLogParser(onProgramParsed: { store.add(program: $0) },
                                  onServiceName: { store.setServiceName($1, for: $0) })
        multiplexLines.forEach { parser.processLine($0) }
        parser.flush()

        let now = Date(timeIntervalSince1970: 1729760400 + 1800)
        // Beide Dienste haben eine laufende Sendung; die Zuordnung kommt nur über den Namen.
        let ard = store.currentProgram(forChannelNames: ["Das Erste HD", "Das Erste"], at: now)
        XCTAssertEqual(ard?.title, "Sportschau")
        let wdr = store.currentProgram(forChannelNames: ["WDR HD Köln"], at: now)
        XCTAssertEqual(wdr?.title, "Lokalzeit")
        XCTAssertEqual(store.nextProgram(forChannelNames: ["Das Erste HD"], at: now)?.title, "Tagesschau")
        // Schreibweise unabhängig von Groß-/Kleinschreibung und Akzenten
        XCTAssertEqual(store.serviceID(forChannelNames: ["wdr hd koln"]), 28111)
        XCTAssertNil(store.serviceID(forChannelNames: ["RTL"]))
    }

    func testLearnOnlyFromUniqueTitle() {
        let store = EPGStore()
        let start = Date(timeIntervalSince1970: 1729760400)
        let now = start.addingTimeInterval(60)
        // Zwei Dienste zeigen dieselbe Tagesschau, einer etwas anderes
        store.add(program: EPGProgram(eventID: 1, serviceID: 10, title: "Tagesschau", startDate: start, duration: 900, isRunningStatus: true))
        store.add(program: EPGProgram(eventID: 2, serviceID: 11, title: "Tagesschau", startDate: start, duration: 900, isRunningStatus: true))
        store.add(program: EPGProgram(eventID: 3, serviceID: 12, title: "Lokalzeit", startDate: start, duration: 900, isRunningStatus: true))

        XCTAssertFalse(store.learn(channelNames: ["Das Erste HD"], fromNowPlayingTitle: "Tagesschau", at: now))
        XCTAssertNil(store.serviceID(forChannelNames: ["Das Erste HD"]))
        XCTAssertTrue(store.learn(channelNames: ["WDR HD Köln"], fromNowPlayingTitle: "Lokalzeit", at: now))
        XCTAssertEqual(store.serviceID(forChannelNames: ["WDR HD Köln"]), 12)
    }

    func testStaleRunningStatusExpires() {
        let start = Date(timeIntervalSince1970: 1729760400)
        let old = EPGProgram(eventID: 1, serviceID: 1, title: "Alt", startDate: start, duration: 3600, isRunningStatus: true)
        let next = EPGProgram(eventID: 2, serviceID: 1, title: "Neu", startDate: start.addingTimeInterval(3600), duration: 3600)
        let schedule = EPGChannelSchedule(serviceID: 1, programs: [old, next])

        // Kurz nach dem geplanten Ende zählt „läuft“ noch (Überziehen) …
        XCTAssertEqual(schedule.currentProgram(at: start.addingTimeInterval(3600 + 600))?.title, "Alt")
        // … 50 Minuten nach dem Ende nicht mehr.
        XCTAssertEqual(schedule.currentProgram(at: start.addingTimeInterval(3600 + 3000))?.title, "Neu")
    }

    func testPruneExpiredRemovesOldPrograms() {
        let store = EPGStore()
        let now = Date()
        let expired = EPGProgram(eventID: 1, serviceID: 1, title: "Gestern",
                                 startDate: now.addingTimeInterval(-20 * 3600), duration: 3600)
        let fresh = EPGProgram(eventID: 2, serviceID: 1, title: "Jetzt",
                               startDate: now.addingTimeInterval(-1800), duration: 3600)
        store.add(program: expired)
        store.add(program: fresh)
        store.setServiceName("Test Sender", for: 1)

        store.pruneExpired(before: now.addingTimeInterval(-10 * 3600))
        let schedule = store.schedule(for: 1)
        XCTAssertEqual(schedule?.programs.count, 1)
        XCTAssertEqual(schedule?.programs.first?.title, "Jetzt")
    }

    func testRelevanceFilterMatchesParsedLines() {
        for line in multiplexLines where !line.contains("extended event") {
            XCTAssertTrue(EITLogParser.isRelevant(line), line)
        }
        XCTAssertFalse(EITLogParser.isRelevant("    - extended event lang=deu [0/1]"))
        XCTAssertFalse(EITLogParser.isRelevant("ts demux: PID 18 discontinuity"))
        XCTAssertFalse(EITLogParser.isRelevant("decoded picture with name=foo"))
    }
}
