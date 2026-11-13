# Design: Medion-GoPal-Tracks (Portierung)

## Context

GPSLoggerKitGPL hat die gemeinsamen Hilfen der früheren Portierungen. Bisher war GoPal das einzige Textformat im Paket. Das Zerlegen in Zeilen übernimmt eine eigene kleine Hilfe, weil `TextLines` von GPSLoggerKit intern ist. Die Alt-App las GoPal über gpsbabel (`gopal`, `input/mytracks4mac/myTracks/Source/Resources/gpslogger.plist`).

## Goals / Non-Goals

**Goals:** Für dieselben Dateien liefert `gopal` dieselben Positionen und Höhen wie gpsbabel 1.7.0. Zeiten, Geschwindigkeit und Ausgabe als Track werden nach D4 korrigiert.

**Non-Goals:** die Optionen der Vorlage (`date`, `maxspeed`, `minspeed`, `clean`) und das Schreiben von GoPal-Dateien.

## Decisions

### D1 Vorlage und Lizenz

- **Archiv:** gpsbabel `gpsbabel_1_7_0`, wie in `skytraq-bin-port`.
- **Datei `gopal.cc`:**
  - Zeile 4: „Copyright (C) 2008 Dr. Jürgen Neumann“ (Latin-1). Zeile 5: „Copyright (C) 2005 Robert Lipe … (based on nmea.c)“.
  - Zeilen 8–11: GPL-2.0-or-later.
- **Übersetzt werden:**
  - die Formatbeschreibung (Zeilen 35–41);
  - `gopal_check_line` (85–96);
  - die Dateinamenregel aus `gopal_rd_init` (139–155);
  - `gopal_read` (165–331) mit den Standardwerten `maxspeed` = 200, `minspeed` = 0 und `clean` = 1.
- **Großkreisentfernung:** Die Vorlage nutzt `gcdist` und `radtometers` aus `grtcirc.cc`. Sie wird als eigene Haversine-Hilfe geschrieben, nicht übersetzt; der Erdradius ist 6 378 137 m. Für eine Grenze von 200 km/h ist die Formel unerheblich.

### D2 Struktur

`Sources/GPSLoggerKitGPL/GoPal/GoPalFileFormat.swift` mit `GoPalFileFormat`. Zeilen werden an LF/CR getrennt und Felder am Komma, getrimmt von Leerzeichen.

### D3 Leser

- **Zeilen:** Die Zeile wird getrimmt. Leere Zeilen und Zeilen mit einer anderen Komma-Anzahl als 8 oder 11 werden übersprungen.
- **Felder:** Die Felder werden wie in der Spec gelesen. Ist ein Pflichtfeld (Zeit, Länge, Breite) nicht lesbar, wird die Zeile als `malformedRecord` gezählt. In der Vorlage blieben die Werte dann einfach 0.
- **Zeit:**
  - 12 Felder: Datum aus Feld 9 plus Zeit plus Millisekunden.
  - 9 Felder: Datum aus dem Dateinamen, mit Tageswechsel bei rückläufiger Zeit (D4).
  - Ohne Datum gibt es keine Zeit, dazu `missingDate` mit der Anzahl.
- **Filter** (`clean`):
  - Verworfen wird bei Länge oder Breite 0 oder außerhalb des Bereichs.
  - Ebenso, wenn die Geschwindigkeit vom letzten übernommenen Punkt aus über 200 km/h liegt. Gerechnet wird mit ganzen Sekunden wie in der Vorlage (`toTime_t`).
  - Bei Zeitabstand 0 ergibt sich in der Vorlage ∞ (verworfen) bzw. NaN bei gleicher Position (übernommen). Das wird nachgebildet.
- **Startpunkt der Prüfung:** Wie in der Vorlage ist der „letzte Punkt“ der erste Punkt mit Fix-Art ungleich `none`, solange noch kein Punkt übernommen ist, hier aber nur mit gültiger Position (D4). Ohne Datum rechnet die Prüfung mit der Tageszeit, wie die Vorlage mit dem 1. Januar 1970.
- **Abbruch:** `Cancellation` je Zeile.

### D4 Abweichungen von der Vorlage (bewusst)

- **Datum aus dem Dateinamen:**
  - Die Vorlage liest das Datum aus dem Namen. Die Übernahme ist auskommentiert (Zeilen 150–155), deshalb setzt sie bei 9 Feldern den 1. Januar 1970 als Datum.
  - Hier wird das Datum übernommen, wie die Vorlage es beabsichtigt.
  - Den Tageswechsel über Mitternacht nennt die Vorlage als offenen Punkt (ToDo, Zeilen 47–48). Hier ist er umgesetzt.
- **Geschwindigkeit:** Die Vorlage übernimmt den km/h-Wert unverändert in das m/s-Feld. Hier wird er umgerechnet (÷ 3,6).
- **Track statt Route:** Die Vorlage legt eine Route und zusätzlich jeden Punkt als Wegpunkt an. Hier entsteht ein Track ohne Wegpunkte, wie bei allen Loggerformaten von gpsloader.
- **Fix-Art:** Werte außer 0 und 2 ergeben `unknown`, also keine Fix-Art.
- **Bezugspunkt der Sprungprüfung:** Die Vorlage nimmt den ersten Punkt mit Fix als Bezug, auch wenn er selbst verworfen wird (Länge oder Breite 0). Dann würden alle folgenden Punkte als Sprung verworfen. Hier zählt nur ein Punkt mit gültiger Position.
- **Abbruch und Zeilen:** Zeilen werden einzeln dekodiert, damit der Abbruch auch bei großen Dateien schnell greift.

### D5 Erkennung

- **Geprüfte Zeilen:** die ersten bis zu fünf nicht leeren Zeilen des Prefix. Die letzte darf abgeschnitten sein und zählt dann nicht. Die erste Zeile und mehr als die Hälfte müssen passen, weil die Vorlage fremde Zeilen überspringt.
- **Passende Zeile:** 9 oder 12 Felder, Feld 0 nur Ziffern, Feld 1 mit sechs Ziffern vor einem optionalen Bruchteil, Felder 2 und 3 als Zahlen.
- **Abgrenzung:**
  - NMEA beginnt mit `$`.
  - V-900 und iBlue haben eine Kopfzeile mit Namen, kein numerisches erstes Feld.
  - IGC beginnt mit `A`.

### D6 Concurrency

Wie bei den übrigen Portierungen.

### D7 Tests und Gegenprüfung

- **Fixture:** `track20261102_080000.trk` mit 12 Feldern, darin ein Sprungpunkt, eine Zeile mit 0/0 und eine Zeile mit anderer Feldzahl. Die Koordinaten sind erfunden und liegen um 50° N, 8° O.
- **Black-Box:** `gpsbabel -i gopal -f … -o gpx`. Verglichen werden die Positionen und Höhen der Routenpunkte mit den Trackpunkten. Die Zeiten folgen D4.

## Risks / Trade-offs

- **Keine echten Dateien:** Die Feldbelegung folgt der Formatbeschreibung der Vorlage. → Hardware-Test (Task 5.2).

## Migration Plan

Entfällt.
