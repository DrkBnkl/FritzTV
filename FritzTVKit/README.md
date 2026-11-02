# FritzTVKit

Liest die Senderlisten einer FRITZ!Box Cable und bereitet sie für die Apple-TV-App auf.

## Einbinden

In Xcode: File → Add Package Dependencies → Add Local… → diesen Ordner wählen.

```swift
import FritzTVKit

let (host, catalog) = try await FritzBoxClient().loadCatalog()
for group in catalog.tvGroups {
    let channel = group.preferredChannel(preferHD: true)
    print(group.displayName, channel.streamURL)   // RTSP-Link für VLCKit
}
```

Info.plist der App:

- `NSAppTransportSecurity` → `NSAllowsLocalNetworking` = YES
- `NSLocalNetworkUsageDescription` = „Zum Abrufen der Sender von deiner FRITZ!Box.“

## Tests

`swift test` (macOS) oder ⌘U in Xcode. Die Tests laufen gegen eine echte DVB-C-Senderliste
(`Tests/FritzTVKitTests/Fixtures/tv.m3u`).

## Was der Parser erledigt

- Platzhalter ohne Namen („.“, „..“, „...“) werden verworfen.
- DVB-Steuerzeichen (0x86/0x87, „†“/„‡“) werden aus Namen entfernt.
- „HD“ wird auch mitten im Namen erkannt („WDR HD Köln“ → „WDR Köln“).
- Sprachkennungen wie „(eng)“ landen in `languageTag`.
- HD- und SD-Variante eines Senders werden zu einer `ChannelGroup` zusammengefasst,
  auch bei abweichender Schreibweise („HSE Extra HD“ / „HSE EXTRA“).

## Senderplätze

`ChannelLineup` vergibt feste Platznummern nach `DefaultLineup` (Öffentlich-Rechtliche,
Dritte, Private, Nischen; Shopping und religiöse Sender ausgeblendet). Eigene Reihenfolge
und ausgeblendete Sender stehen in `LineupPreferences` (Codable). Neu gefundene Sender
landen am Ende und sind als `isNew` markiert.
