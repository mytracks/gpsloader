## ADDED Requirements

### Requirement: Locosys im Katalog
Der Katalog des Pakets SHALL die Formate `sbp` (Endung `sbp`) und `sbn` (Endung `sbn`) enthalten. Der Eintrag für gpsbabel in `credits` SHALL auch Rodney Lorrimar und Tom Hughes nennen.

#### Scenario: Locosys-Formate abfragen
- **WHEN** eine App den Katalog des Pakets abfragt
- **THEN** enthält er `sbp` und `sbn`, und der gpsbabel-Eintrag nennt Rodney Lorrimar
