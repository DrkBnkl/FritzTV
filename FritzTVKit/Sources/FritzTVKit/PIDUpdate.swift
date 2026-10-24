import Foundation

/// Geänderte PIDs: Stellt ein Sender seine Ton- oder Bildspuren um, stimmen die PIDs in der
/// Senderliste der Box nicht mehr, und die Box liefert nur noch einen Teil des Programms.
/// Die PMT im Strom nennt die neuen PIDs; VLC legt dafür Spuren an, deren IDs im
/// TS-Demuxer die PIDs sind. Fehlen diese im RTSP-Link, ergänzt man sie
/// (so macht es auch die FRITZ!App TV).
public extension Channel {
    /// Im RTSP-Link angeforderte PIDs.
    var requestedPIDs: [Int] { tuning?.pids ?? [] }

    /// Spur-IDs (= PIDs) aus VLC, die nicht angefordert werden. Reservierte PIDs (< 32) und
    /// ungültige Werte zählen nicht.
    func missingPIDs(trackIDs: [Int]) -> [Int] {
        let requested = Set(requestedPIDs)
        var seen = Set<Int>()
        return trackIDs.filter { (32...8190).contains($0) && !requested.contains($0) && seen.insert($0).inserted }
    }

    /// RTSP-Link mit zusätzlichen PIDs; die bisherige Reihenfolge bleibt erhalten.
    func streamURL(addingPIDs extra: [Int]) -> URL? {
        guard !extra.isEmpty,
              var components = URLComponents(url: streamURL, resolvingAgainstBaseURL: false),
              var items = components.queryItems,
              let index = items.firstIndex(where: { $0.name == "pids" }) else { return nil }
        let existing = requestedPIDs
        let additions = extra.filter { !existing.contains($0) }
        guard !additions.isEmpty else { return nil }
        items[index].value = (existing + additions).map(String.init).joined(separator: ",")
        components.queryItems = items
        // Kommas nicht kodieren: Die Box erwartet „pids=0,16,…“ wörtlich.
        components.percentEncodedQuery = components.percentEncodedQuery?.replacingOccurrences(of: "%2C", with: ",")
        return components.url
    }
}
