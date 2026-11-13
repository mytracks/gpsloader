# Delta für logger-kit

## MODIFIED Requirements

### Requirement: Formatkatalog
Das Paket SHALL einen Katalog aller unterstützten Dateiformate bereitstellen. Jedes Format SHALL eine feste Kennung, einen lokalisierten Namen und die typischen Dateiendungen haben.

#### Scenario: Katalog abfragen
- **WHEN** eine App den Katalog abfragt
- **THEN** enthält er mindestens diese Formate mit ihren Dateiendungen:
  - NMEA 0183 (Kennung `nmea`)
  - GPX (Kennung `gpx`)
  - IGC (Kennung `igc`)
  - Garmin FIT (Kennung `fit`)
  - TCX (Kennung `tcx`)
  - Suunto SML (Kennung `suunto-sml`)

### Requirement: Fehler und Warnungen
Ist eine Datei gar nicht lesbar oder enthält sie kein einziges verwertbares Element, MUST das Einlesen mit einem Fehler enden. Der Fehler nennt die Datei und, wenn möglich, die Position. Einzelne beschädigte Stellen SHALL das Einlesen nicht abbrechen; sie SHALL als zusammengefasste Warnungen mit Anzahl zurückgegeben werden. Meldungen MUST auf Deutsch und Englisch vorliegen.

#### Scenario: Teilweise beschädigte Datei
- **WHEN** eine Datei 1000 gültige und 3 beschädigte Datensätze enthält
- **THEN** enthält die Aufzeichnung 1000 Punkte, und eine Warnung meldet 3 übersprungene Datensätze

#### Scenario: Leere Datei
- **WHEN** eine Datei leer ist
- **THEN** endet das Einlesen mit einem Fehler, der die Datei nennt

## ADDED Requirements

### Requirement: Warnungen bei Binärdateien
Bei Binärformaten SHALL zwei Fälle je eine eigene Warnung ergeben, die die Datei nennt: eine falsche Prüfsumme der ganzen Datei, deren Inhalt trotzdem gelesen wurde, und eine vorzeitig endende Datei, deren lesbarer Anfang übernommen wurde. Die Meldungen MUST auf Deutsch und Englisch vorliegen.

#### Scenario: Unvollständige Binärdatei
- **WHEN** eine Binärdatei nach der Hälfte endet
- **THEN** enthält die Aufzeichnung die Punkte der ersten Hälfte, und eine Warnung nennt die Datei als unvollständig

#### Scenario: Falsche Prüfsumme
- **WHEN** die Prüfsumme einer sonst lesbaren Binärdatei nicht stimmt
- **THEN** enthält die Aufzeichnung alle Punkte der Datei, und eine Warnung nennt die Datei
