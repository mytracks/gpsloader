## REMOVED Requirements

### Requirement: Inhalt der Aufzeichnung
**Reason**: Die Aufzeichnung von gpsbabel-Aufrufen (Argumente, Ausgaben, Exit-Code) entfällt mit gpsbabel.
**Migration**: Ersetzt durch „Inhalt des Mitschnitts“ ohne Prozessaufrufe.

## ADDED Requirements

### Requirement: Inhalt des Mitschnitts
Eine Aufzeichnung MUST enthalten:
- Kopfdaten: App-Version, macOS-Version, Architektur, ob unter Rosetta, Treiber, Port und Parameter
- alle gesendeten und empfangenen Bytes in der tatsächlichen Reihenfolge, je mit Zeitstempel in Millisekunden
- Ereignisse wie Öffnen, Schließen, Zeitüberschreitung, Abbruch und Fehler

#### Scenario: Serieller Dialog
- **WHEN** ein Treiber bei eingeschaltetem Mitschnitt 16 Bytes sendet und 3 Bytes empfängt
- **THEN** enthält die Aufzeichnung einen Eintrag „gesendet“ mit den 16 Bytes und danach einen Eintrag „empfangen“ mit den 3 Bytes, jeweils mit Zeitstempel

#### Scenario: App unter Rosetta
- **WHEN** der Anwender die App selbst unter Rosetta gestartet hat und einen Vorgang aufzeichnet
- **THEN** vermerken die Kopfdaten, dass die App unter Rosetta läuft
