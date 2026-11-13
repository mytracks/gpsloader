## REMOVED Requirements

### Requirement: Umgebungsstatus im Hauptfenster
**Reason**: Es gibt keine gpsbabel-Laufzeit mehr, deren Zustand das Hauptfenster anzeigen müsste. Rosetta wird nicht mehr gebraucht.
**Migration**: Keine. Das Hauptfenster zeigt nur noch Dateimodus und Direktmodus.

## MODIFIED Requirements

### Requirement: Lizenzhinweise
Die App SHALL im Über-Fenster angeben, dass sie unter der GNU GPL Version 3 oder später steht, und wo ihr Quellcode erhältlich ist. Sie SHALL außerdem GPSLoggerKit unter der MIT-Lizenz sowie die Urheber der Vorlagen portierter Formate und Treiber nennen, jeweils mit Quellcode-Bezugsquelle. Gpsbabel und Qt MUST sie nicht als mitgelieferte Programme nennen. Die Texte der GPL Version 3 und der MIT-Lizenz MUST im App-Bundle enthalten sein.

#### Scenario: Über-Fenster öffnen
- **WHEN** der Anwender „Über gpsloader“ wählt
- **THEN** zeigt das Fenster die App-Version, die Copyright-Angabe, die Lizenz der App mit Verweis auf ihren Quellcode und den Lizenzhinweis für GPSLoggerKit
- **AND** es erwähnt weder gpsbabel 1.7.0 noch Qt als mitgelieferte Programme

#### Scenario: Portierte Formate
- **WHEN** GPSLoggerKitGPL Formate oder Treiber mit Vorlagen enthält
- **THEN** nennt das Über-Fenster die Urheber dieser Vorlagen oder verweist auf eine mitgelieferte Liste, die sie nennt

#### Scenario: Lizenztexte im Bundle
- **WHEN** das ausgelieferte App-Bundle untersucht wird
- **THEN** enthält es die vollständigen Texte der GPL Version 3 und der MIT-Lizenz von GPSLoggerKit
- **AND** es enthält kein `Contents/Helpers` und kein Qt-Framework
