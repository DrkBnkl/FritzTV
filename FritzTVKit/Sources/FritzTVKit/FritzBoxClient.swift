import Foundation

/// Lädt die Senderlisten von der FRITZ!Box.
///
/// Info.plist der App braucht:
/// - `NSAppTransportSecurity` → `NSAllowsLocalNetworking = YES` (HTTP im Heimnetz)
/// - `NSLocalNetworkUsageDescription` (Hinweistext für den Zugriff aufs lokale Netz)
public struct FritzBoxClient: Sendable {

    public enum ClientError: Error, Equatable {
        case unreachable
        case noChannels
    }

    /// Kandidaten in dieser Reihenfolge: eigene Eingabe, `fritz.box`, Standard-IP.
    public let hosts: [String]
    let session: URLSession

    public init(customHost: String? = nil, session: URLSession = .shared) {
        var hosts = ["fritz.box", "192.168.178.1"]
        if let customHost, !customHost.isEmpty { hosts.insert(customHost, at: 0) }
        self.hosts = hosts
        self.session = session
    }

    /// Listen der Box. HD zuerst, damit HD-Varianten vorne einsortiert werden.
    static let playlists: [(path: String, kind: ChannelKind)] = [
        ("/dvb/m3u/tvhd.m3u", .tv),
        ("/dvb/m3u/tvsd.m3u", .tv),
        ("/dvb/m3u/radio.m3u", .radio)
    ]

    /// Lädt alle Listen vom ersten erreichbaren Host.
    /// Fehlende einzelne Listen (z. B. kein Radio) werden übersprungen.
    /// Die drei Listen eines Hosts werden gleichzeitig geladen: Ist ein Host nicht erreichbar
    /// (z. B. `fritz.box` über VPN), dauert der Wechsel zum nächsten nur einmal 5 s statt dreimal.
    public func loadCatalog() async throws -> (host: String, catalog: ChannelCatalog) {
        for host in hosts {
            let session = self.session
            let results = await withTaskGroup(
                of: (index: Int, reached: Bool, data: Data?).self,
                returning: [(index: Int, reached: Bool, data: Data?)].self
            ) { group in
                for (index, playlist) in Self.playlists.enumerated() {
                    let path = playlist.path
                    group.addTask {
                        guard let url = URL(string: "http://\(host)\(path)") else { return (index, false, nil) }
                        var request = URLRequest(url: url)
                        request.timeoutInterval = 5
                        // Nie aus dem Zwischenspeicher: Eine dort hängende dauerhafte Umleitung (301, z. B. aus
                        // einem fremden Netz, in dem `fritz.box` ein anderer Server ist) würde sonst für immer gelten.
                        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
                        guard let (data, response) = try? await session.data(for: request) else {
                            return (index, false, nil)
                        }
                        let status = (response as? HTTPURLResponse)?.statusCode
                        if status == 200 { return (index, Self.isPlaylist(data), Self.isPlaylist(data) ? data : nil) }
                        // 404: Die Box ist da, nur diese Liste fehlt (z. B. kein Radio).
                        return (index, status == 404, nil)
                    }
                }
                var collected: [(index: Int, reached: Bool, data: Data?)] = []
                for await result in group { collected.append(result) }
                return collected.sorted { $0.index < $1.index }
            }
            let reachedHost = results.contains { $0.reached }
            // Reihenfolge der Listen beibehalten (HD vor SD), damit die Positionen stimmen.
            var channels: [Channel] = []
            for result in results {
                guard let data = result.data else { continue }
                channels += M3UParser.parse(data: data, kind: Self.playlists[result.index].kind)
            }
            if reachedHost {
                guard !channels.isEmpty else { throw ClientError.noChannels }
                return (host, ChannelCatalog(channels: channels))
            }
        }
        throw ClientError.unreachable
    }

    /// Antwortet unter der Adresse etwas anderes als die Box (Login-Seite nach einer Umleitung,
    /// fremder Server), ist das keine M3U-Liste – dann kommt die nächste Adresse dran.
    static func isPlaylist(_ data: Data) -> Bool {
        let head = String(decoding: data.prefix(64), as: UTF8.self)
            .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "\u{FEFF}")))
        return head.hasPrefix("#EXTM3U")
    }
}
