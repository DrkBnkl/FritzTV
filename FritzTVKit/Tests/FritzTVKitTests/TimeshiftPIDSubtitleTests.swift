import XCTest
@testable import FritzTVKit

final class TimeshiftPIDSubtitleTests: XCTestCase {

    // MARK: Timeshift-Grenze

    func testRecordingLimitRules() {
        let gb: Int64 = 1024 * 1024 * 1024
        let mb: Int64 = 1024 * 1024
        // Viel Platz: 4 GB (FAT32-Grenze)
        XCTAssertEqual(TimeshiftBufferManager.recordingLimit(availableBytes: 100 * gb), 4 * gb)
        // Wenig Platz: höchstens die Hälfte
        XCTAssertEqual(TimeshiftBufferManager.recordingLimit(availableBytes: 3 * gb), 3 * gb / 2)
        // Sehr wenig: 200 MB Reserve bleiben frei
        XCTAssertEqual(TimeshiftBufferManager.recordingLimit(availableBytes: 300 * mb), 100 * mb)
        XCTAssertEqual(TimeshiftBufferManager.recordingLimit(availableBytes: 150 * mb), 0)
    }

    func testBufferLimitHasNoFileSizeCap() {
        let gb: Int64 = 1024 * 1024 * 1024
        let mb: Int64 = 1024 * 1024
        // Gesamtpuffer aus mehreren Abschnitten: keine 4-GB-Grenze, nur die Hälfte des freien Platzes
        XCTAssertEqual(TimeshiftBufferManager.bufferLimit(availableBytes: 100 * gb), 50 * gb)
        XCTAssertEqual(TimeshiftBufferManager.bufferLimit(availableBytes: 300 * mb), 100 * mb)
        XCTAssertEqual(TimeshiftBufferManager.bufferLimit(availableBytes: 150 * mb), 0)
    }

    func testCleanupKeepsListedFiles() throws {
        let manager = TimeshiftBufferManager()
        manager.cleanup()
        defer { manager.cleanup() }
        try FileManager.default.createDirectory(at: manager.bufferDirectory, withIntermediateDirectories: true)
        let keep = manager.bufferDirectory.appendingPathComponent("a.ts")
        let drop = manager.bufferDirectory.appendingPathComponent("b.ts")
        try Data([1]).write(to: keep)
        try Data([2]).write(to: drop)
        let keptPath = try XCTUnwrap(manager.recordingFiles().first { $0.lastPathComponent == "a.ts" }).path
        manager.cleanup(keeping: [keptPath])
        XCTAssertEqual(manager.recordingFiles().map(\.lastPathComponent), ["a.ts"])
        XCTAssertEqual(manager.latestRecordingURL(excluding: [keptPath]), nil)
    }

    func testSoutOptionDisplaysAndRecords() throws {
        let url = URL(fileURLWithPath: "/tmp/Timeshift/timeshift_das_erste_1.ts")
        XCTAssertEqual(TimeshiftBufferManager.soutDisplayAndRecordOption(destination: url),
                       ":sout=#duplicate{dst=display,dst=std{access=file,mux=ts,dst=/tmp/Timeshift/timeshift_das_erste_1.ts}}")
        let segment = TimeshiftBufferManager.shared.newSegmentURL(channelKey: "wdr köln/hd")
        XCTAssertFalse(segment.lastPathComponent.contains(" "))
        XCTAssertFalse(segment.lastPathComponent.contains("/"))

        let manager = TimeshiftBufferManager.shared
        manager.cleanup()
        defer { manager.cleanup() }
        XCTAssertNil(manager.latestRecordingURL())
        let fakeTS = manager.bufferDirectory.appendingPathComponent("vlc-record-test.ts")
        try Data([0x47, 0x40, 0x00, 0x10]).write(to: fakeTS)
        XCTAssertEqual(manager.latestRecordingURL()?.lastPathComponent, "vlc-record-test.ts")
    }

    // MARK: PID-Änderungen

    private func channel(pids: String) throws -> Channel {
        let m3u = """
        #EXTM3U
        #EXTINF:0,Das Erste HD
        rtsp://192.168.178.1:554/?avm=1&freq=386&bw=8&msys=dvbc&mtype=256qam&sr=6900&specinv=1&pids=\(pids)
        """
        return try XCTUnwrap(M3UParser.parse(m3u).first)
    }

    func testDetectsMissingPIDs() throws {
        let ch = try channel(pids: "0,16,17,18,20,5100,5101,5102")
        XCTAssertEqual(ch.missingPIDs(trackIDs: [5101, 5102, -1, 5110, 5110, 17]), [5110])
        XCTAssertEqual(ch.missingPIDs(trackIDs: [5101, 5102]), [])
    }

    func testBuildsURLWithAddedPIDs() throws {
        let ch = try channel(pids: "0,16,17,18,20,5100,5101")
        let url = try XCTUnwrap(ch.streamURL(addingPIDs: [5110, 5101, 5111]))
        XCTAssertTrue(url.absoluteString.hasSuffix("pids=0,16,17,18,20,5100,5101,5110,5111"), url.absoluteString)
        XCTAssertTrue(url.absoluteString.contains("freq=386"))
        XCTAssertNil(ch.streamURL(addingPIDs: [5101]))
    }

    // MARK: Untertitel

    func testParsesEBUTTWithBroadcastOffset() {
        let ttml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <tt:tt xmlns:tt="http://www.w3.org/ns/ttml" xmlns:ttp="http://www.w3.org/ns/ttml#parameter" ttp:frameRate="25">
          <tt:body><tt:div>
            <tt:p begin="10:00:01.000" end="10:00:03.500"><tt:span>Guten Abend,</tt:span><tt:br/><tt:span>meine Damen und Herren.</tt:span></tt:p>
            <tt:p begin="10:00:04:12" end="10:00:06:00"><tt:span>Grey's Anatomy &amp; Co.</tt:span></tt:p>
          </tt:div></tt:body>
        </tt:tt>
        """
        let cues = SubtitleParser.parse(Data(ttml.utf8))
        XCTAssertEqual(cues.count, 2)
        XCTAssertEqual(cues[0].start, 1.0, accuracy: 0.001)
        XCTAssertEqual(cues[0].end, 3.5, accuracy: 0.001)
        XCTAssertEqual(cues[0].text, "Guten Abend,\nmeine Damen und Herren.")
        XCTAssertEqual(cues[1].start, 4.48, accuracy: 0.001)   // 12 Bilder bei 25 fps
        XCTAssertEqual(cues[1].text, "Grey's Anatomy & Co.")
        XCTAssertEqual(SubtitleParser.text(at: 2, in: cues), "Guten Abend,\nmeine Damen und Herren.")
        XCTAssertNil(SubtitleParser.text(at: 3.8, in: cues))
    }

    func testParsesTicksAndWebVTT() {
        let ticks = """
        <tt xmlns="http://www.w3.org/ns/ttml" xmlns:ttp="http://www.w3.org/ns/ttml#parameter" ttp:tickRate="10000000">
        <body><div><p begin="15000000t" end="30000000t">Hallo</p></div></body></tt>
        """
        XCTAssertEqual(SubtitleParser.parse(Data(ticks.utf8)), [SubtitleCue(start: 1.5, end: 3, text: "Hallo")])

        let vtt = """
        WEBVTT

        1
        00:00:01.000 --> 00:00:02.500 align:center
        <c.yellow>Erste Zeile</c>
        Zweite Zeile

        00:03.000 --> 00:04.000\tposition:50% line:0
        Kurz
        """
        let cues = SubtitleParser.parse(Data(vtt.utf8))
        XCTAssertEqual(cues, [SubtitleCue(start: 1, end: 2.5, text: "Erste Zeile\nZweite Zeile"),
                              SubtitleCue(start: 3, end: 4, text: "Kurz")])

        let simultaneous = [
            SubtitleCue(start: 10, end: 15, text: "Sprecher 1"),
            SubtitleCue(start: 12, end: 16, text: "Sprecher 2")
        ]
        XCTAssertEqual(SubtitleParser.text(at: 13, in: simultaneous), "Sprecher 1\nSprecher 2")
        XCTAssertEqual(SubtitleParser.text(at: 11, in: simultaneous), "Sprecher 1")
        XCTAssertEqual(SubtitleParser.text(at: 15.5, in: simultaneous), "Sprecher 2")
        XCTAssertNil(SubtitleParser.text(at: 20, in: simultaneous))
        XCTAssertEqual(SubtitleParser.parse(Data()), [])
    }

    func testMediathekResultKeepsSubtitleAndSkipsBrokenEntries() {
        let json = """
        {"result":{"results":[
          {"id":"a","channel":"ARD","title":"Tatort","url_video":"https://x/a.mp4","url_subtitle":"https://x/a.xml","timestamp":1,"duration":5400},
          {"id":"b","channel":"ARD","title":"Ohne Video"},
          {"channel":"ZDF","title":"Ohne Beschreibung","url_video":"https://x/c.mp4","duration":""}
        ]}}
        """
        let results = MediathekSearchClient.decodeResults(from: Data(json.utf8))
        XCTAssertEqual(results.map(\.title), ["Tatort", "Ohne Beschreibung"])
        XCTAssertEqual(results.first?.subtitleURL?.absoluteString, "https://x/a.xml")
        XCTAssertEqual(results.last?.duration, 0)
        XCTAssertNil(results.last?.subtitleURL)
        XCTAssertEqual(MediathekSearchResult.mediathekChannel(for: "Das Erste"), "ARD")
        XCTAssertEqual(MediathekSearchResult.mediathekChannel(for: "rbb Berlin"), "RBB")
        XCTAssertEqual(MediathekSearchResult.mediathekChannel(for: "ZDFinfo"), "ZDF")
        XCTAssertNil(MediathekSearchResult.mediathekChannel(for: "RTL"))
    }
}
