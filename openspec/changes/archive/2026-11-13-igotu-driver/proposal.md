# Proposal: i-GotU-Logger auslesen (Portierung)

## Why

i-GotU-Logger wurden in myTracks 4.5.0 entfernt, weil die Hilfsprogramme nicht auf Apple Silicon liefen (`docs/legacy-analysis.md`, Abschnitt 3.2). `openspec/config.yaml` nimmt sie ausdrücklich wieder auf. Der Entwickler hat am 2026-11-13 die Umsetzung beauftragt und die Familie dem GPL-Paket zugeordnet.

## What Changes

- **`IGotUDevice` in GPSLoggerKitGPL** mit zwei Varianten:
  - **GT-800/GT-800 Pro:** seriell mit 9600 Baud, Befehle mit 16 Byte. Grundlage ist der eigene myTracks-Treiber `IGotUGT800.m`.
  - **GT-100/120/200/200e/600:** USB-HID, Befehle in Stücken zu 8 Byte. Grundlage ist igotu2gpx 0.3.0 (GPL-3.0-or-later).
  - **Auslesen:** NMEA-Modus umschalten, Anzahl der Datensätze, Speicherblöcke zu 4 KiB, 32-Byte-Datensätze dekodieren.
  - **Löschen, experimentell:** beim GT-800 nach dem eigenen Code, bei GT-100/120/200 nach igotu2gpx.
- **USB-HID-Transport `HIDTransport` in GPSLoaderKit** (IOKit `IOHIDDevice`): Output-Reports zum Senden, Input-Reports zum Empfangen, Diagnose-Mitschnitt.
- **Gerätekatalog:** fünf USB-Modelle ohne Portwahl, GT-800 und GT-800 Pro seriell.
- **`credits`:** neuer Eintrag igotu2gpx (Michael Hofmann, GPL-3.0-or-later).

## Zuordnung der Familie

- **Familie i-GotU:** GPSLoggerKitGPL, Entscheidung des Entwicklers vom 2026-11-13.
- **Vorlagen:**
  - eigener Code des Entwicklers (myTracks, `3cbc727^:DsTrackFramework/Source/Classes/GpsDriver/IGotUGT800.m`, `IGotU.m`);
  - igotu2gpx 0.3.0, Copyright (C) 2009 Michael Hofmann, GPL-3.0-or-later (`src/igotu/igotucommand.cpp`, Zeilen 2–7), zulässig.

## Offene Entscheidung (noch nicht bestätigter Vorschlag)

`config.yaml` führt „i-GotU-Löschen als experimentell kennzeichnen, mit Warnung“ als **noch nicht bestätigten** Vorschlag. Dieser Change setzt ihn so um: Löschen wird angeboten, mit der vorhandenen Warnung für experimentelle Treiber. Der Entwickler bestätigt das oder entscheidet anders (Task 3.1). Die Alternative wäre, Löschen für i-GotU nicht anzubieten.

**Entscheidung (2026-11-13):** Der Entwickler hat bestätigt, Löschen als experimentell anzubieten. `config.yaml` ist angepasst.

## Capabilities

### New Capabilities

- `igotu-device`: i-GotU-Logger seriell (GT-800) und über USB-HID (übrige Modelle) auslesen und experimentell löschen.

### Modified Capabilities

- `logger-kit-gpl`: `credits` nennt igotu2gpx.

## Betroffene Geräte (gemäß `docs/legacy-analysis.md`, Abschnitt 3.2)

i-GotU GT-100, GT-120, GT-200, GT-200e, GT-600, GT-800 und GT-800 Pro.

## Nicht im Umfang

- **Konfiguration:** Logintervall, Zeitzone und Ähnliches.
- **Löschen bei GT-200e und GT-600:** Auch igotu2gpx kennt dafür keine Blockanzahl.
- **Hinweis nach dem Löschen beim GT-800** („Logger abziehen, damit er neu startet“, Alt-App): eigener kleiner Change in der Sitzungsanzeige.
- **Test mit echter Hardware:** Er bleibt Aufgabe der Anwender, der Entwickler hat keine i-GotU-Geräte.

## Impact

- **GPSLoggerKitGPL:** `IGotU/IGotUDevice.swift`, `credits`, `PROVENANCE.md`.
- **GPSLoaderKit:** Modul `HIDTransport` und `DeviceDrivers/Families/IGotUDevices.swift`.
- **App:** Sie übergibt `IOKitHIDConnectionFactory` an die Gerätewahl. Dazu kommt `project.yml`.
