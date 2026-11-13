## ADDED Requirements

### Requirement: Geräteprotokolle
Das Paket SHALL für Geräteprotokolle eine eigene Verbindungs-Schnittstelle (schreiben, lesen mit Zeitlimit, bis zu einem Endezeichen lesen, Eingang verwerfen, Baudrate wechseln) und einen Treibervertrag (auslesen, löschen, Fortschritt) bereitstellen. Es SHALL dafür von nichts außer GPSLoggerKit abhängen. Jeder Treiber SHALL ohne Hardware gegen ein simuliertes Gerät testbar sein.

#### Scenario: Simuliertes Gerät
- **WHEN** ein Test einen Treiber mit einer simulierten Verbindung ausführt
- **THEN** läuft er ohne seriellen Anschluss und liefert die Aufzeichnung des simulierten Geräts
