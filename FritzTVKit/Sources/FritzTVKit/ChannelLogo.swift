import Foundation

/// Senderlogos vom AVM-Logoserver (`http://tv.avm.de/tvapp/logos/<name>.png`).
///
/// Dateiname nach AVM-Schema: kleingeschrieben, Zeichen `\/:<|>"'?*+-.,@()!%&`
/// entfernt, Präfix `alt_` und Suffix ` eng` entfernt, Leerzeichen → `_`, Umlaute → ae/oe/ue, ß → ss,
/// Akzente vereinfacht, mehrfache `_` zusammengefasst. Beispiele: `wdr.png`, `ndr_fs_hh.png`.
///
/// Ob AVM für HD-Sender eigene Dateien führt, ist nicht bekannt. Deshalb liefert
/// `candidateURLs` den Namen mit und ohne „HD“; die Ansicht probiert sie der Reihe nach.
public enum ChannelLogo {
    public static let baseURL = URL(string: "http://tv.avm.de/tvapp/logos/")!

    public static func slug(for channelName: String) -> String {
        var s = channelName.lowercased()
        s.removeAll { "\\/:<|>\"'?*+-.,@()!%&".contains($0) }
        if s.hasPrefix("alt_") { s.removeFirst(4) }
        if s.hasSuffix(" eng") { s.removeLast(4) }
        s = s.trimmingCharacters(in: .whitespaces)
        s = s.replacingOccurrences(of: " ", with: "_").replacingOccurrences(of: "\u{00A0}", with: "_")
        for (from, to) in [("ü", "ue"), ("ä", "ae"), ("ö", "oe"), ("ß", "ss")] {
            s = s.replacingOccurrences(of: from, with: to)
        }
        // Übrige Akzente vereinfachen (é → e, ç → c …)
        s = s.folding(options: .diacriticInsensitive, locale: Locale(identifier: "en_US_POSIX"))
        while s.contains("__") { s = s.replacingOccurrences(of: "__", with: "_") }
        return s
    }

    /// Mögliche Logo-Adressen, die wahrscheinlichste zuerst.
    public static func candidateURLs(for channelName: String) -> [URL] {
        var names = [channelName]
        let lower = channelName.lowercased()
        if lower.hasSuffix(" hd") {
            names.append(String(channelName.dropLast(3)))
        }
        let canonical = Channel.canonicalGroupKey(for: channelName)
        if !names.contains(canonical) {
            names.append(canonical)
        }
        var seen = Set<String>()
        return names.map(slug(for:)).filter { !$0.isEmpty && seen.insert($0).inserted }
            .compactMap { URL(string: "\($0).png", relativeTo: baseURL)?.absoluteURL }
    }

    public static func url(for channelName: String) -> URL? {
        candidateURLs(for: channelName).first
    }

    /// Logo-Adressen eines Radiosenders: zuerst die eigene Liste, dann der AVM-Logoserver.
    public static func radioCandidateURLs(for stationName: String) -> [URL] {
        let own = radioLogoAddresses[radioKey(stationName)].flatMap(URL.init(string:))
        return (own.map { [$0] } ?? []) + candidateURLs(for: stationName)
    }

    /// Schlüssel für die Radioliste: Die Box nennt Sender je nach Frequenz verschieden
    /// („BAYERN 3“, „Bayern 3“, „Antenne Brbg.“), Sender mit Regionalzusatz teilen sich ein Logo.
    static func radioKey(_ name: String) -> String {
        let plain = name.lowercased().filter { $0.isLetter || $0.isNumber }
        for prefix in ["swr1", "swr4", "sr1", "sr3"] where plain.hasPrefix(prefix) { return prefix }
        return plain
    }

    /// Logos der Sender selbst bzw. der ARD für Sender, die der AVM-Server nicht führt oder nur klein.
    /// Die Bilder werden nur verlinkt (Markenzeichen); fehlt eines, greift die nächste Quelle.
    static let radioLogoAddresses: [String: String] = {
        let ard = "https://api.ardmediathek.de/image-service/images/urn:ard:image:"
        return [
            "1live": "https://www1.wdr.de/radio/1live/resources/img/favicon/apple-touch-icon.png",
            "1livediggi": "https://www1.wdr.de/radio/1live-diggi/resources-v5.122.3/img/favicon/apple-touch-icon.png",
            "swr3": "https://www.swr3.de/assets/swr3/icons/apple-touch-icon.png",
            "swr1": "https://www.swr.de/assets/swr/swr1/apple-touch-icon-180x180.png",
            "swr4": "https://www.swr.de/assets/swr/swr4/apple-touch-icon-180x180.png",
            "swraktuell": "https://www.swr.de/assets/swr/swraktuell/apple-touch-icon-120x120.png",
            "dasding": "https://www.dasding.de/assets/dasding/apple-touch-icon.png",
            "bayern3": ard + "52fd25fc45de7c6a?w=512",
            "br24": ard + "c3ab9296f3b282bf?w=512",
            "brklassik": ard + "476e47d76c4bbf78?w=512",
            "sr3": ard + "9e823fcba01bcdbf?w=512",
            "bremenzwei": "https://www.bremenzwei.de/static/img/favicons/apple-touch-icon-180.png?v=4",
            "bremennext": "https://www.bremennext.de/static/img/favicons/apple-touch-icon-180.png?v=5",
            "bayern1": ard + "d4f96c080ae2cb07?w=512",
            "bayern2": ard + "2b23315c8a165b41?w=512",
            "puls": ard + "42476bae0ad2f133?w=512",
            "brschlager": ard + "59fe8803e5e6eace?w=512",
            "brheimat": ard + "f878fd56428bd997?w=512",
            "mdrsanhaltmd": ard + "2e0fbaf706a75f0e?w=512",
            "mdrthuermittew": ard + "3df9da1086dacb2a?w=512",
            "rbb24inforadio": ard + "7c8fdfffb2439269?w=512",
            "radio3": ard + "a347658c3679f1d6?w=512",
            "fritz": ard + "253d788c0da6b297?w=512",
            "sr1": ard + "5af6cbac85049032?w=512",
            "srkultur": ard + "70d2ec0f73eaf61d?w=512",
            "swrkultur": ard + "829ddf7728ddb7f2?w=512",
            "antennesaar": ard + "026de77bde3b36f5?w=512",
            "radiohoreb": "https://www.horeb.org/apple-touch-icon.png",
            "radioella": "https://www.radio-ella.de/apple-touch-icon.png",
            "radioeins": ard + "d9f4cd23ac2d9fe5?w=512",
            "rbb888": ard + "ae012cae99cc023b?w=512",
            "antennebrandenburg": "https://www.antennebrandenburg.de/content/dam/rbb/rbb/logos/touch/ant-128.png",
            "antennebrbg": "https://www.antennebrandenburg.de/content/dam/rbb/rbb/logos/touch/ant-128.png",
            "dlf": "https://www.deutschlandfunk.de/static/img/deutschlandfunk/icons/apple-touch-icon-128x128.png",
            "dlfkultur": "https://www.deutschlandfunkkultur.de/static/img/deutschlandfunk_kultur/icons/apple-touch-icon-128x128.png",
            "dlfnova": "https://www.deutschlandfunknova.de/apple-touch-icon.png",
            "rockantenne": "https://www.rockantenne.de/logos/rock-antenne/apple-touch-icon.png",
            "oldieantenne": "https://www.oldie-antenne.de/logos/oldie-antenne/apple-touch-icon.png",
            "rtlradio": "https://www.rtlradio.de/assets/fallback/fallback_1x1.jpg",
            "80s80s": "https://upload.80s80s.de/production/static/1697296555757/icons/icon_512.ewwAEi8A30w.png",
            "klassikradio": "https://www.klassikradio.de/img/ms-mediumtile.png",
            "erfplus": "https://erf.de/apple-touch-icon.png"
        ]
    }()
}
