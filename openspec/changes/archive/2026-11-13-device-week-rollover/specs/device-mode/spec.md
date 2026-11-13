## ADDED Requirements

### Requirement: Korrektur des GPS-Wochenüberlaufs beim Auslesen
Der Adapter der Treiber SHALL auf jedes ausgelesene Ergebnis die Korrektur des GPS-Wochenüberlaufs der Spec `logger-kit` anwenden, mit dem Zeitpunkt des Auslesens als Bezug, für Trackpunkte und Wegpunkte. Die Korrektur SHALL immer aktiv sein. Ein Treiber, der Tracks nach Zeiten teilt oder benennt, SHALL dafür die korrigierten Zeiten verwenden.

#### Scenario: Logger mit Wochenüberlauf
- **WHEN** ein simuliertes Gerät am 13. November 2026 einen Punkt mit der Zeit 2. November 2026 minus 1024 Wochen liefert
- **THEN** hat der Punkt im Ergebnis die Zeit 2. November 2026

#### Scenario: Aktuelle Zeiten bleiben
- **WHEN** ein simuliertes Gerät einen Punkt liefert, der weniger als 512 Wochen vor dem Auslesen liegt
- **THEN** ist seine Zeit im Ergebnis unverändert

#### Scenario: Tracknamen nach der Korrektur
- **WHEN** ein GNS 2000 Punkte liefert, deren Zeiten um 1024 Wochen zu früh liegen
- **THEN** tragen die Tracks die Namen der korrigierten Zeiten, und es entsteht keine zusätzliche Trackgrenze
