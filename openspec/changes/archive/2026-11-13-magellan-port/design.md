# Design: Magellan Meridian/SporTrak/eXplorist

## Context

- **Alt-App:** Sie las die Geräte mit `gpsbabel -t -w -i magellan -f /dev/cu.<gerät> -o gpx`. Dateien von der SD-Karte las sie mit `-i magellan` bzw. `-i magellanx`. Fundstellen: `input/mytracks4mac/myTracks/Source/Resources/gpslogger.plist`, die Formatliste in `input/mytracks4mac/DsTrackFramework/Source/Classes/GPSBabel/GPSBabel.m` (Zeilen 66–67) und `docs/legacy-analysis.md`, Abschnitt 3.1.
- **Grundlagen aus `device-mode`:** `DeviceProtocol`, `DeviceConnection` mit `readUntil` und `discardInput`, das Modul DeviceDrivers.
- **Hilfen aus `Support/ImportSupport.swift`:** `Warnings`, `Cancellation` und `trackName(ofFile:)`.

## Goals / Non-Goals

**Goals:**
- **Gerät:** dieselben Punkte und Wegpunkte wie gpsbabel 1.7.0 mit `-t -w -i magellan`.
- **Dateien:** dasselbe Ergebnis wie gpsbabel mit `-t -w -i magellan` bzw. `-i magellanx`.

**Non-Goals:** Schreiben, Löschen, Routen, Explorist-GPX (`usb:`), iOS.

## Decisions

### D1 Vorlagen

- **Projekt und Stand:** gpsbabel, Tag `gpsbabel_1_7_0`.
- **`magproto.cc`:** GPL-2.0-or-later (Zeilen 7–10), Copyright (C) 2002–2008, 2010 Robert Lipe (Zeilen 4–5). Übersetzt werden:
  - die Modelltabelle `pid_to_model` (Zeilen 214–236);
  - `mag_checksum` und `mag_pchecksum` (293–312), `mag_writemsg` ohne Quittungsweg (315–346) und `mag_handoff` (383–389);
  - `mag_verparse` (392–430) und `mag_readmsg` (435–575);
  - `terminit` und `termread` (580–616) sowie `mag_dequote` (630–659);
  - `mag_serial_init_common` (731–779) ohne `nukewpt` und `mag_rd_init_common` (781–832) ohne `usb:`;
  - `parse_istring` (946–964), `mag_trkparse` (972–1027), `mag_wptparse` (1199–1246) und `mag_read` (1249–1330) ohne Routen.
- **`magellan.h`:** GPL-2.0-or-later (Zeilen 4–7), Copyright (C) 2002–2005 Robert Lipe (Zeile 2). Übersetzt wird die Aufzählung `meridian_model`.
- **Gemeinsame Hilfen:** `ddmm2degrees` (`util.cc`, Zeilen 987–992) und die Semantik von `gbser_read_line` (`gbser_posix.cc`, Zeilen 448–480).
- **Nicht übersetzt:** Symboltabellen und Namenskürzung. Sie dienen nur dem Schreiben bzw. der Symbolbeschreibung, und das Modell hat kein Symbolfeld.

### D2 Aufteilung

- **`Magellan/MagellanSentences.swift`:**
  - Prüfsumme, Satzbau und Feldzerlegung (`parse_istring`);
  - `trackPoint(_:)`, `waypoint(_:)` und `dequote`.
  
  Gerät und Datei nutzen diese Teile gemeinsam.
- **`Magellan/MagellanDevice.swift`:** `MagellanDevice: DeviceProtocol` mit `MagellanLink` (Zeilen senden und lesen).
- **`Magellan/MagellanFileFormat.swift`:** `MagellanFileFormat: FileFormat`, ID `magellan`, Endungen `log`, `upt` und `rte`.

### D3 Ablauf am Gerät

1. Baudrate 4800 (Vorgabe `baud=4800`, Zeile 702). `HANDOFF` senden, ohne auf eine Quittung zu warten: Beim Lesen setzt die Vorlage `suppress_ack` (Zeile 838), damit bleibt `magrxstate` auf `mrs_handoff`.
2. `discardInput()`, dann `VERSION` senden. Zeilen lesen, bis `$PMGNVER` kommt, höchstens 6 Sekunden.
   - Bei unbekannter Produktnummer endet der Vorgang mit einem Fehler.
   - Bei falscher Prüfsumme davor endet er mit „Bitrate prüfen“.
3. Kein Modell der 315-Familie: `NMEAOFF` senden. `$PMGNCMD,UNABLE` wird hier ignoriert (`ignore_unable`).
4. `discardInput()`, damit eine späte Antwort auf `NMEAOFF` den Track nicht beendet. Dann `TRACK,2` senden und lesen bis `END`. Kommt `UNABLE`, meldet der Treiber das als Schritt (`DeviceReporter.step`), denn Geräteprotokolle haben keinen Warnungskanal.
5. `WAYPOINT` senden und lesen bis `END`, ebenso mit Schrittmeldung bei `UNABLE`.
6. `HANDOFF` senden. Das geschieht auch nach einem Fehler, mit `try?` in einem `defer`-ähnlichen Abschluss.

### D4 Abweichungen von der Vorlage

- **Zeilen ohne `$`:** Die Vorlage bricht ab (Zeile 466). Am Gerät kommen solche Zeilen vor allem am Anfang vor, als Rest eines NMEA-Satzes. Der Port überspringt sie, in Dateien mit Warnung.
- **Leere Zeilen** in Dateien werden ohne Warnung übersprungen.
- **Track-Name am Gerät:** Die Vorlage benennt den Track nach dem Portnamen bis zum ersten Punkt, also „cu“. Der Port nennt ihn „Magellan“.
- **Track-Name in Dateien:** Der Port nimmt `trackName(ofFile:)`, das nur die letzte Endung entfernt. Die Vorlage schneidet am ersten Punkt.
- **Satzzeit:** Die Vorlage rechnet die Hundertstel mit `10.0 * fracsecs` in Millisekunden um und nimmt damit genau zwei Nachkommastellen an. Der Port übernimmt das.
- **`END` in Dateien:** Die Vorlage liest danach im Wegpunkt-Durchgang weiter. Der Port beendet die Datei dort.

### D5 Erkennung und Wegpunkte in Dateien

- **Erkennung:** `matches(prefix:)` sucht in den ersten 4096 Byte einen `$PMGNTRK`-, `$PMGNWPL`- oder `$PMGNRTE`-Satz mit gültiger Prüfsumme. Das NMEA-Format ignoriert `$P…`-Sätze, daher gibt es keine Konkurrenz.
- **Wegpunkte:** Sie entstehen nur in `.upt`-Dateien. So wirkt der `extension_hint` (Zeilen 822–830) bei `-t -w`. In `.log`- und `.rte`-Dateien entfallen Wegpunktsätze. `$PMGNRTE` wird immer ignoriert.

### D6 Concurrency

- **Typen:** `MagellanDevice` und `MagellanFileFormat` sind `Sendable`-Wertetypen ohne Zustand.
- **Zeitlimits:** Jede Zeile kommt über `readUntil([0x0A], maxLength: 512, timeout: 2 s)`. Für die Versionsabfrage gilt zusätzlich die Frist von 6 Sekunden.
- **Abbruch:** Er wirkt über `connection.read` (`CancellationError`).
- **Fortschritt:** `reporter.activity()` je Satz, weil die Anzahl vorab unbekannt ist.

### D7 Tests

- **Swift-Simulator `MagellanSimulator`** über `SimulatedDevice`:
  - Version mit wählbarer Produktnummer;
  - NMEA-Rauschen am Anfang;
  - Track- und Wegpunktsätze, auf Wunsch `UNABLE`, falsche Prüfsumme oder Stille.
  
  Er deckt die Szenarien der Spec `magellan-device` ab.
- **Synthetische Dateien:** ein Encoder `MagellanTestFile` und die Fixtures `track01.log` und `poi.upt`, ohne echte Ortsdaten. Sie decken die Szenarien der Spec `magellan-import` ab.
- **Black-Box:**
  - gpsbabel 1.7.0 und der Port lesen dieselben Fixtures (`-t -w -i magellan`, zusätzlich `-i magellanx`). Der Vergleich läuft über `GPSLOGGERKITGPL_COMPARE_DIR`.
  - Ein Python-Simulator auf einem pty liefert dasselbe für gpsbabel (`-t -w -i magellan -f <pty>`) und die App (`-DebugReadDevice magellan.meridian`).
  - Die Ergebnisse stehen in `PROVENANCE.md`.

## Risks / Trade-offs

- **Ohne Quittungen:** Das Lesen ohne Quittungen übernimmt der Port von der Vorlage. Ob alle Firmware-Stände das mitmachen, ist ohne Gerät nicht prüfbar. → Hardware-Test 3.2. Bei Bedarf folgt der Quittungsweg (`mag_writeack`) in einem eigenen Change.
- **Explorist-Dateien:** Explorist-Dateien können Felder mit mehr als 8 Zeichen haben. Das Lesen ist davon nicht betroffen.

## Migration Plan

Entfällt.
