# Design: MTK direkt auslesen

## Context

Es gelten die Grundlagen aus `device-mode`. Den Decoder `MTKDump` liefert `mtk-bin-port`. Die Alt-App las MTK-Logger über gpsbabel (`mtk`, `m241`).

## Goals / Non-Goals

**Goals:** Derselbe Ablauf wie gpsbabel 1.7.0.

**Non-Goals:** CSV-Ausgabe, Zwischenspeicher und Optionen.

## Decisions

### D1 Vorlage

- **Datei:** `mtk_logger.cc`.
- **Übersetzt werden:**
  - die Befehlskonstanten (Zeilen 247–251);
  - `do_send_cmd` und `do_cmd` (315–424), `mtk_rd_init` (426–480) und `mtk_rd_deinit` (482–495);
  - `mtk_erase` (497–532);
  - `mtk_read` (534–802) ohne Zwischenspeicher und CSV.

### D2 Abweichungen

- **Quittungen:** Die Vorlage liest das Ergebnis einer `$PMTK001`-Quittung an der Stelle des Unterbefehls. Dadurch wertet sie z. B. `$PMTK001,182,2,3` als Fehler, und der Logstatus geht verloren. Übernommen wird die erkennbare Absicht: Das Ergebnisfeld 0 bis 2 bedeutet Ablehnung. Folge: gpsloader schaltet das Logging nach dem Auslesen wieder ein, wenn es eingeschaltet war. gpsbabel tut das in diesem Fall nicht.
- **Alte Antworten:** Vor jeder Leseanfrage verwirft der Treiber den Eingang. Antwortzeilen mit Adressen außerhalb des angeforderten Blocks übergeht er. Die Vorlage schreibt sie ins Leere und bricht die Blockschleife ab.
- **Dateiende:** Das Abbild wird mit dem Decoder aus `mtk-bin-port` gelesen. Er liest auch die letzten Datensätze, die gpsbabel wegen seines Puffers mit der Länge des größtmöglichen Datensatzes verliert (dort D4).
- **Fehler:** `fatal` wird zum Protokollfehler.

### D3 Tests

- **Swift-Simulator** `MTKSimulator`: NMEA-Rauschen, Quittungen, ganze Blöcke in einer Antwortzeile (die Vorlage dimensioniert ihren Zeilenpuffer mit `2 * Blockgröße + 32`), Ablehnung auf Wunsch, GR-245.
- **Black-Box mit Python-Simulator am Pseudo-Terminal:**
  - gpsbabel liest ihn mit `-i mtk` bzw. `-i m241`, die App mit `-DebugReadDevice`.
  - Für das Holux-Abbild sind Befehlsfolge (bis auf das Wiedereinschalten) und Ergebnis gleich.

## Risks / Trade-offs

- **Antworten echter Geräte:** Größe und Aufteilung der Antwortzeilen sind nur aus der Vorlage erschlossen. → Hardware-Test (Task 3.2).

## Migration Plan

Entfällt.
