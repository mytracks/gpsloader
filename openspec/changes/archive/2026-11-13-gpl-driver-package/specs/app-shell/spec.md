## MODIFIED Requirements

### Requirement: Lizenzhinweise
Die App SHALL im Über-Fenster angeben, dass sie unter der GNU GPL Version 3 oder später steht, und wo ihr Quellcode erhältlich ist. Es SHALL außerdem die Lizenzen der enthaltenen und mitgelieferten Fremdkomponenten anzeigen: GPSLoggerKit unter der MIT-Lizenz, gpsbabel unter der GNU GPL, Qt unter der GNU LGPL sowie die Urheber der Vorlagen portierter Formate, jeweils mit Quellcode-Bezugsquelle. Die vollständigen Lizenztexte MUST im App-Bundle enthalten sein.

#### Scenario: Über-Fenster öffnen
- **WHEN** der Anwender „Über gpsloader“ wählt
- **THEN** zeigt das Fenster die App-Version, die Copyright-Angabe, die Lizenz der App mit Verweis auf ihren Quellcode sowie die Lizenzhinweise für GPSLoggerKit, gpsbabel 1.7.0 und Qt 5.12 mit Verweis auf die Quellcode-Bezugsquellen

#### Scenario: Portierte Formate
- **WHEN** GPSLoggerKitGPL Formate mit Vorlagen enthält
- **THEN** nennt das Über-Fenster die Urheber dieser Vorlagen oder verweist auf eine mitgelieferte Liste, die sie nennt

#### Scenario: Lizenztexte im Bundle
- **WHEN** das ausgelieferte App-Bundle untersucht wird
- **THEN** enthält es die vollständigen Texte der GPL Version 2 und 3, der LGPL Version 3 und der MIT-Lizenz von GPSLoggerKit
