# Offene Hardware- und Anwendertests

Stand: 2026-11-13. Die Changes sind archiviert, diese Tests stehen aber noch aus. Der Entwickler hatte die Logger zu diesem Zeitpunkt nicht zur Hand. Jeder Eintrag nennt den Change (unter `openspec/changes/archive/`) und die Task, aus der er stammt. Nach einem Test hier abhaken und Abweichungen als neuen Change oder Fehlerbericht erfassen.

## Vergleich mit gpsbabel

- **Woher gpsbabel kommt:** Die App enthält kein gpsbabel mehr (Change `remove-gpsbabel`). Für die Vergleiche wird das gpsbabel-1.7.0-Binary der Alt-App benutzt:
  - aus der myTracks-Historie (`input/mytracks4mac`, Commit `e0d1f18`) oder
  - aus `Import/Apps/GPSBabelFE170.app`, samt `QtCoreGpsBabel.framework`.

  Es wird in einen temporären Ordner kopiert, nie ins Repository.
- **Rosetta:** Auf Apple Silicon braucht dieses Binary Rosetta, die App selbst nicht.
- **Bei Fehlern am Gerät:** in der App „Hilfe > Support-Paket erstellen …“ wählen (oder den Knopf in der Fehlermeldung) und das ZIP schicken. Der Diagnose-Mitschnitt läuft immer mit und liegt im Paket; er dient zugleich als Test-Fixture.

## Vor jedem Release

- [ ] **Start ohne Rosetta** (`remove-gpsbabel` 3.3).
  - Release-Build auf einem Apple-Silicon-Mac ohne Rosetta und auf einem Intel-Mac starten.
  - Prüfen: Es erscheint kein Rosetta-Dialog, Dateimodus und Direktmodus funktionieren.
- [ ] **Adresse des Quellcodes** (`gpl-driver-package` 6.2).
  - Entschieden am 2026-11-13: `GPSLOADER_SOURCE_CODE_URL` ist `https://github.com/mytracks/gpsloader`.
  - Prüfen: Das Repository ist öffentlich, und der Stand des Releases ist dort gepusht.
  - Quellen von gpsbabel und Qt müssen dort nicht mehr liegen, weil beide nicht mehr mitgeliefert werden.
  - Prüfen: `Scripts/verify-bundle.sh` ist für den Release-Build grün, und der Link im Über-Fenster öffnet die Quelle.

## Direktmodus – Entwickler

- [ ] **Release 0.1.0 von GitHub** (`split-repositories` 6.2): `myTracks-Loader-0.1.0.zip` von https://github.com/mytracks/gpsloader/releases/tag/0.1.0 auf einem Apple-Silicon-Mac und einem Intel-Mac laden, entpacken, starten und ein Gerät auslesen. Prüfen: Die App startet ohne Gatekeeper-Warnung, und das Auslesen gelingt.

- [ ] **SkyTraq** (`skytraq-device-port` 3.2): einen SkyTraq-Logger auslesen und löschen. Prüfen: Punktanzahl und Zeiten wie gpsbabel (`-i skytraq`), danach ist der Logger leer.
- [ ] **MTK und Holux** (`mtk-device-port` 3.2): einen MTK-Logger (z. B. Qstarz) und einen Holux M-241 auslesen und löschen. Prüfen: Ergebnisse wie gpsbabel, und das Logging läuft danach weiter.
- [x] **Hauptfenster** (`main-window-sections` 2.2): Umschalter in der Werkzeugleiste (beide Segmente lesbar beschriftet, im hellen und dunklen Modus: bestätigt vom Entwickler am 2026-11-19; in den Snapshots der Debug-Automation fehlt die Beschriftung des gewählten Segments, das liegt an der Aufnahme), ⌘1/⌘2, Drag & Drop aus dem Finder in beiden Bereichen, Klick auf die Ablagefläche. Prüfen: Ablauf wie in den Specs `app-shell` und `file-conversion`. Ergebnis: Alles bestätigt vom Entwickler am 2026-11-19 (Beschriftung hell/dunkel, ⌘1/⌘2, Drag & Drop aus dem Finder, Klick auf die Ablagefläche).
- [ ] **Anschlüsse und Hinweise** (`device-ports-and-hints` 4.2): den Holux M-241 per USB anstecken und per Bluetooth koppeln.
  - Prüfen: Beide Anschlüsse haben sprechende Namen; bei gewähltem Bluetooth-Anschluss erscheint der Hinweis „über USB verbinden“.
  - Prüfen: Die vier Treiberseiten (Silicon Labs, Prolific, FTDI, WCH; `USBSerialChip` in `Packages/GPSLoaderKit/Sources/DeviceDrivers/PortPresentation.swift`) öffnen sich im Browser.
- [x] **App-Icon** (`rename-and-icon` 3.4): `myTracks Loader.app` im Finder und im Dock unter macOS 27 und, falls verfügbar, unter macOS 12–15 ansehen. Prüfen: Das Icon steht nicht verkleinert in einer grauen Fläche und wirkt neben myTracks Neo stimmig. Ergebnis: in Ordnung, bestätigt vom Entwickler am 2026-11-19.
- [ ] **Support-Paket** (`support-package` 4.2): nach einem echten Auslesen (z. B. Holux M-241) „Hilfe > Support-Paket erstellen …“ wählen. Prüfen: Das ZIP lässt sich im Finder öffnen, und System, Protokoll, Anschlüsse und der Mitschnitt des Vorgangs sind vollständig und lesbar.
- [ ] **Wochenüberlauf** (`device-week-rollover` 3.2): den Holux M-241, dessen Zeiten um 1024 Wochen zu früh lagen, erneut auslesen. Prüfen: Die Zeiten im GPX liegen im richtigen Jahr.
- [ ] **Wintec** (`wintec-device-port` 3.2): einen WBT-201 bzw. G-Rays 2 auslesen. Prüfen: Ergebnis wie gpsbabel (`-i wbt`).
- [ ] **Magellan** (`magellan-port` 3.2): einen Meridian oder SporTrak seriell auslesen. Prüfen: Track und Wegpunkte wie gpsbabel (`-t -w -i magellan`).

## Direktmodus – Anwender

Der Entwickler hat keine i-GotU- und keine Bluetooth-Logger.

- [ ] **i-GotU auslesen** (`igotu-driver` 3.2): einen GT-800 und ein USB-Modell (z. B. GT-120) auslesen.
  - Prüfen: Das USB-Modell wird über HID gefunden. Meldet die App „Gerät nicht gefunden“, braucht es einen anderen USB-Zugang.
  - Prüfen: Die Punkte stimmen mit @trip PC bzw. igotu2gpx überein.
- [ ] **i-GotU löschen** (`igotu-driver` 3.3), experimentell. Prüfen: Danach meldet das Gerät 0 Datensätze.
- [ ] **Locosys** (`navilink-device-port` 2.2): einen GT-31 im NAVILINK-Modus auslesen. Prüfen: Wegpunkte und Track wie gpsbabel (`-i navilink`).
- [ ] **GNS 2000 / GNS 2000 plus** (`gns2000-driver` 5.2): in den Systemeinstellungen koppeln, in der App auslesen und löschen.
  - Prüfen: Der Bluetooth-Berechtigungsdialog erscheint einmal mit dem Begründungstext.
  - Prüfen: Die Punkte stimmen mit myTracks bzw. der Hersteller-Software überein; nach dem Löschen ist der Speicher leer.
  - Byte 15 der Datensätze notieren (vermutlich eine Prüfsumme), am besten per Diagnose-Mitschnitt.
- [ ] **XAiOX iTrackU** (`itracku-port` 2.2): über Bluetooth oder USB auslesen.
  - Prüfen: Punkte wie gpsbabel (`-t -i itracku`).
  - gpsbabel verwirft die letzten Datensätze, die zusammen mit der Endemarke ankommen. Die App hat dann einige Punkte mehr.

## Dateimodus – Entwickler

- [ ] **Columbus V-900, Visiontac, iBlue-CSV** (`csv-logger-import` 6.2).
  - Prüfen: Punktanzahl, Zeiten (UTC oder Ortszeit?), Höhen und Wegpunkte sind plausibel und wie bei gpsbabel.
  - Abweichende Kopfzeilen notieren.
- [ ] **MTK- und Holux-Speicherabbild** (`mtk-bin-port` 5.2): eine `data.bin` von iBlue 747/Qstarz und von Holux M-241 konvertieren. Prüfen: Punktanzahl, Zeiten und Positionen wie gpsbabel.
  - Die App schreibt beim Auslesen kein Abbild. Es entsteht beim Auslesen mit gpsbabel (`-i mtk` bzw. `-i m241`, Datei `data.bin`) oder stammt aus vorhandenen Sicherungen.
- [ ] **SkyTraq-Speicherabbild** (`skytraq-bin-port` 5.2): ein Abbild aus `gpsbabel -i skytraq,dump-file=venus.bin` konvertieren. Prüfen: wie gpsbabel.
- [ ] **Wintec** (`wintec-file-port` 5.2): eine TES-Datei (WBT-202) und, falls vorhanden, eine BIN- oder TK1-Datei konvertieren. Prüfen: Punktanzahl, Zeiten und Höhen wie gpsbabel.
- [ ] **Locosys SBP und SBN** (`locosys-file-port` 5.2). Prüfen: Die Dateien werden erkannt; Punktanzahl, Zeiten und Positionen wie gpsbabel.
- [ ] **Medion GoPal** (`gopal-port` 5.2): eine `.trk`-Datei konvertieren. Prüfen: Datum, Zeiten, Positionen und Geschwindigkeit sind plausibel.
- [ ] **Magellan SD-Karte** (`magellan-port` 3.2): eine `.log`- bzw. `.upt`-Datei von Meridian oder eXplorist konvertieren. Prüfen: wie gpsbabel.
- [ ] **Alan Map500** (`alan-port` 3.2): eine echte `.trl`-Datei konvertieren.
  - Prüfen: Die Datei wird erkannt. Die Erkennung prüft nur, ob die Koordinaten plausibel sind.
  - Prüfen: Tracks und Punkte wie gpsbabel (`-t -i alantrl`).
- [ ] **KML und KMZ** (`kml-import` 5.3): vorhandene Exporte aus myTracks, Google Earth oder Logger-Programmen konvertieren.
  - Prüfen: Tracks, Punktanzahl und Höhen wie gpsbabel (`-i kml`).
  - Dateien notieren, bei denen Punkte mit Zeitstempel als Wegpunkte statt als Track erscheinen (Kandidaten für Stufe B).
  - Nicht erkannte KMZ-Dateien notieren.
