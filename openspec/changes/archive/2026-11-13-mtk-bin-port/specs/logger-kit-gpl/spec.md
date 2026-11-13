## ADDED Requirements

### Requirement: MTK im Katalog
Der Katalog des Pakets SHALL die Formate `mtk-bin` und `m241-bin` (Endung `bin`) enthalten. Der Eintrag für gpsbabel in `credits` SHALL auch die Urheber der Vorlage `mtk_logger.cc` nennen.

#### Scenario: MTK-Formate abfragen
- **WHEN** eine App den Katalog des Pakets abfragt
- **THEN** enthält er `mtk-bin` und `m241-bin`, und der gpsbabel-Eintrag in `credits` nennt Per Borgentun
