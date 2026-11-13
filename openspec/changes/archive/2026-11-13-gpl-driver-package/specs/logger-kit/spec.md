## ADDED Requirements

### Requirement: Erweiterbarer Formatkatalog
Das Paket SHALL einen Katalog aus seinen eigenen Formaten und zusätzlichen Formaten anderer Pakete bilden können. Erkennung, Suche nach Kennung und Einlesen SHALL auf einem solchen Katalog genauso arbeiten wie auf dem eigenen. Die eigenen Formate SHALL dabei vorn stehen. Eine doppelte Kennung MUST beim Bilden des Katalogs als Programmierfehler gelten. Das Paket MUST dafür keine Kenntnis der anderen Pakete haben.

#### Scenario: Zusätzliches Format erkennen
- **WHEN** ein Katalog aus den eigenen Formaten und einem zusätzlichen Testformat gebildet wird und eine Datei dieses Testformats geprüft wird
- **THEN** schlägt die Erkennung das Testformat vor, und eine NMEA-Datei wird weiterhin als NMEA 0183 erkannt

#### Scenario: Standardkatalog unverändert
- **WHEN** eine App den Katalog wie bisher ohne Zusätze abfragt
- **THEN** enthält er genau die eigenen Formate des Pakets
