## ADDED Requirements

### Requirement: Geräteschnittstelle
Das Paket SHALL eine plattformneutrale Schnittstelle für Logger-Protokolle bereitstellen. Sie besteht aus einer Verbindung (schreiben, lesen mit Zeitlimit, bis zu einem Endezeichen lesen, Eingang verwerfen, Baudrate wechseln) und einem Treibervertrag (auslesen, löschen, Löschunterstützung, Fortschritt). Treiber, die auf ihr aufbauen, SHALL ohne Hardware gegen ein simuliertes Gerät testbar sein und unter iOS bauen.

#### Scenario: Treiber mit simuliertem Gerät
- **WHEN** ein Test den GNS-2000-Treiber mit einer simulierten Verbindung ausführt
- **THEN** läuft er ohne Bluetooth und liefert die Aufzeichnung des simulierten Geräts

#### Scenario: iOS-Build mit Treibern
- **WHEN** das Paket für iOS gebaut wird
- **THEN** gelingt der Build mitsamt Geräteschnittstelle und GNS-2000-Treiber
