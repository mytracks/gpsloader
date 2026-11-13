# Design: Alan Map500 Tracklogs

## Context

- Die Alt-App las `.trl`-Dateien über `gpsbabel -t -w -i alantrl` (Katalogeintrag „Alan Map500“ in `input/mytracks4mac/myTracks/Source/Resources/gpslogger.plist`, Formatliste in `input/mytracks4mac/DsTrackFramework/Source/Classes/GPSBabel/GPSBabel.m`, Zeile 26).
- Es gelten die Regeln des GPL-Pakets aus `gpl-driver-package`. Die Hilfen `ByteReader`, `Warnings`, `Cancellation` und `trackName(ofFile:)` liegen schon in `Support/ImportSupport.swift`.

## Goals / Non-Goals

**Goals:** Dieselben Tracks und Punkte wie gpsbabel 1.7.0 mit `-t -i alantrl`.

**Non-Goals:** Wegpunkte und Routen (`alanwpr`), Schreiben, iOS.

## Decisions

### D1 Vorlage

- **Projekt und Stand:** gpsbabel, Datei `alan.cc`, Tag `gpsbabel_1_7_0`.
- **Lizenz:** GPL-2.0-or-later (`alan.cc`, Zeilen 11–14). Copyright (C) 2007 Gunar Megger und (C) 2002–2014 Robert Lipe (Zeilen 8–9).
- **Übersetzt werden:**
  - die Strukturen `trkhdr`, `loghdr`, `trklog` und `trldata` (Zeilen 107–141);
  - die Kennung `TRL_HDR_ID` (145) und die Skalierungen (165–175);
  - `trl_read` (584–644).
- **Nicht übersetzt** wird der Byte-Tausch (206–243, 342–421). Die Datei ist Little Endian, `ByteReader` liest unabhängig von der Byte-Reihenfolge des Macs.

### D2 Datei-Layout

| Offset | Inhalt |
|---|---|
| 0x10000 · k (k = 0…3) | Tracklogs 2k und 2k+1, je 30 000 Byte: 2500 × (x, y) als Int32, dann 2500 × (Geschwindigkeit, Höhe) als Int16 |
| 0x40000 | Kopf: Kennung (UInt32), num, next (Int16), Datum, Zeit (Int32), dann 8 Track-Köpfe zu 44 Byte |

- **Track-Kopf:** `totalpt` (Int16) an 0, `next` an 2, Name (12 Zeichen) an 4, Kommentar (13) an 16, Reserve (3) an 29, `occupied`, `show` und `fill` (UInt32) an 32, 36 und 40.
- **Mindestgröße:** 0x40000 + 368 = 0x40170 Byte.

### D3 Abweichungen von der Vorlage

- **Punktzahl:** `totalpt` > 2500 liest die Vorlage über das Tracklog hinaus. Der Port begrenzt auf 2500 und warnt.
- **Negatives `totalpt`:** Es ergibt einen leeren Track, und leere Tracks entfallen. Die Vorlage legt einen leeren Track an.
- **Kommentar:** Das Modell kennt keine Track-Beschreibung. Der Kommentar entfällt, gpsbabel schreibt ihn als `<desc>`.
- **Dateiname:** Ein Track ohne Namen heißt wie die Datei (`trackName(ofFile:)`).

### D4 Erkennung

- **Grundlage:** Die Kennung steht erst bei 0x40000 und damit außerhalb der 4096 Byte, die `FormatCatalog.detect` liefert. `matches(prefix:)` prüft deshalb, ob die ersten 512 Koordinatenpaare plausibel sind (D2).
- **Reihenfolge:** Dateien mit Endung `.trl` prüft der Katalog zuerst gegen `alantrl`. Für andere Endungen steht das Format zuletzt in `GPLFileFormats.all`, damit es keine Formate mit eindeutiger Kennung verdrängt.
- **Kennung:** Eine falsch erkannte Datei scheitert beim Lesen an der Kennung (D2) mit einer klaren Meldung.

### D5 Concurrency

`AlanFileFormat` ist ein `Sendable`-Wertetyp ohne Zustand. Das Lesen läuft synchron in `read(_:)`. Bei 8 × 2500 Punkten ruft es je Track `Cancellation.tick()`.

### D6 Tests

- **Synthetische Dateien:** Ein Encoder `AlanTestFile` in den Tests erzeugt Dateien mit wählbaren Köpfen und Punkten. Er deckt die Szenarien der Spec `alan-import` ab.
- **Fixture `map500.trl`:** zwei Tracks, eine Position im Süden und eine im Westen, ohne echte Ortsdaten.
- **Black-Box:** gpsbabel 1.7.0 (`-t -i alantrl -f map500.trl -o gpx`) und der Port liefern gleiche Tracks, Punkte, Höhen und Geschwindigkeiten. Der Vergleich läuft über `GPSLOGGERKITGPL_COMPARE_DIR` wie bei den anderen Fixture-Tests. Das Ergebnis steht in `PROVENANCE.md`.

## Risks / Trade-offs

- **Erkennung am Inhalt:** Unbelegte Punktplätze im Gerät haben unbekannten Inhalt. Steht dort etwas Unplausibles, wird eine echte Datei nicht erkannt. → Der manuelle Test 3.2 prüft eine echte Datei. Notfalls bekommt GPSLoggerKit in einem eigenen Change eine allgemeine Erkennung über die ganze Datei.
- **Keine Zeitstempel:** GPX-Tracks ohne Zeiten sind gültig. Manche Programme sortieren sie aber anders. Das war bei gpsbabel genauso.

## Migration Plan

Entfällt.
