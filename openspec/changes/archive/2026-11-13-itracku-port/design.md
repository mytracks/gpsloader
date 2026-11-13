# Design: XAiOX iTrackU direkt auslesen

## Context

- Die Alt-App rief für „XAiOX iTrackU - gpsbabel“ `gpsbabel -t -w -i itracku -f /dev/cu.<gerät> -o gpx` auf (`input/mytracks4mac/myTracks/Source/Resources/gpslogger.plist`, `input/mytracks4mac/DsTrackFramework/Source/Classes/GPSBabel/GPSBabel.m`, siehe `docs/legacy-analysis.md`, Abschnitt 3.1).
- Es gelten die Grundlagen aus `device-mode`: `DeviceProtocol`, `DeviceConnection` (mit `write`, `read(count:timeout:)`, `readUntil`, `discardInput`) und das Modul DeviceDrivers.
- Das Gerät ist ein Bluetooth-GPS mit Logger. Unter macOS erscheint es nach dem Koppeln als `/dev/cu.*`, über USB als serieller Port.

## Goals / Non-Goals

**Goals:** Dieselben Punkte wie gpsbabel 1.7.0 mit `-t -i itracku`.

**Non-Goals:** Löschen, Echtzeit-Positionen, `itracku-bin`, inkrementelles Auslesen.

## Decisions

### D1 Vorlage

- **Projekt und Stand:** gpsbabel, Datei `itracku.cc`, Tag `gpsbabel_1_7_0`.
- **Lizenz:** GPL-2.0-or-later (`itracku.cc`, Zeilen 5–8). Copyright (C) 2008 Andreas Grimme und (C) 2005 Robert Lipe (Zeilen 2–3).
- **Übersetzt werden:**
  - der Datensatz `itracku_data_record` (Zeilen 56–63), der Lesebefehl und die Endemarke (76–79);
  - `itracku_device_write_string` und `itracku_device_read_string` (125–140);
  - `itracku_device_update_data_read` (154–183);
  - `deg_min_to_deg`, `decode_itracku_time` und `to_waypoint` (215–235, 269–282, 304–314);
  - `init_device` (335–355), `itracku_is_valid_data_record` (514–517) und `itracku_device_dump_waypts` (520–536).
- **Gemeinsame Hilfen:** Gelesen werden nur die Semantik von `gbser_read_line` und `gbser_read_wait` (`gbser_posix.cc`, `gbser.cc`) und die Standard-Baudrate 4800 aus `gbser_init` (`gbser_posix.cc`, Zeile 155).

### D2 Ablauf

1. **Erkennung:** Baudrate 4800. `WP AP-Exit\0` senden, `discardInput()`, `W'P Camera Detect\0` senden. Dann bis zum Nullbyte lesen (`readUntil([0x00], timeout: 1 s)`). Die Antwort muss auf `WP GPS+BT` enden: NMEA-Reste davor werden hingenommen, die Vorlage verlangt genau diese Zeile. Eine Zeitüberschreitung oder eine andere Antwort ergibt `DeviceProtocolError` („No iTrackU found“); der Adapter meldet ihn als Protokollfehler.
2. **Speicher:** `60 B5 00 00 00 00 00` senden. Dann mit `readUntil("WP Update Over", maxLength: 64 MiB, timeout: 1 s)` lesen; das Zeitlimit gilt für Stille, nicht für die Gesamtdauer.
   - Das Byte nach der Marke (die Vorlage erwartet 15 Byte samt Nullbyte) wird mit kurzem Zeitlimit gelesen, sein Fehlen ist kein Fehler.
   - Alle vollständigen 16-Byte-Datensätze vor der Marke werden ausgewertet.
3. **Ergebnis:** ein Track „iTrackU“ mit einem Segment. Ohne gültige Datensätze gibt es ein leeres Ergebnis, das die Sitzung als „keine Daten“ meldet.

### D3 Abweichungen von der Vorlage

- **Wegpunkte statt Track:** gpsbabel setzt bei `-t -w` als Ziel das zuletzt genannte (`main.cc`, Zeilen 378–384), also Wegpunkte. Ein Logger-Track ist aber das, was Anwender erwarten. Der Port liefert daher einen Track, wie gpsbabel mit `-t`.
- **Letzter Block:** Die Vorlage prüft die Endemarke nach jedem Lesen und verwirft dabei die Datensätze, die im selben Block wie die Marke ankamen. Der Port wertet sie aus. Die Black-Box-Prüfung (D5) belegt den Unterschied.
- **Kein Datenstrom:** Kommen keine Daten, ruft sich die Vorlage ohne Ende rekursiv auf. Der Port bricht nach 1 Sekunde Stille mit einer Zeitüberschreitung ab.
- **Höhe:** Die Vorlage liest die Höhe vorzeichenlos (`le_read16`). Der Port übernimmt das.

### D4 Concurrency

- **`ITrackUDevice`:** ein `Sendable`-Wertetyp ohne Zustand.
- **Lesen:** Es läuft in `read(_:_:)` über `connection.readUntil` mit Stille-Zeitlimit; dort wirkt auch der Abbruch der Sitzung (`CancellationError`).
- **Fortschritt:** unbestimmt mit Schrittmeldung, weil die Speichergröße vorab unbekannt ist. Die Verbindung meldet ankommende Daten selbst als Aktivität.

### D5 Tests

- **Swift-Simulator `ITrackUSimulator`** über `SimulatedDevice`:
  - Antwort auf die Erkennung;
  - Speicher mit wählbaren Datensätzen;
  - Endemarke im letzten Block;
  - auf Wunsch Stille statt Marke.
  
  Er deckt die Szenarien der Spec `itracku-device` ab.
- **Black-Box mit Python-Simulator auf einem pty**, wie bei den anderen Geräten:
  - gpsbabel 1.7.0 (`-t -i itracku`) und die App (`-DebugReadDevice itracku.xaiox-itracku`) lesen denselben Speicher.
  - Gleich sein müssen die Punkte, bis auf die Datensätze im letzten Block (D3).
  - Das Ergebnis steht in `PROVENANCE.md`.

## Risks / Trade-offs

- **Keine Hardware:** Der Entwickler hat kein iTrackU, und es ist ein Bluetooth-Gerät. → Den Test übernimmt ein Anwender (Task 2.2). Der Diagnose-Mitschnitt hilft bei Fehlern.
- **Baudrate:** gpsbabel arbeitet mit 4800 Baud. Die iTU4l-Einträge der Alt-App nutzten 115200 Baud. Über Bluetooth spielt die Baudrate keine Rolle, über USB ist sie unbelegt. → Der Port folgt der Vorlage. Meldet ein Anwender Probleme, wird nachgebessert.

## Migration Plan

Entfällt.
