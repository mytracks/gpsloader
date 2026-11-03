# Design: GPSLoggerKit – Fundament, NMEA und GPX-Eingang

## Context

Motivation und Umfang stehen in `proposal.md`, die Anforderungen in den Specs `logger-kit`, `nmea-import`, `gpx-import` und `gpx-export`.

Ausgangslage im Repository:

- `Packages/GPSLoaderKit` (nur macOS 12) enthält zwei Teile, die wir übernehmen. Beide sind unser eigener Code aus `setup-foundation` und deshalb unter MIT übertragbar:
  - das Datenmodell `LoggerCore/Model.swift` (`TrackPoint`, `TrackSegment`, `Track`, `Waypoint`, `Recording`);
  - die GPX-1.1-Ausgabe `GPXExport/GPXWriter.swift`.
- `GPXWriter.write` meldet Fehler bisher als `LoggerError(.writeFailed)` aus `LoggerCore`. Das neue Paket darf `LoggerCore` nicht kennen.
- Werkzeuge: Xcode 27.1 (Swift 6.4) mit iOS-27.1-SDK und den Simulator-Runtimes iOS 27.0 und 27.1.
- Alt-Verhalten, auf das sich die Specs stützen (eigener Code):
  - NMEA-Dateien zusammenführen und `@`-Zeilen entfernen: `myTracks/Source/Classes/Controller/MyTracksMainController.m`, `convertNMEAFile:` und Umgebung (ca. Zeile 1883–1970).
  - Wochenüberlauf: `DsTrackFramework/Source/Classes/ImportExport/TrackLibraryGPX.m`, ca. Zeile 120–135.
  - Wegpunkte zu Track: siehe `docs/legacy-analysis.md`, Abschnitt 4.

## Goals / Non-Goals

**Goals:**

- Eine stabile, kleine öffentliche API, an die spätere Formate und Treiber ohne Umbau andocken.
- Speicher und Laufzeit sollen auch für NMEA-Dateien von 50 MB auf dem iPhone verkraftbar sein.
- Gleiches Ergebnis auf macOS und iOS, abgesichert durch dieselben Tests auf beiden Plattformen.

**Non-Goals:**

- Transporte, Treiber und `LoggerSession` bleiben in `GPSLoaderKit`.
- Keine Streaming-API, die beim Lesen fortlaufend Punkte liefert. Ergebnisse kommen als vollständige Aufzeichnung.
- Kein Schreiben anderer Formate als GPX.

## Decisions

### D1 Paketaufbau: ein Produkt, ein Ziel

`Packages/GPSLoggerKit/Package.swift` enthält:

- `swift-tools-version: 6.0` und `swiftLanguageModes: [.v6]`;
- `platforms: [.macOS(.v12), .iOS("27.0")]`;
- `defaultLocalization: "en"`;
- das Produkt `GPSLoggerKit` aus genau einem Ziel `GPSLoggerKit` mit den Ordnern `Model/`, `Formats/NMEA/`, `Formats/GPX/`, `Output/` und `Processing/`;
- das Testziel `GPSLoggerKitTests` mit `Fixtures/`.

Später kommt ein zweites Ziel `GPSLoggerDevices` dazu. Es enthält die Transporte, die es nur unter macOS gibt, und schließt seinen Code mit `#if os(macOS)` ab. Das passiert mit dem ersten nativen Logger-Treiber.

- *Alternative: viele kleine Module (Core, NMEA, GPX …).* Das wäre jetzt verfrüht und bremst nur die Arbeit; Formate sind intern ohnehin getrennt. Aufteilen lässt sich später ohne Bruch, indem `GPSLoggerKit` als Dachprodukt bleibt.
- *Swift-Tools 6.0* genügt für `.iOS("27.0")` in String-Form und für Swift Testing. Ein höherer Tools-Stand würde nur Nutzer mit älterem Xcode ausschließen.

### D2 Datenmodell

Die Typen aus `LoggerCore/Model.swift` werden übernommen und erweitert. Alle sind Werttypen und `Sendable` sowie `Hashable`.

- `TrackPoint` bekommt optional:
  - `speed` in m/s und `course` in Grad;
  - `satellites` als `Int`;
  - `hdop`, `vdop` und `pdop`;
  - `fix` als `FixType` (`none`, `twoD`, `threeD`, `dgps`).
- `Waypoint` bekommt dieselben optionalen Felder, damit WPL- und GPX-Wegpunkte nichts verlieren.
- Umsetzung: Die optionalen Qualitäts- und Bewegungswerte sind im Werttyp `PositionQuality` gebündelt (`TrackPoint.quality`, `Waypoint.quality`). So teilen Trackpunkt und Wegpunkt dieselbe Definition, und der GPX-Writer prüft mit `quality.isEmpty`, ob er etwas ausgeben muss.
- Einheiten liegen im Modell immer in SI-Einheiten vor. Die Formate rechnen um, z. B. NMEA-Knoten in m/s.

*Alternative: eine generische Attributliste.* Sie ist nicht typsicher und schlechter testbar. Weitere Felder wie Temperatur und Puls kommen bei Bedarf als eigene optionale Eigenschaften dazu.

### D3 Formatvertrag

```swift
public protocol FileFormat: Sendable {
    var id: FileFormatID { get }                       // "nmea", "gpx"
    var displayName: String { get }                   // localized
    var fileExtensions: [String] { get }
    func matches(prefix: Data) -> Bool                 // content sniffing, first 4 KB
    func read(_ inputs: [FileInput], options: ImportOptions) throws -> ImportResult
}
public struct FileInput: Sendable { public var name: String; public var data: Data }
public struct ImportResult: Sendable { public var recording: Recording; public var warnings: [ImportWarning] }
```

- `FileFormats.all` ist der Katalog.
- `FileFormats.detect(prefix:fileName:)` gibt das Format zurück, das als Erstes passt; die Dateiendung legt dabei nur die Reihenfolge der Prüfung fest. Passt keines, ist das Ergebnis `nil` und bedeutet „unbekannt“.
- `FileInput.load(_ url:)` liest per `Data(contentsOf:options: .mappedIfSafe)`. Security-scoped URLs unter iOS bleiben Sache der App.
- **Concurrency:** `read` ist synchron und frei von Seiteneffekten; Formate halten keinen veränderlichen Zustand.
  - Der Abbruch läuft kooperativ: Der Parser prüft alle 4096 Zeilen bzw. Elemente `Task.isCancelled` und wirft dann `CancellationError`.
  - Zusätzlich gibt es die Hülle `func read(...) async throws`. Sie ruft die synchrone Variante in einem Task auf, der nicht an den Main-Actor gebunden ist.
  - Die App ruft das Einlesen nie auf dem Main-Actor auf.
  - *Alternative: nur async mit AsyncSequence.* Mehr Komplexität ohne Nutzen, solange Ergebnisse vollständig zurückkommen.
- `ImportOptions` (`Sendable`):
  - `correctWeekRollover` (Standard `true`);
  - `referenceDate` (Standard: jetzt; in Tests fest gesetzt);
  - `waypointsAsTrackWhenNoTracks` (Standard `false`; die gpsloader-App setzt `true`).

  Die Nachbearbeitung (D8) wendet `FileFormats.read` nach dem Format-Parser an. So verhalten sich alle Formate gleich.

### D4 Fehler und Warnungen

- `GPSLoggerError` ist ein `struct` mit `kind` und `fileName`.
  - `kind` ist `unreadable`, `empty`, `malformed(line:)`, `noUsableData` oder `writeFailed`.
  - Es erfüllt `LocalizedError`; die Texte kommen aus `Localizable.xcstrings` in `Bundle.module` (de und en).
- `ImportWarning` hat `kind`, `count`, `fileName` und `firstLine`.
  - `kind` ist z. B. `checksumMismatch`, `malformedRecord`, `invalidCoordinate` oder `missingDate`.
  - Warnungen werden pro Art und Datei gezählt statt einzeln gesammelt; so bleibt der Speicher bei Millionen beschädigter Zeilen begrenzt.
- `CancellationError` wird unverändert durchgereicht.
- `GPSLoaderKit` übersetzt beim Schreiben `GPSLoggerError(.writeFailed)` in `LoggerError(.writeFailed)`. So bleiben die bestehenden App-Fehlertexte erhalten.

### D5 NMEA-Parser

- Grundlage sind öffentliche Beschreibungen der NMEA-0183-Sätze, also Feldreihenfolge und Prüfsumme (XOR zwischen `$` und `*`). GPL-Quelltext wird nicht genutzt. Die Feldtabellen stehen mit Quellenangabe in `PROVENANCE.md`.
- **Lesen:** Der Parser arbeitet auf den Bytes (`Data` bzw. `UnsafeRawBufferPointer`) und zerlegt in Zeilen bei LF, CR oder CRLF. Nur Zeilen, die mit `$` beginnen, werden als ASCII dekodiert. Andere Bytes werden ignoriert; damit sind auch Binärmüll und UTF-8-BOM abgedeckt.
- **Feldzerlegung:** per `split(separator: ",", omittingEmptySubsequences: false)` auf `Substring`. Talker sind die zwei Zeichen nach `$`, ausgewertet wird der Satztyp ab Zeichen 3; `$P…` wird übersprungen.
- **Epochen:** Ein Akkumulator sammelt alle Sätze mit derselben UTC-Zeit (hhmmss.sss als Ganzzahl in Millisekunden). Ändert sich die Zeit, wird der Punkt erzeugt.
  - GSA hat keine Zeit und gilt für die laufende Epoche.
  - VTG gilt ebenfalls für die laufende Epoche, aber nur als Ersatz für Geschwindigkeit und Kurs.
- **Datum:** Der Parser merkt sich das aktuelle Datum aus RMC bzw. ZDA.
  - Sinkt die Tageszeit gegenüber der vorherigen Epoche um mehr als 12 Stunden, gilt das als Mitternachtsübergang: Datum + 1.
  - Punkte ohne bekanntes Datum kommen in einen Puffer und erhalten beim ersten Datum dieses Datum. Liegt ihre Zeit nach der des ersten datierten Punkts, wird es um einen Tag zurückgerechnet.
  - Gibt es bis zum Dateiende kein Datum, bleiben die Punkte ohne Zeit, und es entsteht die Warnung `missingDate`.
- **Koordinaten:** `ddmm.mmmm` mit Hemisphäre wird zu Grad. Werte außerhalb des Wertebereichs erzeugen die Warnung `invalidCoordinate`.
- **Höhe:** aus GGA, Feld 9 (über dem Meeresspiegel). Die Geoid-Undulation wird nicht addiert, wie bei üblichen GPX-Erzeugern.
- **Segmente:** Mit jeder Datei beginnt ein neues Segment, ebenso, wenn eine Zeit vor der vorherigen liegt (Spec `nmea-import`).
- **Speicher:** Die Punkte liegen als `[TrackPoint]` vor; ein Punkt belegt 144 Byte (`MemoryLayout.stride`). Ohne Zeitsprung wird das Array ohne Kopie zum Segment.
- **Messung (Aufgabe 7.3, 2026-11-03):** synthetische NMEA-Datei mit 52 MB, RMC + GGA mit 1 Hz, 375.028 Epochen.

  | Umgebung | Einlesen | Speicher |
  |---|---|---|
  | macOS, eigenständiges Release-Programm (`/usr/bin/time -l`) | 1,35 s | Footprint-Spitze 129 MB; mit anschließender GPX-Ausgabe (64 MB) 149 MB; max. RSS 248 MB inklusive der eingeblendeten Datei |
  | iOS-27.1-Simulator, Release mit `ENABLE_TESTABILITY` | 2,5 s | Footprint-Zuwachs 103 MB |
  | iOS-27.1-Simulator, Debug | 16,3 s | Footprint-Spitze 130 MB |
  | macOS-Testprozess (`swift test -c release`, mit `-enable-testing`) | 1,3 s | Footprint-Zuwachs 199–200 MB |

  Maßgeblich ist der eigenständige Release-Prozess. Der Mehrbedarf im Testprozess entsteht beim Parsen im Test-Build mit `-enable-testing`, nicht beim Laden der Datei, die eingeblendet bleibt (7 MB nach dem Laden). Der größte Teil der Spitze geht auf das Verdoppeln der Array-Kapazität beim Anhängen zurück. Bei Bedarf lässt sich das mit kompakteren Punkten oder gestückelter Speicherung senken. Der optionale Test `PerformanceTests` (Umgebungsvariable `GPSLOGGERKIT_PERF_FILE`) prüft die 200-MB-Grenze deshalb nur unter iOS.

### D6 GPX-Parser

- Grundlage ist `XMLParser` aus Foundation, auf macOS und iOS verfügbar. Er arbeitet ereignisgesteuert, sodass große Dateien nicht als DOM im Speicher liegen. Ein Delegate-Objekt (`final class`, nur innerhalb von `read` benutzt) baut das Modell auf.
- Elemente werden über ihren lokalen Namen erkannt, der Namensraum spielt keine Rolle. Damit funktionieren GPX 1.0, GPX 1.1 und Dateien ohne Namensraum gleich.
- Text wird nur in den bekannten Blattelementen gesammelt. Innerhalb von `extensions` und `rte` wird nichts übernommen; ein Tiefenzähler steuert das.
- Zeiten liest ein eigener, kleiner ISO-8601-Parser: Datum, Zeit, optionaler Bruchteil, `Z`/`±hh:mm`/ohne Zone. `ISO8601DateFormatter` scheidet aus, weil Bruchteile dort nur mit Option gehen, es langsam ist und nicht `Sendable`.
- Bei einem Parse-Fehler entsteht `GPSLoggerError.malformed(line: parser.lineNumber)`. Das bis dahin aufgebaute Modell wird verworfen.

### D7 GPX-Ausgabe

`GPXWriter` wird mit identischer Ausgabe verschoben; die bestehenden Tests sichern das. Neu:

- `fix`, `sat`, `hdop`, `vdop` und `pdop` erscheinen in Schemareihenfolge nach `time` (bzw. `name`/`cmt` bei `wpt`). Für die DOP-Werte gibt es höchstens 2 Nachkommastellen ohne nachgestellte Nullen.
- `write(_:to:)` wirft `GPSLoggerError(.writeFailed)`.
- `creator` ist ein Parameter ohne Standardwert.

In `GPSLoaderKit` bleiben:

- `GPXFileName` (App-spezifisch);
- eine dünne Funktion `GPXExport.write(...)`, die den Fehler in `LoggerError` übersetzt.

### D8 Nachbearbeitung

`RecordingProcessing` enthält zwei reine Funktionen:

- `correctingWeekRollover(_:reference:)` verschiebt nach der Spec `logger-kit` um `1024 × 7 × 86400` Sekunden, solange die Zeit mehr als 512 Wochen vor der Referenz liegt. Die Funktion gilt für Trackpunkte und Wegpunkte. Das ist eine kleine Erweiterung gegenüber der Alt-App, die nur Trackpunkte korrigierte; ein Wegpunkt aus demselben Logger hat dasselbe Problem.
- `waypointsAsTrack(_:)`.

### D9 Migration in GPSLoaderKit und App

- `Packages/GPSLoaderKit/Package.swift` bekommt `dependencies: [.package(path: "../GPSLoggerKit")]`. `LoggerCore` hängt vom Produkt `GPSLoggerKit` ab.
- `LoggerCore/Model.swift` entfällt. Wer die Modelltypen nutzt, schreibt `import GPSLoggerKit`, also `Driver`, `LoggerSession`, `TestSupport`, die App und die Tests.
  - *Alternative: Typaliasse in `LoggerCore`.* Sie verschleiern, woher die Typen stammen, und müssten beim Auslagern ohnehin wieder weg.
- `GPXExport/GPXWriter.swift` entfällt. Die bisherigen `GPXWriterTests` und `GPXWriterConcurrencyTests` sowie `gpx.xsd` wandern in die Tests von `GPSLoggerKit`.
- `project.yml` braucht keinen Eintrag: XcodeGen und Xcode lösen die lokale Paketabhängigkeit transitiv auf. Falls nicht, wird `GPSLoggerKit` als zweites lokales Paket eingetragen; das prüft Aufgabe 6.3.

### D10 Tests

- Swift Testing, Fixtures liegen als Ressourcen im Testziel.
- Alle Fixtures sind selbst erstellt, aus erfundenen Koordinaten oder aus Aufzeichnungen des Entwicklers. Testdateien aus dem gpsbabel-Repository werden nicht übernommen, weil ihre Lizenz unklar bzw. GPL ist.
- Die XSD-Validierung mit `XMLDocument` läuft nur unter macOS (`#if os(macOS)`) und bleibt serialisiert, weil libxml2 nicht threadsicher ist. Unter iOS prüfen die Tests die Ausgabe durch Wiedereinlesen mit dem eigenen GPX-Parser auf Wohlgeformtheit und Inhalt.
- Auf iOS laufen die Tests über `xcodebuild test -scheme GPSLoggerKit -destination 'platform=iOS Simulator,OS=27.1,name=<verfügbares iPhone>'` im Paketordner.

### D11 Herkunft und Lizenz

- `Packages/GPSLoggerKit/LICENSE`: MIT, „Copyright (c) 2026 Dirk Stichling“.
- `Packages/GPSLoggerKit/PROVENANCE.md` führt pro Format die Grundlagen auf (Spezifikation mit Titel und Fundstelle, eigener Code, Beobachtung). Ein Test prüft, dass jede `FileFormatID` im Katalog dort einen Abschnitt hat.
- `README.md` beschreibt Zweck, Plattformen, Nutzung und die Clean-Room-Regel.

## Risks / Trade-offs

- **NMEA-Dialekte:** Manche Geräte schreiben Zusatzzeilen oder fehlerhafte Felder, etwa Canon mit eigener Kopfzeile oder Sony mit `@`-Zeilen.
  → Robuster Zeilenfilter. Der Entwickler stellt echte Dateien als Fixtures bereit (manuelle Aufgabe).
- **Datumsheuristik:** Die Mitternachtsregel und die Rückdatierung können bei Dateien mit großen Zeitlücken ohne RMC das falsche Datum ergeben.
  → Warnung `missingDate` bei völlig fehlendem Datum; die Regeln sind dokumentiert und getestet.
- **Wochenüberlauf:** Echte Aufzeichnungen, die älter als etwa 9,8 Jahre sind, werden fälschlich um 19,6 Jahre verschoben.
  → Wie in der Alt-App, und die Korrektur ist abschaltbar. Die App kann später eine Einstellung anbieten.
- **Speicher bei großen Dateien auf dem iPhone.**
  → Messung in Aufgabe 7.3. Bei Bedarf liest `FileInput` per Memory-Mapping, das ist bereits so vorgesehen.
- **iOS 27 als Mindestversion:** Mögliche Geräte werden nur auf dem Simulator getestet.
  → Ein Test auf einem echten Gerät ist eine manuelle Aufgabe.
- **Umbau von GPSLoaderKit:** Er kann das Verhalten der App unbemerkt verändern.
  → Die GPX-Ausgabe bleibt byteidentisch (bestehende Tests mit festen Erwartungen). Danach werden alle bestehenden Tests und `xcodebuild test` erneut ausgeführt.

## Migration Plan

1. Paket anlegen: Modell, Writer und Tests dorthin verschieben, Tests grün.
2. NMEA, GPX-Eingang und Nachbearbeitung umsetzen.
3. `GPSLoaderKit` und die App umstellen; alle Tests und der App-Build müssen grün sein.

Ein Rückweg ist einfach: Der Umbau ist ein einzelner Commit, ein `git revert` genügt.

## Open Questions

- Welche echten NMEA- und GPX-Dateien kann der Entwickler als Fixtures beisteuern, etwa Sony CS-1, Canon EOS oder Garmin Oregon? Sie ergänzen die selbst erstellten Fixtures, ohne den Plan zu ändern.
