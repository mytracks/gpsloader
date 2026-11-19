# mtk-device Specification

## Purpose
Die Einträge der MTK-Logger (iBlue 747, Qstarz u. a.) und der Holux M-241 und GPSport 245 im Gerätekatalog der App. Das Geräteprotokoll liegt in GPSLoggerKitGPL (https://github.com/mytracks/GPSLoggerKitGPL, Spec `mtk-device` dort).

## Requirements

### Requirement: MTK-Geräte im Katalog
Der Gerätekatalog SHALL die MTK-Geräte der Alt-App mit 115200 Baud und die Holux-Geräte mit 38400 Baud enthalten und Löschen anbieten.

#### Scenario: MTK-Geräte im Katalog
- **WHEN** der Anwender die Geräteliste öffnet
- **THEN** enthält sie neun MTK- und zwei Holux-Geräte
