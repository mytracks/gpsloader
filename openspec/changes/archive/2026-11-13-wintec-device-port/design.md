# Design: Wintec direkt auslesen

## Context

Es gelten die Grundlagen aus `device-mode`. Die Decoder für BIN- und TK1-Datensätze liefert `wintec-file-port`.

## Goals / Non-Goals

**Goals:** Derselbe Ablauf wie gpsbabel 1.7.0.

**Non-Goals:** keine weiteren.

## Decisions

### D1 Vorlage

- **Datei:** `wbt-200.cc`.
- **Übersetzt werden:**
  - `rd_drain` bis `guess_device` (Zeilen 266–388) und `do_cmd`, `do_simple` und `get_param*` (450–500);
  - `wbt200_data_read` (697–778);
  - `wbt201_read_chunk` und `wbt201_data_read` (852–977) sowie `data_read` (1036–1054).
- **Puffer:** Der Puffer `buf_*` entfällt. Die Prüfsumme eines Stücks ist das XOR seiner Bytes, wie bei `buf_update_checksum`.

### D2 Abweichungen

- **Eingang:** Vor jedem Befehl wird der Eingang verworfen. Die Vorlage tut das in `do_cmd` und beim Stücklesen ebenfalls.
- **Löschen:** Es ist ein eigener Vorgang, nicht ein Anhängsel des Lesens. Dafür wird der Gerätetyp erneut bestimmt.
- **Namen:** Tracks heißen nach dem Gerät, mehrere Tracks tragen eine Nummer, Wegpunkte heißen `POI n`, wie bei den Dateiformaten.

### D3 Tests

- **Swift-Simulator** `WintecSimulator`: alle drei Gerätetypen, NMEA-Rauschen, eine falsche Prüfsumme auf Wunsch und ein Ringpuffer.
- **Black-Box mit Python-Simulator:** gpsbabel (`-i wbt`) und die App (`-DebugReadDevice wbt.wintec-wbt-201`) lesen ihn. Befehlsfolge und Ergebnis sind gleich: 300 Punkte in zwei Tracks, ein Wegpunkt. Für WBT-200 liest gpsbabel 5 Punkte, wie die Swift-Tests.

## Risks / Trade-offs

- **Zeitverhalten bei 57600 Baud** und die Erkennung bei echten Geräten. → Hardware-Test (Task 3.2).

## Migration Plan

Entfällt.
