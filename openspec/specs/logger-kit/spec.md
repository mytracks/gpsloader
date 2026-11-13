# logger-kit Specification

## Purpose
GPSLoggerKit ist eine eigenständige, MIT-lizenzierte Swift-Bibliothek. Sie liest Dateiformate und später Logger-Protokolle nativ ein und bildet daraus ein gemeinsames Datenmodell. Sie läuft unter macOS und iOS/iPadOS.

## Requirements

### Requirement: Unterstützte Plattformen
Das Paket MUST unter macOS ab Version 12 und unter iOS/iPadOS ab Version 27 bauen und laufen. Alle Dateiformate und die GPX-Ausgabe SHALL auf beiden Plattformen verfügbar sein. Funktionen, die es nur unter macOS geben kann, wie Gerätetransporte, MUST so abgegrenzt sein, dass der iOS-Build ohne sie gelingt.

#### Scenario: Tests auf dem iOS-Simulator
- **WHEN** die Tests des Pakets auf einem iOS-27-Simulator ausgeführt werden
- **THEN** bauen und bestehen sie wie unter macOS. Ausgenommen sind nur Prüfungen, die macOS-eigene Werkzeuge brauchen, etwa die XSD-Validierung

#### Scenario: Bauen für macOS 12
- **WHEN** das Paket mit Deployment Target macOS 12 gebaut wird
- **THEN** gelingt der Build ohne Warnungen zur Verfügbarkeit

### Requirement: Eigenständigkeit
Das Paket MUST ohne andere Teile des gpsloader-Repositorys und ohne Pakete von Drittanbietern bauen. Es darf nur die Systembibliotheken der Plattform nutzen.

#### Scenario: Herausgelöst bauen
- **WHEN** der Ordner `Packages/GPSLoggerKit` allein an einen anderen Ort kopiert und dort gebaut und getestet wird
- **THEN** gelingen Build und Tests

### Requirement: Lizenz und Herkunft
Das Paket MUST unter der MIT-Lizenz stehen und eine Lizenzdatei enthalten. Es MUST keinen Code enthalten, der aus GPL- oder CC-BY-SA-lizenziertem Quelltext übersetzt oder kopiert wurde. Für jedes Format MUST die Dokumentation des Pakets die verwendeten Grundlagen nennen: Spezifikationen, eigener Code oder Black-Box-Beobachtung.

#### Scenario: Herkunftsnachweis
- **WHEN** ein Format zum Paket hinzukommt
- **THEN** führt die Herkunftsliste des Pakets dieses Format mit seinen Grundlagen auf

### Requirement: Datenmodell
Das Paket SHALL Aufzeichnungen als Tracks aus Segmenten mit Trackpunkten sowie als Wegpunkte darstellen. Ein Punkt SHALL Breite und Länge (WGS 84) haben. Optional SHALL er Höhe, Zeit (absoluter Zeitpunkt), Geschwindigkeit, Kurs, Anzahl Satelliten, HDOP, VDOP, PDOP und Fix-Art (keine, 2D, 3D, DGPS) haben. Wegpunkte SHALL zusätzlich Name und Kommentar haben können.

#### Scenario: Punkt nur mit Koordinaten
- **WHEN** ein Format nur Breite und Länge liefert
- **THEN** sind alle übrigen Angaben des Punkts leer, nicht mit 0 belegt

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
  - KML und KMZ (Kennung `kml`, Endungen `kml` und `kmz`)
  - Columbus V-900 (Kennung `v900`, Endung `csv`)
  - iBlue-CSV (Kennung `iblue-csv`, Endung `csv`)

### Requirement: Formaterkennung
Das Paket SHALL zu einer Datei anhand ihres Inhalts das passende Format vorschlagen. Die Dateiendung SHALL dabei nur als Hinweis dienen. Erkennt kein Format den Inhalt, SHALL das Ergebnis „unbekannt“ lauten.

#### Scenario: NMEA mit falscher Endung
- **WHEN** eine NMEA-Datei die Endung `.txt` hat
- **THEN** schlägt die Erkennung NMEA 0183 vor

#### Scenario: Unbekannter Inhalt
- **WHEN** eine Datei ein JPEG-Bild enthält
- **THEN** lautet das Ergebnis „unbekannt“

### Requirement: Mehrere Dateien einlesen
Ein Format SHALL eine oder mehrere Dateien zu einer gemeinsamen Aufzeichnung einlesen. Die Reihenfolge der Dateien SHALL der Reihenfolge der Übergabe entsprechen.

#### Scenario: Zwei Dateien
- **WHEN** zwei Dateien desselben Formats gemeinsam eingelesen werden
- **THEN** enthält die Aufzeichnung die Punkte beider Dateien in der Reihenfolge der Übergabe

### Requirement: Fehler und Warnungen
Ist eine Datei gar nicht lesbar oder enthält sie kein einziges verwertbares Element, MUST das Einlesen mit einem Fehler enden. Der Fehler nennt die Datei und, wenn möglich, die Position. Einzelne beschädigte Stellen SHALL das Einlesen nicht abbrechen; sie SHALL als zusammengefasste Warnungen mit Anzahl zurückgegeben werden. Meldungen MUST auf Deutsch und Englisch vorliegen.

#### Scenario: Teilweise beschädigte Datei
- **WHEN** eine Datei 1000 gültige und 3 beschädigte Datensätze enthält
- **THEN** enthält die Aufzeichnung 1000 Punkte, und eine Warnung meldet 3 übersprungene Datensätze

#### Scenario: Leere Datei
- **WHEN** eine Datei leer ist
- **THEN** endet das Einlesen mit einem Fehler, der die Datei nennt

### Requirement: Warnungen bei Binärdateien
Bei Binärformaten SHALL zwei Fälle je eine eigene Warnung ergeben, die die Datei nennt: eine falsche Prüfsumme der ganzen Datei, deren Inhalt trotzdem gelesen wurde, und eine vorzeitig endende Datei, deren lesbarer Anfang übernommen wurde. Die Meldungen MUST auf Deutsch und Englisch vorliegen.

#### Scenario: Unvollständige Binärdatei
- **WHEN** eine Binärdatei nach der Hälfte endet
- **THEN** enthält die Aufzeichnung die Punkte der ersten Hälfte, und eine Warnung nennt die Datei als unvollständig

#### Scenario: Falsche Prüfsumme
- **WHEN** die Prüfsumme einer sonst lesbaren Binärdatei nicht stimmt
- **THEN** enthält die Aufzeichnung alle Punkte der Datei, und eine Warnung nennt die Datei

### Requirement: Abbruch
Das Einlesen MUST sich abbrechen lassen. Nach einem Abbruch SHALL das Einlesen spätestens nach dem nächsten Datenblock mit dem Ergebnis „abgebrochen“ enden, ohne Teilergebnis.

#### Scenario: Große Datei abbrechen
- **WHEN** das Einlesen einer 50-MB-Datei abgebrochen wird
- **THEN** endet es zeitnah mit „abgebrochen“

### Requirement: Korrektur des GPS-Wochenüberlaufs
Liegt die Zeit eines Punkts mehr als 512 Wochen vor einem Bezugszeitpunkt, SHALL das Paket sie wiederholt um 1024 Wochen verschieben, bis die Bedingung nicht mehr gilt. Standardmäßig ist der Bezugszeitpunkt die aktuelle Zeit. Die Korrektur SHALL standardmäßig aktiv und abschaltbar sein.

#### Scenario: Logger mit Wochenüberlauf
- **WHEN** ein Punkt die Zeit 15. März 2007 hat und der Bezugszeitpunkt der 3. November 2026 ist
- **THEN** hat der Punkt nach der Korrektur die Zeit 29. Oktober 2026 (plus 1024 Wochen)

#### Scenario: Korrektur abgeschaltet
- **WHEN** die Korrektur abgeschaltet ist
- **THEN** bleiben alle Zeiten unverändert

### Requirement: Wegpunkte als Track
Enthält eine eingelesene Aufzeichnung keine Trackpunkte, aber Wegpunkte, SHALL das Paket auf Wunsch aus den Wegpunkten in ihrer Reihenfolge einen Track bilden. Die Wegpunkte bleiben dabei erhalten.

#### Scenario: Datei nur mit Wegpunkten
- **WHEN** eine Datei nur 20 Wegpunkte enthält und die Umwandlung gewünscht ist
- **THEN** enthält die Aufzeichnung einen Track mit 20 Punkten sowie die 20 Wegpunkte

### Requirement: Erweiterbarer Formatkatalog
Das Paket SHALL einen Katalog aus seinen eigenen Formaten und zusätzlichen Formaten anderer Pakete bilden können. Erkennung, Suche nach Kennung und Einlesen SHALL auf einem solchen Katalog genauso arbeiten wie auf dem eigenen. Die eigenen Formate SHALL dabei vorn stehen. Eine doppelte Kennung MUST beim Bilden des Katalogs als Programmierfehler gelten. Das Paket MUST dafür keine Kenntnis der anderen Pakete haben.

#### Scenario: Zusätzliches Format erkennen
- **WHEN** ein Katalog aus den eigenen Formaten und einem zusätzlichen Testformat gebildet wird und eine Datei dieses Testformats geprüft wird
- **THEN** schlägt die Erkennung das Testformat vor, und eine NMEA-Datei wird weiterhin als NMEA 0183 erkannt

#### Scenario: Standardkatalog unverändert
- **WHEN** eine App den Katalog wie bisher ohne Zusätze abfragt
- **THEN** enthält er genau die eigenen Formate des Pakets

### Requirement: Geräteschnittstelle
Das Paket SHALL eine plattformneutrale Schnittstelle für Logger-Protokolle bereitstellen. Sie besteht aus einer Verbindung (schreiben, lesen mit Zeitlimit, bis zu einem Endezeichen lesen, Eingang verwerfen, Baudrate wechseln) und einem Treibervertrag (auslesen, löschen, Löschunterstützung, Fortschritt). Treiber, die auf ihr aufbauen, SHALL ohne Hardware gegen ein simuliertes Gerät testbar sein und unter iOS bauen.

#### Scenario: Treiber mit simuliertem Gerät
- **WHEN** ein Test den GNS-2000-Treiber mit einer simulierten Verbindung ausführt
- **THEN** läuft er ohne Bluetooth und liefert die Aufzeichnung des simulierten Geräts

#### Scenario: iOS-Build mit Treibern
- **WHEN** das Paket für iOS gebaut wird
- **THEN** gelingt der Build mitsamt Geräteschnittstelle und GNS-2000-Treiber
