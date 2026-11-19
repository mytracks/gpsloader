## ADDED Requirements

### Requirement: Name der App
Die App MUST für Anwender „myTracks Loader“ heißen: im Finder, im Dock, im App-Menü und seinen Befehlen, in Fenstertiteln, im Über-Fenster, in allen Texten der Lokalisierung und in der Begründung von Systemdialogen. Das App-Bundle MUST `myTracks Loader.app` heißen. Die Bundle-ID MUST `info.stichling.gpsloader` bleiben, damit gespeicherte Einstellungen erhalten bleiben.

#### Scenario: App-Menü
- **WHEN** der Anwender das App-Menü öffnet
- **THEN** heißt es „myTracks Loader“, und es enthält „Über myTracks Loader“ und „myTracks Loader beenden“ (englisch „About myTracks Loader“ und „Quit myTracks Loader“)

#### Scenario: Kein alter Name sichtbar
- **WHEN** alle lokalisierten Texte der App und ihr Info.plist auf Deutsch und Englisch durchsucht werden
- **THEN** kommt „gpsloader“ in keinem sichtbaren Text vor, nur in Kennungen wie der Bundle-ID und der Adresse des Quellcodes

#### Scenario: Einstellungen bleiben
- **WHEN** eine Version mit dem neuen Namen auf einem Mac startet, auf dem eine frühere Version Gerät, Anschluss und Bereich gespeichert hat
- **THEN** zeigt die App dieselbe Auswahl wie zuvor

### Requirement: App-Icon
Die App SHALL ein Icon im Stil von myTracks Neo haben: einen senkrechten Verlauf von `#1A46DE` oben nach `#9F199C` unten und darauf einen weißen Satelliten in Linienzeichnung. Das Icon MUST in allen Größen vorliegen, die macOS 12 und neuer im Finder, im Dock und im Über-Fenster nutzen. Es MUST aus einer versionierten Quelle reproduzierbar erzeugt werden.

#### Scenario: Icon im Dock
- **WHEN** die App läuft
- **THEN** zeigt das Dock das Satelliten-Icon und nicht das allgemeine App-Symbol

#### Scenario: Über-Fenster
- **WHEN** der Anwender das Über-Fenster öffnet
- **THEN** zeigt es das App-Icon

#### Scenario: Reproduzierbar
- **WHEN** das Icon aus seiner Quelle neu erzeugt wird
- **THEN** stimmen die erzeugten Bilder mit denen im Repository überein

## MODIFIED Requirements

### Requirement: Lizenzhinweise
Die App SHALL im Über-Fenster angeben, dass sie unter der GNU GPL Version 3 oder später steht, und wo ihr Quellcode erhältlich ist. Sie SHALL außerdem GPSLoggerKit unter der MIT-Lizenz sowie die Urheber der Vorlagen portierter Formate und Treiber nennen, jeweils mit Quellcode-Bezugsquelle. Gpsbabel und Qt MUST sie nicht als mitgelieferte Programme nennen. Die Texte der GPL Version 3 und der MIT-Lizenz MUST im App-Bundle enthalten sein.

#### Scenario: Über-Fenster öffnen
- **WHEN** der Anwender „Über myTracks Loader“ wählt
- **THEN** zeigt das Fenster die App-Version, die Copyright-Angabe, die Lizenz der App mit Verweis auf ihren Quellcode und den Lizenzhinweis für GPSLoggerKit
- **AND** es erwähnt weder gpsbabel 1.7.0 noch Qt als mitgelieferte Programme

#### Scenario: Portierte Formate
- **WHEN** GPSLoggerKitGPL Formate oder Treiber mit Vorlagen enthält
- **THEN** nennt das Über-Fenster die Urheber dieser Vorlagen oder verweist auf eine mitgelieferte Liste, die sie nennt

#### Scenario: Lizenztexte im Bundle
- **WHEN** das ausgelieferte App-Bundle untersucht wird
- **THEN** enthält es die vollständigen Texte der GPL Version 3 und der MIT-Lizenz von GPSLoggerKit
- **AND** es enthält kein `Contents/Helpers` und kein Qt-Framework
