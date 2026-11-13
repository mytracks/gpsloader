# Proposal: Alan Map500 Tracklogs (Portierung)

## Why

Tracklogs des Alan Map500 (`.trl`) wurden in myTracks über gpsbabel `alantrl` gelesen. Für dieses Format ist laut `openspec/config.yaml` bisher noch gpsbabel vorgesehen. Der Entwickler hat am 2026-11-13 entschieden, gpsbabel ganz aus der App zu entfernen (Change `remove-gpsbabel`) und vorher Alan Map500 zu portieren.

## What Changes

- **Dateiformat `alantrl` in GPSLoggerKitGPL**, nur macOS, Endung `.trl`. Es ist übersetzt aus gpsbabel 1.7.0 `alan.cc`.
- **Inhalt:** Positionen, Höhen, Geschwindigkeit und die Aufteilung in bis zu acht Tracks folgen der Vorlage.
- **Katalog und Herkunft:** `GPLFileFormats.all` enthält das Format, `PROVENANCE.md` bekommt einen Abschnitt dafür.
- **Erkennung:** Die Endung `.trl` teilen sich mehrere Formate (Google Navigator, TrackLogs digital mapping). Erkannt wird daher am Inhalt, nicht allein an der Endung.
- **Keine Zeiten:** Das Format speichert keine Zeitstempel. Die Trackpunkte haben daher keine Zeit, wie bei gpsbabel.

## Zuordnung der Familie

- **Familie Alan Map500:** GPSLoggerKitGPL (Portierung). Grundlage sind die Entscheidung des Entwicklers vom 2026-11-13 („Portieren alles, was möglich ist, in das GPL-Paket“) und seine Bestätigung vom selben Tag.
- **Vorlage:** `alan.cc` (Tag `gpsbabel_1_7_0`), Copyright (C) 2007 Gunar Megger und (C) 2002–2014 Robert Lipe (Zeilen 8–9), GPL-2.0-or-later (Zeilen 11–14).
- **Leseregel:** Gelesen wird nur diese Datei und, soweit nötig, die dort benutzten gemeinsamen Hilfen.

## Capabilities

### New Capabilities

- `alan-import`: Tracklog-Dateien des Alan Map500 einlesen.

### Modified Capabilities

- `logger-kit-gpl`: Der Katalog des Pakets enthält zusätzlich `alantrl`.

## Betroffene Geräte (gemäß `docs/legacy-device-catalog.md`)

- **Treiber `alantrl`, Datei:** Alan Map500.
- **Formatliste der Alt-App (`GPSBabel.m`):** „Alan Map500 tracklogs (.trl)“.

## Nicht im Umfang

- **Wegpunkt- und Routendateien** des Map500 (`alanwpr`, `.wpr`): Die Alt-App bot sie nicht an.
- **Schreiben.**
- **iOS.**
- **Echte Dateien als Fixtures:** Es gibt nur synthetische Dateien, gegengeprüft mit dem gpsbabel-1.7.0-Binary.

## Impact

- **GPSLoggerKitGPL:** `Alan/AlanFileFormat.swift`, Tests, `GPLFileFormats.swift`, `PROVENANCE.md`, `README.md`, Lokalisierung des Formatnamens.
- **`openspec/config.yaml`:** Alan Map500 wandert aus „Weiterhin über gpsbabel“ in die portierten Formate.
