## ADDED Requirements

### Requirement: Magellan im Katalog
Der Katalog des Pakets SHALL das Format `magellan` mit den Endungen `log`, `upt` und `rte` enthalten.

#### Scenario: Magellan-Format abfragen
- **WHEN** eine App den Katalog des Pakets abfragt
- **THEN** enthält er `magellan` mit den Endungen `log`, `upt` und `rte`
