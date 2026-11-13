## MODIFIED Requirements

### Requirement: Geräteprotokolle
Die Geräteprotokolle des Pakets SHALL die Geräteschnittstelle aus GPSLoggerKit nutzen (Verbindung: schreiben, lesen mit Zeitlimit, bis zu einem Endezeichen lesen, Eingang verwerfen, Baudrate wechseln; Treibervertrag: auslesen, löschen, Fortschritt). Eine eigene Schnittstelle SHALL das Paket nicht mehr bereitstellen. Es SHALL dafür von nichts außer GPSLoggerKit abhängen. Jeder Treiber SHALL ohne Hardware gegen ein simuliertes Gerät testbar sein.

#### Scenario: Simuliertes Gerät
- **WHEN** ein Test einen Treiber mit einer simulierten Verbindung ausführt
- **THEN** läuft er ohne seriellen Anschluss und liefert die Aufzeichnung des simulierten Geräts

#### Scenario: Gemeinsame Schnittstelle
- **WHEN** eine App Treiber aus GPSLoggerKit und aus GPSLoggerKitGPL verwendet
- **THEN** erfüllen beide denselben Treibervertrag aus GPSLoggerKit
