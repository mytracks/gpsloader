# app-shell Specification

## Purpose
Der App-Rahmen von gpsloader: Start auf allen unterstützten Macs, Hauptfenster mit dem Zustand der Laufzeitumgebung, Lizenzhinweise für mitgelieferte Fremdprogramme und Lokalisierung.

## Requirements

### Requirement: Unterstützte Systeme
Die App MUST auf macOS 12 und neuer starten, und zwar sowohl auf Apple-Silicon- als auch auf Intel-Macs nativ, ohne Rosetta für die App selbst.

#### Scenario: Start auf Apple Silicon
- **WHEN** die App auf einem Apple-Silicon-Mac mit macOS 12 oder neuer gestartet wird
- **THEN** läuft der App-Prozess nativ (arm64) und das Hauptfenster erscheint

#### Scenario: Start auf Intel
- **WHEN** die App auf einem Intel-Mac mit macOS 12 oder neuer gestartet wird
- **THEN** läuft der App-Prozess nativ (x86_64) und das Hauptfenster erscheint

### Requirement: Umgebungsstatus im Hauptfenster
Das Hauptfenster SHALL anzeigen, ob die gpsbabel-Laufzeit einsatzbereit ist. Ist sie es nicht, SHALL es den Grund nennen und, falls vorhanden, die Abhilfe anbieten (siehe `gpsbabel-runtime`).

#### Scenario: Laufzeit bereit
- **WHEN** die Prüfung der gpsbabel-Laufzeit erfolgreich war
- **THEN** zeigt das Hauptfenster den Status „bereit“ mit der gpsbabel-Version 1.7.0

#### Scenario: Rosetta fehlt
- **WHEN** die Prüfung ergibt, dass Rosetta auf einem Apple-Silicon-Mac fehlt
- **THEN** zeigt das Hauptfenster einen Hinweis, dass Geräte, die gpsbabel nutzen, erst nach der Installation von Rosetta funktionieren
- **AND** bietet eine Aktion zur Installation von Rosetta an

#### Scenario: gpsbabel defekt oder fehlt
- **WHEN** das gebündelte gpsbabel nicht gestartet werden kann und der Grund nicht fehlendes Rosetta ist
- **THEN** zeigt das Hauptfenster eine Fehlermeldung mit dem technischen Grund

### Requirement: Lizenzhinweise
Die App SHALL im Über-Fenster die Lizenzen der mitgelieferten Fremdprogramme anzeigen: gpsbabel unter der GNU GPL, Qt unter der GNU LGPL. Sie SHALL außerdem angeben, wo der zugehörige Quellcode erhältlich ist. Die vollständigen Lizenztexte MUST im App-Bundle enthalten sein.

#### Scenario: Über-Fenster öffnen
- **WHEN** der Anwender „Über gpsloader“ wählt
- **THEN** zeigt das Fenster die App-Version, die Copyright-Angabe sowie die Lizenzhinweise für gpsbabel 1.7.0 und Qt 5.12 mit Verweis auf die Quellcode-Bezugsquelle

#### Scenario: Lizenztexte im Bundle
- **WHEN** das ausgelieferte App-Bundle untersucht wird
- **THEN** enthält es die vollständigen Texte der GPL und der LGPL in den gültigen Versionen

### Requirement: Lokalisierung
Alle sichtbaren Texte der App MUST auf Deutsch und Englisch vorliegen. Die Sprache SHALL der Systemeinstellung folgen, mit Englisch als Rückfall.

#### Scenario: Deutsches System
- **WHEN** die bevorzugte Systemsprache Deutsch ist
- **THEN** erscheinen alle Texte der App auf Deutsch

#### Scenario: Nicht unterstützte Sprache
- **WHEN** die bevorzugte Systemsprache weder Deutsch noch Englisch ist
- **THEN** erscheinen alle Texte der App auf Englisch
