# Proposal: Magellan Meridian/SporTrak/eXplorist (Portierung)

## Why

Die Magellan-Geräte liefen in myTracks über gpsbabel `magellan` (serielles Auslesen) sowie über die Dateiformate `magellan` und `magellanx` (SD-Karte). Für sie ist laut `openspec/config.yaml` bisher noch gpsbabel vorgesehen. Der Entwickler hat am 2026-11-13 entschieden, gpsbabel ganz aus der App zu entfernen (Change `remove-gpsbabel`). Vorher müssen die Magellan-Geräte portiert werden. Mit „ja“ hat er außerdem bestätigt, Magellan, iTrackU und Alan Map500 zu portieren.

## What Changes

- **`MagellanDevice` in GPSLoggerKitGPL**, übersetzt aus gpsbabel 1.7.0 `magproto.cc`:
  - NMEA-artiges Protokoll mit `$PMGN…`-Sätzen und Prüfsumme, beim Lesen ohne Quittungen wie in der Vorlage;
  - Wegpunkte und Tracklog lesen;
  - Baudrate wie in der Vorlage (Standard 4800).
- **Dateiformat `magellan` in GPSLoggerKitGPL** für die SD-Dateien von Meridian und eXplorist (`.log`, `.upt`):
  - gpsbabel führt dafür zwei Formate (`magellan`, `magellanx`), liest beide aber gleich. Sie unterscheiden sich nur beim Schreiben.
  - Der Port hat deshalb ein Format für beide.
  - Es steht in `GPLFileFormats.all`, und `PROVENANCE.md` bekommt einen Abschnitt dafür.
- **Gerätekatalog:** die sieben seriellen Magellan-Geräte der Alt-App, ohne Löschen.

## Zuordnung der Familie

- **Familie Magellan:** GPSLoggerKitGPL (Portierung). Grundlage sind die Entscheidung des Entwicklers vom 2026-11-13 („Portieren alles, was möglich ist, in das GPL-Paket“) und seine Bestätigung vom selben Tag.
- **Vorlagen** (Tag `gpsbabel_1_7_0`), beide GPL-2.0-or-later:
  - `magproto.cc`: Copyright (C) 2002–2008, 2010 Robert Lipe (Zeilen 4–5), Lizenz in den Zeilen 7–10.
  - `magellan.h`: Copyright (C) 2002–2005 Robert Lipe (Zeile 2), Lizenz in den Zeilen 4–7.
- **Leseregel:** Gelesen werden nur diese Dateien und, soweit nötig, die dort benutzten gemeinsamen Hilfen (`ddmm2degrees` in `util.cc`, Semantik von `gbser_read_line`).

## Capabilities

### New Capabilities

- `magellan-device`: Wegpunkte und Track von Magellan-Geräten über die serielle Schnittstelle lesen.
- `magellan-import`: SD-Dateien der Magellan-Geräte (Meridian, eXplorist) einlesen.

### Modified Capabilities

- `logger-kit-gpl`: Der Katalog des Pakets enthält zusätzlich `magellan`.

## Betroffene Geräte (gemäß `docs/legacy-device-catalog.md`)

- **Treiber `magellan`, USB (seriell):**
  - Magellan Meridian, Meridian Gold, Meridian Platinum;
  - SporTrak Map, Map Color, Map Pro und Map Topo.
- **Treiber `magellan`, Datei:** Magellan Explorist.
- **Formatliste der Alt-App (`GPSBabel.m`):** „Magellan SD files (as for Meridian)“ (`magellan`) und „Magellan SD files (as for eXplorist)“ (`magellanx`).

## Nicht im Umfang

- **Schreiben** von Wegpunkten, Routen und Tracks, **Löschen** und **Routen lesen**. Die Alt-App las nur Wegpunkte und Track (`-t -w`) und bot kein Löschen an.
- **Andere Magellan-Formate von gpsbabel:** `maggeo` (Geocaches), `mapsend` und `magnav` (Palm). `mapsend` steht zwar in der Formatliste der Alt-App, ist aber ein Format des PC-Programms MapSend und entfällt mit den übrigen Programmformaten (`remove-gpsbabel`).
- **Explorist GC/510/610/710** (`usb:` in der Vorlage): Diese Geräte speichern GPX, das der Dateimodus schon liest.
- **Ältere Modelle** (GPS 315/320, Map 330/410, GPS 310): Sie stehen nicht im Katalog. Der Treiber erkennt sie wie die Vorlage, getestet wird nur mit Meridian und SporTrak.
- **LoadMyTracks-Geräte:** „Magellan - generic“, eXplorist 210 und Meridian Color. Sie entfallen laut `config.yaml`.
- **iOS.**
- **Echte Dateien und Mitschnitte als Fixtures:** Es gibt nur synthetische Dateien, gegengeprüft mit dem gpsbabel-1.7.0-Binary.

## Impact

- **GPSLoggerKitGPL:** `Magellan/` (Protokoll, Dateiformate, Tests), `GPLFileFormats.swift`, `PROVENANCE.md`, `README.md`, Lokalisierung des Formatnamens.
- **GPSLoaderKit:** `DeviceDrivers/Families/MagellanDevices.swift`, Erweiterung von `DeviceCatalogContent`.
- **`openspec/config.yaml`:** Magellan wandert aus „Weiterhin über gpsbabel“ in die portierten Familien.
