## Purpose

Wie die App und die Pakete GPSLoggerKit und GPSLoggerKitGPL veröffentlicht werden: Versionen, Git-Tags, GitHub-Releases und die Einbindung der Pakete in die App per Version.

## ADDED Requirements

### Requirement: Eigene Repositories der Pakete
GPSLoggerKit und GPSLoggerKitGPL MUST je in einem eigenen öffentlichen GitHub-Repository liegen, mit der `Package.swift` im Wurzelverzeichnis, ihrer Lizenzdatei und ihrer Herkunftsliste. Das Repository von GPSLoggerKit MUST keinen Code aus GPL- oder CC-BY-SA-lizenziertem Quelltext enthalten, auch nicht in seiner Git-Historie.

#### Scenario: Paket per URL einbinden
- **WHEN** ein anderes Swift-Projekt GPSLoggerKit per Repository-URL mit einer veröffentlichten Version als Abhängigkeit angibt
- **THEN** lädt der Swift Package Manager das Paket und das Projekt baut, ohne weitere Teile des gpsloader-Repositorys

#### Scenario: Historie des MIT-Pakets
- **WHEN** die Git-Historie des Repositorys von GPSLoggerKit untersucht wird
- **THEN** enthält sie nur Dateien des Pakets und keine Dateien von GPSLoggerKitGPL, der App oder gpsbabel

### Requirement: Versionen
Die App und die Pakete SHALL Versionen nach Semantic Versioning führen, beginnend mit 0.1.0. Jede veröffentlichte Version MUST ein Git-Tag mit genau der Versionsnummer haben, etwa `0.1.0`. Ein veröffentlichtes Tag MUST NOT nachträglich verschoben werden.

#### Scenario: Erste Versionen
- **WHEN** die App und die Pakete zum ersten Mal veröffentlicht werden
- **THEN** tragen sie die Version 0.1.0, und das Tag `0.1.0` zeigt im jeweiligen Repository auf den veröffentlichten Commit

#### Scenario: Version der App
- **WHEN** das Info.plist der veröffentlichten App gelesen wird
- **THEN** stimmt `CFBundleShortVersionString` mit dem Tag des Releases überein

### Requirement: Pakete in der App per Version
Die App MUST GPSLoggerKit und GPSLoggerKitGPL über ihre Repository-URLs und veröffentlichte Versionen einbinden. Die aufgelösten Versionen MUST im Repository der App festgehalten sein, damit jeder Release-Build dieselben Paketstände nutzt. Solange die Pakete unter 1.0.0 sind, SHALL die App nur Versionen derselben Nebenversion zulassen, etwa 0.1.x.

#### Scenario: Reproduzierbarer Release-Build
- **WHEN** ein Release-Build der App aus einem sauberen Checkout erstellt wird
- **THEN** nutzt er genau die Paketversionen, die im Repository der App festgehalten sind

#### Scenario: Neue Nebenversion eines Pakets
- **WHEN** ein Paket die Version 0.2.0 veröffentlicht
- **THEN** übernimmt die App sie erst nach einer ausdrücklichen Änderung ihrer Abhängigkeit

### Requirement: GitHub-Release der App
Ein Release der App MUST auf GitHub im Repository der App erscheinen. Es MUST das Tag der Version, Release-Notes, das notarisierte ZIP und dessen SHA-256-Prüfsumme enthalten. Das Release-Skript SHALL es nur auf ausdrücklichen Aufruf anlegen. Vorher MUST es prüfen, dass der Commit sauber und gepusht ist und dass die Notarisierung gelungen ist. Versionen unter 1.0.0 MUST als Vorabversion („Pre-release“) erscheinen.

#### Scenario: Release anlegen
- **WHEN** der Entwickler das Release-Skript mit der Option zum Veröffentlichen aufruft und alle Prüfungen bestehen
- **THEN** gibt es auf GitHub ein Release zum Tag der Version mit den Release-Notes, dem ZIP und der Prüfsumme
- **AND** bei einer Version unter 1.0.0 ist es als Vorabversion markiert

#### Scenario: Ohne Option kein Release
- **WHEN** das Release-Skript ohne die Option zum Veröffentlichen läuft
- **THEN** entstehen ZIP und Prüfsumme lokal, aber weder ein Tag noch ein Release auf GitHub

#### Scenario: Notarisierung abgelehnt
- **WHEN** Apple die Notarisierung ablehnt
- **THEN** bricht das Skript ab, bevor ein Tag oder ein Release auf GitHub entsteht

#### Scenario: Version schon veröffentlicht
- **WHEN** es für die Version schon ein Tag oder ein Release gibt
- **THEN** bricht das Skript vor dem Build ab und verändert das bestehende Release nicht

#### Scenario: Release-Notes fehlen
- **WHEN** zur Version keine Release-Notes vorliegen
- **THEN** bricht das Skript vor dem Build ab

### Requirement: GitHub-Release der Pakete
Ein Release eines Pakets MUST auf GitHub im Repository des Pakets erscheinen, mit dem Tag der Version und Release-Notes. Vorher MUST das Release-Skript des Pakets prüfen, dass der Commit sauber und gepusht ist und die Tests bestehen. Bei GPSLoggerKit gehören dazu die Tests unter macOS und auf einem iOS-Simulator. Versionen unter 1.0.0 MUST als Vorabversion erscheinen.

#### Scenario: Paket veröffentlichen
- **WHEN** der Entwickler das Release-Skript eines Pakets aufruft und alle Prüfungen bestehen
- **THEN** gibt es im Repository des Pakets ein Tag und ein GitHub-Release zur Version mit den Release-Notes

#### Scenario: Tests schlagen fehl
- **WHEN** ein Test des Pakets fehlschlägt
- **THEN** entsteht weder ein Tag noch ein Release

### Requirement: Quellcode jeder Version der App
Zu jedem Release der App MUST der vollständige Quellcode öffentlich sein: der Commit des Tags im Repository der App und die Tags der eingebundenen Paketversionen in deren Repositories. Das Über-Fenster SHALL auf das Repository der App und auf das Repository von GPSLoggerKit verweisen.

#### Scenario: Quellcode zu einem Release
- **WHEN** ein Anwender den Quellcode zu einer veröffentlichten Version der App sucht
- **THEN** findet er im Repository der App das Tag dieser Version, und dessen `Package.resolved` nennt die Tags der Pakete, die in ihren öffentlichen Repositories liegen
