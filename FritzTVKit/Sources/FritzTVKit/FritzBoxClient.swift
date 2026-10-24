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
    public func loadCatalog() async throws -> (host: String, catalog: ChannelCatalog) {
        for host in hosts {
            var channels: [Channel] = []
            var reachedHost = false
            for playlist in Self.playlists {
                guard let url = URL(string: "http://\(host)\(playlist.path)") else { continue }
                var request = URLRequest(url: url)
                request.timeoutInterval = 5
                guard let result = try? await session.data(for: request) else { continue }
                let (data, response) = result
                reachedHost = true
                guard (response as? HTTPURLResponse)?.statusCode == 200 else { continue }
                channels += M3UParser.parse(data: data, kind: playlist.kind)
            }
            if reachedHost {
                guard !channels.isEmpty else { throw ClientError.noChannels }
                return (host, ChannelCatalog(channels: channels))
            }
        }
        throw ClientError.unreachable
    }
}
