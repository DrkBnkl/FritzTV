# Umfassende Analyse: FRITZ!App TV vs. dream Player TV for FritzBox

**Stand:** 25. Oktober 2026  
**Untersuchte Pakete (APK/XAPK):**
1. `FRITZ!App TV 2.5.2` (`de.avm.android.fritzapptv`, AVM Berlin)
2. `dream Player TV for FritzBox 8.1.2` (`de.cyberdream.dvbc.tv.player`, CyberDream Karlsruhe)

Die Analyse erfolgte durch statische Dekompilierung (DEX-Bytecode, binäre Ressourcen `resources.arsc`, Android-XMLs) sowie Binär- und Symbolanalyse der nativen Shared Libraries (`libavmplayer.so`, `libffmpegJNI.so`, `libvlc.so`).

---

## 1. Architektur- und Komponentenübersicht

| Kriterium | FRITZ!App TV 2.5.2 (AVM) | dream Player TV 8.1.2 (CyberDream) | FritzTV (tvOS/macOS) |
| :--- | :--- | :--- | :--- |
| **Zielplattform** | Smartphone & Tablet (Touch) | Android TV / Fire TV (10-Foot-UI, D-Pad) | Apple TV (Siri Remote) & Mac (Tastatur) |
| **Player-Engine** | Eigener C++ Player `libavmplayer.so` auf FFmpeg 58 Basis | Dual-Engine: **ExoPlayer (Media3)** + **LibVLC 3.x** | **VLCKitSPM** (LibVLC 3.x) |
| **Paketgröße** | ~13 MB (extrem schlank) | ~48 MB (umfangreich durch VLC + Exo) | ~200 MB (Fat Binary Framework) |
| **Video-Rendering** | Direktes OpenGL ES mit Custom Fragment Shadern | `SurfaceView` / `TextureView` (Exo/VLC) | `VLCVideoView` (Metal/CAEAGLLayer) |
| **Deinterlacing** | FFmpeg `yadif` fest im Filtergraph | LibVLC `--video-filter=deinterlace` | LibVLC Deinterlacing aktiv |
| **EPG-Quelle** | Nur laufender Stream (`naGetEPGEntryList`) | EIT-Stream + **Extended Descriptors** + XMLTV | EIT via `EITLogParser` + Background-Scan |
| **Timeshift** | Nicht vorhanden | RAM-Puffer **oder** TS-Datei (`:sout=...`) | TS-Datei (`TimeshiftBufferManager`) |
| **Aufnahmen (PVR)** | Nicht vorhanden | Ja (`RecordingService`, Timer, Vor-/Nachlauf) | Nicht gewünscht |
| **Videotext** | Nicht vorhanden | Eigener interaktiver Viewer (`TLX:V`) | DVB- & Videotext-Untertitel (zvbi) |
| **HbbTV / Red Button** | Nicht vorhanden | WebViewer + Online-Mapping (`dreamepg.de`) | Nicht unterstützt (tvOS WebKit-Restriktion) |
| **Systemintegration** | Standard Android | Android TV TIF (`TvInputService` / Live Channels)| Apple TV **Top Shelf** + URL Schemes |

---

## 2. Tiefenanalyse: FRITZ!App TV 2.5.2 (AVM)

### A. Schlanker nativer Player (`libavmplayer.so` & OpenGL ES)
* **Zero-Copy Shader Pipeline:** AVM verzichtet auf fertige Player-Frameworks und implementiert einen hochoptimierten C++-Player. Decodierte YUV420P-Frames werden direkt über OpenGL-Texturen (`s_texture_y`, `s_texture_u`, `s_texture_v`) an Fragment-Shader übergeben. Dies spart teure Bildkopien im Speicher.
* **Integriertes Deinterlacing (`yadif`):** In `libavmplayer.so` ist libavfilters `yadif` (Yet Another Deinterlacing Filter) fest einkompiliert (`AVMPlayer_yadif`). Für deutsche SD-Sender (576i) liefert das sauberes Deinterlacing ohne Kamm-Artefakte.
* **Audio-Hardware-Sync ohne Resampling:** Vor dem Stream-Start ermittelt die App über das Android-Audiosystem die exakten Hardware-Parameter (`optimalFramesPerBuffer`, `optimalSampleRate`) und initialisiert FFmpeg passgenau damit (`naInit`). Dadurch wird Software-Resampling im Audiopfad komplett vermieden, was Latenzen und Audio-Jitter eliminiert.
* **Pufferverwaltung:** Nutzt getrennte Circular- und Double-Buffer (`circular_buffer_create`, `double_buffer_toggle`) mit Überlaufschutz für ununterbrochene Wiedergabe bei UDP-Netzwerkschwankungen.

### B. Dynamisches PID-Management im laufenden Stream
* Der AVM-Player analysiert kontinuierlich PAT/PMT im MPEG-TS-Strom.
* Bei Änderungen (z. B. dynamische Audiospuren, Umschalten auf Dolby Digital AC3, Regionalsendungen wie WDR-Lokalzeit) triggert der Player intern `pids_add` bzw. `pids_remove` und meldet via Callback `pidsChanged(newUrl, restart)` an Java.
* Die App modifiziert den SAT>IP-RTSP-Link dynamisch, ohne die Session hart abreißen zu müssen.

### C. Tiefgehende FRITZ!OS-Integration (UPnP & TR-064)
* **Tuner-Diagnose ohne Anmeldung (Port 49000, `urn:ses-com:service:satip:1`):**
  * `X_AVM-DE_GetNumberOfTuners`: Ermittelt die exakte Tuner-Anzahl der Box.
  * `X_AVM-DE_GetTunerInfo` (mit `NewX_AVM-DE_TunerNumber` 0..3):
    * Signalstärke: `NewX_AVM-DE_SignalPower` (in dBm bzw. dBµV)
    * Rauschabstand: `NewX_AVM-DE_SignalNoiseRatio` (SNR in dB)
    * Status: `NewX_AVM-DE_HasLock`, `NewX_AVM-DE_Used`, `NewX_AVM-DE_ClientCount`, `NewX_AVM-DE_IPAddresses`
  * *Nutzen:* Klare Unterscheidung, ob ein schwarzes Bild an fehlendem Antennensignal, Frequenzwechseln des Kabelanbieters oder belegten Tunern liegt.
* **Sendersuchlauf & Tuner-Aktivierung (TR-064, Port 49000 mit Authentifizierung):**
  * `SetDVBCEnable` (`urn:dslforum-org:service:X_AVM-DE_Media:1`): Schaltet den DVB-C-Empfang auf der Box aus der Ferne ein oder aus.
  * `StationSearch`: Startet oder stoppt den Sendersuchlauf mit Statusabfrage über `GetSearchProgress`.

### D. Senderlogos & HLS-Rückfallebene
* **AVM-Logoserver:** `http://tv.avm.de/tvapp/logos/<name>.png` mit Normalisierung (Umlaute `ae/oe/ue`, Sonderzeichen entfernt, Kleinschreibung) und Versionsabgleich via `http://tv.avm.de/tvapp/meta.json`.
* **Kuratierte HLS-Senderliste:** Unter `http://tv.avm.de/tvapp/logos/tv_app_german_tv_channels_new.m3u` pflegt AVM direkte Internet-Livestreams deutscher Sender für den mobilen Betrieb.

---

## 3. Tiefenanalyse: dream Player TV for FritzBox 8.1.2 (CyberDream)

### A. Dual-Engine-Player & Decoder-Feintuning
* **ExoPlayer (Media3) + LibVLC umschaltbar:** 
  * Der Nutzer kann zwischen ExoPlayer (niedrige Latenz, moderne Android TV Media3-Pipeline) und LibVLC (maximale Formatunterstützung) wählen.
* **Automatischer Fallback bei schwarzem Bild:**
  * Option `Software (Fallback bei schwarzem Bild)`: Schlägt die Hardwarebeschleunigung bei interlaced Video (1080i/576i) auf schwächeren TV-Sticks fehl, schaltet die App pro Sender automatisch auf Software-Decoding um (`Using software decoder for this channel`).
* **Spezifische VLC-Decoder-Optionen für TV-Sticks:**
  * `--avcodec-skiploopfilter`: Überspringt den H.264-Deblocking-Filter (bringt dramatischen Leistungsgewinn auf langsamen Quadcore-SoCs).
  * `--avcodec-hurry-up`: Verwirft B-Frames/Non-Reference-Frames, wenn die Decodierung hinter den VSync-Takt fällt.
  * `:no-mediacodec-dr`: Deaktiviert Direct Rendering bei Chipsätzen mit instabilen Treibern.
* **Audio-Präzision:**
  * Getrennte Verzögerungseinstellungen: Eigene Tonverzögerung für Stereo/PCM und separate für AC3 (`Audio delay (AC3)`).
  * `Audio Boost` (Dynamikkompression für bessere Sprachverständlichkeit).
  * Echtes Bitstream-Passthrough (`Digital audio passthrough`).

### B. EPG-Super-Extraktion & intelligenter Multiplex-Scan
* **Extended Event Descriptors direkt aus DVB-SI:**
  * CyberDream verwendet einen selbst kompilierten LibVLC-Build (`ts.c` gepatcht), der nicht nur Kurztitel loggt, sondern auch **Extended Descriptors**:
    ```text
    EPG_EIT event id=%u start_time:%lld duration=%d running=%u svcid=%d - short event lang=%3.3s '%s' : '%s'
    EPG_EIT_EXT event id=%u - text='%s'
    ```
  * Dadurch bezieht der dream Player ausführliche Inhaltsangaben, Regie, Darsteller und Altersfreigaben direkt aus dem Kabelstrom – vollständig offline und ohne externe Web-APIs.
* **Hintergrundscan mit Tuner-Rücksicht:**
  * Unsichtbare Instanz sammelt EPG-Daten im Hintergrund (`--demux --no-video --no-audio -vvvvv`).
  * Vor dem Start prüft die App, ob genügend Tuner frei sind (`Checks if not enough free tuners`), um den Live-TV-Betrieb anderer Geräte im Haushalt nicht zu stören.

### C. Timeshift & Aufnahmearchitektur
* **Duales Timeshift:**
  * **Memory Timeshift:** Hält kurze Pausen im RAM – schont den Flash-Speicher von TV-Geräten.
  * **Disk Timeshift:** TS-Mitschnitt via VLC `:sout=#duplicate{dst=std{access=file,mux=ts,dst=...}}`.
  * Automatisches FAT32-Splitting bei 4 GB und Quotaschutz (maximal 50 % des freien Speichers, mindestens 200 MB Sicherheitsreserve).
* **Vollwertiger PVR (`RecordingService`):**
  * Echte Timer-Aufnahmen mit Weckfunktion (`AlarmManager`), automatischem Vor- und Nachlauf in Minuten und Speicherung auf USB- oder Netzwerkpfaden.

### D. Interaktiver Videotext (Videotext 2.0) & HbbTV
* **Eigener Videotext-Browser:**
  * Über einen modifizierten Teletext-Decoder (`TLX:V` im Logcat) liest die App Seitendaten aus dem VBI-Strom und stellt einen voll interaktiven Videotext-Viewer mit Seitendirektwahl (100–899), Transparenzstufen und Subpage-Navigation bereit.
* **HbbTV / Red Button (`HbbTVActivity`):**
  * CyberDream mappt über eine gepflegte Online-Datenbank (`dreamepg.de/hbbtv/hbbtv.txt`) DVB-Kanal-IDs auf die offiziellen HbbTV-Portale der Sender. Bei Druck auf die rote Taste öffnet eine TV-optimierte WebView die jeweilige Sender-Mediathek.

### E. Zapping & Self-Healing Watchdog
* **Black Screen on Zap:** Option, beim Umschalten sofort ein schwarzes Bild zu zeigen, statt alte Pufferblöcke oder Standbilder flackern zu lassen.
* **Playback Watchdog (`MONITOR MEDIAPLAYER TIMEOUT`):**
  * Ein Hintergrund-Monitor überwacht das Eintreffen neuer Videoframes. Friert ein Stream ein oder schläft der RTSP-Socket ein, greift der Watchdog nach Timeout ein und baut die Verbindung automatisch neu auf.
* **Android TV Live Channels (TIF):**
  * Implementiert `RichTvInputService` und speist alle Sender direkt in den nativen TV-Guide des Google/Android TV Systems ein.

---

## 4. Direkter Funktionsvergleich mit FritzTV

| Bereich | Was FRITZ!App TV besser macht | Was dream Player TV besser macht | Status & Maßnahmen in FritzTV |
| :--- | :--- | :--- | :--- |
| **Player-Pipeline** | Extrem schlank (10 MB), Zero-Copy OpenGL Shader, `yadif` Deinterlacer | Dual-Engine, Fallback auf Software bei schwarzem Bild, Codec-Tweaks (`skiploopfilter`) | Wir nutzen VLCKitSPM. Codec-Tweaks (`--avcodec-skiploopfilter`, `:input-fast-seek`) können wir direkt in die `mediaPlayerOptions` übernehmen. |
| **Tuner-Status** | Exakte SNR- (dB) und Pegel-Werte (dBm) via UPnP ohne Passwort | Kennt Tuner-Zählung und verhindert EPG-Scans bei Vollbelegung | In FritzTV bereits über `FritzBoxTuner` implementiert. Wir sollten den Background-Scan pausieren, wenn alle Tuner belegt sind. |
| **EPG-Tiefe** | Nur Jetzt/Danach aus laufendem Stream | Liest **Extended Event Descriptors** (`EPG_EIT_EXT`) für volle Inhaltsangaben | **Chance für FritzTV:** Unser `EITLogParser` wertet bisher Kurztitel aus. Durch Auswertung der VLCKit-Extended-Descriptor-Logs können wir volle Handlungsbeschreibungen direkt aus DVB-SI extrahieren. |
| **EPG-Hintergrundscan** | Keiner | Headless VLC mit Tuner-Check | Unser `BackgroundEPGScanner` mit PIDs `0,16,17,18,20` ist mit nur ~150 kbit/s sogar sparsamer als Dream Player. Tuner-Check vor dem Scan ergänzen. |
| **Timeshift** | Kein Timeshift | RAM-Puffer für kurze Pausen, FAT32-4GB-Split, Speicherquoten | Unser `TimeshiftBufferManager` deckt 4 GB-Limit, 50 % Quote und 200 MB Floor bereits ab. |
| **Stabilität & Watchdog** | Dynamischer PID-Wechsel bei PMT-Änderungen | **Watchdog-Monitor:** Erkennt Deadlocks / Frame-Stalls automatisch | **Hoher Mehrwert:** Watchdog in `PlayerController` einbauen, der bei stehendem Bild nach 5–6 s selbstständig neu verbindet. |
| **Videotext / HbbTV** | Keine | Eigener Text-Viewer, HbbTV-Portale in WebView | Teletext-Untertitel (Tafel 150/777 via zvbi) sind in FritzTV aktiv. Vollbild-Videotext scheitert an VLCKit 3-API; HbbTV scheitert an tvOS-Restriktionen (kein WebKit). |
| **Ergonomie** | Für Handys optimiert | TV-optimiert (Keymaps, Black Screen on Zap) | FritzTV ist bereits nativ auf Siri Remote (tvOS) und macOS-Tastatur maßgeschneidert; Black Screen beim Umschalten ist als Option denkbar. |

---

## 5. Konkrete Ableitungen und Empfehlungen für FritzTV

1. **EPG Extended Descriptors einbinden:**
   * VLCKit loggt bei ausführlichen Streams auch die Extended Event Descriptors (`event id=... text=...`).
   * `EITLogParser` erweitern, um diese Texte zu sammeln und in `EPGStore` als Handlungsbeschreibung abzulegen.
2. **Playback Watchdog (Self-Healing):**
   * Nach dem Vorbild des Dream Players einen 5-Sekunden-Timer aktivieren: Kommen nach Kanalwechsel oder Pufferabriss keine neuen Video-Timecodes an, schaltet der Watchdog automatisch die RTSP-Session neu auf oder wechselt von UDP auf TCP.
3. **Tuner-Schutz für BackgroundEPGScanner:**
   * Vor dem Anwerfen des Hintergrundscans fragt `BackgroundEPGScanner` über `FritzBoxTuner.fetchTunerStatus()` ab, wie viele Tuner frei sind. Ist nur noch 1 Tuner frei, pausiert der Scan, um Familienmitglieder im Heimnetz nicht zu blockieren.
4. **Decoder-Optionen für schwächere Geräte optimieren:**
   * In `PlayerController` die Optionen `--avcodec-skiploopfilter=all`, `--avcodec-hurry-up=1` und `:input-fast-seek` testen, um die Umschaltzeiten noch weiter zu drücken.
