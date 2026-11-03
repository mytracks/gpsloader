# Proposal: GPSLoggerKit – Fundament, NMEA und GPX-Eingang

## Why

Formate und Logger-Protokolle sollen nativ in Swift entstehen, damit sie ohne gpsbabel und Rosetta laufen und auch auf iPhone und iPad nutzbar sind, etwa für eine NMEA-zu-GPX-Konvertierung. Dafür braucht es ein eigenständiges, MIT-lizenziertes Paket. Dieser erste Change legt sein Fundament und liefert die beiden häufigsten Dateiformate: NMEA 0183 und GPX als Eingang.

## What Changes

- Neues Swift-Paket `GPSLoggerKit` unter `Packages/GPSLoggerKit`:
  - Plattformen macOS 12+ und iOS/iPadOS 27+.
  - Swift 6 Language Mode, MIT-Lizenz.
  - Keine Abhängigkeit auf andere Teile dieses Repositorys; es wird später in ein eigenes Repository ausgelagert.
- Gemeinsames Datenmodell für Tracks, Segmente, Trackpunkte und Wegpunkte, erweitert um Qualitätsangaben (Satelliten, HDOP/VDOP/PDOP, Fix-Art).
- Einheitlicher Vertrag für Dateiformate:
  - Kennung, Name und Dateiendungen.
  - Erkennung anhand des Inhalts.
  - Einlesen mehrerer Dateien zu einer Aufzeichnung, mit Abbruch und Warnungen.
- GPX-1.1-Ausgabe, verschoben aus `GPSLoaderKit/GPXExport` ins neue Paket. Das Verhalten bleibt gleich; neu ausgegeben werden die Qualitätsangaben.
- NMEA-0183-Import:
  - Sätze RMC, GGA, GLL, GSA, VTG, ZDA und WPL, von allen Talkern (GP, GN, GL, GA, GB/BD, GQ).
  - Prüfsummen werden geprüft.
  - Datum und Zeit werden über Satzgrenzen und Mitternacht hinweg zusammengeführt.
  - Mehrere Dateien werden zusammengeführt.
  - Sony-`@`-Zeilen werden ignoriert. Das betrifft Sony GPS CS-1/CS-3 (Verhalten der Alt-App).
- GPX-Eingang:
  - Liest GPX 1.0 und 1.1 mit Tracks und Wegpunkten. Routen sind geplante, keine aufgezeichneten Daten und werden wie bisher nicht übernommen.
- Allgemeine Nachbearbeitung, wie in der Alt-App (`docs/legacy-analysis.md`, Abschnitt 4 und 5):
  - Korrektur des GPS-Wochenüberlaufs: Zeiten mehr als 512 Wochen in der Vergangenheit werden um 1024 Wochen verschoben. Die Korrektur ist abschaltbar.
  - Enthält eine Aufzeichnung keine Tracks, werden ihre Wegpunkte zu einem Track.
- `GPSLoaderKit` und die App nutzen Modell und GPX-Ausgabe aus `GPSLoggerKit`. Dafür entfallen dort `LoggerCore/Model.swift` und `GPXExport/GPXWriter.swift`. Das ist ein interner Umbau, kein öffentliches API.

## Capabilities

### New Capabilities

- `logger-kit`: das Paket selbst, also Plattformen, Lizenz und Clean-Room-Regel, Datenmodell, Formatvertrag, Formaterkennung, Fehler und allgemeine Nachbearbeitung.
- `nmea-import`: NMEA-0183-Dateien einlesen und daraus Tracks und Wegpunkte bilden.
- `gpx-import`: Tracks und Wegpunkte aus GPX-1.0- und GPX-1.1-Dateien einlesen.

### Modified Capabilities

- `gpx-export`: Trackpunkte und Wegpunkte geben zusätzlich vorhandene Qualitätsangaben aus (`sat`, `hdop`, `vdop`, `pdop`, `fix`). Der `creator` wird vom Aufrufer vorgegeben; in gpsloader bleibt er „gpsloader <Version>“.

## Betroffene Geräte (gemäß `docs/legacy-device-catalog.md`)

- **NMEA, Dateimodus:** Amaryllo Trip Tracker, AMOD AGL3080, ATP Photo Finder, Canon EOS LOG, NMEA Fileformat, Sony GPS CS-1, Sony GPS CS-3.
- **GPX, Dateimodus:** Garmin Colorado 300/400c/400i/400t, Dakota, GPSmap 62, Nuvi, Oregon, Road Tech Zumo, StreetPilot, Zumo.

## Nicht im Umfang

- **Dateimodus der App:** Dateiauswahl, Formatwahl und Konvertierung in der gpsloader-UI bekommen einen eigenen Change. Dieser Change liefert nur die Bibliothek.
- **Eine iOS-App:** Das Paket wird lediglich für iOS gebaut und dort getestet.
- **Weitere Formate:** FIT, TCX, Suunto, IGC, Wintec, MTK, SkyTraq, Navilink, i-GotU und die CSV-Logger folgen in eigenen Changes.
- **Transporte und Treiber:** Seriell, HID und Bluetooth bleiben vorerst in `GPSLoaderKit` und wandern mit dem ersten nativen Logger-Treiber.
- **Diagnose-Mitschnitt für Dateiformate.**
- **Auslagerung:** Das Paket wird noch nicht in ein eigenes Repository ausgelagert.
- **Ausgabe von Geschwindigkeit und Kurs:** GPX 1.1 kennt diese Felder nur über Erweiterungen, und Erweiterungen sind ausgeschlossen.
- **NMEA-Sätze ohne Positionsbezug:** GSV, proprietäre `$P…`-Sätze und AIS werden ignoriert und nicht ausgewertet.

## Impact

- **Neu:** `Packages/GPSLoggerKit` mit `Package.swift`, Quellen, Tests und Fixtures, `LICENSE` (MIT) und `README.md`.
- **Geändert:**
  - `Packages/GPSLoaderKit/Package.swift` bekommt eine lokale Abhängigkeit auf `../GPSLoggerKit`.
  - `LoggerCore` und `GPXExport` verwenden die Typen aus `GPSLoggerKit`.
  - In der App ändern sich Imports.
- **`project.yml`:** keine neue Paketreferenz nötig, weil die App das Paket transitiv über GPSLoaderKit bekommt. Das prüfe ich beim Bauen.
- **Tests:**
  - Neue Testziele laufen mit `swift test` auf macOS und mit `xcodebuild test` auf dem iOS-27-Simulator.
  - Die bestehenden GPX-Tests wandern ins neue Paket.
- **Lizenz und Herkunft:**
  - Grundlagen sind die öffentlichen NMEA-0183-Satzbeschreibungen, das Topografix-XSD für GPX 1.0 und 1.1 sowie der eigene myTracks-Code für das `@`-Verhalten.
  - GPL-Quelltext wird nicht verwendet.
