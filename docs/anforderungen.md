# Anforderungen: FRITZ!Box-TV-App für Apple TV

Stand: 24.10.2026 (überarbeitet nach Analyse des dream Player TV for FritzBox; Bildschirmentwürfe in der Slideshow „FRITZ!Box TV – So sieht die App aus“; Mediathek-Seite mit press2arr ergänzt; Version 2 mit Umsetzungsprüfung ergänzt)

## Rahmen

- Rein private App, kein App Store.
- Installation über Xcode auf dem eigenen Mac mit kostenloser Apple-ID. Die Signatur läuft nach 7 Tagen ab; wöchentliches Neuaufspielen, möglichst per Skript automatisiert. Einstellungen sollen dabei erhalten bleiben.
- Quelle: FRITZ!Box Cable (192.168.178.1), Vodafone Kabel Berlin. Nur unverschlüsselte Sender (Öffentlich-Rechtliche in HD, Private in SD).
- Technik: SwiftUI, VLCKit für RTSP, Paket FritzTVKit für Senderliste und Senderplätze. Projekt in ~/coding/FritzTV (XcodeGen), Ziele tvOS und macOS.

## Bedienung (Siri Remote, im Live-Bild)

Grundsatz: keine Wischgesten, alles über Tasten und Klicks.

- Klassisch umschalten wie beim Fernseher. Die App startet direkt mit dem letzten Sender.
- Hoch/Runter: nächster/vorheriger Senderplatz, mit Umlauf am Listenende.
- Klick in die Mitte: Sendungsinfo (links „Jetzt“, rechts „Danach“) mit Schaltern für Ton, Untertitel, Bildformat und dem Zugang zu den Einstellungen.
- Zurück: öffnet die Senderliste als Overlay über dem laufenden Bild. Der Fokus steht auf dem zuletzt gesehenen Sender, Zurück + Klick schaltet also zum vorherigen Sender. Noch einmal Zurück schließt die Liste.
- In der Senderliste ganz oben: „Mediathek · Spielfilme“ und „Platz eingeben“ (Direktwahl per Zahleneingabe auf dem Bildschirm, mit Vorschau des Senders); auf einem Sender: verschieben (Prototyp: Play/Pause) oder ausblenden.
- Play/Pause: Live-Bild anhalten (Timeshift). Links/Rechts: 10 Sekunden zurück/vor; gedrückt halten: spulen.
- Zurück gedrückt halten führt wie bei tvOS üblich zum Homescreen.
- Mac-Version: Esc = Zurück, Return = Klick, Pfeiltasten, Leertaste = Play/Pause, Ziffern = Direktwahl.

## Senderliste

- Die App lädt die Listen direkt per HTTP von der Box, ohne Anmeldung (am 23.10.2026 an der eigenen Box getestet): `http://fritz.box/dvb/m3u/tvhd.m3u`, `tvsd.m3u`, `radio.m3u`; Rückfall auf 192.168.178.1.
- Laden beim Start und automatisch, wenn ein Sender ausfällt; zusätzlich „Senderliste aktualisieren“ in den Einstellungen.
- Sendersuchlauf aus der App (seit 24.10.2026): Einstellungen › Sendersuchlauf, über TR-064 (`X_AVM-DE_Media:1`, `StationSearch` start/stop, Fortschritt über `GetSearchProgress`, Port 49000, HTTP-Digest). Braucht Benutzer und Kennwort der FRITZ!Box (Recht „FRITZ!Box Einstellungen“); das Kennwort liegt im Schlüsselbund des Geräts. Während des Suchlaufs ist das Fernsehbild aus, danach lädt die App die Senderliste neu und setzt die Liste toter Varianten zurück. Ohne gespeichertes Kennwort bleibt der Hinweis, den Suchlauf in der FRITZ!Box-Oberfläche unter DVB-C zu starten.
- Nach einem Suchlauf behält die Box alte Einträge: Sender stehen doppelt, neue Frequenz vorne, alte hinten (23.10.2026: Das Erste/WDR/SWR von 330 auf 386 MHz, BR/NDR/MDR von 338 auf 402 MHz). Die App probiert alle Varianten eines Senders der Reihe nach und merkt sich die funktionierende.

## Senderplätze

- Feste Platznummern, frei sortierbar auf dem Apple TV („Verschieben“-Modus in Einstellungen und Senderliste), Sender ausblendbar, Standardbelegung wiederherstellbar.
- Standardbelegung: zuerst die wichtigen Öffentlich-Rechtlichen (1 Das Erste, 2 ZDF, 3 rbb Berlin, 4 arte, 5 3sat, 6 phoenix, …), dann die Dritten, dann Private (ab 21 RTL), dann Nischen und Lokales (ab 48).
- Shopping und religiöse Sender sind standardmäßig ausgeblendet.
- Neue Sender nach einem Suchlauf landen am Ende und werden als neu markiert.
- Frequenzwechsel des Kabelanbieters (zuletzt Vodafone 10/2022 und erneut 2026): Belegung und ausgeblendete Sender bleiben beim Neuladen der Liste erhalten.

## Timeshift (Kernfunktion)

- Der laufende Sender wird ständig in einen Ringpuffer im Cache geschrieben; Play/Pause hält das Live-Bild an.
- Leiste mit Pufferfenster, Position, Rückstand („12 Min. hinter Live“) und Live-Zeitpunkt.
- Links/Rechts springt 10 s, gedrückt halten spult, Spulen bis ganz rechts führt zurück ins Live-Bild.
- Pufferlänge einstellbar, Ziel 60–90 Minuten (HD grob 3–4 GB/h, SD etwa 1,5 GB/h).
- Ein Senderwechsel leert den Puffer (die Box liefert nur einen Stream pro Gerät).
- Umgesetzt (24.10.2026, noch ungetestet): Der Live-Player zeigt das Bild und schreibt den Strom gleichzeitig in eine TS-Datei (`:sout=#duplicate{dst=display,dst=std{access=file,mux=ts,…}}`, eine RTSP-Sitzung). Anhalten oder Zurückspulen startet einen zweiten Player auf dieser Datei; das Live-Bild läuft stumm weiter. Aufholen bis zum Dateiende oder „Live“ schaltet zurück. Grenze: 4 GB, höchstens 50 % des freien Speichers, 200 MB Reserve; bei Erreichen beginnt der Puffer neu. Liefert ein Sender mit Mitschnitt kein Bild (z. B. fehlendes sout-Modul), folgt ein letzter Versuch ohne; klappt der, bleibt der Mitschnitt für die Sitzung aus.
- Vorbild dream Player (APK untersucht 24.10.2026): eine zweite, unsichtbare VLC-Instanz schreibt den RTSP-Stream unverändert als TS-Datei mit (`:sout=#duplicate{dst=std{access=file,mux=ts,dst=…}}`), die sichtbare spielt die wachsende Datei ab. Neue Datei bei 4 GB (FAT32-Grenze), Abbruch mit Meldung, wenn weniger als die Hälfte des freien Speichers bzw. 200 MB Reserve bleiben. Für uns übertragbar mit VLCKit; auf dem Apple TV ist der Cache-Speicher begrenzt und kann vom System geleert werden.
- Aufnahmen sind ausdrücklich nicht gewünscht.

## Mediathek (Spielfilme, Daten von press2arr)

- Übersichtsseite im Design der App, erreichbar aus der Senderliste. Dort gilt die normale tvOS-Fokussteuerung.
- Daten von press2arr („Lichtspiel“) auf der NAS (192.168.178.99:5056, kein Passwort) über `GET /api/mediathek` und `GET /api/item/movie/<id>`; Adresse in den Einstellungen.
- Reihen: Neu in der Mediathek, Bestbewertet, Lief im Kino, In der Presse besprochen, Merkliste.
- Filter (kombinierbar): „Lief im Kino“ (Kinoprogramme Yorck/ASTOR inkl. Archiv, `n_cinema`) und „In der Presse besprochen“ (SPIEGEL u. a., `n_press`, mit jüngstem Urteil); Sortierung nach Bewertung, Neu oder Jahr.
- Detailseite: Handlung, Regie, Besetzung, Bewertung, Kritiken mit Urteil, Kinos, Merken (Merkliste in press2arr).
- Abspielen direkt über die MP4-Links der Sender mit Apples Player; funktioniert auch unterwegs, nur die Liste kommt von der NAS. Der Fernsehstream wird solange angehalten.
- Zu Beginn nur Spielfilme; Serien später.
- Nicht übernommen aus press2arr: Radarr/Sonarr-Anfragen, Downloads, Plex, Feed-Verwaltung.
- press2arr erweitert (23.10.2026): `cinema=1`, `press=1`, `limit` sowie Felder `n_cinema`, `n_press`, `press_sources`, `press_verdict`; dabei Fehler in der Presse-Zählung von `query_items` behoben (zählte die Artikel aller Titel desselben Typs).

## Bild

- Deinterlacing für SD-Sender (576i, betrifft vor allem die Privaten).
- Bildwiederholrate an die Quelle anpassen (50 Hz für deutsches TV) über AVDisplayManager.
- Bildformat automatisch, manuell umschaltbar.

## Ton und Untertitel

- Auswahl von Audiospur und Untertiteln.
- Dolby Digital (AC3) unverändert an Soundbar/AV-Receiver durchreichen.
- Audiodeskription standardmäßig meiden; Standardsprache Deutsch.
- Tonverzögerung einstellbar (Startwert −125 ms wie im dream Player, am eigenen Gerät justieren).
- DVB-Untertitel; Videotext-Untertitel (Tafel 150/777) über die Untertitelauswahl. Videotext als eigene Ansicht ist mit VLCKit 3 nicht möglich (siehe unten).

## Sendungsinfo

- Jetzt/Danach aus der EIT im Stream.
- Automatisch einblenden beim Senderwechsel und beim Wechsel der Sendung, jeweils 7 Sekunden (einstellbar).

## Verbindung und Stabilität

- Box automatisch finden (fritz.box, dann 192.168.178.1), manuelle Adresse als Rückfall.
- Die FRITZ!Box meldet sich im Netz als SAT>IP-Server (`urn:ses-com:device:SatIPServer:1`, per SSDP); die RTSP-Links folgen der SAT>IP-Syntax (freq, msys=dvbc, pids). Der dream Player sucht die Box per SSDP. Für uns nicht nötig: SSDP-Multicast braucht auf tvOS eine Sonderberechtigung von Apple (Multicast Networking), die es mit kostenloser Apple-ID nicht gibt.
- Netzwerkpuffer: automatisch 500 ms per LAN, 1000 ms per WLAN, einstellbar.
- Automatisches Neuverbinden bei Abriss mit sichtbarem Countdown.
- Kommt per UDP nichts an (z. B. über VPN), automatischer Wechsel auf RTP über TCP.
- Klare Meldungen bei abgeschaltetem Live-TV, belegten Tunern oder nicht erreichbarer Box. Hinweis bei Umschaltzeiten über 5 s: FRITZ!Box neu starten.
- HD/SD-Vorliebe in den Einstellungen.

## Erkenntnisse aus FRITZ!App TV 2.5.2 (AVM, APK untersucht 24.10.2026)

- **Tuner-Status ohne Box-Login (voraussichtlich):** UPnP-SOAP an `http://<box>:49000/upnp/control/satip`, Service `urn:ses-com:service:satip:1`, Aktionen `X_AVM-DE_GetNumberOfTuners` (→ `NewX_AVM-DE_TunerCount`) und `X_AVM-DE_GetTunerInfo` mit `NewX_AVM-DE_TunerNumber` (→ `ChannelName`, `ClientCount`, `HasLock`, `IPAddresses`, `SignalNoiseRatio`, `SignalPower`, `Used`, jeweils mit Präfix `NewX_AVM-DE_`). Liegt im UPnP-Teil der AVM-Bibliothek, nicht im TR-064-Teil mit Anmeldung – am Gerät prüfen. Nutzen: Anzeige „Tuner belegt“, Signalwerte bei Sendern ohne Bild (wie 330/338 MHz), Infos zur Bildqualität.
- **Senderlisten auch per UPnP:** `X_AVM-DE_GetChannelList_m3u_HD/_SD/_Radio` am selben Dienst; Gerätebeschreibung unter `http://<box>:49000/satipdesc.xml`.
- **Sendersuchlauf aus der App ist möglich, aber nur mit Box-Anmeldung:** TR-064 `urn:dslforum-org:service:X_AVM-DE_Media:1`, Aktion `StationSearch` (`NewStationSearchMode` START/STOP, Status über GetInfo/`GetSearchProgress`). Die AVM-App fragt dafür Zugangsdaten ab. Für uns optional, Passwort müsste in der App gespeichert werden.
- **Programmdaten:** auch AVM liest die EIT nur aus dem gerade laufenden Stream (eigener FFmpeg-Player, `naGetEPGEntryList`); keine Programm-Schnittstelle in der Box. Bestätigt den Weg über VLC.
- **PID-Wechsel:** Der AVM-Player erkennt geänderte PIDs im Stream und baut daraus einen neuen RTSP-Link (`pidsChanged`). Für uns: bei Bildausfall nach Programmumstellungen PMT auswerten bzw. die Liste neu laden.
- **Senderlogos von AVM:** `http://tv.avm.de/tvapp/logos/<name>.png`, Name = Sendername kleingeschrieben, Sonderzeichen entfernt, Leerzeichen → `_`, Umlaute → ae/oe/ue, ß → ss (z. B. `wdr.png`, `ndr_fs_hh.png`, `swr_fernsehen_bw.png`); Versionsstand unter `http://tv.avm.de/tvapp/meta.json`. Genaue Pfade am Mac prüfen.
- **Internet-Streams der Sender:** AVM pflegt eine Liste unter `http://tv.avm.de/tvapp/logos/tv_app_german_tv_channels_new.m3u` (HLS, für unterwegs). Kandidat als gepflegte Quelle für „Von Anfang an“.
- **Standardsortierung:** feste Rangliste nach Vodafone/KDG-Reihenfolge im Code (Das Erste 10, ZDF 20, KiKA 30, arte 40, 3sat 50, SAT.1 60 …).

## Version 2 (Umsetzung geprüft am 24.10.2026)

Grundlage für fast alles ist ein EIT-Leser, denn VLCKit 3 liefert über seine normale Schnittstelle nur den Titel der laufenden Sendung, keine Anfangszeiten und kein Programm.

1. **EIT-Leser (Grundlage):** Vorbild dream Player TV for FritzBox 8.1.2 (APK am 24.10.2026 untersucht): Er wertet die EIT nicht selbst aus, sondern lässt libVLC das tun und liest dessen Debug-Meldungen mit (`event id=… start_time:… duration=… svcid=…` plus Textzeilen). Für das Programm eines Senders startet er eine zweite, unsichtbare VLC-Instanz nur zum Demultiplexen (`--demux`, `--no-video`, `--no-audio`, `--codec none`, `-vvvvv`) auf dem normalen RTSP-Link des Senders und sammelt 15 s lang; während der Wiedergabe liest er bis zu 60 s im laufenden Stream mit. Abgerufen wird bei Bedarf: wenn ein Sender ohne Programmdaten angezeigt wird, plus beim Zuschauen. Für uns: VLCKit 3 hat dieselbe libVLC und eine Log-Schnittstelle (Log-Empfänger mit Debug-Stufe) – also dasselbe Verfahren ohne eigenen EIT-Parser. Zu prüfen: ob VLCKit die Meldungen in derselben Form liefert, ob ein Abruf nur mit den PIDs 0/16/17/18/20 klappt (spart Bandbreite) und ob er einen zusätzlichen Tuner belegt. Rückfall: eigener EIT-Parser (ETSI EN 300 468). Aufwand mittel, Risiko mittel.
2. **Von Anfang an (nur Öffentlich-Rechtliche):** Taste in der Sendungsinfo. Die App wechselt auf den offiziellen HLS-Livestream des Senders und springt per AVPlayer auf die Anfangszeit aus der EIT (`seek(to: Date)` über EXT-X-PROGRAM-DATE-TIME). „Live“ führt zurück aufs Kabelbild. Sender-URLs als Tabelle im Code (Quelle: Free-TV/IPTV), Rückspulfenster laut Senderangaben bis 2 Stunden, je Sender zu messen. Bei Sport teils gesperrt. Private Sender nicht möglich. Aufwand mittel.
3. **Sendung verpasst:** in Programmübersicht und Sendungsinfo „In der Mediathek ansehen“ für vergangene Sendungen. Suche über die MediathekViewWeb-API (`/api/query`, Sender + Titel + Zeitstempel, Ergebnis mit MP4-Links), Abspielen mit dem vorhandenen Mediathek-Player. Nur Öffentlich-Rechtliche, nur was die Sender einstellen. Aufwand klein.
4. **Programmübersicht:** Raster über alle Sender aus den EIT-Daten mit Fortschrittsbalken und Sprung zu 20:15; vergangene Sendungen mit Mediathek-Link, laufende mit „Von Anfang an“. Aufwand mittel.
5. **Zuletzt gesehen:** die letzten 3 Sender oben in der Senderliste. Aufwand klein.
6. **Senderliste selbst prüfen:** Doppeleinträge werden bereits der Reihe nach probiert. Neu: tote Einträge merken und ausblenden, Hinweis „Senderliste veraltet – Suchlauf starten“, wenn ein Sender auf keiner Variante Bild liefert. Aufwand klein.
7. **Top Shelf:** Lieblingssender im oberen Bereich des Apple-TV-Startbildschirms, Klick öffnet direkt den Sender (`fritztv://channel/<nummer>`). Umgesetzt als tvOS-Erweiterung (`FritzTVTopShelf`) mit `TVTopShelfContentProvider` und `TopShelfStore` (synchronisiert die ersten Plätze in Standard-UserDefaults und App Group `group.de.home.fritztv` mit solidem Rückfall auf die wichtigsten Öffentlich-Rechtlichen). URLs per `.onOpenURL` und URL-Scheme `fritztv` im Hauptziel verdrahtet.
8. **Untertitel:** DVB-Untertitel und Videotext-Untertitel (Tafel 150/777). Prüfung ergab: das verwendete Paket `VLCKitSPM` enthält `zvbi 0.2.35` (`vbi_decode_teletext`, `zvbi.c`) für tvOS und macOS. Spurnamen wurden lesbar aufbereitet („Deutsch“, „Videotext (Tafel 150)“, „Dolby Digital“); Verfügbarkeitsstatus `hasSubtitles` signalisiert, wenn keine Untertitel vorliegen.
9. **Infos zur Bildqualität:** Auflösung (z. B. `1920×1080 (1080p)`), Bitrate (in Mbit/s), verlorene Bilder und Abrisse aus `VLCMediaStats` in der Sendungsinfo. Zusätzlich Signalstärke (dB), Signal-Rausch-Verhältnis SNR (dB) und Tuner-Auslastung der Box über UPnP-SOAP ohne Passwort direkt in der Sendungsinfo integriert.

Stand 24.10.2026: Alle Punkte 1 bis 9 sind programmiert und nach einer Durchsicht korrigiert (EPG-Zuordnung über die SDT, Logos, Top Shelf, Von Anfang an u. a.), aber noch nicht am Mac oder Apple TV gebaut und getestet.

## Später & Erweiterungen (Umgesetzt am 24.10.2026)

- **Senderlogos:** Vollständig integriert (Quelle: AVM-Logoserver `http://tv.avm.de/tvapp/logos/<name>.png`) mit lokalem Disk-/Memory-Cache (`URLCache`) in Senderliste, Info-Banner, Sendungsinfo, Top Shelf und Programmübersicht.
- **Hintergrund-EPG-Scan:** `BackgroundEPGScanner` durchsucht fremde Multiplexe automatisch mit einer unsichtbaren VLC-Instanz, sobald freie Tuner an der Box vorhanden sind.
- **Mediathek:** Serien-Kategorie und „🎲 Überrasch mich“-Zufallsauswahl in `MediathekView` und `Press2arrClient` ergänzt.
- **Timeshift-Speicher:** `TimeshiftBufferManager` berechnet die Grenze des Mitschnitts (4 GB, 50 % des freien Platzes, 200 MB Reserve) und räumt alte Pufferdateien beim Umschalten weg.
- **Geänderte PIDs:** Kommt nach 6 s kein Bild, vergleicht der Player die Spur-IDs von VLC (im TS-Demuxer = PIDs aus der PMT) mit den PIDs im RTSP-Link, ergänzt fehlende und verbindet einmal neu (wie die FRITZ!App TV).
- **Untertitel in Mediathek-Videos:** TTML/EBU-TT-D und WebVTT (`SubtitleParser`, inkl. Zeitcode-Versatz 10:00:00), Quelle `url_subtitle` von MediathekViewWeb; für Filme aus press2arr über den passenden Treffer bei MediathekViewWeb. Anzeige über dem Apple-Player, Schalter in Einstellungen › Mediathek.
- **Videotext als eigene Ansicht:** mit VLCKit 3 nicht machbar – die öffentliche Schnittstelle kann keine Videotextseite wählen (`libvlc_video_set_teletext` ist nicht freigegeben). Wäre nur mit eigenem Videotext-Decoder möglich wie im dream Player. Videotext-Untertitel (Tafel 150/777) gehen weiter über die Untertitelauswahl.
- **Deployment-Skript:** `scripts/deploy-tvos.sh` für wöchentliches, bequemes Neuaufspielen auf das Apple TV per `xcrun devicectl`, ohne Daten- oder Einstellungsverlust.

## Nicht gewünscht oder nicht machbar

- Radio (ausdrücklich nicht gewünscht, 24.10.2026).
- Aufnahmen (nicht gewünscht).
- Aufholen mit erhöhter Geschwindigkeit, Bild-in-Bild, Einschlaf-Timer (nicht gewünscht, 24.10.2026).
- „Von Anfang an“ für Private Sender (nur in deren Bezahldiensten).
- HbbTV (tvOS hat keinen Browser für Apps), Autostart beim Einschalten.
- Private Sender in HD (verschlüsselt), zwei Sender gleichzeitig.
