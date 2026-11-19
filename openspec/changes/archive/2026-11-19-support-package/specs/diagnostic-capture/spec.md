## REMOVED Requirements

### Requirement: Aufzeichnung einschalten
**Reason**: Der Mitschnitt läuft immer mit (Entscheidung vom 2026-11-14), damit er nach einem Fehler schon vorliegt.
**Migration**: Ersetzt durch „Aufzeichnung immer aktiv“. Die gespeicherte Einstellung `DiagnosticCaptureEnabled` wird ignoriert.

### Requirement: Export für den Support
**Reason**: Einzelne Mitschnitte sichert der Anwender nicht mehr selbst; sie gehen im Support-Paket auf.
**Migration**: Spec `support-package`, „Support-Paket erstellen“ und „Datenschutz im Support-Paket“.

## ADDED Requirements

### Requirement: Aufzeichnung immer aktiv
Die App SHALL jeden Lese- und Löschvorgang aufzeichnen. Einen Schalter zum Abschalten SHALL es nicht geben. Aufzeichnungen MUST lokal bleiben, bis der Anwender sie in ein Support-Paket übernimmt.

#### Scenario: Erster Start
- **WHEN** die App zum ersten Mal gestartet wird und der Anwender ein Gerät ausliest
- **THEN** liegt danach ein Mitschnitt dieses Vorgangs vor

#### Scenario: Fehlgeschlagener Vorgang
- **WHEN** ein Vorgang mit einem Fehler endet
- **THEN** wird sein Mitschnitt ebenso gespeichert wie der eines erfolgreichen Vorgangs
