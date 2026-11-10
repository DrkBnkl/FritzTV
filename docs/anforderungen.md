# Architektur und Funktionsbeschreibung: FritzTV

## Überblick

| | |
| :--- | :--- |
| **Targets** | `FritzTV-tvOS` (tvOS 17+), `FritzTV-macOS` (macOS 14+), `FritzRadio` (macOS 14+), tvOS-Top-Shelf-Erweiterung |
| **Quelle** | DVB-C-Tuner der FRITZ!Box Cable 6690, 6670, 6660, 6591, 6590, 6490 (4 Tuner, `fritz.box` / `192.168.178.1`) und FRITZ!WLAN Repeater DVB-C (2 Tuner, `fritz.repeater`) |
| **Empfang** | Alle unverschlüsselten DVB-C-Programme: Öffentlich-Rechtliche in HD, Private in SD, Radio |
| **UI** | SwiftUI; plattformspezifische Eingabe in `App/tvOS` (UIKit) und `App/macOS` (AppKit) |
| **Wiedergabe** | VLCKit (`VLCKitSPM` 3.6.0) für RTSP/MPEG-TS und DVB-Untertitel; `AVPlayer` für HLS-Replay und Mediathek |
| **Logik** | Swift-Paket `FritzTVKit` (Parser, EPG, Timeshift, UPnP/TR-064), siehe [`FritzTVKit/README.md`](../FritzTVKit/README.md) |
| **Projekt** | XcodeGen (`project.yml`) |

## Senderliste

- **Abruf:** HTTP ohne Authentifizierung: `http://fritz.box/dvb/m3u/tvhd.m3u`, `tvsd.m3u`, `radio.m3u`. Fallback auf `192.168.178.1` und `fritz.repeater`.
- **Gruppierung:** HD/SD- und Frequenzvarianten eines Senders werden über den normalisierten Namen (`groupKey`) zu einer `ChannelGroup` zusammengefasst. Die Zuordnung ist damit unabhängig von der Kanalbelegung des Kabelnetzes.
- **Variantenwahl:** Die Varianten werden der Reihe nach probiert (HD bevorzugt); die funktionierende Variante wird gespeichert (`workingVariantIDs`).
- **PID-Nachforderung:** Liefert ein Sender nach 6 s kein Bild, vergleicht `PlayerController` die in der PMT gemeldeten Spuren mit den im RTSP-Link angeforderten PIDs (`missingPIDs`) und öffnet den Sender einmalig mit ergänzten PIDs neu.
- **Senderplätze:** Feste Nummern nach `DefaultLineup` (Öffentlich-Rechtliche, Dritte, Private, Spartensender). Reihenfolge und Sichtbarkeit in *Einstellungen › Sender verwalten* änderbar.
- **Sendersuchlauf:** TR-064, Dienst `X_AVM-DE_Media:1`, Aktion `StationSearch`, Port 49000, HTTP-Digest. Das Kennwort wird im Schlüsselbund gespeichert.
- **Tuner-Diagnose:** UPnP-Dienst `satip:1` (Port 49000): Signalpegel, SNR, Belegung je Tuner.

## Programmdaten (EPG)

Die FRITZ!Box liefert pro Client-IP nur einen RTSP-Stream. Ein zweiter Stream zum Einlesen von EPG-Daten anderer Multiplexe ist daher nicht möglich. Die EPG-Daten stammen aus zwei Quellen:

1. **DVB-EIT (laufender Multiplex):** `EITLogParser` und `EPGLogReceiver` lesen SDT und EIT (inkl. Extended Event Descriptors) aus den Debug-Meldungen des libVLC-TS-Demuxers.
2. **XMLTV (alle übrigen Sender):** `XMLTVLoader` lädt alle 12 h eine gzip-komprimierte XMLTV-Datei. Übernommen werden nur bekannte Sender im Zeitfenster −6 h bis +4 Tage.

`EPGStore` ordnet beide Quellen den Sendern zu und speichert sie in `epg_cache.json`. Der Cache wird beim Start asynchron geladen und bereinigt.

## SD-Bildaufbereitung

- **Deinterlacing:** Für SD-Sender setzt `PlayerController` den Filter `yadif2x` (Einstellung `deinterlaceSD`, Standard an). Jedes Halbbild wird zu einem Vollbild, die Ausgabe hat 50 Bilder/s und passt zur 50-Hz-Anzeige (`DisplayCriteria.request50Hz()`). HD-Sender bleiben ungefiltert.
- **Nachschärfen (nur macOS):** Einstellung `sharpenSD` (Standard aus) hängt an das `VLCMedia` die Optionen `:video-filter=sharpen` und `:sharpen-sigma=0.1`. Das Modul ist nur in VLCKit für macOS enthalten, in TVVLCKit fehlt es (ebenso `postproc`).
- **Bildausschnitt für SD (`PictureCrop`):** PAL-SD mit 720 Pixeln und SAR 16:11 bzw. 12:11 ist knapp breiter als 16:9 bzw. 4:3 (Randspalten der Austastung); viele SD-Signale enthalten zudem oben und unten schwarze Zeilen. `PictureCrop.geometry` liefert deshalb einen VLC-Ausschnitt `BxH+X+Y`, der oben und unten je 1,5 % der sichtbaren Zeilen (576, auch bei 578 gelieferten) abschneidet und die Breite so wählt, dass genau 16:9 bzw. 4:3 entsteht (bei 720 × 576, SAR 16:11: `684x560+18+8`). Andere Formate behalten ihr Seitenverhältnis. Der Ausschnitt wird vor dem Start am Player gesetzt (`videoCropGeometry`), damit er ab dem ersten Bild gilt; eine Medienoption `:crop=…` wirkt nicht, weil die Videoausgabe von VLC am Player hängt und Medienoptionen nicht erbt; sobald die Videospur Größe und SAR meldet, setzt `PlayerController.updateCrop` den passenden Wert, auch für den Timeshift-Player.
- **Skalierung:** Die Vergrößerung auf die Fenster- bzw. Bildschirmauflösung übernimmt die OpenGL-Videoausgabe von VLCKit 3 (bilinear). Ein hochwertigerer Skalierer (z. B. libplacebo in VLC 4 oder MetalFX) ist mit VLCKit 3 nicht ohne eigene Videoausgabe möglich.

## Timeshift, „Von Anfang an“, Mediathek

- **Timeshift (`TimeshiftBufferManager`):** Der Live-Player schreibt den Stream parallel in segmentierte TS-Dateien (max. 4 GB je Segment). Bei Pause oder Rücksprung übernimmt ein zweiter Player die Wiedergabe aus dem Puffer, der Live-Player läuft stumm weiter. Pufferlänge: 30, 60, 90 oder 120 min.
- **Spulen (`ProgressiveJump`):** Schrittweite wächst mit wiederholtem Tastendruck: 10 s, 30 s, 1 min, 3 min, 5 min, danach je +5 min.
- **Von Anfang an (`HLSReplayPlayerView`):** Für Sender aus `PublicHLSChannels` wird auf den offiziellen HLS-Livestream gewechselt und per `AVPlayerItem.seek(to:)` anhand von `EXT-X-PROGRAM-DATE-TIME` zum Sendungsbeginn gesprungen.
- **Mediathek (`MediathekSearchClient`, `MediathekSearchResultsView`, `MediathekPlayer`):** Abfrage der MediathekViewWeb-API (`/api/query`) nach Titel/Thema und Sender. Untertitel in TTML/EBU-TT-D und WebVTT werden mit `SubtitleParser` gelesen.

## Bedienung

### Live-Bild

| Eingabe (Siri Remote / Mac) | Funktion |
| :--- | :--- |
| Hoch/Runter / `↑` `↓`, `⌘→` `⌘←` | Senderwechsel mit Umlauf am Listenende, 350 ms Entprellung |
| Nach oben wischen | Senderleiste (`ChannelFooter`), blendet nach 8 s ohne Eingabe aus |
| Klick, nach unten wischen / `Return`, `⌘I`, Info-Knopf der Steuerleiste, Rechtsklick | Sendungsinfo (`InfoPanel`): Tonspur, Untertitel, „Von Anfang an“, „In Mediathek suchen“, Einstellungen |
| Zurück / `Esc`, `⌃⌘S`, Klick ins Bild | Senderliste (`ChannelListOverlay`); Fokusziel beim Öffnen einstellbar (Programmübersicht, letzter oder aktueller Sender) |
| Play/Pause / Leertaste, `⌘P` | Timeshift anhalten/fortsetzen |
| Links/Rechts / `←` `→`, Ziehen in der Zeitleiste | Timeshift spulen; im Live-Bild Ziffern-Direktwahl |
| – / `⌘L`, Klick auf „LIVE“ | Timeshift: zurück zum Live-Bild |
| – / `⇧⌘←` | Von Anfang an (`PublicHLSChannels`) |
| – / `⌘↑` `⌘↓`, `⌥⌘↓` | Lautstärke der App (`AppModel.volume`, gespeichert in `AppSettings.volume`), Ton aus (nur für die Sitzung) |
| – / Doppelklick ins Bild, `⌃⌘F` | Vollbild umschalten |

**Mac-Steuerleiste (`MacControlBar`, `MacCommands` in `App/macOS`):** Ersetzt auf dem Mac Infoleiste und Timeshift-Leiste. Sichtbar bei Mausbewegung (`MacControlsState`, 3 s Nachlauf, bleibt stehen, solange der Zeiger auf der Leiste liegt), nach dem Umschalten (`bannerVisible`) und während der Pause. Inhalt: Sender und Sendung, Timeshift-Zeitleiste (Breite = Puffer, auf 5 min gerundet, höchstens die eingestellte Pufferlänge; Ziehen springt per `seekToBehind`), „LIVE“-Knopf, Info-Knopf (öffnet `InfoPanel`), Menü für Tonspur und Untertitel, Lautstärke, Vollbild. Das Fenster hat keine sichtbare Titelleiste und wird als Ganzes auf 16:9 gehalten (`WindowAspectRatioModifier`: `NSWindow.aspectRatio` statt `contentAspectRatio`, da das Bild unter die ausgeblendete Titelleiste reicht; SwiftUI-Mindesthöhe 328 pt plus Titelleiste ergibt 640 × 360; abweichend wiederhergestellte Fensterrahmen werden korrigiert); die Fensterknöpfe blenden sich mit der Leiste aus (im Vollbild verwaltet macOS die Titelleiste selbst). Den Mauszeiger blendet die App nur über dem Bild aus, nie außerhalb des Fensters. Die Lautstärke wird auf Live- und Mitschnitt-Player angewendet und als Ausgangswert an die AVPlayer von Mediathek und „Von Anfang an“ übergeben (`AppModel.outputVolume`); Stummschalten setzt sie auf 0, damit es sich nicht mit dem Stummschalten beim Wechsel zwischen Live-Bild und Mitschnitt überschneidet. „Leiser“ lässt eine Stummschaltung bestehen; „Lauter“ und der Regler heben sie auf. Menüs „Wiedergabe“ und „Sender“ enthalten alle Befehle; ⌘-Befehle für das Live-Bild sind gesperrt, solange Einstellungen, Suchergebnisse oder Mediathek-Wiedergabe offen sind; die Lautstärke-Befehle in den Einstellungen (Textfelder) und bei Mediathek- bzw. HLS-Wiedergabe.

### Programmübersicht (`EPGOverviewView`)

| Eingabe | Funktion |
| :--- | :--- |
| `↑` `↓`, Mausrad, Trackpad | Senderzeile wechseln; das Live-Bild läuft im Vorschaufenster weiter |
| `←` `→`, horizontales Scrollen | Von Sendung zu Sendung, −6 h bis +22 h; rastet beim Erreichen der laufenden Sendung auf „Jetzt“ ein |
| Klick / `Return` | Laufende Sendung: umschalten. Sonst: `EPGDetailPanel` mit Titel, Untertitel, Beschreibung, „In Mediathek suchen“, „Umschalten“, „Schließen“ |
| Play/Pause / Leertaste | Auf „Jetzt“: Detailtafel der laufenden Sendung (inkl. „Von Anfang an“). Bei verschobenem Zeitstrahl: zurück zu „Jetzt“ |

## Implementierungsdetails

1. **Zeilen-Virtualisierung:** `EPGOverviewView` und `ChannelListOverlay` rendern nur die sichtbaren Senderzeilen zuzüglich Puffer.
2. **Zap-Entprellung:** `cancelPendingZap()` verwirft ausstehende Senderwechsel, damit eine Touchpad-Geste der Siri Remote nach einem `onMoveCommand` keinen zusätzlichen Wechsel auslöst.
3. **Skalierung und Layout:** Abmessungen und Schriftgrößen über `UI.s(...)` / `UI.font(...)`; einheitlicher `PanelBackground` und Akzentfarbe `UI.accent`.
4. **Top Shelf:** Die Erweiterung zeigt 12 Sender mit Deep Link `fritztv://channel/<nummer>`. Ohne App Group (kostenloses Personal Team) ist das eine feste Standardliste.
