# Proposal: Dateien nach GPX konvertieren (Dateimodus)

## Why

GPSLoggerKit liest NMEA, GPX und IGC inzwischen nativ, aber die App bietet dafür noch keine Bedienung. Der Dateimodus ist laut `docs/legacy-analysis.md` (Abschnitt 1 und 4) ein Kern der Alt-App: Viele Logger und Kameras legen ihre Daten als Dateien auf Speicherkarte oder USB-Speicher ab. Mit diesem Change kann der Anwender solche Dateien in gpsloader auswählen und als GPX speichern, ohne gpsbabel und ohne Rosetta.

## What Changes

- Neuer Befehl „Dateien konvertieren…“ (⌘O) im neuen Menü „Ablage“ und als Schaltfläche im Hauptfenster. Er öffnet einen Dateidialog für eine oder mehrere Dateien.
- Dateien lassen sich auch per Drag & Drop auf das Hauptfenster ziehen.
- Das Format jeder Datei wird am Inhalt erkannt. Angeboten werden alle Formate des GPSLoggerKit-Katalogs, derzeit NMEA 0183, GPX und IGC; neue Formate erscheinen ohne Änderung an der App.
- Nicht erkannte Dateien nennt die App mit Namen. Der Anwender kann ohne sie fortfahren oder abbrechen.
- Mehrere Dateien ergeben eine GPX-Datei. Dateien desselben Formats werden gemeinsam gelesen (NMEA: ein Track, ein Segment pro Datei; IGC: ein Track pro Datei), Ergebnisse verschiedener Formate werden zusammengefügt.
- Nachbearbeitung wie in der Alt-App: Korrektur des GPS-Wochenüberlaufs, und enthält das Ergebnis keine Tracks, werden die Wegpunkte zu einem Track.
- Während der Konvertierung erscheint das bekannte Fortschrittsfenster mit „Abbrechen“.
- Speichern über den Sicherungsdialog; vorgeschlagen wird der Name der ersten Datei mit Endung `.gpx`.
- Warnungen des Imports (z. B. verworfene Sätze) werden nach dem Speichern zusammengefasst angezeigt; Fehler mit lokalisierter Meldung und technischem Detail.
- Die Logik (Gruppieren nach Format, Lesen, Zusammenfügen, Dateiname) liegt in einem neuen, UI-unabhängigen Modul `FileConversion` in GPSLoaderKit und ist ohne Oberfläche testbar.

## Capabilities

### New Capabilities

- `file-conversion`: Dateien der nativ unterstützten Formate in der App auswählen, erkennen, zusammenführen und als GPX speichern.

### Modified Capabilities

(keine)

## Betroffene Geräte (gemäß `docs/legacy-device-catalog.md`)

Alle Katalogeinträge im Dateimodus, deren Format GPSLoggerKit nativ liest:

- **NMEA:** Amaryllo Trip Tracker, AMOD AGL3080, ATP Photo Finder, Canon EOS LOG, NMEA Fileformat, Sony GPS CS-1, Sony GPS CS-3.
- **GPX:** Garmin Colorado 300/400c/400i/400t, Dakota, GPSmap 62, Nuvi, Oregon, Road Tech Zumo, StreetPilot, Zumo.
- **IGC:** IGC Fileformat.

Weitere Familien (FIT/TCX/Suunto, CSV-Logger, Wintec-Dateien, Speicherabbilder) kommen mit ihren GPSLoggerKit-Changes automatisch hinzu.

## Nicht im Umfang

- **Dateiformate über gpsbabel** (Locosys SBP/SBN, Magellan u. a.): Sie brauchen die gpsbabel-Laufzeit und Rosetta und bekommen einen eigenen Change.
- **Gerätewahl aus dem Katalog:** Der Anwender wählt kein Gerätemodell; das Format wird erkannt. Die Gerätewahl für den Direktmodus ist ein eigener Change.
- **Manuelle Formatwahl** für Dateien, die nicht erkannt werden. Kommt bei Bedarf später; bisher erkennt jedes native Format seinen Inhalt zuverlässig.
- **Einstellungen** für Wochenüberlauf und Wegpunkte-als-Track: feste Voreinstellung wie in der Alt-App; ein Einstellungsfenster ist ein eigener Change.
- **Öffnen über Finder oder Dock** („Öffnen mit“, Dateitypen im Info.plist).
- **Diagnose-Mitschnitt** für Dateikonvertierungen.
- **Getrennte GPX-Dateien pro Eingabedatei.**

## Impact

- Neues Bibliotheksziel `FileConversion` in `Packages/GPSLoaderKit` (abhängig nur von `GPSLoggerKit`) mit Testziel `FileConversionTests`.
- `project.yml`: Produkt `FileConversion` für die App, Testziel im Schema.
- App: `MainMenuBuilder` (Menü „Ablage“), `MainWindowController` (Bereich „Dateien“, Drop-Ziel), neuer `ConversionPresenter`, Wiederverwendung von `ProgressSheetController`, `DebugAutomation` (Startargument für automatische Tests), `Localizable.xcstrings` (de, en).
- Keine Änderung an GPSLoggerKit.
