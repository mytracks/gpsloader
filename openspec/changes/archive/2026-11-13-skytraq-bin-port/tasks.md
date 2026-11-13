# Tasks: skytraq-bin-port

## 1. Gemeinsame Hilfen im GPL-Paket

- [x] 1.1 `Support/ImportSupport.swift` nach design.md D2: `Warnings`, `Cancellation`, `trackName(ofFile:)`, `ByteReader`, `GPSTime` mit Schaltsekunden und Wochenzyklus, `L10n`. Dazu `Resources/Localizable.xcstrings` und `defaultLocalization` in `Package.swift`.
- [x] 1.2 Tests zu 1.1. Prüfen: `GPSTime` ergibt für Woche 380, Sekunde 302 400 und das Referenzdatum 2026-11-13 die Zeit 2026-07-22T11:59:42Z (Szenario „Aktueller Wochenzyklus“). Bei einer Woche über der aktuellen Woche modulo 1024 gilt der vorige Zyklus. Die Schaltsekunden an den Grenzen 2016-12-31/2017-01-01 stimmen. `Warnings` fasst gleiche Arten zusammen, und `ByteReader` liefert außerhalb des Bereichs `nil`.

## 2. SkyTraq-Leser

- [x] 2.1 `SkyTraq/SkyTraqBinFileFormat.swift` nach D1, D3 und D4 mit dem Dateikopf nach Regel 6: Sektoren, Eintragstypen, middle-endian-Werte, ECEF nach WGS 84, Markierungen, Fehlerverhalten, Track pro Abbild, Abbruch. Eintrag in `GPLFileFormats.all`, Name `format.skytraq-bin` (de, en).
- [x] 2.2 `GPLFileFormats.credits` um gpsbabel ergänzen (Projekt „GPSBabel“, Urheber laut `skytraq.cc`, Lizenz GPL-2.0-or-later, Adresse `https://github.com/GPSBabel/gpsbabel/tree/gpsbabel_1_7_0`). Den Test, der bisher leere `credits` erwartet, anpassen. Prüfen: Das Szenario „SkyTraq im Katalog“ der Spec `logger-kit-gpl` ist abgedeckt.
- [x] 2.3 Test-Encoder `SkyTraqTestDump` nach D7 und Tests zu 2.1. Prüfen:
  - Die Szenarien der Spec `skytraq-import` sind abgedeckt: „Leerer Sektor beendet das Abbild“, „Voller Sektor“, „Zeit eines vollen Eintrags“, „Position aus ECEF“, „Fortgeschriebene Position“ und „Zehn Punkte pro Sekunde“.
  - Ebenso „Taste gedrückt“, „Unbekannter Eintrag“, „Komprimierter Eintrag am Anfang“, „Abbild aus gpsbabel“, „Abbild mit Endung .bin“ und „Andere Binärdatei“.
  - Negative Deltas (Wert 512 ergibt -1) und ein POI mit hoher Rate werden geprüft.
  - Der Abbruch eines Abbilds mit über 50 MB endet in weniger als einer Sekunde mit `CancellationError`.

## 3. Fixture und Gegenprüfung

- [x] 3.1 `Fixtures/venus.bin` mit dem Encoder erzeugen (D7), dazu ein Test, der die Fixture mit der Encoder-Ausgabe vergleicht, und ein Fixture-Test über den Katalog der App (`FormatCatalog.standard.adding(GPLFileFormats.all)`). Die geschriebene GPX-Datei ist gültig nach dem GPX-1.1-Schema (`xmllint` im Scratchpad; das Schema liegt nur im Testziel von GPSLoggerKit).
- [x] 3.2 Black-Box-Gegenprüfung mit dem gpsbabel-1.7.0-Binary (`-i skytraq-bin`). Prüfen: Punktanzahl, Positionen, Höhen, Zeiten und Geschwindigkeiten stimmen bis auf die Abweichungen aus D4 überein. Das Ergebnis steht in `PROVENANCE.md`.

## 4. Dokumentation und Regeln

- [x] 4.1 `PROVENANCE.md` des GPL-Pakets: Abschnitt `skytraq-bin` mit Vorlage, Zeilen, Lizenzzitat, SHA-256 des Archivs, Abweichungen und Gegenprüfung. Die README des GPL-Pakets nennt das Format. Im README des Repositorys kommt SkyTraq in die Formatliste.
- [x] 4.2 `openspec/config.yaml`: Die Zuordnung der Familien nach der Entscheidung des Entwicklers vom 2026-11-13 eintragen. SkyTraq, Navilink/Locosys, MTK, Wintec, i-GotU und GoPal gehen nach GPSLoggerKitGPL, SkyTraq mit dem Vermerk „Dateiformat portiert“. NAL bleibt ausgenommen, V-900 und iBlue-CSV bleiben in GPSLoggerKit. Prüfen: Der Kontext bleibt unter 51 200 Byte, und `openspec validate --all --strict` ist grün.

## 5. Abschluss

- [x] 5.1 Prüfen, dass alles grün ist:
  - `swift test` in GPSLoggerKitGPL, GPSLoggerKit und GPSLoaderKit, dazu `xcodebuild test` für die App;
  - das GPL-Paket mit GPSLoggerKit in den Scratchpad kopiert und dort getestet;
  - `openspec validate skytraq-bin-port --strict`.

  Snapshots zeigen das Hauptfenster mit zehn Formaten und das Über-Fenster mit „Portierte Formate“.
- [ ] 5.2 [manuell, Hardware] Der Entwickler liest einen SkyTraq-Logger mit gpsbabel aus (`-i skytraq,dump-file=venus.bin`) und konvertiert das Abbild in der App. Prüfen: Punktanzahl, Zeiten und Positionen stimmen mit der gpsbabel-Ausgabe überein.
