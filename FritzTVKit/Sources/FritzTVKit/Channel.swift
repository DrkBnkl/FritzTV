import Foundation

/// DVB-C-Tuning-Daten, die die FRITZ!Box in jeden RTSP-Link schreibt.
/// Beispiel: `?avm=1&freq=450&bw=8&msys=dvbc&mtype=256qam&sr=6900&specinv=1&pids=0,16,17,18,20,…`
public struct TuningParameters: Hashable, Sendable {
    /// Frequenz in MHz. Sender mit gleicher Frequenz liegen im selben Multiplex.
    public let frequencyMHz: Int
    public let bandwidthMHz: Int?
    public let modulation: String?
    public let symbolRate: Int?
    public let spectralInversion: Int?
    /// Angeforderte Paket-IDs. 0/16/17/18/20 = PAT/NIT/SDT/EIT/TDT.
    public let pids: [Int]

    /// PID 18 trägt die Programminformationen (EIT).
    public var includesEIT: Bool { pids.contains(18) }

    init?(url: URL) {
        guard let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems else {
            return nil
        }
        func value(_ name: String) -> String? { items.first { $0.name == name }?.value }
        guard let freq = value("freq").flatMap(Int.init) else { return nil }
        frequencyMHz = freq
        bandwidthMHz = value("bw").flatMap(Int.init)
        modulation = value("mtype")
        symbolRate = value("sr").flatMap(Int.init)
        spectralInversion = value("specinv").flatMap(Int.init)
        pids = (value("pids") ?? "")
            .split(separator: ",")
            .compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
    }
}

/// Art der Senderliste, aus der ein Eintrag stammt.
public enum ChannelKind: String, Sendable, CaseIterable {
    case tv
    case radio
}

/// Ein einzelner Eintrag der M3U-Liste.
public struct Channel: Identifiable, Hashable, Sendable {
    /// Der RTSP-Link ist eindeutig und dient als ID.
    public var id: String { streamURL.absoluteString }

    /// Name wie in der Liste, ohne DVB-Steuerzeichen.
    public let name: String
    /// Name ohne „HD“ und ohne Sprachkennung, z. B. „WDR Köln“.
    public let displayName: String
    public let isHD: Bool
    /// Sprachkennung aus dem Namen, z. B. „eng“ bei „CNN (eng)“.
    public let languageTag: String?
    public let kind: ChannelKind
    /// Position in der Liste der Box (für die Standardsortierung).
    public let position: Int
    public let streamURL: URL
    public let tuning: TuningParameters?
    /// Pufferzeit aus `#EXTVLCOPT:network-caching=…` in Millisekunden.
    public let networkCachingMilliseconds: Int?

    /// Schlüssel, unter dem HD- und SD-Variante zusammengefasst werden.
    public var groupKey: String {
        displayName.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "de_DE"))
    }
}

public extension Array where Element == Channel {
    /// Schlüssel für die gemerkte funktionierende Variante: Sender plus gewünschte Qualität.
    /// Gilt für eine Kandidatenliste, wie `ChannelGroup.candidates` sie liefert.
    var variantKey: String {
        guard let first else { return "" }
        return "\(first.kind.rawValue):\(first.groupKey):\(first.isHD)"
    }
}
