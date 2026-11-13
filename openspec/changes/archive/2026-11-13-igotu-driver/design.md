# Design: i-GotU

## Context

- **Grundlagen:** `device-mode` stellt `HIDConnectionFactory` als Schnittstelle bereit, aber noch keine Umsetzung.
- **Analyse:** `docs/legacy-analysis.md` (Abschnitt 3.2) beschreibt das Protokoll aus dem eigenen myTracks-Code.
- **GT-800 in der Alt-App:** `IGotUGT800.m` (eigener Code) war produktiv.
- **USB-Modelle in der Alt-App:** `IGotU.m` war unfertig, produktiv lief igotu2gpx als externes Programm.

## Goals / Non-Goals

**Goals:** Auslesen aller Modelle und Löschen, wo es Vorlagen gibt.

**Non-Goals:** Konfiguration.

## Decisions

### D1 Vorlagen

- **GT-800, eigener Code:**
  - Grundlage: `IGotUGT800.m` mit `sendCommandWithChunk:`, `sendCountCommand`, `sendModelCommand`, `sendReadCommandForPosition:`, `readTrackData`, `createTrackPoints:` und `purgeMemory`.
  - Eigener Code des Entwicklers ist in GPSLoggerKitGPL ohne Einschränkung nutzbar.
- **USB-Modelle, igotu2gpx 0.3.0:**
  - Grundlage: `HACKING` (USB-Transport, Befehle), `src/igotu/igotucommand.cpp` (Stücke zu 8 Byte, Antwortkopf, Wiederholungen), `commands.cpp` (Modell, Anzahl) und `igotucontrol.cpp` (Download-Schleife, Löschen mit Blockanzahl je Modell und Firmware ab 2.15).
  - Lizenz: GPL-3.0-or-later.
- **Dateikopf** nach Regel 6 mit beiden Quellen.

### D2 HID-Transport

- **Modul:** `HIDTransport` in GPSLoaderKit, eigener Code.
- **Gerät finden und öffnen:** `IOHIDManager` mit Matching auf Vendor/Product, dann `IOHIDDeviceOpen` mit `kIOHIDOptionsTypeSeizeDevice`.
- **Empfangen:** Input-Reports über `IOHIDDeviceRegisterInputReportCallback` auf einer eigenen Dispatch-Queue (`IOHIDDeviceSetDispatchQueue`, ab macOS 10.15) in einen gesperrten Puffer.
- **Senden:** `IOHIDDeviceSetReport(kIOHIDReportTypeOutput, 0, …)` mit 8 Byte. Das ist der Control-Transfer 0x21/0x09/0x0200 aus igotu2gpx.
- **Lesen:** Abfrage des Puffers alle 5 ms, mit Inaktivitäts-Timeout und Abbruch.

### D3 Abweichungen

- **Millisekunden** bleiben erhalten; die Alt-App verwarf sie.
- **Wegpunkte** ergeben zusätzlich einen Wegpunkt `POI n`; die Alt-App benannte nur den Trackpunkt „WPT“.
- **Löschen** wird als experimentell angeboten (offener Vorschlag, siehe Proposal).
- **Eingang verwerfen:** Vor jedem Befehl bzw. Stück wird der Eingang verworfen, wie `NonBlockingPurge` in igotu2gpx. Das fängt auch die doppelten Antworten der Firmware ab 2.15 ab.

### D4 Tests

- **Swift-Simulator** `IGotUSimulator`: serielle und HID-Variante, Gerätefehler, Löschen.
- **Python-Simulator am Pseudo-Terminal:** Die App liest einen GT-800. Ein gpsbabel-Gegenstück gibt es nicht.

## Risks / Trade-offs

- **HID-Klasse unbestätigt:** Ob die USB-Modelle unter macOS als HID-Geräte erscheinen, ist unbestätigt (Analyse: Hypothese). → Erscheinen sie nicht, meldet die App „Gerät nicht gefunden“. Der Test durch Anwender (Task 3.2) klärt das. Andernfalls folgt ein Transport über IOUSBHost.
- **Löschen ungetestet:** → experimentell, mit Warnung.

## Migration Plan

Entfällt.
