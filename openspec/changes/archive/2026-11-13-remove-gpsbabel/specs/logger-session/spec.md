## REMOVED Requirements

### Requirement: Abbruch
**Reason**: Das Szenario „Abbruch bei laufendem gpsbabel“ entfällt mit gpsbabel. Es gibt keine gestarteten Prozesse mehr.
**Migration**: Ersetzt durch „Abbruch eines Vorgangs“ ohne Prozesse.

### Requirement: Einheitliche Fehlermeldungen
**Reason**: Die Fehlerarten „Rosetta fehlt“ und „gpsbabel-Fehler“ entfallen mit gpsbabel.
**Migration**: Ersetzt durch „Fehlermeldungen der Sitzung“ mit den verbleibenden Fehlerarten.

## ADDED Requirements

### Requirement: Abbruch eines Vorgangs
Der Anwender MUST jeden laufenden Vorgang abbrechen können. Nach einem Abbruch SHALL die Sitzung alle Geräteverbindungen innerhalb von 5 Sekunden freigeben. Teilergebnisse SHALL sie verwerfen.

#### Scenario: Abbruch beim Auslesen
- **WHEN** der Anwender während des Auslesens „Abbrechen“ wählt
- **THEN** endet der Vorgang mit dem Status „abgebrochen“
- **AND** es wird keine GPX-Datei geschrieben
- **AND** der serielle Port ist anschließend wieder frei

### Requirement: Fehlermeldungen der Sitzung
Die Sitzung SHALL Fehler als verständliche, lokalisierte Meldung mit Fehlerart und technischem Detail ausgeben. Fehlerarten sind: Gerät nicht gefunden, Port belegt, Zeitüberschreitung, Protokollfehler, Schreibfehler, abgebrochen.

#### Scenario: Port belegt
- **WHEN** der gewählte serielle Port bereits von einem anderen Programm geöffnet ist
- **THEN** meldet die Sitzung „Port belegt“ mit dem Portnamen

#### Scenario: Protokollfehler
- **WHEN** ein Treiber eine unerwartete Antwort des Geräts meldet
- **THEN** meldet die Sitzung „Protokollfehler“ und zeigt die Meldung des Treibers als Detail
