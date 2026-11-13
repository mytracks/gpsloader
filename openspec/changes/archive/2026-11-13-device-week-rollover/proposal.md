# Proposal: device-week-rollover

## Why

Beim Auslesen eines Holux M-241 hat der Entwickler am 2026-11-13 Zeiten erhalten, die um 1024 GPS-Wochen
(rund 19,6 Jahre) zu früh liegen. Ältere GPS-Chips zählen die Woche mit 10 Bit und springen nach dem
Wochenüberlauf (zuletzt April 2019) zurück. Die Korrektur gibt es in GPSLoggerKit
(`RecordingProcessing.correctingWeekRollover`, Spec `logger-kit`), die App wendet sie aber nur beim
Konvertieren von Dateien an (Spec `file-conversion`), nicht im Gerätemodus. In myTracks lief jeder
Geräte-Import über den GPX-Import mit dieser Korrektur, gpsloader fällt hier also hinter die Alt-App zurück.

## What Changes

- Der Adapter `ProtocolDriver` (GPSLoaderKit, Modul `DeviceDrivers`) wendet nach jedem Auslesen die
  Korrektur des Wochenüberlaufs mit der aktuellen Zeit als Bezug an, für Trackpunkte und Wegpunkte.
  Das betrifft alle Geräte mit nativem Treiber aus `docs/legacy-device-catalog.md`, also die Familien
  MTK (`mtk`, `m241`, u. a. Holux M-241 und GPSport 245), SkyTraq, Wintec, Navilink, Magellan, iTrackU,
  i-GotU und GNS 2000.
- Der GNS-2000-Treiber (GPSLoggerKit) teilt die Punkte dort in Tracks, wo die Zeit zurückspringt, und benennt
  die Tracks nach der Zeit des ersten Punkts. Er korrigiert die Zeiten deshalb schon vor dem Teilen, damit
  Tracknamen und Trackgrenzen zu den korrigierten Zeiten passen.
- Wie beim Konvertieren ist die Korrektur immer aktiv; eine Einstellung zum Abschalten gibt es nicht.

Neue Logger-Familien entstehen nicht; die Paketzuordnung bleibt unverändert. Unbestätigte Vorschläge aus
`openspec/config.yaml` sind nicht berührt.

## Capabilities

### New Capabilities

(keine)

### Modified Capabilities

- `device-mode`: neue Anforderung „Korrektur des GPS-Wochenüberlaufs beim Auslesen“.

## Nicht im Umfang

- Eine andere Regel für den Überlauf (etwa „nie in die Zukunft verschieben“). Es gilt die Regel der Spec
  `logger-kit`: mehr als 512 Wochen vor dem Bezug, dann 1024 Wochen addieren.
- Eine Einstellung zum Abschalten der Korrektur in der App.
- Änderungen an den Dateiformaten und am Konvertieren; dort ist die Korrektur schon aktiv.
- Die Demo-Treiber der Debug-Automation.

## Impact

- `Packages/GPSLoaderKit/Sources/DeviceDrivers/ProtocolDriver.swift`: Korrektur nach dem Auslesen, Bezugszeit
  für Tests einstellbar.
- `Packages/GPSLoggerKit/Sources/GPSLoggerKit/Devices/GNS2000/GNS2000Device.swift`: Korrektur vor dem Teilen.
- Tests in `DeviceDriversTests` und `GPSLoggerKitTests`.
