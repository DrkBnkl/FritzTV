import Foundation

/// Zustand des DVB-C-Sendersuchlaufs der FRITZ!Box.
public struct StationSearchStatus: Equatable, Sendable {
    public let isActive: Bool
    /// Fortschritt in Prozent (0–100), sofern die Box ihn meldet.
    public let progress: Int

    public init(isActive: Bool, progress: Int) {
        self.isActive = isActive
        self.progress = progress
    }
}

public enum StationSearchError: LocalizedError, Equatable {
    case unauthorized
    case unreachable
    case boxError(String)

    public var errorDescription: String? {
        switch self {
        case .unauthorized:
            return "Anmeldung an der FRITZ!Box fehlgeschlagen. Benutzername und Kennwort prüfen."
        case .unreachable:
            return "Die FRITZ!Box ist nicht erreichbar."
        case .boxError(let message):
            return "Die FRITZ!Box meldet einen Fehler: \(message)"
        }
    }
}

/// Startet und überwacht den Sendersuchlauf der FRITZ!Box über TR-064.
///
/// Dienst `urn:dslforum-org:service:X_AVM-DE_Media:1` unter `/upnp/control/x_media` (Port 49000),
/// wie ihn die FRITZ!App TV verwendet:
/// - `StationSearch` mit `NewStationSearchMode` = `start` / `stop` → `NewStationSearchStatus`
/// - `GetSearchProgress` → `NewSearchProgress` (Prozent) und `NewStationSearchStatus` (`active`/`inactive`)
///
/// TR-064 verlangt eine Anmeldung (HTTP-Digest) mit einem Benutzer der FRITZ!Box, der die
/// Berechtigung „FRITZ!Box Einstellungen“ hat.
public struct FritzBoxStationSearch: Sendable {
    public static let serviceType = "urn:dslforum-org:service:X_AVM-DE_Media:1"
    public static let controlPath = "/upnp/control/x_media"

    public let host: String
    public let username: String
    public let password: String
    private let session: URLSession

    public init(host: String, username: String, password: String, session: URLSession = .shared) {
        self.host = host
        self.username = username
        self.password = password
        self.session = session
    }

    @discardableResult
    public func start() async throws -> StationSearchStatus {
        try await call("StationSearch", arguments: ["NewStationSearchMode": "start"])
        return try await status()
    }

    public func stop() async throws {
        try await call("StationSearch", arguments: ["NewStationSearchMode": "stop"])
    }

    public func status() async throws -> StationSearchStatus {
        let xml = try await call("GetSearchProgress")
        return Self.parseStatus(xml)
    }

    /// Prüft nur die Anmeldung (für „Zugangsdaten testen“ in den Einstellungen).
    public func verifyCredentials() async throws {
        _ = try await call("GetSearchProgress")
    }

    // MARK: SOAP

    static func parseStatus(_ xml: String) -> StationSearchStatus {
        let state = tag("NewStationSearchStatus", in: xml)?.lowercased() ?? ""
        let progress = tag("NewSearchProgress", in: xml).flatMap(Int.init) ?? 0
        return StationSearchStatus(isActive: state == "active", progress: min(max(progress, 0), 100))
    }

    static func envelope(action: String, arguments: [String: String]) -> String {
        let args = arguments.sorted { $0.key < $1.key }
            .map { "<\($0.key)>\(escape($0.value))</\($0.key)>" }
            .joined()
        return """
        <?xml version="1.0" encoding="utf-8"?>
        <s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">\
        <s:Body><u:\(action) xmlns:u="\(serviceType)">\(args)</u:\(action)></s:Body></s:Envelope>
        """
    }

    @discardableResult
    private func call(_ action: String, arguments: [String: String] = [:]) async throws -> String {
        guard let url = URL(string: "http://\(host):49000\(Self.controlPath)") else {
            throw StationSearchError.unreachable
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 8
        request.setValue("text/xml; charset=\"utf-8\"", forHTTPHeaderField: "Content-Type")
        request.setValue("\(Self.serviceType)#\(action)", forHTTPHeaderField: "SOAPACTION")
        request.httpBody = Data(Self.envelope(action: action, arguments: arguments).utf8)

        let delegate = DigestDelegate(username: username, password: password)
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request, delegate: delegate)
        } catch {
            if delegate.rejected { throw StationSearchError.unauthorized }
            throw StationSearchError.unreachable
        }
        let body = String(data: data, encoding: .utf8) ?? ""
        switch (response as? HTTPURLResponse)?.statusCode ?? 0 {
        case 200:
            return body
        case 401:
            throw StationSearchError.unauthorized
        default:
            // SOAP-Fehler, z. B. 606 „Action not authorized“ bei fehlender Berechtigung
            let code = Self.tag("errorCode", in: body) ?? ""
            let text = Self.tag("errorDescription", in: body) ?? "unbekannt"
            if code == "606" || code == "401" { throw StationSearchError.unauthorized }
            throw StationSearchError.boxError(code.isEmpty ? text : "\(text) (\(code))")
        }
    }

    static func tag(_ name: String, in xml: String) -> String? {
        guard let open = xml.range(of: "<\(name)>"),
              let close = xml.range(of: "</\(name)>", range: open.upperBound..<xml.endIndex) else { return nil }
        return String(xml[open.upperBound..<close.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func escape(_ value: String) -> String {
        value.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
}

/// Beantwortet die Digest-Anmeldung der Box genau einmal; ein zweiter Versuch heißt: falsche Daten.
private final class DigestDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    private let username: String
    private let password: String
    private(set) var rejected = false

    init(username: String, password: String) {
        self.username = username
        self.password = password
    }

    func urlSession(_ session: URLSession, task: URLSessionTask,
                    didReceive challenge: URLAuthenticationChallenge,
                    completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        let method = challenge.protectionSpace.authenticationMethod
        guard method == NSURLAuthenticationMethodHTTPDigest || method == NSURLAuthenticationMethodHTTPBasic else {
            completionHandler(.performDefaultHandling, nil)
            return
        }
        if challenge.previousFailureCount > 0 {
            rejected = true
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }
        completionHandler(.useCredential, URLCredential(user: username, password: password, persistence: .forSession))
    }
}
