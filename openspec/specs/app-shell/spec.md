# app-shell Specification

## Purpose
Der App-Rahmen von gpsloader: Start auf allen unterstützten Macs, Hauptfenster, Lizenzhinweise für enthaltene Fremdkomponenten und portierte Vorlagen und Lokalisierung.

## Requirements

### Requirement: Unterstützte Systeme
Die App MUST auf macOS 12 und neuer starten, und zwar sowohl auf Apple-Silicon- als auch auf Intel-Macs nativ, ohne Rosetta für die App selbst.

#### Scenario: Start auf Apple Silicon
- **WHEN** die App auf einem Apple-Silicon-Mac mit macOS 12 oder neuer gestartet wird
- **THEN** läuft der App-Prozess nativ (arm64) und das Hauptfenster erscheint

#### Scenario: Start auf Intel
- **WHEN** die App auf einem Intel-Mac mit macOS 12 oder neuer gestartet wird
- **THEN** läuft der App-Prozess nativ (x86_64) und das Hauptfenster erscheint

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

### Requirement: Lokalisierung
Alle sichtbaren Texte der App MUST auf Deutsch und Englisch vorliegen. Die Sprache SHALL der Systemeinstellung folgen, mit Englisch als Rückfall.

#### Scenario: Deutsches System
- **WHEN** die bevorzugte Systemsprache Deutsch ist
- **THEN** erscheinen alle Texte der App auf Deutsch

#### Scenario: Nicht unterstützte Sprache
- **WHEN** die bevorzugte Systemsprache weder Deutsch noch Englisch ist
- **THEN** erscheinen alle Texte der App auf Englisch

### Requirement: Bereiche des Hauptfensters
Das Hauptfenster SHALL in der Werkzeugleiste einen Umschalter mit den Bereichen „Dateien konvertieren“ und „Gerät auslesen“ zeigen und darunter nur den gewählten Bereich. Das Menü „Darstellung“ SHALL beide Bereiche mit ⌘1 und ⌘2 anbieten. Die App SHALL den zuletzt gewählten Bereich beim nächsten Start wieder zeigen; beim ersten Start SHALL „Gerät auslesen“ gewählt sein.

#### Scenario: Erster Start
- **WHEN** die App zum ersten Mal startet
- **THEN** zeigt das Hauptfenster den Bereich „Gerät auslesen“, und im Umschalter ist dieser Bereich gewählt

#### Scenario: Bereich merken
- **WHEN** der Anwender „Dateien konvertieren“ wählt und die App neu startet
- **THEN** zeigt das Hauptfenster den Bereich „Dateien konvertieren“

#### Scenario: Tastenkürzel
- **WHEN** der Anwender im Bereich „Dateien konvertieren“ ⌘2 drückt
- **THEN** zeigt das Hauptfenster den Bereich „Gerät auslesen“
