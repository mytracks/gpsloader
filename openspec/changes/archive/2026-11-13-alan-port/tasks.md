# Tasks: alan-port

## 1. Format

- [x] 1.1 `Alan/AlanFileFormat.swift` nach design.md D1–D4, mit Dateikopf nach den Regeln des GPL-Pakets (Vorlage, Urheber, Lizenz, Übersetzungshinweis, SPDX).
- [x] 1.2 Tests mit `AlanTestFile`. Prüfen: Die Szenarien „Falsche Kennung“, „Zu kurze Datei“, „Zwei belegte Tracks“, „Umrechnung“, „Zu große Punktzahl“ und „Textdatei mit Endung trl“ der Spec `alan-import` sind abgedeckt.

## 2. Katalog und Herkunft

- [x] 2.1 `GPLFileFormats.all` (am Ende), `credits` (Gunar Megger), Lokalisierung des Formatnamens (de/en), `PROVENANCE.md` und `README.md` des Pakets. Prüfen: Das Szenario „Alan-Format abfragen“ der Spec `logger-kit-gpl` ist durch einen Test abgedeckt.
- [x] 2.2 `openspec/config.yaml`: Alan Map500 aus „Weiterhin über gpsbabel“ in die Zuordnungsliste des GPL-Pakets (Change `alan-port`).

## 3. Gegenprüfung und Abschluss

- [x] 3.1 Fixture `map500.trl` und Black-Box-Vergleich nach D6. Prüfen: Das Ergebnis steht in `PROVENANCE.md`, und alle Tests sowie `openspec validate alan-port --strict` sind grün.
- [ ] 3.2 [manuell, Hardware] Der Entwickler konvertiert eine echte `.trl`-Datei eines Alan Map500 im Dateimodus. Prüfen: Die Datei wird erkannt, und Tracks und Punkte stimmen mit gpsbabel 1.7.0 (`-t -i alantrl`) überein.
