# Analyse vergleichbarer Apps (24.10.2026)

Untersucht wurden die Android-Pakete zweier Apps für die FRITZ!Box Cable – nur statisch (entpackt und mit jadx zerlegt, nicht ausgeführt), um zu verstehen, wie sie die Schnittstellen der Box nutzen. Es wurde kein Code übernommen.

| App | Version | Paket | Signatur | Player |
|---|---|---|---|---|
| dream Player TV for FritzBox | 8.1.2 | `de.cyberdream.dvbc.tv.player` | CyberDream, Karlsruhe | libVLC (eigener Build) + FFmpeg, ExoPlayer |
| FRITZ!App TV | 2.5.2 | `de.avm.android.fritzapptv` | AVM Computersysteme Vertriebs GmbH, Berlin | eigener Player `libavmplayer` auf FFmpeg-Basis |

Hinweis: Zwei vorher heruntergeladene Dateien („dream-player-tv-for-fritzbox.apk“ = Aptoide-Store, „uptodown-de.cyberdream.dvbc.player.apk“ = Uptodown-Store) waren App-Store-Installer mit Werbung und weitreichenden Rechten, nicht die gewünschte App. Nicht installieren.

## dream Player TV for FritzBox

### Programmdaten (EPG)
- Kein eigener EIT-Parser und kein Server: libVLC wertet die EIT im Stream aus und schreibt bei hoher Protokollstufe Zeilen wie `EPG_EIT event id=… start_time:… duration=… svcid=…` plus Textzeilen (`- text …`). Die App liest ihr eigenes Protokoll mit (`logcat d EPG:V *:S`) und baut daraus die Datenbank.
- Die Kennung „EPG“ und `svcid=` stammen vermutlich aus einem angepassten libVLC-Build; das normale VLC protokolliert die Ereignisse in ähnlicher Form (zu prüfen).
- Programm eines anderen Senders: zweite, unsichtbare libVLC-Instanz nur zum Demultiplexen (`--demux --no-video --no-audio --no-spu --codec none -vvvvv`, Medienoption `:no-video`) auf dem normalen RTSP-Link des Senders, 15 s sammeln, dann beenden.
- Beim Zuschauen: bis zu 60 s im laufenden Stream mitlesen („Check for EPG“). Übersprungen, solange Timeshift läuft.
- Abruf bei Bedarf: Sender ohne Programmdaten in der Übersicht → nach 3 s Auftrag „EPG Update <Sender>“ in eine Warteschlange.
- Einstellungen: „Auf Kanal umschalten bevor EPG geladen wird“, „EPG Zeitzone Offset“, Aufbewahrungszeit in Tagen; zusätzlich XMLTV-Listen aus dem Internet einbindbar.

### Timeshift
- Zweite libVLC-Instanz schreibt den RTSP-Stream unverändert als TS-Datei: `:sout=#duplicate{dst=std{access=file,mux=ts,dst=<Datei>}}`.
- Der sichtbare Player spielt die wachsende Datei (`file://…/timeshift.ts`) ab.
- Neue Datei bei 4 GB (FAT32), Abbruch mit Meldung bei knappem Speicher (Reserve 200 MB, höchstens die Hälfte des freien Platzes).

### Box und Senderliste
- Box-Suche per SSDP (`M-SEARCH`, `ST: ssdp:all`), Filter auf `urn:ses-com:device:SatIPServer:1` und „FRITZ“ im Namen → die Box ist ein SAT>IP-Server; RTSP-Links folgen der SAT>IP-Syntax.
- Senderlisten: `/dvb/m3u/tvhd.m3u`, `tvsd.m3u`, `radio.m3u` (optional per https), höchstens 500 Zeilen, keine Duplikatprüfung, Steuerzeichen 0x86/0x87 werden entfernt.
- RTSP-Link: `rtsp://<host>:554/?<Query aus der M3U>`.
- VLC-Medienoptionen u. a. `:input-fast-seek`, Hardware-Dekodierung je Gerät.

### Sonstiges
- Eigener Videotext-Dekoder (Farbtasten, transparent, Vollbild).
- Getrennte Tonverzögerung für AC3, Option „Schwarzer Bildschirm beim Umschalten“.
- Meldung bei belegten Tunern; Hinweis, dass schwache Geräte (Fire TV Stick 2) HD nicht flüssig schaffen.
- Von dreamepg.de werden nur Senderlogos geladen.

## FRITZ!App TV (AVM)

### Tuner-Status (UPnP, voraussichtlich ohne Anmeldung)
- `POST http://<box>:49000/upnp/control/satip`, `SOAPACTION: urn:ses-com:service:satip:1#<Aktion>`
- `X_AVM-DE_GetNumberOfTuners` → `NewX_AVM-DE_TunerCount`
- `X_AVM-DE_GetTunerInfo` mit `NewX_AVM-DE_TunerNumber` → `NewX_AVM-DE_ChannelName`, `…_ClientCount`, `…_HasLock`, `…_IPAddresses`, `…_SignalNoiseRatio`, `…_SignalPower`, `…_Used`
- Am selben Dienst: `X_AVM-DE_GetChannelList_m3u_HD`, `…_SD`, `…_Radio`
- Gerätebeschreibung: `http://<box>:49000/satipdesc.xml`

### Sendersuchlauf (TR-064, mit Anmeldung)
- Dienst `urn:dslforum-org:service:X_AVM-DE_Media:1`, Aktion `StationSearch` mit `NewStationSearchMode` = START/STOP, Antwort `NewStationSearchStatus`; Fortschritt über `GetSearchProgress`/GetInfo.
- Die App fragt dafür Box-Zugangsdaten ab.

### Programmdaten
- Nur aus dem laufenden Stream: der native Player liefert EIT-Einträge (`naGetEPGEntryList`), laufende Sendung = Running Status 4. Keine Programm-Schnittstelle in der Box.

### PID-Wechsel
- Der Player meldet geänderte PIDs mit einem neuen RTSP-Link (`pidsChanged(newUrl, restart)`), die App startet den Sender damit neu.

### AVM-Server
- Senderlogos: `http://tv.avm.de/tvapp/logos/<name>.png`; Name = Sendername kleingeschrieben, Zeichen `\/:<|>"'?*+-.,@()!%&` entfernt, Präfix `alt_` und Suffix ` eng` entfernt, Leerzeichen → `_`, ü/ä/ö/ß → ue/ae/oe/ss, Akzente vereinfacht, mehrfache `_` zusammengefasst (Beispiele aus dem Code: `wdr.png`, `ndr_fs_hh.png`, `swr_fernsehen_bw.png`, `arte.png`).
- Versionsstand der Logos: `http://tv.avm.de/tvapp/meta.json` (`{"logos":{"sd":"1","hd":"1","radio":"1"}}`).
- Internet-Streams deutscher Sender (HLS, für unterwegs): `http://tv.avm.de/tvapp/logos/tv_app_german_tv_channels_new.m3u`.

### Standardsortierung
- Feste Rangliste nach Vodafone/KDG-Reihenfolge, z. B. Das Erste 10, ZDF 20, KiKA 30, arte 40, 3sat 50, SAT.1 60, SAT.1 Gold 360, ZDFinfo 430, ZDFneo 450.

## Folgerungen für FritzTV

1. Programmdaten über VLCKit-Protokoll mitlesen (Log-Empfänger mit Debug-Stufe) statt eigenem EIT-Parser; Abruf je Multiplex mit zweiter, unsichtbarer VLC-Instanz.
2. Timeshift auf Mitschnitt in Datei umstellen (zweite VLC-Instanz mit `:sout=#duplicate…`), sichtbarer Player spielt die Datei.
3. Tuner-Status per UPnP abfragen: „Tuner belegt“, Signalwerte bei Sendern ohne Bild, Bildqualität.
4. Senderlogos vom AVM-Server; AVM-HLS-Liste als Quelle für „Von Anfang an“ prüfen.
5. Geänderte PIDs abfangen (neu laden bzw. PMT auswerten).
6. Optional: Sendersuchlauf aus der App per TR-064, nur mit gespeichertem Box-Passwort.

Am Mac zu testen: Tuner-Abfrage ohne Passwort, VLCKit-Protokollzeilen zur EIT, Abruf nur mit PIDs 0/16/17/18/20, Logo-Pfade.
