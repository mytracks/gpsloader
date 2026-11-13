# Proposal: XAiOX iTrackU direkt auslesen (Portierung)

## Why

Der XAiOX iTrackU lief in myTracks als „XAiOX iTrackU - gpsbabel“ über gpsbabel `itracku`. Für ihn ist laut `openspec/config.yaml` bisher noch gpsbabel vorgesehen. Der Entwickler hat am 2026-11-13 entschieden, gpsbabel ganz aus der App zu entfernen (Change `remove-gpsbabel`) und vorher iTrackU zu portieren.

## What Changes

- **`ITrackUDevice` in GPSLoggerKitGPL**, übersetzt aus gpsbabel 1.7.0 `itracku.cc`:
  - Verbindung und Baudrate wie in der Vorlage;
  - Speicher lesen und die Datensätze zu Trackpunkten dekodieren.
- **Ergebnis:** ein Track „iTrackU“. gpsbabel lieferte mit `-t -w` dieselben Punkte als Wegpunkte; design.md begründet die Abweichung.
- **Gerätekatalog:** ein Eintrag „XAiOX iTrackU“, ohne Löschen. Die Vorlage kann nicht löschen, und die Alt-App bot es nicht an.

## Zuordnung der Familie

- **Familie XAiOX iTrackU:** GPSLoggerKitGPL (Portierung). Grundlage sind die Entscheidung des Entwicklers vom 2026-11-13 („Portieren alles, was möglich ist, in das GPL-Paket“) und seine Bestätigung vom selben Tag.
- **Vorlage:** `itracku.cc` (Tag `gpsbabel_1_7_0`), Copyright (C) 2008 Andreas Grimme und (C) 2005 Robert Lipe (Zeilen 2–3), GPL-2.0-or-later (Zeilen 5–8).
- **Leseregel:** Gelesen wird nur diese Datei und, soweit nötig, die dort benutzten gemeinsamen Hilfen.
- **iTU4l:** Die Perl-Skripte `iTU4l.pl` und `sr2x.pl` werden nicht gelesen. Ihre Katalogeinträge (Nemerix, SiRF III) entfallen laut `config.yaml`.

## Capabilities

### New Capabilities

- `itracku-device`: Den Speicher des XAiOX iTrackU über die serielle Schnittstelle lesen und dekodieren.

### Modified Capabilities

(keine)

## Betroffene Geräte (gemäß `docs/legacy-device-catalog.md`)

- **Treiber `itracku`, USB (seriell):** XAiOX iTrackU - gpsbabel.

## Nicht im Umfang

- **„XAiOX iTrackU - Nemerix“ und „- SIRFIII“:** Diese Geräte liefen über Perl-Skripte (iTU4l) und entfallen.
- **Dateiformat `itracku-bin`:** Diese Sicherungsdatei schreibt nur gpsbabel selbst (Option `backup`). Sie steht weder im Katalog noch in der Formatliste der Alt-App.
- **Positionsausgabe in Echtzeit** (`itracku_rt_*`): kein Echtzeit-Tracking laut `config.yaml`.
- **Inkrementelles Auslesen:** Die gpsbabel-Option `backup`/`new` setzt eine Datei auf dem Mac voraus. Die Alt-App nutzte sie nicht.
- **iOS.**
- **Echte Mitschnitte als Fixtures:** Es gibt nur synthetische Daten, gegengeprüft mit dem gpsbabel-1.7.0-Binary.

## Impact

- **GPSLoggerKitGPL:** `ITrackU/ITrackUDevice.swift`, Tests, `PROVENANCE.md`, `README.md`, Eintrag in `credits`.
- **GPSLoaderKit:** `DeviceDrivers/Families/ITrackUDevices.swift`, Erweiterung von `DeviceCatalogContent`.
- **`openspec/config.yaml`:** iTrackU wandert aus „Weiterhin über gpsbabel“ in die portierten Familien.
