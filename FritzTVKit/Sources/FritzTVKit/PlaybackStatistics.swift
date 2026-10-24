import Foundation
import CoreGraphics

/// Statistiken zur Bildqualität und Empfangsdaten des laufenden Streams.
public struct PlaybackStatistics: Equatable, Sendable {
    public var videoSize: CGSize = .zero
    public var inputBitrateMbps: Double = 0
    public var demuxBitrateMbps: Double = 0
    public var displayedPictures: Int = 0
    public var lostPictures: Int = 0
    public var demuxDiscontinuities: Int = 0
    public var signalPowerDB: Double?
    public var signalNoiseRatioDB: Double?
    public var tunerUsage: (used: Int, total: Int)?

    public init(
        videoSize: CGSize = .zero,
        inputBitrateMbps: Double = 0,
        demuxBitrateMbps: Double = 0,
        displayedPictures: Int = 0,
        lostPictures: Int = 0,
        demuxDiscontinuities: Int = 0,
        signalPowerDB: Double? = nil,
        signalNoiseRatioDB: Double? = nil,
        tunerUsage: (used: Int, total: Int)? = nil
    ) {
        self.videoSize = videoSize
        self.inputBitrateMbps = inputBitrateMbps
        self.demuxBitrateMbps = demuxBitrateMbps
        self.displayedPictures = displayedPictures
        self.lostPictures = lostPictures
        self.demuxDiscontinuities = demuxDiscontinuities
        self.signalPowerDB = signalPowerDB
        self.signalNoiseRatioDB = signalNoiseRatioDB
        self.tunerUsage = tunerUsage
    }

    public static func == (lhs: PlaybackStatistics, rhs: PlaybackStatistics) -> Bool {
        lhs.videoSize == rhs.videoSize &&
        abs(lhs.inputBitrateMbps - rhs.inputBitrateMbps) < 0.1 &&
        abs(lhs.demuxBitrateMbps - rhs.demuxBitrateMbps) < 0.1 &&
        lhs.displayedPictures == rhs.displayedPictures &&
        lhs.lostPictures == rhs.lostPictures &&
        lhs.demuxDiscontinuities == rhs.demuxDiscontinuities &&
        lhs.signalPowerDB == rhs.signalPowerDB &&
        lhs.signalNoiseRatioDB == rhs.signalNoiseRatioDB &&
        lhs.tunerUsage?.used == rhs.tunerUsage?.used &&
        lhs.tunerUsage?.total == rhs.tunerUsage?.total
    }

    public var resolutionLabel: String {
        guard videoSize.width > 0 && videoSize.height > 0 else { return "" }
        let w = Int(videoSize.width)
        let h = Int(videoSize.height)
        if h >= 1080 {
            return "\(w)×\(h) (1080p)"
        } else if h >= 720 {
            return "\(w)×\(h) (720p HD)"
        } else {
            return "\(w)×\(h) (576i SD)"
        }
    }

    public var bitrateLabel: String {
        guard inputBitrateMbps > 0.05 || demuxBitrateMbps > 0.05 else { return "" }
        let rate = inputBitrateMbps > 0.05 ? inputBitrateMbps : demuxBitrateMbps
        return String(format: "%.1f Mbit/s", rate)
    }

    public var lossLabel: String {
        if lostPictures == 0 && demuxDiscontinuities == 0 {
            return "0 Bildfehler"
        } else {
            var parts: [String] = []
            if lostPictures > 0 { parts.append("\(lostPictures) verloren") }
            if demuxDiscontinuities > 0 { parts.append("\(demuxDiscontinuities) Abrisse") }
            return parts.joined(separator: ", ")
        }
    }

    public var signalLabel: String? {
        guard let p = signalPowerDB, let snr = signalNoiseRatioDB else { return nil }
        return String(format: "Signal: %.0f dB · SNR: %.0f dB", p, snr)
    }

    public var tunerLabel: String? {
        guard let t = tunerUsage else { return nil }
        return "Tuner \(t.used)/\(t.total)"
    }
}
