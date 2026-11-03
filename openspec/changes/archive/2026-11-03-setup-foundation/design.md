# Design: setup-foundation

## Context

Ausgangslage:

- Das Repository enthält bisher nur OpenSpec und die Dokumentation. Es gibt weder Code noch ein Xcode-Projekt.
- Werkzeuge: Xcode 27.1 (macOS-27-SDK, kleinstes Deployment Target **macOS 12.0**), Swift 6.4, XcodeGen unter `/opt/homebrew/bin/xcodegen`.
- Auf dem Entwicklungsrechner (Apple M4) ist **Rosetta für macOS nicht installiert**; unter `/Library/Apple/usr/libexec/oah` liegt nur `RosettaLinux`. Das mitgelieferte gpsbabel lässt sich dort erst nach der Rosetta-Installation testen.

Motivation und Umfang stehen in `proposal.md`, das verbindliche Verhalten in den Specs unter `specs/`.

Relevante Teile des Alt-Codes:

- `input/mytracks4mac/DsTrackFramework/Source/Classes/GPSBabel/GPSBabel.m`: gpsbabel-Aufrufe über `system()`/`popen()`, Abbruch per `killall gpsbabel`. Das übernehmen wir ausdrücklich **nicht**.
- `input/mytracks4mac/DsTrackFramework/Source/Classes/GpsDriver/GpsDriver.h`: der bisherige Treibervertrag, synchron und ohne Fortschritt oder Abbruch.
- `input/mytracks4mac/DsTrackFramework/Source/Classes/GpsDriver/AMSerialPort/`: serielle Fremdbibliothek in Objective-C. Wird durch eigenen Swift-Code ersetzt.
- `input/mytracks4mac/DsTrackFramework/Source/Classes/ImportExport/TrackGPX.m`: GPX-Export mit myTracks-Extensions.
- gpsbabel 1.7.0: `git show e0d1f18:myTracks/Source/Resources/X86Only/gpsbabel1_7_0` (SHA-1 `a94af8dd88d50a4addbb7d02398b33ef6db7855b`) und `git show e0d1f18:myTracks/Source/Resources/X86Only/QtCoreGpsBabel.framework/…` (Qt 5.12.9, x86_64).
  - Beide sind ohne Hardened Runtime signiert (`flags=0x0`) und für die Notarisierung neu zu signieren.
  - Die Install-Namen lauten `@executable_path/../Frameworks/QtCoreGpsBabel.framework/Versions/A/QtCoreGpsBabel`.
  - Weitere Abhängigkeiten sind nur Systembibliotheken.
- GPL-Text von gpsbabel: `input/mytracks4mac/Import/Apps/GPSBabelFE170.app/Contents/MacOS/COPYING.txt` (GPLv2).

## Goals / Non-Goals

**Goals:**

- Eine Projektstruktur, in der jeder spätere Treiber nur noch seine Protokolllogik und Tests hinzufügen muss.
- Gerätelogik vollständig ohne Hardware und ohne UI testbar.
- Swift 6 mit Strict Concurrency ohne `@preconcurrency`-Ausnahmen in eigenem Code. Ausnahmen nur an klar gekapselten Systemgrenzen.
- Ein reproduzierbarer Release-Weg: Build, Signatur, Notarisierung.

**Non-Goals:**

- Keine endgültige UI-Gestaltung. Das Hauptfenster ist ein funktionaler Platzhalter, der mit den Gerätetreibern wächst.
- Keine Bluetooth- und HID-Transporte (siehe proposal.md, Nicht im Umfang). Die Transport-Abstraktion ist aber so geschnitten, dass sie diese später aufnimmt.

## Decisions

### D1: Projektstruktur mit XcodeGen und lokalem Swift-Package

```
gpsloader/
  project.yml                  XcodeGen-Definition (App + Hilfs-App + Test-Schemes)
  App/                         AppKit-App-Target "gpsloader" (UI, AppDelegate, Lokalisierung)
  RosettaInstaller/            Mini-App-Target nur für x86_64 (siehe D6)
  Packages/GPSLoaderKit/       lokales Swift-Package, ohne UI
    Sources/LoggerCore         Datenmodell, Treibervertrag, Session, Fehler, Diagnose-Schnittstelle
    Sources/SerialTransport    serieller Port (termios), Port-Katalog (IOKit)
    Sources/GPSBabelRuntime    Locator, Rosetta-Prüfung, Prozess-Runner
    Sources/GPXExport          GPX-1.1-Writer
    Sources/DiagnosticCapture  Recorder, Dateiformat, Ablage, Wiedergabe-Transport
    Sources/TestSupport        Mock-Transport, Fixture-Helfer (nur für Tests)
    Tests/...                  ein Test-Target pro Modul (Swift Testing)
  Vendor/gpsbabel-1.7.0/       gpsbabel, QtCoreGpsBabel.framework, Lizenzen, PROVENANCE.md
  Scripts/release.sh           Archiv, Export, Notarisierung, Stapling
```

- `.xcodeproj` wird generiert und **nicht** eingecheckt. `xcodegen generate` ist der erste Schritt jedes Builds.
- Abhängigkeiten zwischen den Modulen laufen nur in eine Richtung:
  `LoggerCore` ← `SerialTransport`, `GPSBabelRuntime`, `GPXExport`, `DiagnosticCapture` ← App.
- Die Diagnose-Schnittstelle (`DiagnosticSink`) liegt in `LoggerCore`. Die Transporte melden ihre Bytes dorthin, ohne `DiagnosticCapture` zu kennen.
- Bundle-ID: `info.stichling.gpsloader`, analog zu `info.stichling.myTracks`. Der Produktname folgt dem Arbeitstitel und ist leicht änderbar.
- Alternativen:
  - Eingechecktes `.xcodeproj` ist fehleranfälliger bei Änderungen durch Agenten und erzeugt Merge-Konflikte.
  - Ein reines SwiftPM-Projekt verlangt einen selbst gebauten Bundle-Aufbau und eigene Signierung. Beides entschied der Entwickler zugunsten von XcodeGen.

### D2: Sprache, Concurrency und Plattform

- Swift 6 Language Mode, `SWIFT_STRICT_CONCURRENCY = complete`, Deployment Target macOS 12.0, `ARCHS = arm64 x86_64` im Release.
- Datenmodell (`Recording`, `Track`, `TrackSegment`, `TrackPoint`, `Waypoint`) als `Sendable`-Werttypen.
- macOS 12 bietet weder `Mutex` (Synchronization, ab 15) noch `OSAllocatedUnfairLock` (ab 13).
  Für den wenigen gemeinsam genutzten veränderlichen Zustand an Systemgrenzen gibt es einen kleinen,
  eigenen Lock-Typ auf Basis von `NSLock`. Er ist `@unchecked Sendable` und zentral gekapselt.
  Sonst überall Actors.
- `Observation` (ab 14) steht nicht zur Verfügung. Die UI erhält Zustandsänderungen über `AsyncStream`,
  die auf dem `@MainActor` konsumiert werden.
- Tests mit Swift Testing (`import Testing`). Die Tests laufen auf dem Entwicklungsrechner; das Deployment Target bleibt davon unberührt.

### D3: Treibervertrag und Session (`logger-session`)

```
protocol LoggerDriver: Sendable {
  var descriptor: DriverDescriptor { get }         // Name, kann löschen?, Löschen experimentell?
  func read(_ context: DriverContext) async throws -> Recording
  func erase(_ context: DriverContext) async throws // nur wenn unterstützt
}

struct DriverContext: Sendable {
  let progress: @Sendable (ProgressUpdate) -> Void // bestimmt (n von m) oder unbestimmt (Schritt)
  let diagnostics: any DiagnosticSink
  let timeouts: Timeouts
  // + Zugriff auf Transport-Fabriken bzw. GPSBabelRunner
}
```

- `LoggerSession` ist ein Actor. Er startet den Treiber in einer `Task`, leitet den Fortschritt als
  `AsyncStream<SessionEvent>` weiter und bildet Fehler auf `LoggerError` ab:
  `deviceNotFound`, `portBusy`, `timeout`, `protocolError`, `rosettaMissing`, `gpsbabelFailed`,
  `writeFailed`, `cancelled`. Jede Fehlerart hat eine lokalisierte Beschreibung und ein technisches Detail.
- Abbruch geht über die normale Task-Cancellation. Transporte und Runner reagieren über
  `withTaskCancellationHandler`. Die Session wartet auf das Ende des Treibers, höchstens 5 s
  (siehe Spec). Erst danach gilt der Vorgang als abgebrochen.
- Exklusivität: Ein app-weiter `PortReservations`-Actor vergibt Reservierungen pro Port bzw. pro gpsbabel-Gerät. Ein zweiter Vorgang für denselben Port wird abgelehnt.
- Bestätigung vor dem Löschen und der Speicherdialog liegen in der App (UI). Die Session bekommt die
  Bestätigung als Parameter (`erase(confirmed:)`); ohne ihn startet sie nicht.
- Ein Demo-Treiber, nur in Debug-Builds, simuliert Auslesen, Fortschritt, Fehler und Löschen. Damit lässt sich die Session-UI ohne echte Treiber bedienen und manuell testen.
- Alternative: Callback- bzw. Delegate-basiert wie `GpsDriver.h`. Verworfen, weil sich Abbruch und Zeitlimits damit nicht sauber und ohne Data Races abbilden lassen.

### D4: Serieller Transport (`serial-transport`)

- `protocol ByteTransport: Sendable` mit `open()`, `write(_:)`, `read(count:timeout:)`,
  `readUntil(_ terminator:, maxLength:, timeout:)` und `close()`. `SerialPort` ist ein Actor und implementiert dieses Protokoll.
- POSIX direkt aus Swift:
  1. `open(path, O_RDWR | O_NOCTTY | O_NONBLOCK)`
  2. `ioctl(fd, TIOCEXCL)` für exklusiven Zugriff; bei `EBUSY` folgt `portBusy`
  3. zusätzlich `flock(fd, LOCK_EX | LOCK_NB)`; bei `EWOULDBLOCK` folgt `portBusy`
  4. `cfmakeraw`, `cfsetspeed`, `CLOCAL | CREAD`, kein `CRTSCTS`, `tcsetattr`
  5. `tcflush` nach dem Öffnen
- Ergebnis des Machbarkeitstests (Task 1.5):
  - Die Swift-Überladungen von `ioctl` funktionieren, auch für `TIOCEXCL`.
  - `termios` und IOKit (`kIOMainPortDefault`) sind direkt nutzbar.
  - Auf Pseudo-Terminals verhindert `TIOCEXCL` ein zweites `open` jedoch nicht. Deshalb gibt es zusätzlich das `flock`. Es schützt vor parallelem Zugriff aus gpsloader selbst und aus Programmen, die ebenfalls sperren, und macht „Port belegt“ mit PTYs testbar.
  - `IOSSIOSPEED` schlägt auf PTYs fehl. Nicht-Standard-Baudraten werden in diesem Change nicht gebraucht.
- Lesen: Eine eigene serielle `DispatchQueue` wartet mit `poll()` in Schritten von 100 ms und prüft dazwischen ein Abbruch-Flag. Die Ergebnisse gehen per `CheckedContinuation` an den Actor zurück. So blockiert kein Thread des Swift-Concurrency-Pools, und der Abbruch greift spätestens nach 100 ms.
- Port-Katalog über IOKit (`IOServiceMatching(kIOSerialBSDServiceValue)`, `kIOCalloutDeviceKey`).
  USB-Angaben (`idVendor`, `idProduct`, `USB Product Name`) kommen per
  `IORegistryEntrySearchCFProperty` mit `kIORegistryIterateParents`.
  Änderungen meldet `IOServiceAddMatchingNotification` (first match/terminated) als `AsyncStream`.
  `kIOMainPortDefault` ist ab macOS 12 verfügbar.
- Für Tests stellt `TestSupport` einen skriptbaren `MockTransport` bereit (erwartete Bytes → Antwortbytes, Verzögerungen, Schweigen).
- Alternative: `AMSerialPort` aus myTracks weiterverwenden. Ausgeschlossen, weil der Code Objective-C ist. Eine Weiterentwicklung mit `FileHandle` scheidet aus, weil es dort keinen Timeout und keine termios-Konfiguration gibt.

### D5: gpsbabel im Bundle (`gpsbabel-runtime`)

- Ablage im Repository unter `Vendor/gpsbabel-1.7.0/`. Herkunft und Prüfsummen stehen in `PROVENANCE.md`:
  Commit `e0d1f18`, SHA-1 der Originaldateien, Datum der Übernahme.
- Ablage im Bundle:
  - `Contents/Helpers/gpsbabel`
  - `Contents/Frameworks/QtCoreGpsBabel.framework`

  Damit trifft `@executable_path/../Frameworks/…` aus dem Install-Namen genau den richtigen Ort, ohne
  `install_name_tool` und ohne Änderung der Binaries.
- Signierung: Xcode-Copy-Phasen mit „Code Sign On Copy“. Die eigene Developer ID ersetzt die Originalsignatur.
  - gpsbabel bekommt Hardened Runtime und Timestamp; Entitlements braucht es keine.
  - Library Validation passt, weil App, gpsbabel und Framework dasselbe Team haben.
  - Ein Skript-Schritt in `project.yml` prüft nach dem Build mit `codesign --verify --strict`.
- `GPSBabelRunner` ist ein Actor um `Foundation.Process`:
  - `executableURL` zeigt auf das Bundle (siehe D5).
  - Argumente werden als Array übergeben, es gibt keine Shell.
  - Jeder Aufruf bekommt ein eigenes temporäres Arbeitsverzeichnis, das danach gelöscht wird.
  - Die Umgebung ist reduziert: keine geerbten `DYLD_*`-Variablen.
  - stdout und stderr werden über `Pipe` und `readabilityHandler` gesammelt (Lock-Typ aus D2).
  - Das Ende kommt per `terminationHandler` an eine Continuation.
  - Abbruch und Zeitlimit: `terminate()` (SIGTERM), nach 3 s `kill(pid, SIGKILL)`.
  - Ein app-weites Register der laufenden Prozesse sorgt dafür, dass `applicationShouldTerminate`
    sie vor dem Beenden der App abräumt (`.terminateLater`).
- Für die Diagnose meldet der Runner Argumentliste, Ausgaben und Exit-Code an den `DiagnosticSink`.

### D6: Rosetta-Erkennung und -Installation

- Auf Intel (`sysctl hw.optional.arm64` ist nicht 1) gilt die Laufzeit immer als bereit, sofern gpsbabel startet.
- Auf Apple Silicon entscheidet eine tatsächliche Probe: `gpsbabel -V`.
  - Wirft `Process.run()` einen POSIX-Fehler `EBADARCH` (86) bzw. „Bad CPU type“, fehlt Rosetta.
  - Andere Startfehler, oder eine Version ungleich 1.7.0, bedeuten „defekt“ mit Grund.
- Die Probe hat ein großzügiges Zeitlimit von 30 s, weil Rosetta beim ersten Start die Übersetzung vorbereitet. Die UI zeigt währenddessen „wird geprüft“.
- Das Ergebnis wird zwischengespeichert. Vor jedem gpsbabel-Vorgang wird kurz erneut geprüft.
- Installation: Die Mini-App `RosettaInstaller.app` (Swift, **nur x86_64**, ohne UI, beendet sich sofort) liegt in `Contents/Helpers/`.
  - Startet gpsloader sie per `NSWorkspace.openApplication`, zeigt macOS ohne Rosetta seinen eigenen Installationsdialog.
  - Nach dem Start wird die Prüfung wiederholt (auf Aktivierung der App bzw. mit Abfrageintervall, bis zu 10 min).
  - Rückfall, falls der Systemdialog nicht erscheint: Die App zeigt den Terminal-Befehl `softwareupdate --install-rosetta --agree-to-license` zum Kopieren.
- Alternativen:
  - `softwareupdate` selbst mit Administratorrechten ausführen (AppleScript `do shell script … with administrator privileges`). Verworfen: Das ist ein Shell-Aufruf mit Rechteerhöhung, der den Projektregeln widerspricht.
  - Nur einen Text mit dem Befehl anzeigen. Bleibt als Rückfall.

### D7: GPX-Export (`gpx-export`)

- Ein eigener Streaming-Writer, der in `Data` schreibt. Er erzeugt XML mit expliziter Maskierung und feste Element-Reihenfolge nach XSD:
  `metadata(time)`, `wpt*`, `trk*(name, trkseg*(trkpt*(ele?, time?)))`.
- Zahlen werden ohne `NumberFormatter` und ohne Locale formatiert (eigene Formatierung auf 7 bzw. 2
  Nachkommastellen, nachgestellte Nullen entfernt). Zeiten formatiert ein ISO-8601-Formatter mit UTC
  und optionalen Millisekunden.
- Schreiben atomar über `Data.write(to:options: .atomic)`.
- Für die Tests liegt das GPX-1.1-XSD als Testressource bei. Validiert wird per `XMLDocument.validate()`;
  ist eine Schema-Validierung so nicht möglich, folgt der Rückfall auf eine Prüfung von Struktur und Wohlgeformtheit.
- Alternative: Text über `XMLDocument` aufbauen. Verworfen, weil die Ausgabe weniger deterministisch und schwerer byte-genau zu testen ist.

### D8: Diagnose-Mitschnitt (`diagnostic-capture`)

- Format: **JSON Lines**, eine Zeile pro Ereignis.
  - Erste Zeile ist der Kopf: `{"format":"gpsloader-capture","version":1,"app":…,"os":…,"arch":…,"translated":…,"driver":…,"port":…,"params":…}`.
  - Folgezeilen: `{"t":<ms seit Start>,"kind":"tx|rx|event|process","hex":"…","ascii":"…",…}`.
  - Damit ist das Format im Editor lesbar, robust parsebar und versioniert.
- `DiagnosticSink` (Protokoll in `LoggerCore`) mit einer `CaptureRecorder`-Implementierung (Actor).
  Ist der Mitschnitt aus, gibt es eine `NullSink`. Ein Decorator `CapturingTransport` umhüllt jeden `ByteTransport`.
- Ablage: `~/Library/Application Support/gpsloader/Captures/`. Es bleiben nur die letzten 10 Dateien.
  Die Einstellung wird in `UserDefaults` gespeichert.
- `ReplayTransport` liest eine Aufzeichnung und spielt sie als `ByteTransport` ab. Abweichungen meldet er mit Position, erwarteten und tatsächlichen Bytes. Treiber-Tests späterer Changes nutzen ihn mit Aufzeichnungen aus dem Feld als Fixtures.
- Alternativen:
  - Binärformat oder pcap. Verworfen: für Anwender und den Entwickler schlecht lesbar.
  - `os_log`/OSLog. Verworfen: Anwender können es schlecht exportieren, und es lässt sich nicht wiedergeben.

### D9: App-Rahmen (`app-shell`)

- AppKit mit programmatischer UI, ohne Storyboard. Das Hauptmenü wird im Code aufgebaut.
- Hauptfenster:
  - Bereich „Umgebung“ mit dem gpsbabel- bzw. Rosetta-Status und der Installationsaktion
  - Platzhalter für die Gerätewahl
  - in Debug-Builds der Demo-Treiber (siehe D3)
- Menü „Hilfe“ bzw. „Diagnose“ mit:
  - Schalter „Diagnose-Mitschnitt aufzeichnen“
  - „Letzten Mitschnitt sichern…“
- Über-Fenster: eigenes Fenster, weil der Standard-Über-Dialog für längere Lizenztexte ungeeignet ist.
  - Inhalt: Version, Copyright, Lizenzhinweise und Link zur Quellcode-Seite (URL als Konstante, Ziel auf der Website des Entwicklers).
  - Volltexte liegen unter `Contents/Resources/Licenses/`: `GPL-2.0.txt` (aus `COPYING.txt` von GPSBabelFE170) und `LGPL-3.0.txt` (offizieller Text der FSF).
- Lokalisierung über String Catalog (`Localizable.xcstrings`) in Deutsch und Englisch, Entwicklungssprache Englisch.
- Erkenntnisse aus der Umsetzung (Task 7.7):
  - Der Fortschritt erscheint als Child-Fenster über dem Hauptfenster, **nicht als Sheet**. AppKit lehnt das Beenden der App ab, solange ein Sheet angezeigt wird, ohne `applicationShouldTerminate` aufzurufen. Damit wären Beenden und Abmelden während eines Vorgangs blockiert, und gpsbabel liefe weiter.
  - Nach `.terminateLater` läuft der Main-Run-Loop im Modus `modalPanel`, in dem keine Main-Actor-Jobs ausgeführt werden. Das Aufräumen läuft deshalb in `Task.detached`, die Antwort `reply(toApplicationShouldTerminate:)` über `RunLoop.main.perform(inModes: [.default, .modalPanel])`.
- Debug-Hilfen, nur in Debug-Builds (`DebugAutomation.swift`): Startargumente zum Simulieren von Zuständen, zum Starten von Demo-Abläufen und zum Rendern der Fenster als PNG. Sie ermöglichen eine Prüfung der UI ohne Berechtigung für Bildschirmaufnahmen.

### D10: Release

- `Scripts/release.sh`, ein zsh-Skript. Es ist reines Build-Werkzeug, kein Teil der App. Ablauf:
  1. `xcodegen generate`
  2. `xcodebuild archive` (Release, universal)
  3. `xcodebuild -exportArchive` (Developer ID)
  4. `ditto` zu ZIP
  5. `xcrun notarytool submit --wait` mit Keychain-Profil
  6. `xcrun stapler staple`
  7. Abschließende Prüfung mit `spctl -a -vv` und `codesign -dv` für App, Helfer und Framework
- Team-ID `4TNB35NY7G` (aus der Signatur der myTracks-Binaries). Das Notarisierungsprofil richtet der Entwickler einmalig ein.

## Risks / Trade-offs

- [Rosetta wird nach macOS 27 eingeschränkt, und gpsbabel 1.7.0 läuft dann eventuell nicht mehr] → Bewusst akzeptiert. Alles gpsbabel-Spezifische ist hinter `GPSBabelRuntime` gekapselt, und ein klarer Status in der UI zeigt den Zustand. Native Treiber sind nicht betroffen.
- [Der Systemdialog zur Rosetta-Installation erscheint beim Start der Hilfs-App nicht zuverlässig] → Rückfall mit Terminal-Befehl (D6). Das ist manuell auf einem Mac ohne Rosetta zu verifizieren; der Entwicklungsrechner ist genau so ein Mac.
- [Der Signaturwechsel bei gpsbabel und QtCoreGpsBabel scheitert an der Notarisierung, z. B. wegen des alten SDK 10.12] → Ein früher Task notarisiert ein Test-Archiv. Bei Problemen wird geprüft, ob `--options runtime` am Framework oder ein Entitlement nötig ist.
- [Die Swift-Überladungen von `ioctl` decken `TIOCEXCL` oder `IOSSIOSPEED` nicht ab, weil C-Variadics nicht importiert werden] → Ein früher Task verifiziert das. Rückfall: `TIOCEXCL` über die vorhandene Überladung ohne Argument. Nicht-Standard-Baudraten werden in diesem Change nicht gebraucht.
- [Die Probe per Prozessstart macht den App-Start langsam, wenn Rosetta erst übersetzen muss] → Die Probe läuft asynchron. Die UI ist sofort bedienbar und zeigt „wird geprüft“.
- [Die Lizenzpflichten bei GPL und LGPL werden falsch eingeschätzt] → Quellcode von gpsbabel 1.7.0 und Qt 5.12.9 neben dem Download anbieten, Lizenztexte im Bundle. Das ist keine Rechtsberatung; der Entwickler entscheidet über eine rechtliche Prüfung.
- [Der Mitschnitt enthält Positionsdaten] → Er ist standardmäßig aus, wird nur lokal gespeichert, ist auf 10 Dateien begrenzt, und vor dem Export kommt ein ausdrücklicher Hinweis.

## Migration Plan

Entfällt. Es gibt keinen Bestand.

Für den Rollout reicht ein interner Build für den Entwickler. Öffentlich verteilt wird erst mit den ersten Gerätetreibern.

## Open Questions

- Endgültiger Produktname und Bundle-ID (Arbeitstitel „gpsloader“, `info.stichling.gpsloader`). Lässt sich später ändern, ohne Specs oder Tasks zu ändern.
- Konkrete URL der Quellcode-Seite für gpsbabel und Qt auf der Website. Wird als Konstante eingetragen, sobald sie feststeht.
