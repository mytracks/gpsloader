# fit-import Specification

## Purpose
Liest Garmin-FIT-Dateien von Sportuhren, Fahrradcomputern und Apps nach dem öffentlichen FIT-Protokoll ein. Aus Aktivitäten entstehen Tracks, aus Kursdateien Tracks und Wegpunkte, ohne gpsbabel.

## Requirements

### Requirement: Dateiaufbau
Der Import SHALL FIT-Dateien nach dem FIT-Protokoll lesen:
- **Dateikopf:** 12 oder 14 Byte mit der Kennung `.FIT` und der Länge des Datenbereichs.
- **Nachrichten:** Definitions- und Datennachrichten in Little- und Big-Endian, auch Datennachrichten mit komprimiertem Zeitstempel.
- **Verkettung:** Folgen nach der abschließenden Prüfsumme weitere FIT-Dateien, SHALL der Import auch diese lesen.

#### Scenario: Big-Endian-Definition
- **WHEN** eine Datei eine `record`-Nachricht mit Big-Endian-Definition enthält
- **THEN** werden Position und Zeit genauso gelesen wie bei Little-Endian

#### Scenario: Komprimierter Zeitstempel
- **WHEN** auf eine `record`-Nachricht mit dem Zeitstempel T eine Nachricht mit komprimiertem Zeitstempel und dem Versatz 3 folgt
- **THEN** hat der zweite Punkt die Zeit T + 3 s

#### Scenario: Verkettete Dateien
- **WHEN** zwei vollständige FIT-Dateien direkt hintereinander in einer Datei stehen
- **THEN** enthält das Ergebnis die Punkte beider Teile

### Requirement: Unbekannte Inhalte
Unbekannte Nachrichten und Felder, Entwicklerfelder und Felder, die größer sind als im Profil, SHALL anhand ihrer Größe ohne Warnung übersprungen werden. Felder mit dem Ungültigkeitswert ihres Basistyps SHALL als fehlend gelten.

#### Scenario: Entwicklerfelder
- **WHEN** eine Definition zusätzlich Entwicklerfelder enthält
- **THEN** werden diese übersprungen, und die übrigen Felder der Nachricht werden richtig gelesen

#### Scenario: Ungültige Höhe
- **WHEN** das Feld `altitude` einer `record`-Nachricht den Wert 0xFFFF hat
- **THEN** hat der Punkt keine Höhe

### Requirement: Trackpunkte
Jede `record`-Nachricht mit gültiger Breite und Länge SHALL einen Trackpunkt ergeben:
- **Position:** aus Semicircles in Grad umgerechnet (Faktor 180 / 2³¹).
- **Zeit:** UTC aus dem Zeitstempel (Sekunden ab dem 31.12.1989, 00:00 UTC). Werte unter 0x10000000 sind relative Gerätezeit; der Punkt SHALL dann keine Zeit haben, und eine Warnung zählt ihn.
- **Höhe:** `enhanced_altitude`, sonst `altitude`.
- **Geschwindigkeit:** `enhanced_speed`, sonst `speed`, in m/s.

#### Scenario: Punkt umrechnen
- **WHEN** eine `record`-Nachricht die Werte `position_lat` 536870912, `position_long` −1073741824, `altitude` 3000 und `timestamp` 1100000000 enthält
- **THEN** entsteht ein Punkt bei 45° Nord und 90° West, auf 100 m Höhe und mit der Zeit 2024-11-08 11:33:20 UTC

#### Scenario: Erweiterte Höhe
- **WHEN** eine `record`-Nachricht `altitude` und `enhanced_altitude` enthält
- **THEN** wird `enhanced_altitude` verwendet

#### Scenario: Relative Gerätezeit
- **WHEN** ein Zeitstempel kleiner als 0x10000000 ist
- **THEN** hat der Punkt keine Zeit, und eine Warnung zählt die Punkte ohne Datum

### Requirement: Nachrichten ohne gültige Position
`record`-Nachrichten ohne Position SHALL ohne Warnung übergangen werden, etwa wenn nur Sensordaten aufgezeichnet sind. Eine Position außerhalb des gültigen Bereichs MUST verworfen und als Warnung gezählt werden.

#### Scenario: Nur Herzfrequenz
- **WHEN** eine `record`-Nachricht keine Position, aber eine Herzfrequenz enthält
- **THEN** entsteht kein Punkt und keine Warnung

#### Scenario: Breite außerhalb des Bereichs
- **WHEN** `position_lat` mehr als 90° entspricht
- **THEN** entsteht kein Punkt, und eine Warnung zählt die Nachricht

### Requirement: Tracks und Segmente
Jede FIT-Datei SHALL einen Track ergeben. Enthält die Datei eine `course`-Nachricht mit Namen, SHALL der Track so heißen, sonst wie die Datei ohne Endung. Ein Timer-Stopp (`event` `timer` mit dem Typ `stop` oder `stop_all`) SHALL das laufende Segment beenden; Punkte nach dem nächsten Start SHALL in ein neues Segment kommen. Segmente ohne Punkte SHALL entfallen.

#### Scenario: Pause in einer Aktivität
- **WHEN** eine Aktivität 10 Punkte enthält, danach einen Timer-Stopp, einen Timer-Start und weitere 5 Punkte
- **THEN** hat der Track zwei Segmente mit 10 und 5 Punkten

#### Scenario: Kursdatei
- **WHEN** eine Kursdatei die `course`-Nachricht mit dem Namen „Runde Alster“ enthält
- **THEN** heißt der Track „Runde Alster“

#### Scenario: Zwei Dateien
- **WHEN** zwei FIT-Dateien gemeinsam eingelesen werden
- **THEN** enthält die Aufzeichnung zwei Tracks in der Reihenfolge der Übergabe

### Requirement: Kurspunkte
Jede `course_point`-Nachricht mit gültiger Position SHALL einen Wegpunkt ergeben, mit Name und, falls vorhanden, Zeit.

#### Scenario: Kurspunkt
- **WHEN** eine Kursdatei einen `course_point` mit dem Namen „Wende“ enthält
- **THEN** enthält die Aufzeichnung einen Wegpunkt „Wende“ an dieser Position

### Requirement: Unvollständige Dateien
Kann eine Datei nicht bis zum Ende dekodiert werden, SHALL die Aufzeichnung alle Punkte bis zur beschädigten Stelle enthalten, und eine Warnung MUST das melden. Das gilt, wenn die Datei kürzer ist als im Kopf angegeben, eine Nachricht über das Dateiende hinausreicht oder eine Datennachricht auf eine nicht definierte lokale Nachrichtenart verweist.

#### Scenario: Abgeschnittene Aktivität
- **WHEN** eine Datei mit 100 Punkten nach dem 60. Punkt mitten in einer Nachricht endet
- **THEN** enthält der Track 60 Punkte, und eine Warnung meldet die unvollständige Datei

#### Scenario: Undefinierte Nachrichtenart
- **WHEN** nach 10 Punkten eine Datennachricht ohne vorherige Definition ihrer lokalen Art folgt
- **THEN** enthält der Track 10 Punkte, und eine Warnung meldet den beschädigten Datensatz

### Requirement: Prüfsummen und Kopf
Stimmt die Prüfsumme des Kopfs oder der Datei nicht, SHALL der Inhalt trotzdem gelesen werden, und eine Warnung MUST das melden. Ist der Kopf selbst ungültig, MUST das Einlesen mit einem Fehler enden.

#### Scenario: Falsche Prüfsumme
- **WHEN** die Prüfsumme am Ende der Datei nicht stimmt
- **THEN** werden alle Punkte gelesen, und eine Warnung meldet die falsche Prüfsumme

#### Scenario: Ungültiger Kopf
- **WHEN** der Kopf eine Länge von 20 Byte angibt
- **THEN** endet das Einlesen mit einem Fehler, der die Datei nennt

### Requirement: Erkennung
Eine Datei SHALL als FIT erkannt werden, wenn ihr erstes Byte 12 oder 14 ist und die Bytes 8 bis 11 `.FIT` lauten. Die Dateiendung `.fit` SHALL nur als Hinweis dienen.

#### Scenario: Endung fehlt
- **WHEN** eine FIT-Datei ohne Endung übergeben wird
- **THEN** schlägt die Erkennung FIT vor

#### Scenario: Andere Binärdatei
- **WHEN** eine Binärdatei mit der Endung `.fit` an den Bytes 8 bis 11 nicht `.FIT` enthält
- **THEN** wird sie nicht als FIT erkannt
