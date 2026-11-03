# Tasks: setup-foundation

## 1. Projektgerüst

- [x] 1.1 `.gitignore` ergänzen um `*.xcodeproj`, `DerivedData/`, `.build/`, `build/` und `*.xcarchive`; prüfen mit `git status`, dass nach einem Build keine generierten Dateien auftauchen.
- [x] 1.2 Lokales Swift-Package `Packages/GPSLoaderKit` anlegen:
  - Module `LoggerCore`, `SerialTransport`, `GPSBabelRuntime`, `GPXExport`, `DiagnosticCapture`, `TestSupport` mit den Abhängigkeiten aus design.md D1
  - je ein Test-Target mit Swift Testing
  - Swift 6 Language Mode, Plattform `.macOS(.v12)`

  Prüfen: `swift build` und `swift test` im Package laufen ohne Fehler und ohne Concurrency-Warnungen.
- [x] 1.3 `project.yml` für XcodeGen anlegen:
  - App-Target `gpsloader` (AppKit, Bundle-ID `info.stichling.gpsloader`, Deployment Target 12.0, `ARCHS = arm64 x86_64`, Swift 6, Strict Concurrency complete, Hardened Runtime, Team `4TNB35NY7G`)
  - Abhängigkeit auf alle Bibliotheksmodule des Packages
  - Schemes für Debug und Release

  Prüfen: `xcodegen generate` und `xcodebuild -scheme gpsloader build` laufen erfolgreich.
- [x] 1.4 Minimalen App-Einstieg anlegen (`App/`): `AppDelegate`, programmatisches Hauptmenü, leeres Hauptfenster. Prüfen: Die App startet aus Xcode, und `lipo -archs` auf das Release-Binary meldet `x86_64 arm64`.
- [x] 1.5 Früher Machbarkeitstest für die Systemgrenzen:
  - `ioctl(fd, TIOCEXCL)` aus Swift aufrufbar
  - `cfsetspeed`/`tcsetattr` funktionieren
  - `IOServiceMatching(kIOSerialBSDServiceValue)` liefert Ports

  Prüfen: ein Test in `SerialTransport`, der kompiliert und auf einem Pseudo-Terminal (`openpty`) läuft. Ergebnis (Überladungen, Rückfälle) in design.md D4 festhalten, falls es abweicht.

## 2. Datenmodell und Treibervertrag (`LoggerCore`)

- [x] 2.1 `Sendable`-Werttypen `Recording`, `Track`, `TrackSegment`, `TrackPoint` (lat, lon, ele?, time?) und `Waypoint` anlegen. Prüfen: Unit-Tests für Gleichheit und dafür, dass ein `Recording` als leer gilt, wenn es keine Punkte und keine Wegpunkte enthält.
- [x] 2.2 `LoggerError` mit den Fehlerarten aus der Spec `logger-session` anlegen, inklusive lokalisierter Beschreibung (de/en) und technischem Detail. Prüfen: Test, dass jede Fehlerart eine nicht leere Beschreibung in beiden Sprachen hat.
- [x] 2.3 Lock-Hilfstyp für Systemgrenzen anlegen (NSLock-basiert, `@unchecked Sendable`, design.md D2). Prüfen: Test mit parallelen Zugriffen aus einer `TaskGroup` (1000 Inkremente ergeben 1000).
- [x] 2.4 `ByteTransport`-Protokoll, `DiagnosticSink`-Protokoll mit `NullSink`, `ProgressUpdate`, `Timeouts`, `DriverDescriptor`, `DriverContext` und `LoggerDriver` anlegen (design.md D3). Prüfen: `swift build` ohne Concurrency-Warnungen.
- [x] 2.5 Den skriptbaren `MockTransport` in `TestSupport` anlegen: erwartete Bytes → Antwort, Verzögerung, Schweigen; bei unerwarteten Bytes eine Meldung mit erwartetem und tatsächlichem Befehl. Prüfen: eigene Tests, darunter das Szenario „Unerwarteter Befehl im Mock“ (Spec `serial-transport`).
- [x] 2.6 `PortReservations`-Actor anlegen. Prüfen: Test, dass eine zweite Reservierung für denselben Port abgelehnt und nach der Freigabe wieder erlaubt wird (Spec `logger-session`, „Nur ein Vorgang gleichzeitig“).
- [x] 2.7 `LoggerSession`-Actor anlegen:
  - Auslesen und Löschen (nur mit Bestätigung)
  - `AsyncStream<SessionEvent>`
  - Fortschritt bestimmt und unbestimmt
  - Abbruch mit Frist von 5 s
  - Fehlerabbildung
  - Ablehnung eines Löschauftrags ohne Löschfähigkeit des Treibers

  Prüfen: Tests mit Mock-Treibern für alle Szenarien der Spec `logger-session`, außer den UI-Dialogen.

## 3. Serieller Transport (`SerialTransport`)

- [x] 3.1 `SerialPort`-Actor anlegen:
  - exklusives Öffnen (`TIOCEXCL`, `EBUSY` → `portBusy`, `ENOENT` → `deviceNotFound`)
  - Raw-Modus 8N1 ohne Flusskontrolle, Standardbaudraten 4800–115200
  - `write`
  - `close` in allen Pfaden

  Prüfen: Tests gegen ein Pseudo-Terminal (`openpty`) für Öffnen, Baudrate, Belegt und Nicht vorhanden.
- [x] 3.2 Lesen mit `poll()` auf einer eigenen Queue: `read(count:timeout:)` und `readUntil(terminator:maxLength:timeout:)`, Abbruch spätestens nach 100 ms (design.md D4). Prüfen: PTY-Tests für die Szenarien „Zeile lesen“, „Daten in Teilstücken“, „Gerät schweigt“ und „Abbruch während des Lesens“.
- [x] 3.3 Den Fall „Gerät wird abgezogen“ behandeln: `POLLHUP` bzw. Lesefehler führen zu einem Fehler und zur Freigabe des Ports. Prüfen: PTY-Test, der die Master-Seite während des Lesens schließt.
- [x] 3.4 Port-Katalog über IOKit: Liste mit Pfad, USB-Vendor-ID, Product-ID und Produktname sowie `AsyncStream` für hinzugekommene und entfernte Ports. Prüfen: Test, dass die Liste ohne Fehler geliefert wird und jeder Eintrag mit `/dev/cu.` beginnt. Die USB-Angaben werden manuell geprüft (Task 3.5).
- [ ] 3.5 [manuell, Hardware] Einen USB-Seriell-Adapter oder Logger einstecken und abziehen, während die Debug-App läuft. Prüfen: Der Port erscheint und verschwindet in der Liste, inklusive Vendor- und Product-ID.

## 4. GPX-Export (`GPXExport`)

- [x] 4.1 `GPXWriter` mit fester Element-Reihenfolge, XML-Maskierung, Zahlen ohne Locale (7 bzw. 2 Nachkommastellen, ohne nachgestellte Nullen), UTC-Zeiten mit optionalen Millisekunden, `creator` mit App-Version und ohne `extensions`. Prüfen: Tests für alle Szenarien der Spec `gpx-export`, darunter ein Test unter einer deutschen Locale.
- [x] 4.2 Das GPX-1.1-XSD als Testressource beilegen und eine Schema-Validierung der erzeugten Dateien per `XMLDocument` einrichten. Prüfen: Test „Validierung gegen das Schema“ ist grün. Ist keine XSD-Validierung möglich, Rückfall laut design.md D7 und Abweichung dort vermerken.
- [x] 4.3 Deterministische Ausgabe und atomares Schreiben. Prüfen: Test auf byte-gleiche Ausgabe bei festem Zeitstempel; Test mit schreibgeschütztem Zielordner, nach dem kein Ziel existiert und eine bestehende Datei unverändert bleibt.

## 5. Diagnose-Mitschnitt (`DiagnosticCapture`)

- [x] 5.1 Das JSON-Lines-Format aus design.md D8 definieren (Kopf, `tx`/`rx`/`event`/`process`, Hex plus ASCII) und `CaptureRecorder` als `DiagnosticSink` umsetzen. Prüfen: Test für das Szenario „Serieller Dialog“ (Reihenfolge, Zeitstempel, 16 gesendete und 3 empfangene Bytes) und ein Test, dass jede Zeile einzeln als JSON parsebar ist.
- [x] 5.2 Den `CapturingTransport`-Decorator um beliebige `ByteTransport` anlegen. Prüfen: Test mit `MockTransport`, der alle Bytes und die Ereignisse Öffnen, Schließen und Zeitüberschreitung im Mitschnitt wiederfindet.
- [x] 5.3 `ReplayTransport` aus einer Aufzeichnung anlegen. Prüfen:
  - Fixture-Datei unter `Tests/Fixtures/`: Ein Test-Treiber liefert bei der Wiedergabe dasselbe Ergebnis.
  - Abweichungstest: Melden an Position 5 mit erwarteten und tatsächlichen Bytes.
- [x] 5.4 `CaptureStore`: Ablage in Application Support, nur die letzten 10 Dateien, Einstellung „Mitschnitt an/aus“ in `UserDefaults` mit dem Standardwert „aus“. Prüfen: Tests für den Standardzustand und das Szenario „Elfter Vorgang“ in einem temporären Verzeichnis.

## 6. gpsbabel-Laufzeit (`GPSBabelRuntime`) und Bundle

- [x] 6.1 gpsbabel 1.7.0 aus `git show e0d1f18:…/X86Only/gpsbabel1_7_0` und `QtCoreGpsBabel.framework` aus demselben Commit nach `Vendor/gpsbabel-1.7.0/` übernehmen. Dazu kommen `COPYING.txt` (GPLv2) aus `Import/Apps/GPSBabelFE170.app`, der offizielle LGPL-3.0-Text und `PROVENANCE.md` mit Commit und Prüfsummen. Prüfen: `shasum` des Binaries ergibt `a94af8dd88d50a4addbb7d02398b33ef6db7855b`, `file` meldet x86_64.
- [x] 6.2 `project.yml` ergänzen: Copy-Phasen nach `Contents/Helpers/gpsbabel` und `Contents/Frameworks/QtCoreGpsBabel.framework` mit „Code Sign On Copy“, dazu Lizenzen nach `Contents/Resources/Licenses/` und einen Prüfschritt `codesign --verify --strict --deep`. Prüfen: Im gebauten Bundle liegen die Dateien an diesen Orten, und `codesign -dv` zeigt die eigene Developer ID mit Hardened Runtime für gpsbabel.
- [x] 6.3 `GPSBabelRunner`-Actor anlegen:
  - `Process` mit Argument-Array und Bundle-Pfad
  - eigenes temporäres Arbeitsverzeichnis, das danach entfernt wird
  - reduzierte Umgebung
  - stdout, stderr und Exit-Code erfassen
  - Exit-Code ungleich 0 → `gpsbabelFailed` mit stderr
  - Meldung an den `DiagnosticSink`

  Prüfen: Tests mit einem austauschbaren Ausführungspfad (z. B. `/bin/echo`, `/bin/sh`-freie Testhelfer aus `/usr/bin`) für Erfolg, Fehler, Sonderzeichen im Argument (Szenario „Dateiname mit Sonderzeichen“) und das Szenario „Nebenprodukt im Arbeitsverzeichnis“.
- [x] 6.4 Abbruch und Zeitlimit: SIGTERM, nach 3 s SIGKILL, ein app-weites Prozessregister. Prüfen: Test mit `/bin/sleep 60`, dass der Prozess nach dem Abbruch höchstens 3 s weiterläuft und keine PID zurückbleibt.
- [x] 6.5 Rosetta- und Laufzeitprüfung (design.md D6):
  - `hw.optional.arm64`
  - Probe `gpsbabel -V` mit 30 s Zeitlimit
  - `EBADARCH` → „Rosetta fehlt“
  - fehlende Dateien bzw. falsche Version → „defekt“ mit Grund
  - Zwischenspeicher und erneute Prüfung vor jedem Vorgang

  Prüfen: Unit-Tests mit simulierten Startfehlern (EBADARCH, ENOENT, falsche Versionsausgabe); dazu der Test „gpsbabel im System vorhanden“, der zeigt, dass immer der Bundle-Pfad verwendet wird.
- [x] 6.6 Die Hilfs-App `RosettaInstaller` als eigenes XcodeGen-Target anlegen (Swift, nur `x86_64`, ohne UI, beendet sich sofort), nach `Contents/Helpers/` kopieren und signieren. Prüfen: `lipo -archs` meldet nur `x86_64`, `codesign --verify` ist erfolgreich.
- [ ] 6.7 [manuell, Hardware] Auf dem Entwicklungsrechner (Apple Silicon, Rosetta fehlt) prüfen:
  1. Die App zeigt „Rosetta fehlt“.
  2. Die Installationsaktion öffnet den Systemdialog. Erscheint er nicht, wird der Rückfall-Text angezeigt.
  3. Nach der Installation wechselt der Status ohne Neustart auf „bereit, gpsbabel 1.7.0“.
  4. `gpsbabel -V` aus dem Bundle meldet 1.7.0.

## 7. App-Rahmen und UI

- [x] 7.1 Hauptfenster mit dem Bereich „Umgebung“ anlegen: Zustände „wird geprüft“, „bereit (1.7.0)“, „Rosetta fehlt“ mit Installationsaktion sowie „defekt“ mit Grund; dazu ein Platzhalter für die Gerätewahl. Prüfen: UI-Test oder manuelle Prüfung aller vier Zustände über einen Debug-Schalter, der den Prüfstatus simuliert.
- [x] 7.2 Session-UI anlegen:
  - Fortschrittsanzeige (bestimmt und unbestimmt) mit „Abbrechen“
  - Fehlerdialog (Art und Detail)
  - Speicherdialog mit vorgeschlagenem Dateinamen „<Gerät> yyyy-MM-dd HH-mm.gpx“
  - Meldung „keine Daten“
  - Bestätigungsdialog vor dem Löschen, inklusive Hinweis bei experimentellem Löschen

  Prüfen: Alle Abläufe sind manuell mit dem Demo-Treiber (Debug-Build) durchspielbar; ein Unit-Test prüft das Format des Dateinamens.
- [x] 7.3 Demo-Treiber anlegen, nur im Debug-Build (`#if DEBUG`): Er simuliert Auslesen mit Fortschritt, einen Fehler, Zeitüberschreitung, leeres Gerät und Löschen (normal und experimentell). Prüfen: Er erscheint im Release-Build nicht (Symbolsuche im Release-Binary).
- [x] 7.4 Menü „Diagnose“ mit dem Schalter „Diagnose-Mitschnitt aufzeichnen“ und dem Eintrag „Letzten Mitschnitt sichern…“, inklusive Hinweis auf Positionsdaten vor dem Speichern. Prüfen: Manuell mit dem Demo-Treiber; die gesicherte Datei ist gültiges JSON Lines.
- [x] 7.5 Über-Fenster mit Version, Copyright, Lizenzhinweisen zu gpsbabel 1.7.0 (GPLv2) und Qt 5.12 (LGPLv3), Verweis auf die Quellcode-Seite und Links auf die Volltexte im Bundle. Prüfen: Das Fenster zeigt alle Angaben, und die Volltexte öffnen sich.
- [x] 7.6 String Catalog `Localizable.xcstrings` anlegen, mit Englisch als Entwicklungssprache und Deutsch vollständig übersetzt. Prüfen: Start mit `-AppleLanguages (de)` und `(fr)` zeigt deutsche bzw. englische Texte; der Katalog meldet keine fehlenden Übersetzungen.
- [x] 7.7 Sauberes Beenden: `applicationShouldTerminate` bricht laufende Sessions ab und räumt gpsbabel-Prozesse ab (`.terminateLater`, höchstens 3 s). Prüfen: Manuell mit einem Demo-Vorgang, der einen `sleep`-Prozess startet; nach dem Beenden der App läuft kein Kindprozess mehr (`pgrep`).

## 8. Release-Weg

- [x] 8.1 `Scripts/release.sh` (zsh) laut design.md D10 anlegen: generate, archive, export, ZIP, notarytool, stapler und die Abschlussprüfung mit `spctl`/`codesign`. Prüfen: `zsh -n Scripts/release.sh` ist fehlerfrei; ein Trockenlauf ohne Notarisierung (`--skip-notarize`) erzeugt ein signiertes ZIP.
- [ ] 8.2 [manuell, Hardware] Der Entwickler richtet das notarytool-Keychain-Profil ein und führt `Scripts/release.sh` vollständig aus. Prüfen: Die Notarisierung ist erfolgreich, `spctl -a -vv` meldet „accepted, source=Notarized Developer ID“ für die App, und gpsbabel lässt sich aus dem notarisierten Bundle starten.
- [x] 8.3 `README.md` im Repository anlegen: Voraussetzungen (Xcode 27, XcodeGen, Rosetta für gpsbabel-Tests), Build mit `xcodegen generate`, Tests, Release, Herkunft von gpsbabel. Prüfen: Die dokumentierten Befehle laufen auf einem frischen Klon wie beschrieben.

## 9. Integration

- [x] 9.1 Ende-zu-Ende-Test mit dem Demo-Treiber im Debug-Build: Auslesen mit eingeschaltetem Mitschnitt, Speichern als GPX, Mitschnitt sichern. Prüfen: Die GPX-Datei validiert gegen das XSD (Hilfsskript bzw. Test aus 4.2), und der Mitschnitt enthält Kopf und Ereignisse.
- [ ] 9.2 [manuell, Hardware] Release-Build auf einem Intel-Mac (oder unter Rosetta erzwungen) und auf Apple Silicon starten. Prüfen: Die App läuft jeweils nativ (Aktivitätsanzeige: Architektur), und der Umgebungsstatus ist „bereit“.
- [x] 9.3 Alle Tests laufen grün (`swift test` im Package, `xcodebuild test`), und `openspec validate setup-foundation --strict` ist erfolgreich.

## Workflow follow-up

- `openspec/config.yaml`, `CLAUDE.md` und `docs/legacy-analysis.md` nennen noch macOS 11 als Minimum. Sie sind auf macOS 12 zu aktualisieren, die Entscheidung stammt vom 2026-11-02. Der Diagnose-Mitschnitt ist in der Config als bestätigt zu markieren. Erledigt am 2026-11-03 (`docs/legacy-analysis.md` nennt macOS 11 nur als historische Angabe zu myTracks 4.5.0 und bleibt deshalb unverändert).
- Nach Abschluss und Review den Change archivieren (`/opsx:archive`). Archiviert am 2026-11-03 auf Wunsch des Entwicklers. Die manuellen Hardware-Prüfungen 3.5, 6.7, 8.2 und 9.2 holt er später nach.
