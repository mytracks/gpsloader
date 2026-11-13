## MODIFIED Requirements

### Requirement: Unterstützte Formate
Die App SHALL alle Formate ihres Katalogs konvertieren. Der Katalog SHALL aus den Formaten von GPSLoggerKit und von GPSLoggerKitGPL bestehen. Das Format jeder Datei SHALL über die Formaterkennung auf diesem Katalog bestimmt werden. Kommt ein Format zu einem der beiden Pakete hinzu, SHALL es ohne Änderung an der App verfügbar sein. Der Dateidialog SHALL alle Dateien zur Auswahl zulassen, weil die Endung nur ein Hinweis ist.

#### Scenario: NMEA mit Endung .LOG
- **WHEN** der Anwender die Datei `GPS_20261102.LOG` einer Canon EOS wählt
- **THEN** wird sie als NMEA 0183 erkannt und konvertiert

#### Scenario: Neues Format im Katalog
- **WHEN** GPSLoggerKit oder GPSLoggerKitGPL ein weiteres Format in seinen Katalog aufnimmt
- **THEN** konvertiert die App Dateien dieses Formats, ohne dass ihr Code geändert wird

#### Scenario: Format aus dem GPL-Paket
- **WHEN** die Konvertierung mit einem Katalog geprüft wird, der zusätzlich ein Testformat enthält, und eine Datei dieses Formats gewählt wird
- **THEN** wird sie mit dem Testformat gelesen und in die GPX-Datei übernommen
