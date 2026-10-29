# Architektur & Funktionsbeschreibung: FritzTV (tvOS & macOS)

## Überblick

- **Plattformen:** Native SwiftUI-Anwendung für **Apple TV (`FritzTV-tvOS`, ab tvOS 17)** und **Mac (`FritzTV-macOS`, ab macOS 14)**.
- **Unterstützte TV-Tuner:**
  - **FRITZ!Box Cable mit Quad-Tuner (4× DVB-C):** FRITZ!Box 6690 Cable, 6670 Cable, 6660 Cable, 6591 Cable, 6590 Cable, 6490 Cable (`fritz.box` / `192.168.178.1`)
  - **Repeater mit Dual-Tuner (2× DVB-C):** FRITZ!WLAN Repeater DVB-C (`fritz.repeater`)
  - Empfangen werden alle unverschlüsselten DVB-C-Kabelprogramme (Öffentlich-Rechtliche in HD, Private in SD sowie digitales Kabelradio).
- **Technik-Stack:** SwiftUI, VLCKit (`VLCKitSPM`) für RTSP/MPEG-TS und DVB-Untertitel, `AVKit`/`AVPlayer` für HLS-Replay und Mediathek-Streams, modulares Swift-Paket `FritzTVKit` für Parser, EPG-Speicher, UPnP/TR-064 und Timeshift-Verwaltung.

## Bedienung (Siri Remote, Tastatur & Maus)

- **Im Live-Bild:**
  - **Hoch/Runter (Ring-Klick auf Siri Remote / `↑`/`↓` am Mac):** nächster/vorheriger Senderplatz mit Umlauf am Listenende und 350-ms-Entprellung beim schnellen Durchzappen.
  - **Nach oben wischen (Siri Remote):** öffnet die horizontale Senderleiste am unteren Bildrand (`ChannelFooter`).
  - **Klick oder nach unten wischen (`Return` / `⌘I` / Rechtsklick am Mac):** öffnet die Sendungsinfo (`InfoPanel`, links „LÄUFT“, rechts „DANACH“) mit Schaltern für Tonspur, Untertitel, „Von Anfang an“ (Öffentlich-Rechtliche), „In Mediathek suchen“ und „Einstellungen“.
  - **Zurück (`Esc` / `⌘L` / Klick ins Bild am Mac):** öffnet die zweispaltige Senderliste (`ChannelListOverlay`). Wohin der Fokus beim Öffnen springt („Programmübersicht“, „letzter Sender“ oder „aktueller Sender“), ist in den Einstellungen wählbar.
  - **Play/Pause (`Leertaste` / `⌘P`):** Live-Bild anhalten (Timeshift).
  - **Links/Rechts (`←`/`→` oder Klick in die Zeitleiste am Mac):** im Timeshift progressiv spulen (1× 10 s, 2× 30 s, 3× 1 Min., 4× 3 Min., 5× 5 Min., ab 6× jeweils +5 Min.); im Live-Bild Ziffern-Direktwahl über Bildschirmtastatur.
  - **Doppelklick ins Bild (Mac):** Vollbildmodus umschalten.
- **In der Programmübersicht (`EPGOverviewView`):**
  - **Hoch/Runter (`↑`/`↓`, gedrückt halten oder Mausrad/Trackpad):** Senderzeile wechseln. Das Live-Bild läuft rechts oben im Vorschaufenster weiter.
  - **Links/Rechts (`←`/`→` oder horizontales Trackpad-Scrollen):** im Zeitstrahl von Sendung zu Sendung blättern – bis zu **6 Stunden zurück in die Vergangenheit** und bis zu **22 Stunden in die Zukunft**. Beim Erreichen der aktuell laufenden Sendung rastet die Ansicht automatisch wieder auf „Jetzt“ ein.
  - **Klick (`Return` oder Mausklick):** auf der laufenden Sendung („Jetzt“) sofort umschalten; auf einer vergangenen oder zukünftigen Sendung öffnet sich die **Detailtafel (`EPGDetailPanel`)** mit Titel, Untertitel, vollständiger Beschreibung sowie den Aktionen **„In Mediathek suchen“**, **„Umschalten“** und **„Schließen“**.
  - **Play/Pause (`Leertaste`):** öffnet auf „Jetzt“ die Detailtafel für die aktuell laufende Sendung (inkl. **„Von Anfang an“** und **„In Mediathek suchen“**); ist der Zeitstrahl in die Vergangenheit oder Zukunft verschoben, springt `Play/Pause` sofort zurück zu „Jetzt“.

## Senderliste & Senderplätze

- Abruf direkt per HTTP von der FRITZ!Box ohne Anmeldung: `http://fritz.box/dvb/m3u/tvhd.m3u`, `tvsd.m3u`, `radio.m3u` (automatischer Rückfall auf `192.168.178.1` und `fritz.repeater`).
- **Sendersuchlauf aus der App:** Einstellungen › Sendersuchlauf über TR-064 (`X_AVM-DE_Media:1`, `StationSearch`, Port 49000, HTTP-Digest, Kennwort im Schlüsselbund).
- **Varianten-Gedächtnis & PID-Nachforderung:** Probiert alle Frequenzvarianten eines Senders der Reihe nach, merkt sich die funktionierende (`workingVariantIDs`) und prüft bei fehlendem Bild nach 6 Sekunden die PMT-Spuren aus VLC (`missingPIDs`), um geänderte Audio-/Video-PIDs automatisch im RTSP-Link zu ergänzen.
- **Sortierung & Sichtbarkeit:** Feste Platznummern nach `DefaultLineup` (Öffentlich-Rechtliche, Dritte, Private, Spartenkanäle). In Einstellungen › „Sender verwalten“ frei umsortierbar und ein-/ausblendbar.

## Programmdaten (EPG)

- **Duale Quelle ohne Tuner-Konflikt:**
  1. **Aus dem laufenden Stream (DVB-EIT):** `EITLogParser` und `EPGLogReceiver` werten die DVB-SI-Tabellen (SDT und EIT inkl. Extended Event Descriptors) des aktuell empfangenen Multiplexes in Echtzeit aus.
  2. **Aus dem Internet (XMLTV):** Da die FRITZ!Box pro Client-IP nur einen RTSP-Stream gleichzeitig ausliefert, lädt `XMLTVLoader` für alle übrigen Sender alle 12 Stunden eine komprimierte XMLTV-Datei (`epg.xml.gz`, Zeitfenster −6 h bis +4 Tage) im Hintergrund herunter und legt sie zusammen mit dem DVB-Cache (`epg_cache.json`) persistent ab.

## Timeshift, „Von Anfang an“ & Mediathek-Suche

- **Timeshift (`TimeshiftBufferManager`):** Der Live-Player zeigt das Bild und schreibt den Strom gleichzeitig in segmentierte TS-Dateien. Anhalten oder Zurückspulen startet den Replay-Player nahtlos über dem stumm weiterlaufenden Live-Player; beim Erreichen der Segmentgrenze wird automatisch eine neue TS-Datei begonnen (Pufferlänge einstellbar: 30, 60, 90 oder 120 Minuten).
- **Von Anfang an (`HLSReplayPlayerView`):** Wechselt für öffentlich-rechtliche Sender (`PublicHLSChannels`) auf den offiziellen HLS-Livestream und springt per `AVPlayerItem.seek(to: startDate)` über `EXT-X-PROGRAM-DATE-TIME` an den Sendungsanfang.
- **In Mediathek suchen (`MediathekSearchClient` & `MediathekSearchResultsView`):** Durchsucht die MediathekViewWeb-API (`/api/query`) nach Titel/Thema und Sender und spielt gefundene Sendungen im `MediathekPlayer` inklusive TTML-/WebVTT-Untertiteln (`SubtitleParser`) ab.

## Technische Details

1. **Zeilen-Virtualisierung (Viewport Culling):** Sowohl `EPGOverviewView` als auch `ChannelListOverlay` rendern nur die tatsächlich im Sichtfenster liegenden Senderzeilen (plus Puffer), wodurch das Blättern auf Apple TV und Mac verzögerungsfrei bleibt.
2. **Asynchroner EPG-Cache-Start:** `EPGStore` lädt und bereinigt `epg_cache.json` beim App-Start asynchron im Hintergrund, ohne den Main-Thread zu blockieren.
3. **Siri-Remote-Wischgesten vs. Zap-Debounce:** `cancelPendingZap()` verhindert zuverlässig, dass eine Wischgeste auf dem Touchpad der Siri Remote nach einem ausgelösten `onMoveCommand` im Hintergrund noch den Sender wechselt.
4. **Einheitliches Design-System:** Durchgängige Skalierung über `UI.s(...)` / `UI.font(...)`, einheitliches `PanelBackground` mit Glas-Effekt und feinem Rahmen auf allen Tafeln sowie konsistente Akzentfarben (`UI.accent`).
