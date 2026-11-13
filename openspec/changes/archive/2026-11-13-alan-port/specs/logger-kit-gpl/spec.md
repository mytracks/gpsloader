## ADDED Requirements

### Requirement: Alan Map500 im Katalog
Der Katalog des Pakets SHALL das Format `alantrl` (Endung `trl`) enthalten. Der Eintrag für gpsbabel in `credits` SHALL auch Gunar Megger nennen.

#### Scenario: Alan-Format abfragen
- **WHEN** eine App den Katalog des Pakets abfragt
- **THEN** enthält er `alantrl`, und der gpsbabel-Eintrag nennt Gunar Megger
