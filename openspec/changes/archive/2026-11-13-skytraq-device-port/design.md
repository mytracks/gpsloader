# Design: SkyTraq direkt auslesen

## Context

- **Schnittstelle:** `DeviceConnection` und `DeviceProtocol` aus `device-mode`.
- **Decoder:** `SkyTraqDump` aus `skytraq-bin-port`.
- **Alt-App:** Sie las SkyTraq über gpsbabel (`skytraq`, `input/mytracks4mac/myTracks/Source/Resources/gpslogger.plist`, Zusatzargumente `initbaud`/`baud`).

## Goals / Non-Goals

**Goals:** Derselbe Ablauf wie gpsbabel 1.7.0, geprüft durch ein simuliertes Gerät, das auch gpsbabel selbst erfolgreich ausliest.

**Non-Goals:** die Konfigurationsoptionen der Vorlage.

## Decisions

### D1 Vorlage

- **Datei:** `skytraq.cc` (Archiv wie in `skytraq-bin-port`).
- **Übersetzt werden:**
  - die Konstanten (Zeilen 35–52);
  - `skytraq_calc_checksum`, `skytraq_rd_msg`, `skytraq_wr_msg`, `skytraq_expect_ack`, `skytraq_expect_msg`, `skytraq_wr_msg_verify`, `skytraq_system_restart` und `skytraq_set_baud` (279–494);
  - `skytraq_get_log_buffer_status` (533–578);
  - `skytraq_read_single_sector`, `skytraq_read_multiple_sectors` und `skytraq_read_tracks` (929–1196);
  - `skytraq_probe` (1198–1271), `skytraq_erase` (1273–1285) und `skytraq_read` (1335–1366).
- **Eigene Hilfen:** Die seriellen Hilfen der Vorlage (`rd_char`, `rd_buf`, `rd_word`, `wr_*`) ersetzt `DeviceConnection`.

### D2 Abweichungen

- **Dateneinheit:** Einzel-Lesen nutzt `readUntil` mit der Endmarke statt 16-Byte-Blöcken. Das Ergebnis ist dasselbe.
- **Zeitlimits:** Ein Zeitlimit beim Warten auf eine Bestätigung zählt als „keine Antwort“, damit der Treiber erneut senden bzw. die nächste Baudrate versuchen kann. In der Vorlage zählt `rd_char` Fehler und bricht nach fünf mit `fatal` ab.
- **Fehler:** `fatal` wird zum Protokollfehler mit Detailtext.
- **Namen:** Der Track heißt „SkyTraq“, im Speicherdialog schlägt die App den Gerätenamen vor.

### D3 Tests

- **Swift-Simulator** `SkyTraqSimulator`: Er antwortet nur auf der eingestellten Baudrate, wechselt sie bei `0x05`, liefert Status, Mehrfach- und Einzel-Sektoren und NACK auf Wunsch.
- **Black-Box mit Python-Simulator:** Derselbe Ablauf als Python-Simulator (Scratchpad) am Pseudo-Terminal.
  - Das gpsbabel-1.7.0-Binary liest ihn aus, mit `-i skytraq,baud=0`.
  - Die App liest ihn aus, mit `-DebugReadDevice skytraq.venus -DebugPort <pty>`.
  - Beide Ergebnisse werden verglichen.

## Risks / Trade-offs

- **Timing echter UARTs:** Baudwechsel und Pausen sind am Pseudo-Terminal nicht prüfbar. → Hardware-Test (Task 3.2).

## Migration Plan

Entfällt.
