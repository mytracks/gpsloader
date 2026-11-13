# Proposal: KML- und KMZ-Import in GPSLoggerKit

## Why

KML und KMZ sind die Austauschformate von Google Earth, vielen Tracker-Apps und Logger-Programmen. Außerdem erzeugen gpsbabel und der Export von myTracks selbst KML. Wer solche Dateien hat, kann sie im Dateimodus bisher nicht nach GPX konvertieren. Das Paket liest sie nicht, und der Dateimodus nutzt bewusst kein gpsbabel. KML 2.2 ist ein offener OGC-Standard, und Googles `gx:`-Erweiterung ist öffentlich beschrieben. Deshalb lässt sich der Import clean-room umsetzen.

Repräsentative Beispieldateien hat der Entwickler nicht. Deshalb beschränkt sich der Change auf die Dialekte, die Standard und Erweiterung eindeutig festlegen. Dazu kommen genau die zwei Abweichungen, die sich am eigenen myTracks-Code und an der Ausgabe des gpsbabel-Binaries beobachten ließen (Stufe A, entschieden am 2026-11-04).

## What Changes

- **Neues Format `kml` (Keyhole Markup Language, Endungen `.kml` und `.kmz`)** in GPSLoggerKit, für macOS und iOS:
  - `Placemark` mit `LineString` ergibt einen Track ohne Zeiten. Mehrere `LineString` in einer `MultiGeometry` ergeben Segmente desselben Tracks.
  - `gx:Track` ergibt einen Track mit Zeiten aus `when` und Koordinaten aus `gx:coord`. `gx:MultiTrack` ergibt einen Track mit einem Segment pro enthaltenem `gx:Track`.
  - `Placemark` mit `Point` ergibt einen Wegpunkt mit Name, Beschreibung und, falls vorhanden, der Zeit aus `TimeStamp`.
  - Gelesen werden die Namensräume KML 2.2 (OGC), die älteren Google-Namensräume 2.0, 2.1 und 2.2 sowie Dateien ohne Namensraum.
- **Zeiten aus gpsbabels Ordner „Points“** (entschieden am 2026-11-04):
  - gpsbabel 1.7.0 legt standardmäßig neben jede `LineString` einen Ordner „Points“ mit einem zeitgestempelten Placemark pro Trackpunkt.
  - Passt dieser Ordner Punkt für Punkt zum Track, übernimmt der Track die Zeiten. Die Punkte werden dann keine Wegpunkte.
  - Jede andere Struktur folgt den allgemeinen Regeln.
- **Höhe** (entschieden am 2026-11-04):
  - Übernommen wird sie bei `altitudeMode` `absolute` und bei fehlendem `altitudeMode`. myTracks und gpsbabel schreiben echte Höhen ohne `altitudeMode`.
  - Ist ausdrücklich ein Bodenbezug gesetzt (`clampToGround`, `relativeToGround`, `clampToSeaFloor`, `relativeToSeaFloor`), bleibt die Höhe leer.
  - Sind alle Höhen einer Geometrie 0, bleibt die Höhe ebenfalls leer.
- **KMZ:** Ein eigener kleiner ZIP-Leser nach der öffentlichen PKWARE-Spezifikation liest das Hauptdokument (`doc.kml`, sonst die erste `.kml` im Wurzelverzeichnis). Entpackt wird mit Apples `Compression`-Framework.
- Ein Track ohne jede Zeitangabe ergibt pro Datei eine Warnung, aber keine Warnung pro Punkt.
- KML und KMZ werden am Inhalt erkannt. Der Formatkatalog enthält zusätzlich `kml`, und `PROVENANCE.md` nennt die Quellen.

## Capabilities

### New Capabilities

- `kml-import`: KML- und KMZ-Dateien einlesen und daraus Tracks und Wegpunkte bilden.

### Modified Capabilities

- `logger-kit`: Der Formatkatalog enthält zusätzlich `kml` mit den Endungen `kml` und `kmz`.

## Betroffene Geräte (gemäß `docs/legacy-device-catalog.md`)

- Der Gerätekatalog enthält keinen Eintrag für KML. In myTracks lief KML nur über die allgemeine Konvertierung von gpsbabel (`-i kml`), die zur Track-Verwaltung gehörte.
- Mittelbar betroffen sind alle Logger und Programme, die KML exportieren. Ihre Ausgaben sind nicht als Beispieldateien verfügbar. Bei ihnen greifen nur die allgemeinen Regeln.
- **Abweichung von `openspec/config.yaml`:** KML steht weder im nativen Umfang noch in der festgelegten Reihenfolge. Der Entwickler hat den Change am 2026-11-04 vor SkyTraq gestartet. `config.yaml` wird entsprechend ergänzt.

## Nicht im Umfang

- **Stufe B:** Gemeint sind Ordner mit zeitgestempelten Punkten, die nicht gpsbabels Muster „Points“ folgen. Solche Punkte bleiben Wegpunkte. Ein eigener Change folgt, sobald echte Dateien vorliegen.
- **`ExtendedData`:** Werte wie Puls, Trittfrequenz oder Geschwindigkeit in `SchemaData` bzw. `gx:SimpleArrayData` werden nicht übernommen. Ihre Namen sind nicht genormt, und das Datenmodell hat für Sportdaten keine Felder.
- **Zeiten aus `TimeSpan`:** Ein `TimeSpan` an einer `LineString` wird nicht auf die Punkte verteilt, denn das wären erfundene Zeitstempel.
- **Andere Geometrien:** `Polygon`, `LinearRing`, `Model`, Overlays, Styles, `gx:Tour` und Kamera-Elemente werden ohne Warnung übergangen.
- **`NetworkLink`:** Das Paket ruft keine URLs ab.
- **Weitere Dateien im KMZ:** Bilder und verlinkte weitere KML-Dateien werden nicht gelesen.
- **ZIP-Varianten:** ZIP64, verschlüsselte Archive und andere Kompressionsverfahren als „stored“ und „deflate“.
- **KML-Ausgabe:** Das Paket schreibt nur GPX.
- **Echte Dateien als Fixtures:** Wie bei FIT, TCX und Suunto gibt es nur synthetische Fixtures. Ihre Struktur folgt dem Standard bzw. der beobachteten Ausgabe von gpsbabel und myTracks.

## Impact

- Neue Dateien in `Packages/GPSLoggerKit/Sources/GPSLoggerKit/Formats/KML/`: KML-Leser und ZIP-Leser.
- `FileFormatID.kml` wird in `FileFormats.all` eingetragen.
- `ImportWarningKind` bekommt einen neuen Fall für einen Track ohne Zeiten, mit Lokalisierung (Deutsch, Englisch).
- Tests mit synthetischen Fixtures. Für KMZ baut ein kleiner Test-Encoder Archive mit „stored“ und „deflate“.
- `PROVENANCE.md`, das README des Pakets, das README des Repositorys und `openspec/config.yaml` werden ergänzt.
- Die App braucht keine Änderung, denn der Dateimodus übernimmt neue Formate automatisch.
- Neue Paketabhängigkeiten gibt es nicht. `Compression` ist ein Systemframework für macOS 12 und iOS.
