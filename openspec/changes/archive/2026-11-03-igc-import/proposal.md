# Proposal: IGC-Import in GPSLoggerKit

## Why

IGC ist das Standardformat für Flugaufzeichnungen im Segel-, Gleitschirm- und Drachenflug. Die Alt-App las es nur über gpsbabel, also nur auf dem Mac und mit Rosetta. Die FAI veröffentlicht eine vollständige Spezifikation des Formats, deshalb lässt es sich sauber und ohne Hardware nativ umsetzen. Es ist der erste Change der umgestellten Reihenfolge (Familien mit öffentlicher Spezifikation zuerst).

## What Changes

- Neues Dateiformat `igc` in GPSLoggerKit (macOS und iOS):
  - Liest die B-Records (Positionsfixe) mit UTC-Zeit, Breite, Länge, Fix-Gültigkeit, Druckhöhe und GNSS-Höhe.
  - Das Datum kommt aus dem H-Record `HFDTE`, in der alten Form `HFDTEddmmyy` und in der neuen Form `HFDTEDATE:ddmmyy,nn`. Über Mitternacht hinweg wird das Datum weitergezählt.
  - Erweiterungen der B-Records werden über den I-Record gefunden. Ausgewertet wird `SIU` (Satelliten in Gebrauch); die übrigen werden übersprungen.
  - Höhe: GNSS-Höhe, wenn der Fix gültig ist und sie nicht 0 ist, sonst die Druckhöhe, wenn diese nicht 0 ist, sonst keine Höhe.
  - Jede Datei ergibt einen eigenen Track; mehrere Dateien ergeben mehrere Tracks.
  - Erkennung am Inhalt (erste Zeile ist ein A-Record, dazu ein H- oder B-Record) und an der Endung `.igc`.
  - Unbrauchbare B-Records werden übersprungen und als Warnung gezählt.
- Der Formatkatalog enthält zusätzlich IGC.
- `PROVENANCE.md` nennt die FAI-Spezifikation als Quelle.

## Capabilities

### New Capabilities

- `igc-import`: IGC-Dateien einlesen und daraus Tracks bilden.

### Modified Capabilities

- `logger-kit`: Der Formatkatalog enthält zusätzlich IGC (Kennung `igc`).

## Betroffene Geräte (gemäß `docs/legacy-device-catalog.md`)

- **IGC Fileformat** (Dateimodus, bisher gpsbabel `-i igc`). Der Katalogeintrag der Alt-App hatte einen Tippfehler (`i-o gpx`); er entfällt mit der nativen Umsetzung.
- Damit sind alle Flugrekorder abgedeckt, die IGC-Dateien schreiben (Vario-Geräte, Flarm, Smartphone-Apps). Einzelne Gerätemodelle führt der Katalog nicht.

## Nicht im Umfang

- **Aufgabendeklaration (C-Records):** Sie beschreibt eine geplante Strecke, keine Aufzeichnung, und wird wie GPX-Routen nicht übernommen.
- **Sicherheitsprüfung (G-Record):** Die Signatur wird nicht geprüft. Dafür bräuchte es die herstellerspezifischen Prüfprogramme.
- **Ereignisse und Satellitenlisten (E-, F-, K-, L-Records)** sowie die übrigen B-Erweiterungen wie `FXA`, `GSP` oder `TRT`. GPX kann Geschwindigkeit und Kurs ohnehin nicht ausgeben.
- **Metadaten als Track-Name:** Pilot, Flugzeugtyp und Kennzeichen aus den H-Records werden nicht ausgewertet; der Track heißt wie die Datei.
- **IGC-Ausgabe:** Das Paket schreibt nur GPX.
- **Dateimodus in der App:** bleibt ein eigener Change.

## Impact

- Neue Dateien in `Packages/GPSLoggerKit/Sources/GPSLoggerKit/Formats/IGC/`, Tests und synthetische Fixtures.
- `FileFormatID.igc`, Eintrag in `FileFormats.all`, Lokalisierung `format.igc` (Deutsch, Englisch).
- `PROVENANCE.md` und README des Pakets.
- Keine Änderung an GPSLoaderKit oder der App, keine neuen Abhängigkeiten.
