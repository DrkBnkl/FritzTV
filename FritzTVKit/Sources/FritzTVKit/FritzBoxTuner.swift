import Foundation

/// Informationen zu einem einzelnen DVB-C-Tuner der FRITZ!Box.
public struct TunerInfo: Sendable, Hashable {
    public let tunerNumber: Int
    public let isUsed: Bool
    public let hasLock: Bool
    public let signalPower: Double?
    public let signalNoiseRatio: Double?
    public let channelName: String?
    public let clientCount: Int
    public let ipAddresses: [String]

    public init(
        tunerNumber: Int,
        isUsed: Bool,
        hasLock: Bool,
        signalPower: Double? = nil,
        signalNoiseRatio: Double? = nil,
        channelName: String? = nil,
        clientCount: Int = 0,
        ipAddresses: [String] = []
    ) {
        self.tunerNumber = tunerNumber
        self.isUsed = isUsed
        self.hasLock = hasLock
        self.signalPower = signalPower
        self.signalNoiseRatio = signalNoiseRatio
        self.channelName = channelName
        self.clientCount = clientCount
        self.ipAddresses = ipAddresses
    }
}

/// Gesamtzustand aller Tuner der FRITZ!Box.
public struct TunerStatus: Sendable, Hashable {
    public let totalTuners: Int
    public let tuners: [TunerInfo]

    public init(totalTuners: Int, tuners: [TunerInfo]) {
        self.totalTuners = totalTuners
        self.tuners = tuners
    }

    public var usedCount: Int {
        tuners.filter(\.isUsed).count
    }

    public var freeCount: Int {
        max(totalTuners - usedCount, 0)
    }

    public var allTunersBusy: Bool {
        totalTuners > 0 && usedCount >= totalTuners
    }
}

/// Fragt den Tuner-Status der FRITZ!Box per UPnP-SOAP ohne Passwort ab
/// (Service `urn:ses-com:service:satip:1` unter Port 49000).
public struct FritzBoxTunerClient: Sendable {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    /// Fragt den aktuellen Tuner-Status ab. Gibt `nil` zurück, wenn die Box nicht erreichbar ist.
    public func fetchStatus(host: String) async -> TunerStatus? {
        guard let count = await fetchTunerCount(host: host), count > 0 else {
            return nil
        }
        // Ob die Box ab 0 oder ab 1 zählt, ist nicht dokumentiert: antwortet Tuner 0 nicht,
        // wird ab 1 gezählt.
        var tuners: [TunerInfo] = []
        let numbers: [Int]
        if let info = await fetchTunerInfo(host: host, tunerNumber: 0) {
            tuners.append(info)
            numbers = Array(1..<count)          // 0 … count-1, Tuner 0 schon abgefragt
        } else {
            numbers = Array(1...count)          // 1 … count
        }
        for number in numbers {
            if let info = await fetchTunerInfo(host: host, tunerNumber: number) {
                tuners.append(info)
            }
        }
        return TunerStatus(totalTuners: count, tuners: tuners)
    }

    private func fetchTunerCount(host: String) async -> Int? {
        let envelope = """
        <?xml version="1.0" encoding="utf-8"?>
        <s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">
            <s:Body>
                <u:X_AVM-DE_GetNumberOfTuners xmlns:u="urn:ses-com:service:satip:1"/>
            </s:Body>
        </s:Envelope>
        """
        guard let xml = await postSoap(host: host, action: "X_AVM-DE_GetNumberOfTuners", body: envelope) else {
            return nil
        }
        return extractTag("NewX_AVM-DE_TunerCount", from: xml).flatMap(Int.init)
    }

    private func fetchTunerInfo(host: String, tunerNumber: Int) async -> TunerInfo? {
        let envelope = """
        <?xml version="1.0" encoding="utf-8"?>
        <s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">
            <s:Body>
                <u:X_AVM-DE_GetTunerInfo xmlns:u="urn:ses-com:service:satip:1">
                    <NewX_AVM-DE_TunerNumber>\(tunerNumber)</NewX_AVM-DE_TunerNumber>
                </u:X_AVM-DE_GetTunerInfo>
            </s:Body>
        </s:Envelope>
        """
        guard let xml = await postSoap(host: host, action: "X_AVM-DE_GetTunerInfo", body: envelope) else {
            return nil
        }

        let used = extractTag("NewX_AVM-DE_Used", from: xml) == "1"
        let lock = extractTag("NewX_AVM-DE_HasLock", from: xml) == "1"
        // Dezimalkomma vorsichtshalber zulassen
        func decimal(_ tag: String) -> Double? {
            extractTag(tag, from: xml).flatMap { Double($0.replacingOccurrences(of: ",", with: ".")) }
        }
        let power = decimal("NewX_AVM-DE_SignalPower")
        let snr = decimal("NewX_AVM-DE_SignalNoiseRatio")
        let name = extractTag("NewX_AVM-DE_ChannelName", from: xml).flatMap { $0.isEmpty ? nil : $0 }
        let clientCount = extractTag("NewX_AVM-DE_ClientCount", from: xml).flatMap(Int.init) ?? 0
        let ipString = extractTag("NewX_AVM-DE_IPAddresses", from: xml) ?? ""
        let ips = ipString.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }

        return TunerInfo(
            tunerNumber: tunerNumber,
            isUsed: used,
            hasLock: lock,
            signalPower: power,
            signalNoiseRatio: snr,
            channelName: name,
            clientCount: clientCount,
            ipAddresses: ips
        )
    }

    private func postSoap(host: String, action: String, body: String) async -> String? {
        guard let url = URL(string: "http://\(host):49000/upnp/control/satip") else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 3
        request.setValue("text/xml; charset=\"utf-8\"", forHTTPHeaderField: "Content-Type")
        request.setValue("\"urn:ses-com:service:satip:1#\(action)\"", forHTTPHeaderField: "SOAPACTION")
        request.httpBody = Data(body.utf8)

        guard let (data, response) = try? await session.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200 else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    private func extractTag(_ tag: String, from xml: String) -> String? {
        guard let open = xml.range(of: "<\(tag)>"),
              let close = xml.range(of: "</\(tag)>", range: open.upperBound..<xml.endIndex) else {
            return nil
        }
        return String(xml[open.upperBound..<close.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
