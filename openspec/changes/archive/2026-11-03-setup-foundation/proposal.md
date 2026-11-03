# Proposal: setup-foundation

## Why

gpsloader soll die Logger-Funktionen aus myTracks ablösen. Bisher existiert jedoch weder ein Projekt noch Code.
Bevor der erste Treiber entstehen kann, braucht es ein tragfähiges Fundament, auf dem alle weiteren Changes aufbauen:

- eine lauffähige, signierbare App für macOS 12 und neuer
- eine einheitliche Abwicklung von Auslesevorgängen
- serielle Kommunikation
- das gebündelte gpsbabel 1.7.0 samt Rosetta-Prüfung
- GPX-Ausgabe
- ein Diagnose-Mitschnitt

Diese Teile werden zuerst gebaut, weil jeder spätere Treiber sie benötigt. So entstehen sie einmal, einheitlich und testbar, statt pro Treiber neu.

## What Changes

- Neues Projekt-Gerüst:
  - Xcode-Projekt per XcodeGen (`project.yml`), AppKit-App, Swift 6 Language Mode mit Strict Concurrency
  - Deployment Target macOS 12, Universal Binary. Ursprünglich war macOS 11 geplant; das macOS-27-SDK von Xcode 27.1 unterstützt aber erst ab macOS 12. Entscheidung des Entwicklers vom 2026-11-02.
  - lokales Swift-Package mit UI-unabhängigen Modulen und Tests
- **App-Rahmen**:
  - Hauptfenster mit Statusanzeige der Laufzeitumgebung (gpsbabel/Rosetta)
  - Über-Fenster mit Lizenzhinweisen für gpsbabel (GPL) und Qt (LGPL), samt Hinweis auf den Quellcode
  - Lokalisierung Deutsch/Englisch
- **Auslese-Sitzung**:
  - gemeinsames Treiber-Protokoll für Auslesen und Löschen: asynchron, abbrechbar, mit Fortschritt und einheitlichen Fehlern
  - Ergebnis wird als GPX-Datei gespeichert
  - Löschen nur nach ausdrücklicher Bestätigung
- **Serieller Transport**:
  - Ermittlung der seriellen Ports (`/dev/cu.*`)
  - Öffnen mit Baudrate/8N1, Lesen mit Timeout, Schreiben, Abbruch
  - austauschbar gegen einen Mock-Transport für Tests
- **gpsbabel-Laufzeit**:
  - gpsbabel 1.7.0 (x86_64) und `QtCoreGpsBabel.framework` werden aus der myTracks-Historie übernommen, im Bundle mitgeliefert und mit eigener Signatur und Hardened Runtime versehen
  - Aufruf als Prozess mit Argument-Array, Erfassung von stdout/stderr, Abbruch und Timeout
  - Erkennung von fehlendem Rosetta mit verständlicher Erklärung und Installationsangebot
- **GPX-Export**:
  - GPX 1.1 mit Tracks, Segmenten und Wegpunkten
  - Zeiten in UTC, ohne myTracks-Extensions
  - deterministische, gebietsschema-unabhängige Ausgabe
- **Diagnose-Mitschnitt**:
  - zeichnet auf Wunsch alle gesendeten und empfangenen Bytes, gpsbabel-Aufrufe und deren Ausgaben mit Zeitstempel auf
  - Export als Datei, die Anwender dem Entwickler schicken können
  - lässt sich in Tests als Gerätedialog wiedergeben
  - Entscheidung des Entwicklers vom 2026-11-02: Der Mitschnitt gehört ins Fundament. Er war bis dahin ein unbestätigter Vorschlag.
- Vorbereitung von Signierung und Notarisierung (Developer ID, Hardened Runtime) samt Release-Skript.

## Capabilities

### New Capabilities

- `app-shell`: App-Start, Hauptfenster mit Umgebungsstatus, Über-Fenster mit Lizenzhinweisen, Lokalisierung
- `logger-session`: Ablauf eines Auslese- oder Löschvorgangs über einen Treiber: Fortschritt, Abbruch, Fehler, Bestätigung vor dem Löschen, Speichern des Ergebnisses
- `serial-transport`: Ermittlung serieller Ports und byteweise Kommunikation mit Timeouts und Abbruch
- `gpsbabel-runtime`: Bereitstellung und Ausführung des gebündelten gpsbabel 1.7.0 inklusive Rosetta-Erkennung
- `gpx-export`: Erzeugung von GPX-1.1-Dateien aus den ausgelesenen Daten
- `diagnostic-capture`: Aufzeichnung, Export und Wiedergabe von Gerätedialogen

### Modified Capabilities

Keine. Es existieren noch keine Specs.

## Nicht im Umfang

- Jeglicher Gerätetreiber, also BG728, GNS2000, i-GotU, NAL sowie alle gpsbabel-Treiber wie mtk, m241, wbt, skytraq, navilink, magellan oder itracku. Nach diesem Change lässt sich **noch kein Gerät auslesen**.
- Gerätekatalog, Gerätewahl und Geräteerkennung in der UI.
- Dateimodus (Konvertieren von Dateien).
- Bluetooth/IOBluetooth und USB/HID-Transport (kommen mit GNS2000 bzw. i-GotU).
- Nachbearbeitung wie Week-Rollover-Korrektur und Track-Aufteilung (kommt mit den ersten Treibern).
- Sparkle/Updates, „In myTracks öffnen“, Website und Download-Seite.

## Betroffene Geräte und Treiberfamilien

Direkt betroffen ist kein Gerät. Mittelbar legt der Change die Grundlage für den gesamten Katalog:

- **gpsbabel-Laufzeit**: Basis aller gpsbabel-Treiber (mtk, m241, wbt, skytraq, navilink, magellan, itracku) und des Dateimodus. Damit gilt die Rosetta-Abhängigkeit für alle diese Geräte.
- **Serieller Transport**: Basis der nativen seriellen Treiber BG728 (Maptaq Trip IQ) und i-GotU GT-800.
- **Diagnose-Mitschnitt**: vor allem für die Geräte ohne Testgerät beim Entwickler (i-GotU, Bluetooth-Logger).

## Impact

- **Neue Dateien und Ordner im Repository:**
  - `project.yml`
  - App-Target
  - lokales Swift-Package mit Modulen und Tests
  - `Vendor/gpsbabel-1.7.0/` mit Binary, Framework, Lizenztexten und Herkunftsnachweis
  - `Scripts/` für das Release
- Das generierte `.xcodeproj` und Build-Artefakte kommen in `.gitignore`.
- **Abhängigkeiten:**
  - XcodeGen als Build-Werkzeug beim Entwickler
  - keine Laufzeit-Abhängigkeiten außer dem gebündelten gpsbabel 1.7.0 und Qt 5.12.9
  - keine Swift-Packages von Dritten
- **Rechtliches:**
  - gpsbabel (GPL) und Qt (LGPL) werden als getrennte Programme mitgeliefert
  - Lizenztexte liegen im Bundle
  - der Quellcode muss zusammen mit dem Download angeboten werden
- **Entwickler-Umgebung:** Developer-ID-Zertifikat und Zugangsdaten für die Notarisierung sind für das Release nötig. Das ist ein manueller Schritt.
