# Mood-Bus & Filter-Cutoff-Multiplikatoren

## Sendesymbole

| Send | Bedeutung | Typischer Wertebereich |
|------|-----------|-------------------------|
| **mood-raw** | Rohwert vom Mood-Slider (GUI) oder von UDP (`netreceive`, Route `mood-raw`) | 0 … 1 |
| **mood-norm** | Nach Normierung: `min(1, max(0, mood-raw))` — identisch zu `mood-raw`, solange 0…1 eingehalten wird | 0 … 1 |

Die Filter-Basis in Hz kommt aus **mood-norm** über  
`expr 200 + sqrt(mood-norm) * 1000` → **filter-cutoff-base** (ca. 200 … 1200 Hz).

UDP (z. B. `shiftko-hw.py`): Nachricht `mood-raw <float>;` — muss mit der **Route** in `shiftko-main.pd` übereinstimmen (Outlet `mood-raw`).

## Multiplikatoren → `filter-cutoff` (nach Mix-Abstraktion)

Das Gesamt-Cutoff ist  
**Hz = filter-cutoff-base × mul_lfo × mul_rnd × mul_chaos**  
(siehe `shiftko-filter-cutoff-mix.pd`).

| Quelle | mul (ungefähr) | Spanne in **%** um 100 % | ungefähre **dB** (20·log₁₀(mul)) |
|--------|------------------|----------------------------|----------------------------------|
| **LFO** (Sinus um 600 Hz) | 0,65 … 1,35 | ca. −35 % … +35 % um 1,0 | ca. −3,7 … +2,6 dB |
| **Random** (langsam 0…1) | 0,65 + x·0,7 → 0,65 … 1,35 | ca. −35 % … +35 % | ca. −3,7 … +2,6 dB |
| **Lorenz** (Chaos, um ~235 Hz normiert) | 0,72 … 1,28 | ca. −28 % … +28 % | ca. −2,9 … +2,1 dB |

Die dB-Angaben beschreiben **nur** den jeweiligen Multiplikator; kombinierte Abweichungen addieren sich **multiplikativ** (nicht in dB addieren).

## Referenz

- `shiftko-main.pd` — Mood-HSL, `mood-raw` / `mood-norm`, Modulator-`expr`  
- `shiftko-filter-cutoff-mix.pd` — Produkt der vier Faktoren → `s filter-cutoff`  
- `shiftko-fx.pd` — `r filter-cutoff` für die FX-Kette  

## Chirurgischer Befund — nachgezogene Punkte

| Thema | Umsetzung |
|--------|-----------|
| **else/plate.rev~** (`shiftko-fx.pd`) | Trockensignal vom Summenpunkt nach EQ/Rausch-Mix (**+~** obj. 34) zum **Eingang** von `plate.rev~`; Ausgang weiter auf **+~** (35) als Wet — parallel zur FDN-Kette. |
| **note-bus** (Chords/Akzent) | Alle `throw~ note-bus` → **`throw~ note-bus-L`**, damit sie im gleichen linken Summen-Bus wie die Melodie (`catch~ note-bus-L`) ankommen. |
| **noise `switch~`** (`shiftko-noise.pd`) | Entfernt wie bei Texture — Anheben nur noch über `noise-level` / bestehende *~, kein DSP-Hartgate bei kleinem Level. |

## Archive-Hinweis

Die früheren Orphan-Patches `shiftko-pedal.pd` und `shiftko-accent.pd` liegen jetzt unter `archive/` und sind bewusst nicht Teil der Runtime-Instanziierung in `shiftko-main.pd`.
