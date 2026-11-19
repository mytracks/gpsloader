## MODIFIED Requirements

### Requirement: GPX-1.1-Konformität
Erzeugte Dateien MUST gültiges GPX 1.1 nach dem Schema `http://www.topografix.com/GPX/1/1` in UTF-8 sein. Das `creator`-Attribut SHALL „myTracks Loader“ und die App-Version enthalten, etwa „myTracks Loader 0.1.0“. Erweiterungen, insbesondere die von myTracks, SHALL die Datei nicht enthalten.

#### Scenario: Validierung gegen das Schema
- **WHEN** eine erzeugte Datei gegen das GPX-1.1-XSD geprüft wird
- **THEN** ist sie gültig

#### Scenario: Keine Erweiterungen
- **WHEN** eine Datei erzeugt wird
- **THEN** enthält sie kein `extensions`-Element

#### Scenario: Creator
- **WHEN** die App in Version 0.1.0 eine Datei erzeugt
- **THEN** lautet ihr `creator`-Attribut „myTracks Loader 0.1.0“
