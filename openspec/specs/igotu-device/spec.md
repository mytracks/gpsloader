# igotu-device Specification

## Purpose
Die i-GotU-Logger in der App: ihre Einträge im Gerätekatalog und die USB-HID-Verbindung der USB-Modelle. Das Geräteprotokoll liegt in GPSLoggerKitGPL (https://github.com/mytracks/GPSLoggerKitGPL, Spec `igotu-device` dort).

## Requirements

### Requirement: USB-HID-Verbindung
Für USB-Modelle SHALL die App das Gerät über Hersteller- und Produktkennung (`0x0DF7`/`0x0900`) finden, exklusiv öffnen, Befehle als Output-Reports zu 8 Byte senden und Antworten aus den Input-Reports lesen, mit Zeitlimit und Diagnose-Mitschnitt. Ist kein Gerät angeschlossen, MUST der Vorgang mit „Gerät nicht gefunden“ enden.

#### Scenario: Kein i-GotU angeschlossen
- **WHEN** der Anwender ein USB-Modell ausliest und kein Gerät angeschlossen ist
- **THEN** meldet die App, dass das Gerät nicht gefunden wurde

### Requirement: i-GotU-Geräte im Katalog
Der Gerätekatalog SHALL die fünf USB-Modelle ohne Portwahl und den GT-800 und GT-800 Pro mit seriellem Anschluss enthalten.

#### Scenario: i-GotU-Geräte im Katalog
- **WHEN** der Anwender ein USB-Modell wählt
- **THEN** zeigt das Fenster keine Portwahl
