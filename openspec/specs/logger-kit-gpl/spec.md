# logger-kit-gpl Specification

## Purpose
GPSLoggerKitGPL ist das Swift-Paket von gpsloader für Dateiformate und Logger-Protokolle, die aus Quelltext unter der GPL oder einer damit vereinbaren Lizenz portiert werden. Es ergänzt das MIT-lizenzierte GPSLoggerKit, ohne dessen Clean-Room-Regel zu berühren.

## Requirements

### Requirement: Lizenz des Pakets
Das Paket MUST unter der GNU GPL Version 3 oder später (GPL-3.0-or-later) stehen und den vollständigen Lizenztext als Lizenzdatei enthalten. Die README des Pakets SHALL die Lizenz nennen und erklären, dass jede App, die das Paket einbindet, als Ganzes unter die GPL fällt.

#### Scenario: Lizenzdatei
- **WHEN** der Ordner des Pakets untersucht wird
- **THEN** enthält er eine Lizenzdatei mit dem Text der GPL Version 3, und die README nennt GPL-3.0-or-later

### Requirement: Plattform und Abhängigkeiten
Das Paket MUST unter macOS ab Version 12 bauen und laufen. Es MUST nur von GPSLoggerKit und den Systembibliotheken abhängen, nicht von GPSLoaderKit, der App oder Paketen von Drittanbietern. GPSLoggerKit MUST umgekehrt nicht von diesem Paket abhängen.

#### Scenario: Bauen mit GPSLoggerKit allein
- **WHEN** die Ordner `Packages/GPSLoggerKitGPL` und `Packages/GPSLoggerKit` gemeinsam an einen anderen Ort kopiert werden und das GPL-Paket dort gebaut und getestet wird
- **THEN** gelingen Build und Tests

#### Scenario: Keine Rückabhängigkeit
- **WHEN** GPSLoggerKit allein gebaut wird
- **THEN** gelingt der Build, ohne dass das GPL-Paket vorhanden ist

### Requirement: Formatkatalog des Pakets
Das Paket SHALL einen eigenen Katalog seiner Formate bereitstellen, der sich mit dem Katalog von GPSLoggerKit zusammensetzen lässt. Jedes Format SHALL eine feste Kennung, einen lokalisierten Namen auf Deutsch und Englisch und die typischen Dateiendungen haben. Eine Kennung MUST sich von allen Kennungen in GPSLoggerKit unterscheiden. Der Katalog darf leer sein.

#### Scenario: Leerer Katalog
- **WHEN** das Paket noch kein Format enthält und eine App seinen Katalog mit dem von GPSLoggerKit zusammensetzt
- **THEN** enthält das Ergebnis genau die Formate von GPSLoggerKit

#### Scenario: Eindeutige Kennungen
- **WHEN** die Tests des Pakets laufen
- **THEN** prüft ein Test, dass keine Kennung des Pakets auch in GPSLoggerKit vorkommt

### Requirement: Zulässige Quellen
Portierter Code MUST aus Quellen stammen, deren Lizenz mit GPL-3.0-or-later vereinbar ist. Dazu gehören GPL Version 2 oder später, GPL Version 3, LGPL Version 2.1 oder später, CC BY-SA 4.0 sowie freizügige Lizenzen wie MIT, BSD, Apache 2.0 und Public Domain. Quellen unter GPL nur Version 2, unter CC BY-SA bis Version 3.0, unter eigenen Lizenzen oder ohne erkennbare Lizenz MUST NOT verwendet werden, solange die Urheber keine vereinbare Lizenz erteilen.

#### Scenario: Quelle nur unter GPLv2
- **WHEN** eine Vorlage ausschließlich unter der GPL Version 2 steht
- **THEN** wird sie nicht portiert, und das Design der Familie nennt den Grund

#### Scenario: Eigene Lizenz der Vorlage
- **WHEN** eine Vorlage eine eigene Lizenz hat, die keine vereinbare Lizenz ausdrücklich erteilt
- **THEN** wird sie nicht portiert, und die Familie wird aus Black-Box-Beobachtung umgesetzt

### Requirement: Herkunft portierter Formate
Für jedes Format MUST die Herkunftsliste des Pakets die Vorlagen nennen: Projekt, Datei, Version oder Commit, Urheber und Lizenz. Sie MUST auch eigene Ergänzungen, Spezifikationen und Black-Box-Beobachtungen nennen. Jede Quelldatei, die aus einer Vorlage portiert ist, MUST einen Kopf mit den Urheberhinweisen der Vorlage, ihrer Lizenz und dem Hinweis tragen, dass sie für gpsloader übersetzt und verändert wurde, mit Datum.

#### Scenario: Neues Format
- **WHEN** ein Format zum Katalog des Pakets hinzukommt
- **THEN** führt die Herkunftsliste dieses Format mit seinen Vorlagen auf, und ein Test schlägt fehl, solange der Eintrag fehlt

#### Scenario: Portierte Datei
- **WHEN** eine Quelldatei aus einer Vorlage übersetzt wurde
- **THEN** nennt ihr Kopf die Urheber der Vorlage, deren Lizenz und die Veränderung durch gpsloader mit Datum

### Requirement: Trennung von GPSLoggerKit
Eine Logger-Familie SHALL entweder in GPSLoggerKit (Clean-Room) oder in diesem Paket (Portierung) umgesetzt werden, nicht in beiden. Wurde für eine Familie Quelltext unter einer Copyleft-Lizenz gelesen, MUST sie in diesem Paket bleiben. Die Zuordnung jeder Familie MUST im Projektkontext festgehalten sein.

#### Scenario: Familie mit gelesenem GPL-Quelltext
- **WHEN** für eine Familie gpsbabel-Quelltext gelesen wurde
- **THEN** gibt es für diese Familie keinen Code in GPSLoggerKit, und der Projektkontext ordnet sie GPSLoggerKitGPL zu

### Requirement: Katalog portierter Formate
Der Katalog des Pakets SHALL jedes portierte Format genau einmal enthalten, in der Reihenfolge, in der die Formate aufgenommen wurden. Zu jeder Vorlage SHALL `credits` einen Eintrag mit Projekt, Urhebern, Lizenz und Bezugsquelle des Quellcodes der verwendeten Version enthalten.

#### Scenario: SkyTraq im Katalog
- **WHEN** eine App den Katalog des Pakets abfragt
- **THEN** enthält er das Format `skytraq-bin` (Endung `bin`), und `credits` nennt gpsbabel mit der Lizenz GPL-2.0-or-later und der Adresse des Tags `gpsbabel_1_7_0`

### Requirement: MTK im Katalog
Der Katalog des Pakets SHALL die Formate `mtk-bin` und `m241-bin` (Endung `bin`) enthalten. Der Eintrag für gpsbabel in `credits` SHALL auch die Urheber der Vorlage `mtk_logger.cc` nennen.

#### Scenario: MTK-Formate abfragen
- **WHEN** eine App den Katalog des Pakets abfragt
- **THEN** enthält er `mtk-bin` und `m241-bin`, und der gpsbabel-Eintrag in `credits` nennt Per Borgentun

### Requirement: Wintec im Katalog
Der Katalog des Pakets SHALL die Formate `wintec-tes` (Endung `tes`), `wbt-bin` (Endung `bin`) und `wbt-tk1` (Endung `tk1`) enthalten. Der Eintrag für gpsbabel in `credits` SHALL auch Robert Lipe als Urheber der Vorlage `wintec_tes.cc` nennen.

#### Scenario: Wintec-Formate abfragen
- **WHEN** eine App den Katalog des Pakets abfragt
- **THEN** enthält er `wintec-tes`, `wbt-bin` und `wbt-tk1`, und der gpsbabel-Eintrag nennt Robert Lipe

### Requirement: Locosys im Katalog
Der Katalog des Pakets SHALL die Formate `sbp` (Endung `sbp`) und `sbn` (Endung `sbn`) enthalten. Der Eintrag für gpsbabel in `credits` SHALL auch Rodney Lorrimar und Tom Hughes nennen.

#### Scenario: Locosys-Formate abfragen
- **WHEN** eine App den Katalog des Pakets abfragt
- **THEN** enthält er `sbp` und `sbn`, und der gpsbabel-Eintrag nennt Rodney Lorrimar

### Requirement: GoPal im Katalog
Der Katalog des Pakets SHALL das Format `gopal` (Endung `trk`) enthalten. Der Eintrag für gpsbabel in `credits` SHALL auch Jürgen Neumann nennen.

#### Scenario: GoPal abfragen
- **WHEN** eine App den Katalog des Pakets abfragt
- **THEN** enthält er `gopal`, und der gpsbabel-Eintrag nennt Jürgen Neumann

### Requirement: Geräteprotokolle
Das Paket SHALL für Geräteprotokolle eine eigene Verbindungs-Schnittstelle (schreiben, lesen mit Zeitlimit, bis zu einem Endezeichen lesen, Eingang verwerfen, Baudrate wechseln) und einen Treibervertrag (auslesen, löschen, Fortschritt) bereitstellen. Es SHALL dafür von nichts außer GPSLoggerKit abhängen. Jeder Treiber SHALL ohne Hardware gegen ein simuliertes Gerät testbar sein.

#### Scenario: Simuliertes Gerät
- **WHEN** ein Test einen Treiber mit einer simulierten Verbindung ausführt
- **THEN** läuft er ohne seriellen Anschluss und liefert die Aufzeichnung des simulierten Geräts

### Requirement: igotu2gpx in den Credits
`credits` SHALL igotu2gpx mit Michael Hofmann, der Lizenz GPL-3.0-or-later und der Adresse der Version 0.3.0 nennen.

#### Scenario: Credits mit igotu2gpx
- **WHEN** das Über-Fenster die portierten Formate und Protokolle auflistet
- **THEN** erscheinen GPSBabel und igotu2gpx

### Requirement: Magellan im Katalog
Der Katalog des Pakets SHALL das Format `magellan` mit den Endungen `log`, `upt` und `rte` enthalten.

#### Scenario: Magellan-Format abfragen
- **WHEN** eine App den Katalog des Pakets abfragt
- **THEN** enthält er `magellan` mit den Endungen `log`, `upt` und `rte`

### Requirement: Alan Map500 im Katalog
Der Katalog des Pakets SHALL das Format `alantrl` (Endung `trl`) enthalten. Der Eintrag für gpsbabel in `credits` SHALL auch Gunar Megger nennen.

#### Scenario: Alan-Format abfragen
- **WHEN** eine App den Katalog des Pakets abfragt
- **THEN** enthält er `alantrl`, und der gpsbabel-Eintrag nennt Gunar Megger
