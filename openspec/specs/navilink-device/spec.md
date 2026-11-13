# navilink-device Specification

## Purpose
Liest Wegpunkte und Tracklog von Locosys-Geräten im NAVILINK-Modus (GT-11, GT-31, BGT-31, NaviGPS) über die serielle Schnittstelle, portiert aus gpsbabel 1.7.0.

## Requirements

### Requirement: Navilink-Pakete
Der Treiber SHALL Pakete als `0xA0 0xA2`, Länge (16 Bit, Little Endian, Typ plus Nutzdaten), Typ, Nutzdaten, Summe von Typ und Nutzdaten (15 Bit, Little Endian) und `0xB0 0xB3` senden und empfangen. Ein falscher Kopf, ein unerwarteter Typ, eine falsche Prüfsumme oder ein falsches Ende MUST den Vorgang mit einem Protokollfehler beenden.

#### Scenario: Nicht im NAVILINK-Modus
- **WHEN** das Gerät NMEA-Sätze statt Paketen sendet
- **THEN** endet der Vorgang mit dem Hinweis, das Gerät in den NAVILINK-Modus zu schalten

#### Scenario: Prüfsummenfehler
- **WHEN** ein Datenpaket eine falsche Prüfsumme hat
- **THEN** endet der Vorgang mit einem Protokollfehler

### Requirement: Auslesen
Der Treiber SHALL mit `SYNC` (0xD6) synchronisieren, die Geräteinformation abfragen (0x20), die Wegpunkte in Gruppen zu 32 lesen (0x28) und das Tracklog ab der gemeldeten Adresse in Gruppen zu 512 Punkten (0x14), jede Gruppe mit `ACK` (0x0C) quittiert. Trackpunkte SHALL Position (10⁻⁷ Grad), Höhe (Fuß), Zeit (UTC), Kurs und Geschwindigkeit (2 km/h je Einheit) enthalten, Wegpunkte zusätzlich ihren Namen.

#### Scenario: Auslesen
- **WHEN** das Gerät 40 Wegpunkte und 600 Trackpunkte meldet
- **THEN** liefert der Treiber 40 Wegpunkte und einen Track mit 600 Punkten, und er hat zwei Gruppen quittiert

### Requirement: Navilink-Geräte im Katalog
Der Gerätekatalog SHALL die sechs Navilink-Geräte der Alt-App mit 115200 Baud und ohne Löschen enthalten.

#### Scenario: Navilink-Geräte im Katalog
- **WHEN** der Anwender ein Navilink-Gerät wählt
- **THEN** ist „Speicher löschen …“ nicht verfügbar
