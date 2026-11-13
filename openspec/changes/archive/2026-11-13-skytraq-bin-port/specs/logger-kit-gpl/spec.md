## ADDED Requirements

### Requirement: Katalog portierter Formate
Der Katalog des Pakets SHALL jedes portierte Format genau einmal enthalten, in der Reihenfolge, in der die Formate aufgenommen wurden. Zu jeder Vorlage SHALL `credits` einen Eintrag mit Projekt, Urhebern, Lizenz und Bezugsquelle des Quellcodes der verwendeten Version enthalten.

#### Scenario: SkyTraq im Katalog
- **WHEN** eine App den Katalog des Pakets abfragt
- **THEN** enthält er das Format `skytraq-bin` (Endung `bin`), und `credits` nennt gpsbabel mit der Lizenz GPL-2.0-or-later und der Adresse des Tags `gpsbabel_1_7_0`
