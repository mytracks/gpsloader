# Design: Wintec-Dateien (Portierung)

## Context

- **Vorhandene Bausteine:** Seit `skytraq-bin-port` und `mtk-bin-port` hat GPSLoggerKitGPL die gemeinsamen Hilfen `Warnings`, `Cancellation`, `ByteReader` (mit Little-Endian-Werten), `trackName` und `L10n`. Dazu kommen die Tracknamen-Regel mit Nummer in Klammern und die Wegpunktnamen `POI n`.
- **Alt-App:** Sie las Wintec-Dateien über gpsbabel (`wintec_tes` für den WBT-202, `wbt` für die seriellen Geräte; `input/mytracks4mac/myTracks/Source/Resources/gpslogger.plist`). gpsbabel ab 1.8 hat diese Formate entfernt (`docs/legacy-analysis.md`, Abschnitt 3).

## Goals / Non-Goals

**Goals:** Für dieselben Dateien liefern alle drei Formate dieselben Punkte wie gpsbabel 1.7.0, bis auf D4.

**Non-Goals:** serielles Auslesen (WBT-100/200/201, WSG-1000) und Löschen.

## Decisions

### D1 Vorlagen und Lizenz

- **Archiv:** gpsbabel `gpsbabel_1_7_0`, wie in `skytraq-bin-port`.
- **`wintec_tes.cc`:**
  - Zeile 5: „Copyright (C) 2010 Robert Lipe“. Zeilen 7–10: GPL-2.0-or-later.
  - Übersetzt werden `wintec_date_to_time` (Zeilen 40–53) und `wintec_tes_read` (55–90).
- **`wbt-200.cc`:**
  - Zeile 4: „Copyright (C) 2006 Andy Armstrong“. Zeilen 6–9: GPL-2.0-or-later.
  - Übersetzt werden:
    - die Konstanten (37–46) und Merkmale (59–63);
    - `_SPLIT_DATE`, `decode_date` und `check_date` (502–535);
    - `wbt200_data_chunk` (563–605) und `is_valid` (608–642);
    - `all_null` und `wbt201_data_chunk` (780–838);
    - `file_read` (979–1034).
  - Nicht übersetzt werden der serielle Teil und der Puffer `buf_*`; der Puffer entfällt, weil `ByteReader` die ganze Datei hat.

### D2 Struktur

`Sources/GPSLoggerKitGPL/Wintec/`:
- `WintecFileFormats.swift` (eine Datei, weil die Teile klein sind):
  - `WintecTime`: der Zeitstempel und seine Prüfung, gemeinsam für alle drei Formate.
  - `WintecTESFileFormat`: `wintec-tes`, Endung `tes`.
  - `WintecBinFileFormat` und `WintecTK1FileFormat`: `wbt-bin` (Endung `bin`) und `wbt-tk1` (Endung `tk1`).
  - Beide nutzen einen Leser `WintecLog`, wie die Vorlage mit ihrem gemeinsamen `file_read`.
  - Liest man eine TK1-Datei mit `wbt-bin` oder umgekehrt, entscheidet der Kopf, wie in der Vorlage.

### D3 Leser

- **TES:** Datensätze zu 16 Byte bis zum Dateiende. Ein Rest unter 16 Byte ergibt `truncatedFile`. Es entsteht ein Track pro Datei, mit dem Merkmal `0x02` zusätzlich ein Wegpunkt.
- **BIN:**
  - Die Datensatzlänge wird zuerst mit 12, dann mit 16 Byte geprüft. Voraussetzung sind Dateigröße modulo Länge = 0 und alle Zeitstempel gültig (`check_date`).
  - Ab einem Betrag der Breite von 100 beginnt ein neuer Track.
  - Die Höhe (nur bei 16 Byte) ist ein `Int32` in Dezimetern.
- **TK1:**
  - Der Kopf besteht aus den 15 Zeichen `WintecLogFormat` und einem Nullbyte. Die Daten beginnen bei `0x400`, in Datensätzen zu 16 Byte.
  - Datensätze aus lauter Nullen werden übersprungen. Der Zeitstempel `0x04000000` beendet die Datei.
  - Merkmal `0x01` beginnt einen neuen Track, Merkmal `0x02` ergibt einen Wegpunkt.
- **Zeit:** UTC aus den Bitfeldern. Ungültige Felder ergeben bei TES und TK1 `malformedRecord` ohne Punkt (D4). Bei BIN schließt die Längenprüfung sie aus.
- **Abbruch:** `Cancellation` je Datensatz.

### D4 Abweichungen von der Vorlage (bewusst)

- **Ungültige Zeitstempel bei TES und TK1:**
  - Die Vorlage lässt `mkgmtime` beliebige Werte normalisieren, etwa den Monat 0 als Dezember des Vorjahrs.
  - Hier wird ein solcher Datensatz verworfen und gezählt.
  - Bei den Testdaten aus der Vorlage kommt das nicht vor.
- **Unvollständiger letzter TES-Datensatz:** Die Vorlage liest bis `gbfeof` und erzeugt aus einem unvollständigen letzten Datensatz einen Punkt aus Restbytes. Hier entsteht eine Warnung.
- **Unbekannte BIN-Länge:** Passt keine Datensatzlänge, bricht die Vorlage mit `fatal` ab. Hier entsteht der Fehler `.malformed` für die Datei.
- **Namen:**
  - Tracks heißen nach der Datei statt unbenannt, wie bei den übrigen Formaten.
  - Wegpunkte heißen `POI n` statt `WP0001` (BIN, TK1) bzw. unbenannt (TES).

### D5 Erkennung

- **`wbt-tk1`:** die 16 Bytes des Kopfs.
- **`wbt-bin`:**
  - Ohne TK1-Kopf gilt: Für 12 oder 16 Byte sind alle vollständigen Datensätze des Prefix gültig, mit Zeitstempel nach `check_date`, |Länge| ≤ 180° und |Breite| < 190°. Dazu muss es mindestens zwei Datensätze geben.
  - Das Prefix sagt nichts über die Dateigröße. Die Teilbarkeit prüft erst `read`.
- **`wintec-tes`:** TES-Dateien haben keinen Kopf; der Formatvertrag `matches(prefix:)` kennt den Dateinamen nicht. Erkannt wird deshalb am Inhalt: mindestens zwei Datensätze zu 16 Byte, deren Merkmale höchstens `0x0007` sind (die Vorlage nennt nur die Bits 0–2), mit gültigem Zeitstempel, |Breite| ≤ 90° und |Länge| ≤ 180°. Weil bei BIN-Dateien das erste Feld der Zeitstempel ist, schließt die Merkmalsprüfung sie praktisch aus; die Endung `.tes` lässt `FormatCatalog.detect` das Format zuerst prüfen.
- **Kreuztests:** Die Fixtures von SkyTraq, MTK und Holux lösen keines der Wintec-Formate aus und umgekehrt.

### D6 Concurrency

Wie bei den übrigen Portierungen: zustandslose `Sendable`-Formate, lokale Leser, Abbruch über `Cancellation`.

### D7 Tests und Gegenprüfung

- **Test-Encoder:** `WintecTestFile` schreibt TES-, BIN- (12 und 16 Byte) und TK1-Dateien.
- **Fixtures:** `wbt202.tes`, `wbt200.bin` und `wbt201.tk1`, mit erfundenen Koordinaten um 50° N, 8° O.
- **Black-Box:** `gpsbabel -i wintec_tes`, `-i wbt-bin` und `-i wbt-tk1`, jeweils `-o gpx`. Das Ergebnis kommt nach `PROVENANCE.md`.

## Risks / Trade-offs

- **Schwache Erkennung von TES** (kein Kopf): Ein fremdes Binärformat könnte zufällig passen. → Die Prüfung verlangt mehrere plausible Datensätze; Kreuztests mit allen Fixtures.
- **Einheit der TES-Höhe:** Die Vorlage nennt sie unklar, Zeilen 72–74. → Sie wird wie in der Vorlage als Meter übernommen. Der Hardware-Test (Task 5.2) prüft das.

## Migration Plan

Entfällt.
