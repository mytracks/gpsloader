## ADDED Requirements

### Requirement: GoPal im Katalog
Der Katalog des Pakets SHALL das Format `gopal` (Endung `trk`) enthalten. Der Eintrag für gpsbabel in `credits` SHALL auch Jürgen Neumann nennen.

#### Scenario: GoPal abfragen
- **WHEN** eine App den Katalog des Pakets abfragt
- **THEN** enthält er `gopal`, und der gpsbabel-Eintrag nennt Jürgen Neumann
