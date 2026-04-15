# SuperCollider Verbesserungs-Roadmap (Live-Status)

## Zielbild

- Stabiler Live-Betrieb ohne Audio-Spikes, Knackser oder Device-Abstuerze.
- Musikalisch lebendige Endlos-Entwicklung ohne starre Wiederholschleifen.
- Performance-UI mit sicheren Ranges und klaren Makro-Kontrollen.

## Aktueller Status (Code)

- **Done:** Server-Boot-Haertung, Audio-Device-Fallback, konservative DSP-Safety (`clip2`, `Compander`, `Limiter`, `Lag`).
- **Done:** Vollwertige Live-UI mit Scene-System (`safe/focus/wild`), Morph, Auto-Scene, A/B-Snapshots, Mutate+Undo.
- **Done:** MIDI Learn, Soft-Takeover/Pickup, Deadband/Jitter-Filter, Relative Encoder-Decoding, Profile Save/Load.
- **Done:** MIDI-Out Feedback inkl. Page-System, Quantisierung, Status-CCs, OLED-Frame-CCs.
- **Done:** DnB-Slicer mit dynamischer BPM-Rate, 80/20 Slice-Default, Ghost/Main-Akzentlogik, Pdup-Stutter.
- **Done (neu):** Expliziter `dnbStutter` Parameter (State + MIDI + UI + Feedback) statt nur indirekter Chaos-Kopplung.
- **Done (neu):** Monolithischer DnB-Ausbau mit Break-HPF, synthetischer Kick-Layer und Sidechain-Depth-Regelung.
- **Done (neu):** Automatisches OLED-Streaming-Task (ON/OFF + Hz-Regelung), nicht nur manueller `OLED`-Button.
- **Done (neu):** Arrangement-Autopilot (`Task`) mit Intro -> Drop -> Breakdown inkl. UI Start/Stop und Phasenstatus.
- **Done (neu):** Arrangement-Dauern live editierbar (Intro/Drop/Breakdown Sekunden direkt im UI).
- **Done (neu):** Arrangement-Makro-Slots A/B/C mit Save/Load und persistenter Datei.
- **Done (neu):** Strict Pickup Mode fuer nicht-motorisierte Controller (Lock nach Szenen/Makros + Override).
- **Done (neu):** Arrangement-Phase-Editor im UI (Phase+Param+Wert direkt editierbar).

## Bereits implementierte Entscheidungen

- **Machen:** harte Sicherheitsgrenzen in der DSP-Kette.
- **Machen:** Trigger-basierte, direkt hoerbare musikalische Steuerung.
- **Machen:** Chaos als optionaler Organik-Anteil statt nur statischer LFO-Periodik.
- **Machen:** Live-Bedienoberflaeche mit musikalisch sinnvollen Parameterranges.
- **Nicht jetzt:** Quark-Abhaengigkeiten als Pflicht (MarkovSet/MathLib).
- **Nicht jetzt:** starke Rhythmus-Fraktalisierung als Standardmodus.

## Open Tasks (Software, jetzt machbar)

- Vollstaendiger Source/FX-Bus-Refactor mit deterministischer Order (`Group.head/tail`) fuer alle Klangquellen.
- Monolith/Modular vollstaendig angleichen (gleiche Defaults und Makro-Logik in beiden Pfaden).
- Optionaler separater "Performance Safe Lock"-Button (temporare Limits fuer kritische Parameter bei Live-Sets).
- NodeProxy/Ndef-Crossfade-Layer fuer Szenenwechsel (`fadeTime`) als optionaler Live-Modus.
- BPM-Metadaten-Workflow: Sample-Quelle (`sourceBpm`) verpflichtend pro Break/Vocal dokumentieren und beim Laden setzen.
- Optionales Vocal-Granularmodul (`Warp1`/`GrainBuf`) fuer zeitgedehnte Atmos ohne Pitch-Drift.
- Naechster Schritt: Arrangement-Phase-Editor um Multi-Parameter-Apply pro Szene (Batch) erweitern.

## Open Tasks (Hardware-/PoC-gebunden)

- Teensy PoC (3-4 Fader) auf Breadboard mit echtem End-to-End MIDI-Loop gegen SuperCollider.
- Teensy-Firmware fuer OLED/LED Rendering (eingehende MIDI-CCs auf SSD1306/SH1106/WS2812 darstellen).
- TRS/DIN I/O Hardwareauslegung (inkl. MIDI-IN Isolation) und mechanisches Panel-Mount-Design.

## Kommunikations-Architektur

- Kette bleibt: `Hardware -> Teensy -> USB-MIDI -> sclang -> scsynth`.
- Verantwortlichkeiten:
  - Debounce/Jitter auf Teensy
  - Mapping/State im sclang
  - Glättung/Safety in scsynth

## Umsetzungsfahrplan (verbindlich)

1. **Phase 1: Code & Sound** – weiter Stabilitaet, Mix und Live-Flow perfektionieren.
2. **Phase 2: Proof of Concept** – Teensy + wenige Fader + Feedback-Kanal validieren.
3. **Phase 3: Hardware/PCB** – erst nach stabilem PoC finalisieren.
4. **Phase 4: Pro-I/O & Chassis** – TRS/DIN/Panel-Mount/Bidirektionales Feedback.

## DnB Timing Merkregel

- `rate = (clock.tempo * 60) / originalSampleBPM`
- Dokumentiert in `DNB-TIMING-NOTES.md`.

## OLED / Headless Feedback

- Protokoll: `TEENSY-OLED-FEEDBACK-PROTOCOL.md`.
- SC-Seite: manuelles und automatisches Senden aktiv.
- Naechster Ausbau: Teensy-seitige Darstellung und Animationen fuer Live-Feedback.