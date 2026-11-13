# Design: Locosys-Dateien (Portierung)

## Context

- **Vorhandene Bausteine:** GPSLoggerKitGPL hat aus den früheren Portierungen (`skytraq-bin-port`, `mtk-bin-port`, `wintec-file-port`) die gemeinsamen Hilfen und Namensregeln.
- **Byte-Reihenfolge:** SBP ist Little Endian, SBN Big Endian (SiRF-Binärprotokoll).
- **Alt-App:** Sie las beide Formate über gpsbabel (`sbp`, `sbn`; `input/mytracks4mac/myTracks/Source/Resources/gpslogger.plist`). gpsbabel ab 1.8 kennt sie nicht mehr.

## Goals / Non-Goals

**Goals:** Für dieselben Dateien liefern beide Formate dieselben Punkte wie gpsbabel 1.7.0, bis auf D4.

**Non-Goals:** das Navilink-Protokoll (serielles Auslesen, Wegpunkte, Routen) und die Satellitenliste (Typ 13).

## Decisions

### D1 Vorlagen und Lizenz

- **Archiv:** gpsbabel `gpsbabel_1_7_0`, wie in `skytraq-bin-port`.
- **`sbp.cc`:**
  - Zeilen 4–5: Copyright (C) 2008 Rodney Lorrimar und (C) 2005 Robert Lipe. Zeilen 7–10: GPL-2.0-or-later.
  - Übersetzt werden `read_sbp_header` (Zeilen 50–82), `read_logpoint` (84–94) und `sbp_read` (96–108).
- **`navilink.cc`:**
  - Zeilen 4–5: Copyright (C) 2007 Tom Hughes und (C) 2008 Rodney Lorrimar. Zeilen 7–10: GPL-2.0-or-later.
  - Übersetzt werden `navilink_checksum_packet` (209–220), `decode_sbp_msec`, `decode_sbp_datetime_packed`, `decode_sbp_position` und `navilink_decode_logpoint` (768–829).
  - Dazu kommt `SBP_RECORD_LEN` aus `navilink.h` (Zeile 29; Copyright Rodney Lorrimar und Robert Lipe, GPL-2.0-or-later).
- **`sbn.cc`:**
  - Zeilen 4–5 wie `sbp.cc`, Zeilen 7–10 GPL-2.0-or-later.
  - Übersetzt werden die Konstanten (45–55), `read_packet` (62–118), `read_sbn_header` (169–182) und `is_sbn_valid`, `decode_sbn_mode`, `decode_sbn_datetime`, `decode_sbn_position`, `decode_sbn_record` und `add_logpoints` (184–271).
  - Nicht übersetzt wird die abgeschaltete Auswertung der Geräteinformation (`LOCOSYS_PARSE_FILE_ID`).

### D2 Struktur

- **Datei:** `Sources/GPSLoggerKitGPL/Locosys/LocosysFileFormats.swift` mit `SBPFileFormat` (`sbp`) und `SBNFileFormat` (`sbn`).
- **Gemeinsam:** die Navilink-Prüfsumme (Summe & 0x7FFF).
- **Byte-Leser:** `ByteReader` bekommt `u32be`, das schon vorhanden ist, und `i32be`/`i16be`, die als vorzeichenbehaftete Varianten über `bitPattern` entstehen.

### D3 Leser

- **SBP:**
  - Kopf mit 64 Byte, danach Datensätze zu 32 Byte. Die Felder stehen in der Spec.
  - Bei der gepackten Zeit bezeichnet ein Monatsrest 0 den Dezember des Vorjahrs. In der Vorlage ergibt sich das aus `tm_mon = -1` und der Normalisierung durch `mkgmtime`.
  - Unmögliche Felder ergeben `malformedRecord` ohne Punkt (D4).
  - Es entsteht ein Track pro Datei.
- **SBN:**
  - Die Pakete werden in Dateireihenfolge gelesen.
  - Das erste Paket muss vom Typ 253 sein, mit höchstens 41 Byte Nutzdaten.
  - Danach gilt je Paket:
    - Typ 41 mit höchstens 97 Byte ergibt einen Punkt.
    - Typ 13 wird übergangen.
    - Andere Typen werden übergangen, wie die Vorlage mit ihrer Warnung, aber ohne Meldung (D4).
  - Die Zeit setzt sich aus Jahr, Monat, Tag, Stunde und Minute sowie Millisekunden der Minute zusammen. Die Sekunde ist `ms / 1000`.
- **Abbruch:** `Cancellation` je Datensatz bzw. Paket.

### D4 Abweichungen von der Vorlage (bewusst)

- **SBN, Prüfsumme:** Bei falscher Prüfsumme bricht die Vorlage mit `fatal` ab. Hier wird das Paket verworfen und als `checksumMismatch` gezählt, weil seine Länge bekannt ist.
- **SBN, Rahmen:** Bei fehlerhaftem Paketanfang, Paketende oder zu großer Länge bricht die Vorlage ebenfalls mit `fatal` ab. Hier endet das Lesen mit `truncatedFile`, die Punkte bis dahin bleiben erhalten.
- **SBN, unbekannte Pakettypen:** Die Vorlage gibt eine Warnung aus. Hier werden sie ohne Warnung übergangen. Das Datenmodell kennt keine Meldung dafür, und für die Konvertierung sind sie belanglos.
- **SBP, unmögliche Zeitfelder:** Die Vorlage normalisiert sie. Hier wird der Datensatz verworfen und gezählt.
- **SBP, letzter Datensatz:** Ist er unvollständig, übergeht ihn die Vorlage still. Hier entsteht eine Warnung.
- **Tracknamen:** Der Track heißt nach der Datei.

### D5 Erkennung

- **`sbn`:**
  - Byte 0–1 `A0 A2`, Länge 1–41 und Byte 4 = 253.
  - Prüfsumme und `B0 B3` stimmen.
- **`sbp`:**
  - Kopf und erster Datensatz müssen im Prefix liegen (≥ 96 Byte).
  - Byte 6 ist `0xFD`, oder ab Byte 7 stehen bis zum ersten `0xFF` bzw. `0x00` nur druckbare ASCII-Zeichen mit mindestens einem Komma.
  - Der erste Datensatz hat eine gültige Zeit (Jahr ≥ 2004), |Breite| ≤ 90° und |Länge| ≤ 180°.
  - Der Aufbau des Kopfs (Länge, dann ein SiRF-Paket `MID_FILE_ID`) folgt aus dem Kommentar in `sbp.cc`, Zeilen 53–60, und dem Wert `HEADER_SKIP` = 7. Das Format der Geräteinformation steht in `sbn.cc`, Zeilen 140–148.
- **Kreuztests** mit allen Fixtures der anderen Portierungen.

### D6 Concurrency

Wie bei den übrigen Portierungen.

### D7 Tests und Gegenprüfung

- **Test-Encoder:** `LocosysTestFile` schreibt SBP-Köpfe und -Datensätze sowie SBN-Pakete mit Prüfsumme.
- **Fixtures:** `gt31.sbp` und `gt31.sbn`, mit erfundenen Koordinaten um 50° N, 8° O.
- **Black-Box:** `gpsbabel -i sbp` bzw. `-i sbn`, `-o gpx`. Das Ergebnis kommt nach `PROVENANCE.md`.

## Risks / Trade-offs

- **Erkennung von SBP:** Der Kopf echter Dateien ist nur aus den Kommentaren der Vorlage bekannt. → Zwei alternative Merkmale und der Hardware-Test (Task 5.2). Erkennt die App eine echte SBP-Datei nicht, folgt ein Bugfix-Change.

## Migration Plan

Entfällt.
