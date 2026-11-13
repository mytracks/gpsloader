# Design: gpsbabel, Qt und Rosetta entfernen

## Context

- **Herkunft:** gpsbabel kam mit `setup-foundation` in die App. Grundlage war der Plan, alle nicht nativen Geräte und Formate darüber zu betreiben (Spec `gpsbabel-runtime`, `docs/legacy-analysis.md`, Abschnitt 3.1, Binary aus `input/mytracks4mac`, Commit `e0d1f18`).
- **Heute:** Kein Treiber und kein Dateiformat ruft `GPSBabelRunner` noch auf. Übrig sind nur:
  - die Prüfung beim Start (`AppEnvironment.refreshRuntime`) und die Statusanzeige (`EnvironmentStatusView`);
  - der Rosetta-Installer;
  - die Lizenzhinweise;
  - das Beenden von Kindprozessen beim Quit (`ProcessRegistry`).
- **Voraussetzung:** `magellan-port`, `itracku-port` und `alan-port` sind umgesetzt.

## Goals / Non-Goals

**Goals:**
- **Bundle:** Die App ist ein Universal Binary ohne x86_64-Hilfsprogramme, ohne Qt und ohne Rosetta-Bezug.
- **Code und Dokumente:** Es gibt keinen toten Code und keine Spec-Anforderungen mehr, die gpsbabel voraussetzen.

**Non-Goals:**
- Ersatz für die 45 entfallenden Programmformate.
- Änderungen an portierten Formaten.
- Die Alt-App-Dokumentation.

## Decisions

### D1 Was entfällt, was bleibt

| Bereich | Entfällt | Bleibt |
|---|---|---|
| GPSLoaderKit | Modul `GPSBabelRuntime` (`GPSBabel.swift`, `ProcessRunner.swift`, `ProcessRegistry.swift`), `GPSBabelRuntimeTests`, Produkt in `Package.swift` | alle übrigen Module |
| LoggerCore | `LoggerError.Kind.rosettaMissing`, `.gpsbabelFailed` und ihre Texte; `DiagnosticEvent.process` und `ProcessRecord` | übrige Fehlerarten und Ereignisse |
| DiagnosticCapture | Ausgabe von `process`-Zeilen | Kopfangabe `isTranslated` |
| App | `RosettaInstallation.swift`, `EnvironmentStatusView`, Laufzeitstatus in `AppEnvironment`, Statusmenü der Debug-Ansicht, `-DebugSimulatedStatus`, Demo-Fall `childProcess` | `AppEnvironment` mit Reservierungen, Mitschnitt-Speicher und GPX-Creator |
| Projekt | Helpers-Kopie, Qt-Framework, Ziel `RosettaInstaller`, Bauphase `sign-helpers.sh`, `Vendor/gpsbabel-1.7.0` | `Vendor/Licenses` |

### D2 Lizenztexte

- **Neuer Ort:** `Vendor/Licenses/GPL-3.0.txt`, eine Kopie von `LICENSE`. Das Bundle erhält sie zusammen mit `MIT-GPSLoggerKit.txt` unter `Contents/Resources/Licenses`.
- **Test:** `AppFormatsTests.gplLicenseFilesMatch` vergleicht künftig `LICENSE`, `Packages/GPSLoggerKitGPL/LICENSE` und diese Kopie.
- **GPL-2.0 und LGPL-3.0:** Die portierten Dateien stehen unter GPL-3.0-or-later. Ihre Vorlagen erlauben „version 2 or any later version“, daher genügt der Text der GPL-3.0. LGPL-3.0 gehörte zu Qt.

### D3 Beenden der App

- **Ablauf:** `applicationShouldTerminate` bricht laufende Konvertierungen und Sitzungen ab und antwortet sofort mit `.terminateNow`.
- **Begründung:** Den Umweg über `.terminateLater` und `RunLoop.main.perform(inModes:)` gab es nur, um Kindprozesse abzuwarten. Ohne Kindprozesse schließt das System beim Beenden die offenen Ports.
- **Concurrency:** Alles läuft auf dem Main Actor, `Task.detached` entfällt.

### D4 Über-Fenster

- **Entfällt:** Der Absatz „gpsloader includes GPSBabel 1.7.0 … Qt Core 5.12.9 …“ und der Link „GPSBabel 1.7.0 source code“ (`AboutWindowController`, Zeilen 68–80 und 174).
- **Bleibt:** Die Liste aus `GPLFileFormats.credits` mit GPSBabel und igotu2gpx als Vorlagen. Damit bleibt die Quellenangabe für die portierten Dateien erhalten, und ein eigener gpsbabel-Link ist überflüssig.

### D5 Bundle-Prüfung

- **Entfällt:** die drei `check`-Zeilen für Helpers und Qt in `Scripts/verify-bundle.sh`.
- **Neue Prüfungen:**
  - Es gibt kein `Contents/Helpers` und kein `Contents/Frameworks/QtCoreGpsBabel.framework`.
  - Das Hauptprogramm enthält arm64 und x86_64 (`lipo -archs`).
  - `Contents/Resources/Licenses` enthält `GPL-3.0.txt` und `MIT-GPSLoggerKit.txt`.
- **Release-Builds:** Die Prüfung der Quellcode-Adresse bleibt unverändert.

### D6 Dokumentation

Angepasst werden:
- **`openspec/config.yaml`:**
  - Vertrieb (kein „Starten von gpsbabel“);
  - Treiber-Architektur (nur native Treiber);
  - die Abschnitte gpsbabel und Rosetta (gestrichen, mit einem Satz zur Entscheidung vom 2026-11-13);
  - „Weiterhin über gpsbabel“ (ersetzt durch die Liste der entfallenen Formate);
  - Lizenzsatz ohne RosettaInstaller;
  - Diagnose-Mitschnitt ohne gpsbabel-Ausgaben;
  - Streichung des gegenstandslosen GPSport-245-Vorschlags.
- **`CLAUDE.md`:** Leitplanken ohne gpsbabel und Rosetta. Die Verweise auf das gpsbabel-Binary der Alt-App bleiben als Quelle für Black-Box-Prüfungen.
- **`README.md`:** Aufbau, Module und Lizenzen.

### D7 Black-Box-Prüfungen nach dem Entfernen

- **Bisher:** Die Ports wurden gegen das gpsbabel-Binary aus dem App-Bundle geprüft (`Contents/Helpers`).
- **Künftig:** Die Quelle ist `input/mytracks4mac` (Commit `e0d1f18`, siehe `CLAUDE.md`), entpackt in den Scratchpad. Es kommt nie wieder ins Repository.
- **Ablage:** Die Memory-Notiz und `Packages/GPSLoggerKitGPL/README.md` nennen diesen Weg.

## Risks / Trade-offs

- **Anwender verlieren Programmformate:** Das betrifft z. B. OziExplorer, MapSource und CompeGPS. → Das ist bewusst entschieden (2026-11-13). Die Release Notes nennen die entfallenen Formate und verweisen auf gpsbabel als eigenständiges Werkzeug.
- **Prüfungen ohne Hardware:** Künftige Ports lassen sich nicht mehr mit dem gebündelten Binary prüfen. → D7.
- **Reihenfolge beim Archivieren:** `app-shell` wird auch von `gpl-driver-package` geändert. Die MODIFIED-Fassung hier baut auf dessen Stand auf. → `gpl-driver-package` wird zuerst archiviert.

## Migration Plan

- **Für Anwender:** Ein Update entfernt gpsbabel aus dem Bundle, Einstellungen bleiben erhalten.
- **UserDefaults:** Gespeicherte Gerätewahlen (`DeviceSelection`) verweisen nur auf native Einträge und bleiben gültig.
- **Rückweg:** ein Revert des Commits.
