# Design: MTK-Speicherabbilder (Portierung)

## Context

- **Vorhandene Bausteine:** GPSLoggerKitGPL hat seit `skytraq-bin-port` gemeinsame Hilfen (`Warnings`, `Cancellation`, `ByteReader`, `trackName`, `L10n`) und den gpsbabel-Eintrag in `credits`.
- **Wochenüberlauf:** Die MTK-Zeit ist UTC in Sekunden seit 1970, aber ältere Firmware-Stände schreiben Zeiten, die um 1024 Wochen zurückliegen (`docs/legacy-analysis.md`, Abschnitt zum Wochenüberlauf). Diese korrigiert die nachgelagerte `RecordingProcessing.correctingWeekRollover` von GPSLoggerKit, die beim Lesen standardmäßig aktiv ist.
- **Alt-App:** Sie las MTK-Logger nur über gpsbabel (Treiber `mtk`, `m241`). Für den GPSport 245 gab es den zweistufigen Ablauf `-i m241`, dann `-i m241-bin` auf `data.bin` (`input/mytracks4mac/myTracks/Source/Resources/gpslogger.plist`, Eintrag „Holux GPSport 245 - alternative“).

## Goals / Non-Goals

**Goals:**
- Für dieselben Abbilder liefert `mtk-bin` bzw. `m241-bin` dieselben Punkte wie gpsbabel 1.7.0. Ausgenommen sind die Abweichungen aus D4.

**Non-Goals:**
- Serielles Auslesen, CSV-Ausgabe, Satellitendetails im Datenmodell und Distanz.

## Decisions

### D1 Vorlage und Lizenz

- **Vorlage:** gpsbabel `gpsbabel_1_7_0` (Archiv wie in `skytraq-bin-port`, SHA-256 `30b18663…a797`), Datei `mtk_logger.cc`.
- **Urheber und Lizenz:**
  - Zeile 4: „Copyright (C) 2007 Per Borgentun“.
  - Zeilen 5–6: „With lot of inspiration from wbt-200.c, Copyright (C) 2006 Andy Armstrong“.
  - Zeilen 8–11: GPL-2.0-or-later.
- **Übersetzt werden:**
  - die Ereignisbits (Zeilen 129–134) und die Feldtabelle `log_type` mit Größen (139–188);
  - `LOG_RST` (118–122);
  - `add_trackpoint` (804–923), `mtk_parse` (1113–1335), `mtk_parse_info` (1337–1419) und `mtk_log_len` (1421–1452);
  - `file_init`, `holux245_init` und `is_holux_string` (1460–1507) sowie `file_read` (1509–1661).
- **Gemeinsame Hilfen** (`le_read16/32`, `endian_read_float/double`) sind triviale Leseoperationen. Sie entstehen als eigene Hilfen in `ByteReader` (Float32 und Float64 Little Endian), ohne Übersetzung.

### D2 Struktur

`Sources/GPSLoggerKitGPL/MTK/`:
- `MTKBinFileFormat.swift`: zwei öffentliche Werttypen, `MTKBinFileFormat` (`mtk-bin`) und `M241BinFileFormat` (`m241-bin`). Sie teilen den Leser `MTKDump` mit dem Gerätetyp `.mtk`, `.holuxM241` oder `.holuxGR245`.
- **Feldgrößen:** Sie hängen vom Gerätetyp ab.
  - MTK: Breite und Länge 8 Byte, Höhe 4.
  - Holux: Breite und Länge 4 Byte, Höhe 3.
  - GR245: Höhe und Geschwindigkeit tauschen Inhalt und Größe (4 bzw. 3).
  - Die Tabelle ist ein Wert im Leser, kein globaler Zustand wie in der Vorlage.

### D3 Ablauf des Lesers

- **Kopf:** Formatmaske und Aufzeichnungsart nach Spec „Kopf“. Bei Holux wird Bit 31 gelöscht.
- **Lesen ab `0x200`:** Je Block wird von `blockStart + 0x200` gelesen. An jeder Position gilt:
  1. **Info-Block** (AA×7 … BB×4): Formatmaske, Intervall, Distanz und Track-Ereignisse aktualisieren, 16 Byte weiter.
  2. **Holux-Kennung** (`HOLUX`): Steht ab Byte 10 `WAYPNT`, wird das Ereignis Wegpunkt gesetzt. `HOLUXGR245` und `HOLUXM1200` schalten auf `.holuxGR245`. Weiter geht es um 16 Byte, plus 4 bei folgenden Leerzeichen.
  3. **Vier Bytes `0xFF`:** weiter im nächsten Block bei `0x200`.
  4. **Sonst ein Datensatz** nach Formatmaske.
- **Blockende:** Erreicht ein Datensatz das Blockende, geht es ebenfalls im nächsten Block weiter (D4).
- **Datensatz:**
  - Die Felder werden in Bitreihenfolge gelesen und ihre Bytes XOR-verknüpft.
  - Satellitendaten (SID): Die Anzahl steht in Byte 2–3 des ersten Blocks. Je Satellit kommen 4 Byte, dazu Elevation, Azimut und SNR, soweit gesetzt und mehr als 0 Satelliten.
  - MTK: Es folgt `*`. Fehlt es und steht dort `0xFF`, wird der Datensatz übersprungen (Länge + 2).
  - Danach folgt die Prüfsumme.
- **Punkt:** Zeit plus Millisekunden, Höhe, Geschwindigkeit (km/h / 3,6; GR245: cm/s / 100), Kurs, DOP, genutzte Satelliten und Fix-Art nach Spec.
- **Track-Wechsel:** bei `start`-Ereignis oder vor dem ersten Punkt.
- **Wegpunkt:** bei RCR-Bit `0x0008` oder Holux-Ereignis Wegpunkt. Danach werden die Ereignisse zurückgesetzt.
- **Abbruch:** `Cancellation` je Datensatz.

### D4 Abweichungen von der Vorlage (bewusst)

- **Falsche Prüfsumme:** Die Vorlage gibt nur eine Debug-Meldung aus und übernimmt den Punkt. Hier wird der Datensatz verworfen und als `checksumMismatch` gezählt, wie bei NMEA. Ein beschädigter Datensatz ergäbe sonst eine falsche Position.
- **Unsinnige Positionen:** Die Bedingung der Vorlage `latitude - 90.0 < .000001 && longitude < 0.000001` trifft bei Punkten ohne Fix praktisch jede westliche Länge. Übernommen wird die erkennbare Absicht: Verworfen werden Punkte ohne oder mit unbekanntem Fix bei 90°/0° oder 0°/0°.
- **Fix-Art:**
  - Die Vorlage macht aus `0x0008` (militärisch) die Fix-Art `pps`. Das Datenmodell von GPSLoggerKit kennt `pps` nicht, deshalb ergibt es keine Fix-Art.
  - `0x0040` (geschätzt) ergibt in beiden keine Fix-Art.
- **Ende des Abbilds:** Die Vorlage liest nur, solange der Puffer die Länge des größtmöglichen Datensatzes (32 Satelliten) enthält. Am Dateiende können dadurch Datensätze fehlen. Hier zählt die tatsächliche Länge.
- **Block ohne `0xFF`-Ende:** Die Vorlage würde in den Kopf des nächsten Blocks hineinlesen, hier geht es bei `0x200` weiter.
- **Namen:**
  - Die Vorlage nennt Tracks `track-1`, `track-2` usw. Hier tragen sie den Dateinamen, mit Nummer in Klammern, wenn es mehrere sind.
  - Wegpunkte heißen `POI n` statt `WP000001`.

### D5 Erkennung

- **Kopf** (Prefix ≥ `0x210` Byte):
  - Die Formatmaske enthält Bit 0 (Zeit), Bit 2 und Bit 3 (Breite, Länge).
  - Außer Bit 31 ist kein Bit über 19 gesetzt.
  - Die Aufzeichnungsart ist `0x0104` oder `0x0106`.
- **Ab `0x200`:** ein Info-Block, eine Kennung `HOLUX` oder ein Datensatz (MTK-Größen) mit `*` und richtiger Prüfsumme.
- **Wahl des Formats:**
  - `m241-bin` passt, wenn ab `0x200` (auch nach Info-Blöcken) `HOLUX` steht oder Bit 31 gesetzt ist.
  - `mtk-bin` passt sonst.
  - Beide schließen sich so aus.
- **Abgrenzung zu SkyTraq:** Ein SkyTraq-Abbild hat keinen solchen Kopf. Umgekehrt scheitert ein MTK-Kopf an der Radiusprüfung von SkyTraq. Beides prüfen Tests.

### D6 Concurrency

Wie bei SkyTraq: zustandslose `Sendable`-Formate und ein lokaler Werttyp als Leser, Abbruch über `Cancellation`.

### D7 Tests und Gegenprüfung

- **Test-Encoder:** `MTKTestDump` schreibt Köpfe, Info-Blöcke, Holux-Kennungen und Datensätze für eine Formatmaske, mit Prüfsumme, und füllt Blöcke mit `0xFF` auf.
- **Fixtures:**
  - `mtk.bin`: zwei Blöcke, zwei Tracks, Taste, Millisekunden, Satellitendaten.
  - `m241.bin`: Holux M-241 mit `HOLUXGR241LOGGER` und einem `WAYPNT`.
  - Koordinaten erfunden, um 50° N, 8° O.
- **Black-Box:** `gpsbabel -i mtk-bin` bzw. `-i m241-bin`, `-o gpx`. Verglichen werden Punktanzahl, Positionen, Höhen, Zeiten und Geschwindigkeiten, das Ergebnis kommt nach `PROVENANCE.md`.

## Risks / Trade-offs

- **Viele Gerätevarianten** (Formatmasken, Holux-Sonderfälle): Die Fixtures decken nur die in der Vorlage beschriebenen ab. → Hardware-Test (Task 5.2).
- **`.bin` teilen sich drei Familien** (SkyTraq, MTK, Wintec): → Die Erkennung prüft Strukturen, nicht die Endung. Kreuztests mit allen Fixtures.
- **Verworfene Datensätze mit falscher Prüfsumme:** Echte Abbilder mit vielen Bitfehlern ergeben weniger Punkte als bei gpsbabel. → Die Warnung nennt die Anzahl.

## Migration Plan

Entfällt. Rückbau: beide Formate aus `GPLFileFormats.all` entfernen.
