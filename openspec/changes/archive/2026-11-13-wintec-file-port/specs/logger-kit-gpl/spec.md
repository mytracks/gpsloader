## ADDED Requirements

### Requirement: Wintec im Katalog
Der Katalog des Pakets SHALL die Formate `wintec-tes` (Endung `tes`), `wbt-bin` (Endung `bin`) und `wbt-tk1` (Endung `tk1`) enthalten. Der Eintrag für gpsbabel in `credits` SHALL auch Robert Lipe als Urheber der Vorlage `wintec_tes.cc` nennen.

#### Scenario: Wintec-Formate abfragen
- **WHEN** eine App den Katalog des Pakets abfragt
- **THEN** enthält er `wintec-tes`, `wbt-bin` und `wbt-tk1`, und der gpsbabel-Eintrag nennt Robert Lipe
