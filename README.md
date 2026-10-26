# FritzTV – Kabelfernsehen von der FRITZ!Box auf Apple TV und Mac

Prototyp der Version 1. Ein Projekt, zwei Ziele:

- **FritzTV-tvOS** – die eigentliche Apple-TV-App, testbar im Apple TV Simulator
- **FritzTV-macOS** – dieselbe App als Mac-Fenster, Tastatur statt Fernbedienung

## Starten

1. Im Terminal in diesen Ordner wechseln und `./setup.sh` ausführen.
   Das installiert bei Bedarf XcodeGen (über Homebrew), erzeugt `FritzTV.xcodeproj` und öffnet es.
2. Xcode lädt beim ersten Öffnen VLCKit herunter (rund 200 MB, dauert etwas).
3. **Mac:** Oben das Schema `FritzTV-macOS` und „My Mac“ wählen, ⌘R.
4. **Apple TV Simulator:** Schema `FritzTV-tvOS`, als Ziel einen „Apple TV 4K“-Simulator wählen, ⌘R.
   Fehlt der Simulator: Xcode › Settings › Components › tvOS installieren.

Aus dem Hotel: vorher das WireGuard-VPN der FRITZ!Box verbinden. Klappt `fritz.box` über das VPN nicht,
nimmt die App automatisch `192.168.178.1`.

## Bedienung

| Siri Remote | Mac | Im Live-Bild |
| --- | --- | --- |
| Hoch / Runter | ↑ / ↓ | nächster / vorheriger Sender |
| Klick | Return | Sendungsinfo mit Ton, Untertitel, Einstellungen |
| Zurück | Esc | je nach Einstellung: Programmübersicht oder Senderliste (Fokus auf letztem bzw. aktuellem Sender) |
| Play/Pause | Leertaste | Live-Bild anhalten (Timeshift) |
| Links / Rechts | ← / → | 10 Sekunden zurück / vor |
| – | Ziffern | Direktwahl |

In der Senderliste: ganz oben „Platz eingeben“; Play/Pause bzw. Leertaste startet das Verschieben,
dann mit Hoch/Runter an den neuen Platz, Klick bzw. Return setzt ab.

Im Apple TV Simulator steuert man mit den Pfeiltasten, Return (Klick), Esc (Zurück) und Leertaste
(Play/Pause) oder über Window › Show Apple TV Remote.

## Mediathek

Ganz oben in der Senderliste: „Mediathek · Spielfilme“. Die Seite zeigt alle Spielfilme, die gerade in
den Mediatheken laufen, in Reihen: Neu, Bestbewertet, Lief im Kino, In der Presse besprochen, Merkliste.
Die Schalter „Lief im Kino“ und „In der Presse besprochen“ filtern (kombinierbar). Auf der Detailseite
stehen Kritiken und Kinos; „Abspielen“ startet den Film direkt von den Servern der Sender.

Die Daten kommen von press2arr („Lichtspiel“) auf der NAS. Adresse in den Einstellungen unter
„Mediathek“ (Standard `192.168.178.99:5056`). press2arr braucht dafür den Stand mit den Filtern
`cinema=1`/`press=1` (ab 23.10.2026). Hier gilt die normale Bedienung von tvOS bzw. die Maus auf dem Mac.

## Aufbau

- `FritzTVKit/` – Swift-Paket: M3U laden und parsen, HD/SD zusammenfassen, Senderplätze (mit Tests)
- `App/Shared/` – gemeinsamer App-Code: Modell, Player (VLCKit), Overlays, Einstellungen
- `App/tvOS/` – Siri-Remote-Steuerung, 50-Hz-Umschaltung
- `App/macOS/` – Tastatursteuerung
- `project.yml` – Projektbeschreibung für XcodeGen

## Stand und bekannte Lücken

- **Timeshift** nutzt vorerst das eingebaute Timeshift von VLC. Ob Pause und Zurückspringen mit den
  RTSP-Streams der Box sauber funktionieren, ist der wichtigste Test.
- **Sendungsinfo:** Nur „Jetzt“, so wie VLC es aus der EIT liefert. „Danach“ und Beschreibungen
  kommen mit einem eigenen EPG-Leser.
- **Senderplätze verschieben** per Play/Pause statt „gedrückt halten“ (lässt sich auf beiden Plattformen
  einheitlich umsetzen).
- **Apple TV Simulator:** Ob das VLCKit-Paket eine Bibliothek für den tvOS-Simulator mitbringt, ist
  noch ungeprüft. Falls der Build dort scheitert, erst mit dem Mac-Ziel testen.
- **Über VPN:** In den Einstellungen den Netzwerkpuffer auf 3000 ms stellen; bei Bildabrissen
  „RTP über TCP“ probieren.
