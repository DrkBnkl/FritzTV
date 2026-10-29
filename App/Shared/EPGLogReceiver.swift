import Foundation
import VLCKitSPM
#if canImport(TVVLCKit)
import TVVLCKit
#elseif canImport(MobileVLCKit)
import MobileVLCKit
#elseif canImport(VLCKit)
import VLCKit
#endif
import FritzTVKit

/// Empfängt Debug-Meldungen von libVLC und leitet SDT-/EIT-Meldungen an den `EITLogParser` weiter.
/// Jede Meldung wird mit der Objekt-ID ihres Absenders übergeben, damit sich Zeilen
/// gleichzeitig laufender Demuxer nicht vermischen.
final class EPGLogReceiver: NSObject, VLCLogging, @unchecked Sendable {
    var level: VLCLogLevel = .debug
    private let parser: EITLogParser

    init(parser: EITLogParser) {
        self.parser = parser
        super.init()
    }

    func handleMessage(_ message: String, logLevel level: VLCLogLevel, context: VLCLogContext?) {
        #if DEBUG
        // Nur Debug-Builds: Warnungen und Fehler von VLC mitschreiben (Fehlersuche Bildaussetzer).
        if level.rawValue <= VLCLogLevel.warning.rawValue,
           !message.contains("picture is too late"), !message.contains("buffer too late"),
           !message.contains("late frames"), !message.contains("does not exist") {
            let module = context?.module ?? "?"
            let id = context.map { String($0.objectId, radix: 16) } ?? "?"
            DebugLog.log("VLC[\(module) \(id)] \(message.prefix(160))")
        }
        #endif
        guard EITLogParser.isRelevant(message) else { return }
        let source = context.map { Int(truncatingIfNeeded: $0.objectId) } ?? 0
        parser.processLine(message, source: source)
    }
}
