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

/// Empfängt Debug-Meldungen von libVLC und leitet EIT-Meldungen an den EITLogParser weiter.
final class EPGLogReceiver: NSObject, VLCLogging, @unchecked Sendable {
    var level: VLCLogLevel = .debug
    private let parser: EITLogParser

    init(parser: EITLogParser) {
        self.parser = parser
        super.init()
    }

    func handleMessage(_ message: String, logLevel level: VLCLogLevel, context: VLCLogContext?) {
        // Filtere uninteressante Meldungen vorab, um Rechenzeit zu sparen
        if message.contains("EIT") || message.contains("event id") || message.contains("short event") || message.contains("text='") {
            parser.processLine(message)
        }
    }
}
