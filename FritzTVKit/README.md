# FritzTVKit

Swift-Paket ohne UI-Abhängigkeiten mit der plattformunabhängigen Logik von FritzTV und FritzRadio: Abruf und Aufbereitung der Senderlisten einer FRITZ!Box Cable, EPG, Timeshift-Verwaltung und Netzwerkschnittstellen zur Box.

- Swift Tools 5.9, Plattformen: tvOS 17, iOS 17, macOS 14
- Keine externen Abhängigkeiten

## Module

| Datei | Inhalt |
| :--- | :--- |
| `FritzBoxClient` | Abruf von `tvhd.m3u`, `tvsd.m3u`, `radio.m3u` per HTTP, Host-Fallback `fritz.box` → `192.168.178.1` → `fritz.repeater` |
| `M3UParser`, `Channel` | Parsen der M3U-Listen in `Channel` (Name, Stream-URL, Sprachkennung, HD/SD) |
| `ChannelCatalog` | Zusammenfassung der HD/SD- und Frequenzvarianten eines Senders zu `ChannelGroup` |
| `ChannelLineup`, `DefaultLineup` | Vergabe fester Senderplätze, Benutzerreihenfolge (`LineupPreferences`) |
| `PIDUpdate` | Ermittlung fehlender PIDs aus der PMT und Ergänzung im RTSP-Link |
| `EITLogParser`, `EPG`, `EPGStore` | DVB-EIT/SDT aus dem VLC-Log, EPG-Datenmodell, Zuordnung zu Sendern, Cache |
| `XMLTV` | XMLTV-Parser mit Zeitfensterfilter |
| `TimeshiftBufferManager` | Segmentierte TS-Pufferdateien (max. 4 GB je Segment) |
| `ProgressiveJump` | Spulschritte bei wiederholtem Tastendruck |
| `PublicHLSChannels` | HLS-Livestreams öffentlich-rechtlicher Sender für „Von Anfang an“ |
| `MediathekSearchClient` | Client für die MediathekViewWeb-API |
| `SubtitleParser` | TTML/EBU-TT-D und WebVTT |
| `FritzBoxStationSearch` | TR-064-Sendersuchlauf (`X_AVM-DE_Media:1`, Port 49000, HTTP-Digest) |
| `FritzBoxTuner` | Tunerstatus per UPnP (`satip:1`, Port 49000) |
| `PlaybackStatistics` | Bild- und Empfangsstatistik des laufenden Streams |
| `PictureCrop` | Beschnitt von PAL-SD (SAR 16:11 bzw. 12:11) auf exakt 16:9 bzw. 4:3 |
| `RadioStations` | Radiosenderliste für FritzRadio (ohne Senderplätze) |
| `ChannelLogo` | Logo-URLs nach dem Namensschema des AVM-Logoservers |
| `TopShelfStore` | Senderdaten für die tvOS-Top-Shelf-Erweiterung |

## Einbinden

Xcode: *File › Add Package Dependencies › Add Local…* → diesen Ordner wählen. Im FritzTV-Projekt erfolgt die Einbindung über `project.yml`.

```swift
import FritzTVKit

let (host, catalog) = try await FritzBoxClient().loadCatalog()
for group in catalog.tvGroups {
    let channel = group.preferredChannel(preferHD: true)
    print(group.displayName, channel.streamURL)   // RTSP-URL für VLCKit
}
```

Erforderliche Info.plist-Einträge der App:

- `NSAppTransportSecurity` › `NSAllowsLocalNetworking` = `YES` (die Box liefert die Listen nur per HTTP)
- `NSLocalNetworkUsageDescription` (Zugriff auf das lokale Netzwerk)

## M3U-Aufbereitung

- Platzhalter ohne Namen („.“, „..“, „...“) werden verworfen.
- DVB-Steuerzeichen (0x86/0x87, dargestellt als „†“/„‡“) werden aus Sendernamen entfernt.
- „HD“ wird auch innerhalb des Namens erkannt („WDR HD Köln“ → „WDR Köln“).
- Sprachkennungen wie „(eng)“ werden nach `languageTag` übernommen.
- HD- und SD-Variante eines Senders werden zu einer `ChannelGroup` zusammengefasst, auch bei abweichender Schreibweise („HSE Extra HD“ / „HSE EXTRA“).

## Senderplätze

`ChannelLineup` vergibt Platznummern nach `DefaultLineup` (Öffentlich-Rechtliche, Dritte, Private, Spartensender; Shopping- und religiöse Sender standardmäßig ausgeblendet). Benutzerreihenfolge und ausgeblendete Sender werden in `LineupPreferences` (`Codable`) gespeichert. Neu gefundene Sender werden am Ende angehängt und mit `isNew` markiert.

## Tests

```bash
swift test
```

Alternativ ⌘U in Xcode. Als Testdaten dienen reale DVB-C-Senderlisten in `Tests/FritzTVKitTests/Fixtures/` (`tv.m3u`, `tv-nach-suchlauf.m3u`).
