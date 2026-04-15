# Hardware Audio Strategy (Speaker / Headphones / Bluetooth / AUX-In)

## Ziel
- Integrierte Lautsprecher als Standard-Ausgabe.
- Kopfhörer sofort nutzbar per Klinke.
- Optional Bluetooth-Audio (als Komfort, nicht als Live-Standard).
- Externer AUX-In für Live-Verarbeitung in SuperCollider.
- Stabiler Betrieb ohne Dropouts.

## 1) Lautsprecher + Kopfhörer (empfohlene Standardarchitektur)
- **Empfehlung:** Umschaltung rein hardwareseitig über eine `Stereo-Klinkenbuchse mit Schaltkontakt` (switched jack).
- **Signalfluss:**
  - DAC/Audio-Interface Line-Out -> switched jack -> (ohne Stecker) Class-D Amp -> interne Speaker
  - DAC/Audio-Interface Line-Out -> switched jack -> (mit Stecker) Kopfhörer
- **Wichtig:** Kein Neustart notwendig. Kein Software-Umschalten nötig. Das geschieht mechanisch.
- **Status fürs Projekt:** Speaker-Module noch offen -> **nicht hardcoden**, nur Architektur vorbereiten.

## 2) Bluetooth-Audio (optional)
- Für Live-Stabilität nicht als Primärweg planen.
- In Linux-Stacks kollidiert dynamisches Bluetooth-Rerouting häufig mit low-latency Audio-Engines.
- **Empfehlung:** Bluetooth als separater Modus mit möglichem Audio-Server-Neustart, nicht als nahtloses Live-Switchover.

## 3) Stromversorgung: Akku vs. Dauerstrom
- **Empfehlung klar:** Dauerstrom via hochwertigem USB-C-Netzteil.
- Gründe:
  - Hohe Lastspitzen (Pi + DSP + Verstärker)
  - Gefahr von Unterspannung bei Powerbanks/Akkus -> CPU-Throttling, XRUNs, Knackser
- **Akku nur sinnvoll**, wenn eine saubere 5V-Regelung mit ausreichender Stromreserve nachweislich stabil ist.

## 4) AUX-In (Line Input)
- Erfordert Audio-Hardware mit ADC-Eingängen (nicht nur Playback-DAC).
- Im SuperCollider-Code kann das Signal dann über `SoundIn.ar(...)` verarbeitet werden.
- Für stabile Latenz: Sample-Rate/Blocksize konsistent auf Audio-Hardware abstimmen.

## 5) Elektrische Sicherheits-/Audio-Qualitätsregeln
- Teensy-I/O strikt 3.3V (keine 5V an I/O-Pins).
- Fader empfohlen: 10k linear.
- Class-D Amp möglichst entkoppelt versorgen (Störgeräusche vermeiden).
- Saubere Masseführung (Star Grounding), analog/digital trennen.

## 5b) Studio-I/O Verkabelung (merken)
- **6.35mm TS (unsymmetrisch):**
  - Tip = Signal, Sleeve = Ground/Shield.
  - Für kurze Leitungen ok, störanfälliger bei längeren Kabeln.
- **6.35mm TRS (symmetrisch, empfohlen):**
  - Tip = Hot(+), Ring = Cold(-), Sleeve = Shield/Ground.
  - Bei längeren Leitungen klar bevorzugt (Noise/Ground-Loop-resistenter).
- **Grounding-Hinweis:**
  - Unsymmetrisch: Masse nicht trennen.
  - Symmetrisch: Ground-Lift-Konzepte nur gezielt und kontrolliert einsetzen.

## 5c) MIDI-DIN Schaltung (merken)
- Für klassisches 5-Pin DIN MIDI-IN galvanische Isolation einplanen (Optokoppler-Pfad).
- MIDI-OUT sauber nach DIN-Standard treiben (korrekte Vorwiderstände/Signalführung).
- Umsetzung in dedizierter Hardware-Phase, nicht in der aktuellen Softwarephase erzwingen.

## 5d) Mechanische Stabilität (merken)
- Fader/Potis nicht nur über Lötstellen tragen lassen.
- Panel-Mount bevorzugen, mechanische Last ins Gehäuse leiten.
- PCB mit Standoffs (z. B. M3) stabilisieren, damit keine Leiterbahn-Haarrisse durch Hebelkräfte entstehen.

## 6) Umsetzungsphasen
- **Phase A (jetzt):** Dokumentation + Software nicht auf spezielles Speaker-Modul fixieren.
- **Phase B (nach Modulauswahl):** Verdrahtung switched jack + Amp + Speaker verifizieren.
- **Phase C:** Optionaler Bluetooth-Modus als separater Runtime-Profil-Start.
- **Phase D:** AUX-In aktivieren + Live-FX-Processing testen.
- **Phase E:** Professionelle I/O-Mechanik (TRS/DIN/Panel-Mount) im finalen Chassis umsetzen.

## 7) Kommunikationskette (verbindliches Architekturmodell)
- Datenfluss: `Spannungsänderung -> Teensy (C++) -> USB-MIDI -> Raspberry Pi (sclang) -> scsynth`.
- Ziel: Raspberry Pi fuer Audio-DSP freihalten; Vorverarbeitung auf Teensy/Hardware.

### Wer löst was?
- **PCB/Hardware** loest Debounce/Prellen (z. B. Pull-Up + Kondensator bei Schaltern/Encodern).
- **Teensy-Firmware** loest Sensor-Jitter (EMA/Filter), skaliert auf MIDI und sendet nur relevante Aenderungen.
- **sclang (Client)** loest Mapping-Logik:
  - absolute Faderwerte `0..127` -> musikalische Werte (`linexp`, `linlin`)
  - relative Encoderimpulse (`+1/-1`) -> interner Zustand + `clip`.
- **scsynth (Server)** loest Audio-Glättung/Anti-Zipper per `Lag.kr` / `VarLag.kr`.

### Absolute Fader (Pflicht)
- Teensy sendet CC mit absoluten Werten.
- sclang mappt auf musikalische Zielbereiche.
- scsynth glättet die Zielwerte.

### Relative Encoder (Empfehlung)
- Teensy sendet relative CC-Codes (z. B. Two's Complement).
- sclang dekodiert Richtung/Schritt, aktualisiert internen Zustand und clippt.
- Dadurch keine "Endanschlag"-Problematik wie bei absoluten 0..127 Encodern.

## 8) Bidirektionales Feedback (merken, nächste Ausbaustufe)
- Ziel: Headless-Feedback (OLED/LED) über Rückkanal von SC -> Teensy.
- Architektur: `scsynth Parameter -> sclang -> MIDI Out -> Teensy`.
- Teensy zeigt empfangene Werte auf OLED (SSD1306 via I2C) oder LED-Status an.
- Hardware-Hinweise:
  - OLED I2C am Teensy in 3.3V-Logik betreiben.
  - WS2812/NeoPixel mit sauberem 3.3V->5V Pegelwandler betreiben.
