# Tasks: mtk-bin-port

## 1. Leser

- [x] 1.1 `ByteReader` um Float32 und Float64 (Little Endian) erweitern. Prüfen: Ein Test liest die Werte 1,5 und -100,25 korrekt.
- [x] 1.2 `MTK/MTKBinFileFormat.swift` nach design.md D1–D4 mit Dateikopf nach Regel 6: `MTKDump` mit Kopf, Blöcken, Info-Blöcken, Holux-Kennungen, Datensätzen, Satellitendaten, Prüfsumme, Fix-Art, Tracks, Wegpunkten und Abbruch. `MTKBinFileFormat` und `M241BinFileFormat` in `GPLFileFormats.all` eintragen, Namen `format.mtk-bin` und `format.m241-bin` (de, en).
- [x] 1.3 Erkennung nach D5.
- [x] 1.4 `credits`: Die Urheber des gpsbabel-Eintrags um Per Borgentun und Andy Armstrong ergänzen. Prüfen: Das Szenario „MTK-Formate abfragen“ der Spec `logger-kit-gpl` ist abgedeckt.

## 2. Tests

- [x] 2.1 Test-Encoder `MTKTestDump` nach D7.
- [x] 2.2 Tests zu 1.2 und 1.3. Prüfen:
  - Abgedeckt sind alle Szenarien der Spec `mtk-import`: „Ungültiger erster Kopf“, „Zwei Blöcke“, „Datensatz eines iBlue 747“, „Millisekunden“, „Falsche Prüfsumme“, „Drei Satelliten“, „Unsinnige Position“ und „Neue Formatmaske“.
  - Ebenso „Logger zweimal eingeschaltet“, „Taste gedrückt“, „Holux M-241“, „Holux GPSport 245“, „Abbild eines iBlue 747“, „Abbild eines Holux M-241“ und „SkyTraq-Abbild“.
  - Ein fehlendes `*` vor `0xFF` überspringt den Datensatz.
  - Das SkyTraq-Format erkennt die MTK-Fixtures nicht.
  - Der Abbruch eines Abbilds mit über 50 MB endet in weniger als einer Sekunde.

## 3. Fixtures und Gegenprüfung

- [x] 3.1 `Fixtures/mtk.bin` und `Fixtures/m241.bin` mit dem Encoder erzeugen. Dazu ein Test, der sie mit der Encoder-Ausgabe vergleicht, und ein Fixture-Test über den Katalog der App. Prüfen: Die GPX-Ausgabe ist mit `xmllint` gültig nach dem GPX-1.1-Schema.
- [x] 3.2 Black-Box-Gegenprüfung mit dem gpsbabel-1.7.0-Binary nach D7. Prüfen: Übereinstimmung bis auf die Abweichungen aus D4, das Ergebnis steht in `PROVENANCE.md`.

## 4. Dokumentation

- [x] 4.1 `PROVENANCE.md` (Abschnitte `mtk-bin`, `m241-bin`), die README des GPL-Pakets, das README des Repositorys und `openspec/config.yaml` (MTK: Dateiformate portiert). Prüfen: Der Provenance-Test und `openspec validate --all --strict` sind grün.

## 5. Abschluss

- [x] 5.1 Prüfen, dass alles grün ist: `swift test` in GPSLoggerKitGPL und GPSLoaderKit, `xcodebuild test` für die App, das GPL-Paket als Kopie im Scratchpad und `openspec validate mtk-bin-port --strict`. Ein Snapshot zeigt das Hauptfenster mit zwölf Formaten.
- [ ] 5.2 [manuell, Hardware] Der Entwickler liest einen MTK-Logger (z. B. iBlue 747 oder Qstarz) und einen Holux M-241 mit gpsbabel aus und konvertiert die entstandene `data.bin` in der App. Prüfen: Punktanzahl, Zeiten und Positionen stimmen mit der gpsbabel-Ausgabe überein.
