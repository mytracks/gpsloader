# gns2000-device Specification

## Purpose
Der Eintrag des Bluetooth-Loggers GNS 2000 (auch GNS 2000 plus) im Gerätekatalog der App. Das Geräteprotokoll liegt in GPSLoggerKit (https://github.com/mytracks/GPSLoggerKit, Spec `gns2000-device` dort).

## Requirements

### Requirement: GNS 2000 im Katalog
Der Gerätekatalog SHALL einen Eintrag „GNS 2000“ mit der Verbindungsart Bluetooth enthalten. Er gilt für die Gerätenamen „GNS 2000“ und „GNS 2000 plus“ und den SDP-Dienst „GNS GPS“. Er SHALL ohne Anschlusswahl auskommen und Löschen anbieten.

#### Scenario: GNS 2000 wählen
- **WHEN** der Anwender „GNS 2000“ wählt
- **THEN** zeigt das Fenster keine Anschlusswahl, und „Auslesen“ und „Speicher löschen …“ sind verfügbar
