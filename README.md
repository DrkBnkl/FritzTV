# FritzTV – Kabelfernsehen (DVB-C) von der FRITZ!Box auf Apple TV & Mac

[![Plattformen](https://img.shields.io/badge/Plattform-tvOS%2017%2B%20%7C%20macOS%2014%2B-blue)](#starten)
[![Swift](https://img.shields.io/badge/Swift-5.9%2B-F05138?logo=swift&logoColor=white)](#aufbau)
[![FRITZ!Box](https://img.shields.io/badge/FRITZ!Box%20Cable-DVB--C%20%2F%20RTSP-red)](#funktionen-im-überblick)
[![Lizenz: MIT](https://img.shields.io/badge/Lizenz-MIT-green.svg)](LICENSE)

**FritzTV** ist eine native **Apple-TV- (tvOS)** und **Mac-App (macOS)** in SwiftUI zum Fernsehen über den integrierten **DVB-C-Kabeltuner einer AVM FRITZ!Box Cable** – direkt aus dem Heimnetz oder per WireGuard-VPN, ohne zusätzlichen Zwischenserver.

> **🇬🇧 English Summary:** Native **Apple TV (tvOS)** and **macOS** Live TV & IPTV player for **AVM FRITZ!Box Cable (DVB-C)** routers (`6690`, `6670`, `6660`, `6591`, `6590`, `6490 Cable`, and `FRITZ!WLAN Repeater DVB-C`). Streams unencrypted cable TV channels directly via RTSP/M3U using VLCKit, featuring a 30-hour **EPG timeline** (DVB-EIT + XMLTV), **live timeshift** (pause & rewind), **start-over replay** via public broadcaster HLS streams, integrated **MediathekViewWeb** catch-up search with subtitles, **TR-064 station scan**, and **UPnP tuner diagnostics**.

Ein Projekt, zwei Ziele:

- **FritzTV-tvOS** – die Apple-TV-App für das Wohnzimmer (optimiert für die Siri Remote & 50-Hz-Wiedergabe)
- **FritzTV-macOS** – dieselbe App nativ für den Mac (optimiert für Maus, Trackpad und Tastatur)

## Unterstützte FRITZ!Box-Modelle (DVB-C-Tuner)

Voraussetzung ist eine FRITZ!Box mit integriertem **DVB-C-Tuner** und aktivierter Funktion **„DVB-C → Live-TV“** in FRITZ!OS:

| Gerät | Integrierte Tuner | Standard-Hostname |
| :--- | :--- | :--- |
| **FRITZ!Box 6690 Cable** | 4× DVB-C (Quad-Tuner) | `fritz.box` (`192.168.178.1`) |
| **FRITZ!Box 6670 Cable** | 4× DVB-C (Quad-Tuner) | `fritz.box` (`192.168.178.1`) |
| **FRITZ!Box 6660 Cable** | 4× DVB-C (Quad-Tuner) | `fritz.box` (`192.168.178.1`) |
| **FRITZ!Box 6591 Cable** | 4× DVB-C (Quad-Tuner) | `fritz.box` (`192.168.178.1`) |
| **FRITZ!Box 6590 Cable** | 4× DVB-C (Quad-Tuner) | `fritz.box` (`192.168.178.1`) |
| **FRITZ!Box 6490 Cable** | 4× DVB-C (Quad-Tuner) | `fritz.box` (`192.168.178.1`) |
| **FRITZ!WLAN Repeater DVB-C** | 2× DVB-C (Dual-Tuner) | `fritz.repeater` |

> **Hinweise zur Kompatibilität:**
> - **Nicht unterstützt:** Das Einsteigermodell *FRITZ!Box 6430 Cable* sowie reine DSL- oder Glasfaser-Modelle (z. B. 7590, 7690, 5590) besitzen keinen eingebauten DVB-C-Tuner.
> - **Unverschlüsselte Sender (Free-TV):** Über den DVB-C-Tuner der FRITZ!Box werden alle frei empfangbaren digitalen Kabelsender (öffentlich-rechtliche Sender in HD, private Sender in SD sowie Radiosender) gestreamt.
> - **Provider-Mietgeräte:** Bei einzelnen Kabelnetzbetreibern kann der Menüpunkt *„DVB-C / Live-TV“* auf gebrandeten Miet-Routern durch die Anbieter-Firmware ausgeblendet sein.

## Ansichten

| Programmübersicht (EPG-Zeitstrahl) | Live-TV mit Senderliste & Infotafel |
| :---: | :---: |
| ![Programmübersicht](docs/screenshots/epg-zeitstrahl.png) | ![Senderliste & Infotafel](docs/screenshots/senderliste-live.png) |
| **Sendungsinfo, „Von Anfang an“ & Timeshift** | **Mediathek-Suche („Sendung verpasst“)** |
| ![Sendungsinfo & Timeshift](docs/screenshots/sendungsinfo-timeshift.png) | ![Mediathek-Suche](docs/screenshots/mediathek-suche.png) |

## Starten

1. Im Terminal in diesen Ordner wechseln und `./setup.sh` ausführen.
   Das installiert bei Bedarf XcodeGen (über Homebrew), erzeugt `FritzTV.xcodeproj` und öffnet es.
2. Xcode lädt beim ersten Öffnen VLCKit herunter (rund 200 MB, dauert etwas).
3. **Mac:** Oben das Schema `FritzTV-macOS` und „My Mac“ wählen, ⌘R – oder direkt `./scripts/deploy-macos.sh` ausführen, um die fertige Release-Version nach `/Applications/FritzTV.app` zu installieren.
4. **Apple TV:** Zum Aktualisieren auf dem eigenen Apple TV im Heimnetz `./scripts/deploy-tvos.sh` ausführen (baut die Release-Version und installiert sie per `xcrun devicectl` ohne Daten- oder Einstellungsverlust).

Unterwegs (z. B. über Mobilfunk oder im Hotel): vorher das WireGuard-VPN der FRITZ!Box verbinden. Klappt die Namensauflösung von `fritz.box` über das VPN nicht, nimmt die App automatisch `192.168.178.1`.

## Bedienung

| Siri Remote | Mac (Tastatur & Maus) | Im Live-Bild |
| --- | --- | --- |
| Hoch / Runter (Ring-Klick) | ↑ / ↓ | nächster / vorheriger Sender |
| Nach oben wischen | – | Senderleiste am unteren Rand |
| Klick oder nach unten wischen | Return / `⌘I` / Rechtsklick | Sendungsinfo mit Ton, Untertitel, „Von Anfang an“, „In Mediathek suchen“, Einstellungen |
| Zurück | Esc / `⌘L` / Klick ins Bild | Senderliste (mit Mausrad-Scrollen & Hover-Vorschau auf dem Mac) |
| – | `⌘E` / Rechtsklick | Programmübersicht (EPG-Zeitstrahl, mit vertikalem & horizontalem Trackpad-/Mausrad-Scrollen) |
| – | Doppelklick ins Bild | Vollbildmodus umschalten |
| Play/Pause | Leertaste / `⌘P` | Live-Bild anhalten (Timeshift) |
| Links / Rechts | ← / → oder Klick in Zeitleiste | progressives Spulen im Timeshift (10 s → 30 s → 1 Min. → 3 Min. → 5 Min.) |
| – | Ziffern (oder Mausklick) | Direktwahl |

### Programmübersicht (EPG-Zeitstrahl)

- **Hoch / Runter (`↑` / `↓`):** Sender wechseln (auf der Siri Remote gedrückt halten für schnelles Blättern).
- **Links / Rechts (`←` / `→`):** Im Zeitstrahl von Sendung zu Sendung blättern – sowohl bis zu **6 Stunden zurück in die Vergangenheit** („Sendung verpasst“) als auch bis zu **22 Stunden voraus**.
- **Klick (`Return`):** Auf der laufenden Sendung („Jetzt“) sofort umschalten; auf einer vergangenen oder zukünftigen Sendung öffnet sich die **Detailtafel** mit ausführlicher Beschreibung, **„In Mediathek suchen“** (MediathekViewWeb) und **„Umschalten“**.
- **Play/Pause (`Leertaste`):** Öffnet auf „Jetzt“ die Detailtafel zur laufenden Sendung (inkl. **„Von Anfang an“** bei öffentlich-rechtlichen Sendern und **„In Mediathek suchen“**); im verschobenen Zeitstrahl springt die Taste direkt zurück zu „Jetzt“.

## Funktionen im Überblick

- **Live-TV & Zapping:** Schnelles Umschalten mit optionalem schwarzem Bildschirm beim Kanalwechsel (`Black Screen on Zap`), automatischer Variantenwahl (HD bevorzugt, Rückfall auf funktionierende Frequenzen nach Kabel-Umstellungen) und automatischer Nachforderung geänderter PIDs aus der PMT.
- **EPG (DVB-EIT + XMLTV):** Liest für den laufenden Multiplex die genauen DVB-EIT-Daten (inkl. Extended Event Descriptors) aus dem Stream und ergänzt alle übrigen Sender unterbrechungsfrei über eine komprimierte XMLTV-Quelle aus dem Internet (Cache für 12 Stunden).
- **Timeshift:** Pausieren und progressives Vor-/Zurückspulen des laufenden Programms über mehrteilige TS-Ringpufferdateien (`TimeshiftBufferManager`, bis zu 120 Minuten) ohne zweite RTSP-Sitzung an der FRITZ!Box.
- **Von Anfang an (HLS-Replay):** Laufende Sendungen öffentlich-rechtlicher Sender per Klick über deren offizielle HLS-Streams mit `EXT-X-PROGRAM-DATE-TIME` nahtlos vom Sendungsbeginn abspielen.
- **Sendung verpasst (MediathekViewWeb):** Aus der Sendungsinfo oder direkt über die Detailtafel im EPG-Zeitstrahl (auch beim Zurückblättern) vergangene und aktuelle Sendungen in den öffentlich-rechtlichen Mediatheken suchen und abspielen (inkl. EBU-TT-D-/WebVTT-Untertiteln).
- **Senderverwaltung & Sendersuchlauf:** Sender in den Einstellungen frei sortieren oder ausblenden; DVB-C-Sendersuchlauf der FRITZ!Box direkt aus der App über TR-064 starten; Live-Diagnose der 4 Kabel-Tuner (Signalstärke, SNR, Auslastung) über UPnP.
- **Apple TV Top Shelf:** Zeigt die ersten 12 Lieblingssender auf dem Apple-TV-Startbildschirm zum direkten Einschalten per Deep Link (`fritztv://channel/<nummer>`).

## Aufbau

- `FritzTVKit/` – Swift-Paket mit 48 Unit Tests: M3U-Parser, Senderkatalog & Sortierung, EIT-Log-Parser, XMLTV-Parser, EPGStore, Timeshift-Pufferverwaltung, MediathekViewWeb-Client, Untertitel-Parser (TTML/WebVTT), UPnP-Tunerstatus und TR-064-Sendersuchlauf
- `App/Shared/` – gemeinsamer App-Code: `AppModel`, `PlayerController` (VLCKit), `EPGOverviewView`, `Overlays`, `HLSReplayPlayerView`, `MediathekSearchResultsView`, `MediathekPlayer`, `SettingsView`, `XMLTVLoader`
- `App/tvOS/` – Siri-Remote-Steuerung (`RemoteInput`), 50-Hz-Bildwiederholrate (`DisplayCriteria`), UIKit-Videofensterausschnitt
- `App/macOS/` – Tastatursteuerung (`KeyboardInput`), AppKit-Videofläche
- `App/TopShelf/` – tvOS-Top-Shelf-Erweiterung
- `project.yml` – Projektbeschreibung für XcodeGen

## Lizenz & Rechtliche Hinweise

- **Quellcode:** Veröffentlicht unter der [MIT-Lizenz](LICENSE).
- **VLCKit / libVLC:** Die Videowiedergabe nutzt [VLCKit](https://code.videolan.org/videolan/VLCKit) von VideoLAN (dynamisch eingebunden unter der [GNU Lesser General Public License v2.1](https://www.gnu.org/licenses/old-licenses/lgpl-2.1.html)).
- **Mediathek-Suche:** Die Suche nach vergangenen Sendungen nutzt die öffentlich zugängliche Programmierschnittstelle von [MediathekViewWeb](https://mediathekviewweb.de).
- **Markenhinweis:** *FRITZ!* und *FRITZ!Box* sind eingetragene Marken der AVM Computersysteme Vertriebs GmbH. Dieses Projekt ist ein unabhängiges Open-Source-Projekt und steht in keiner Verbindung zu AVM oder den genannten Rundfunkanstalten.
