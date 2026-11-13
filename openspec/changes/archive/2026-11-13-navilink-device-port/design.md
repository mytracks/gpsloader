# Design: Navilink direkt auslesen

## Context

Es gelten die Grundlagen aus `device-mode`. Die Hilfen `Locosys.utc` und `i32le` liefert `locosys-file-port`.

## Goals / Non-Goals

**Goals:** Derselbe Leseablauf wie gpsbabel 1.7.0 mit `-w -t`.

**Non-Goals:** Schreiben, Löschen und Routen.

## Decisions

### D1 Vorlage

- **Datei:** `navilink.cc`.
- **Übersetzt werden:**
  - die Konstanten (Zeilen 56–89);
  - `write_packet`, `read_word` und `read_packet` (243–345);
  - `decode_datetime`, `decode_position`, `decode_waypoint` und `decode_trackpoint` (346–443);
  - `serial_read_waypoints` (466–518) ohne Routen-IDs;
  - `serial_read_track` (541–582) und die Initialisierung aus `navilink_common_init` (1054–1072).

### D2 Abweichungen

- **Geräteinformation:** Die Vorlage fragt sie für Wegpunkte und Track getrennt ab, hier geschieht das einmal.
- **Namen:** Der Track heißt „NaviGPS“.

### D3 Tests

- **Swift-Simulator** `NavilinkSimulator`: Wegpunkte, Trackpunkte, Quittungen, Prüfsummenfehler auf Wunsch.
- **Black-Box mit Python-Simulator:** gpsbabel (`-i navilink`) und die App (`-DebugReadDevice navilink.locosys-gt-31`) lesen dieselben 40 Wegpunkte und 600 Trackpunkte mit gleichen Werten.

## Risks / Trade-offs

- **NAVILINK-Modus:** Das Gerät muss am Gerät in den NAVILINK-Modus geschaltet sein. → Die Fehlermeldung sagt das.

## Migration Plan

Entfällt.
