#!/usr/bin/env python3
"""
shiftko-hw.py — Hardware Bridge für Shift K.O.
================================================
Raspberry Pi 4 GPIO → Pure Data via UDP/FUDI (Port 7400)

ARCHITEKTUR:
  Hardware (GPIO) → dieses Script → UDP → PD [netreceive 7400 1 udp]

AKTUELLER STATUS: SCAFFOLD — kein GPIO aktiv
  Alle Hardware-Klassen sind vorbereitet und kommentiert.
  Zur Aktivierung: TODO-Kommentare abarbeiten, Pins verdrahten.

FUDI-PROTOKOLL:
  PD erwartet: "empfangername wert1 wert2 ...;\n"
  Beispiel:    "drone-level 0.75;\n"

INSTALLATION AUF PI:
  sudo apt install python3-pip python3-smbus python3-spidev
  pip3 install RPi.GPIO spidev smbus2 luma.oled pillow

AUTOSTART (systemd):
  Wird via shiftko.service gestartet — siehe shiftko.service
"""

import socket
import time
import threading
import math
import sys
import logging
import argparse

logging.basicConfig(
    level=logging.INFO,
    format='[%(levelname)s %(asctime)s] %(message)s',
    datefmt='%H:%M:%S'
)
log = logging.getLogger('shiftko-hw')

# ── KONFIGURATION ────────────────────────────────────────────────────────────

PD_HOST = '127.0.0.1'
PD_PORT = 7400
POLL_HZ = 60  # GPIO polling rate (60x/s = 16ms resolution, gut für Encoder)

# ── GPIO PIN MAPPING ─────────────────────────────────────────────────────────
# Basierend auf BOM und Schaltplan Shift K.O.
# WICHTIG: BCM-Nummerierung (nicht physical/board)

# Encoder EC11E (3×)
# Jeder Encoder: CLK, DT, SW (Button)
# TODO: Pins mit tatsächlicher PCB-Verdrahtung abgleichen
ENCODER_PINS = [
    {'clk': 17, 'dt': 18, 'sw': 27},  # Encoder 1 (BPM)
    {'clk': 22, 'dt': 23, 'sw': 24},  # Encoder 2 (Mood/Filter)
    {'clk': 5,  'dt': 6,  'sw': 13},  # Encoder 3 (Dense/Noise)
]

# Fader PTA6043 (4×) → MCP3008 ADC → SPI
# MCP3008: 8-Kanal 10-bit ADC, SPI-Interface
# SPI Pins: CLK=GPIO11, MOSI=GPIO10, MISO=GPIO9, CS=GPIO8 (SPI0)
SPI_CS_PIN = 8       # Chip Select für MCP3008
ADC_CHANNELS = {     # ADC-Kanal → PD-Ziel
    0: 'drone-level',
    1: 'notes-level',
    2: 'noise-level',
    3: 'reverb-room',
    4: 'master-vol',  # 5. Fader wenn vorhanden
}
ADC_MAX = 1023       # 10-bit MCP3008

# Buttons Kailh Choc V1 (4×) — digitale Eingänge
# TODO: Tatsächliche Pins aus PCB-Layout eintragen
BUTTON_PINS = {
    25: 'pent',    # Skala Pentatonik
    26: 'min',     # Skala Moll
    16: 'lydi',    # Skala Lydisch
    20: 'play',    # Play/Stop (alternativ: transport toggle)
}

# Touch-Sensor TTP223
TOUCH_PIN = 21      # TODO: Bestätigen, ob TTP223 HIGH oder LOW bei Touch

# Kopfhörer-Erkennung via TRRS (Sleeve = GND bei HP eingesteckt)
HP_DETECT_PIN = 12  # TODO: Pull-up/Pull-down konfigurieren

# I²C OLED SSD1306
I2C_ADDRESS = 0x3C  # Standard SSD1306 I²C Adresse (alternativ: 0x3D)

# ── UDP SENDER ───────────────────────────────────────────────────────────────

class PDSender:
    """Sendet FUDI-Messages an Pure Data via UDP."""

    def __init__(self, host=PD_HOST, port=PD_PORT):
        self.sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        self.addr = (host, port)
        log.info(f"UDP sender → {host}:{port}")

    def send(self, name: str, *values):
        """
        Sendet eine FUDI-Message an PD.

        Beispiel: sender.send('drone-level', 0.75)
        → PD empfängt: "drone-level 0.75;"

        Beispiel: sender.send('pent')
        → PD empfängt: "pent;"
        """
        vals_str = ' '.join(str(v) for v in values)
        msg = f"{name} {vals_str};\n" if values else f"{name};\n"
        try:
            self.sock.sendto(msg.encode('ascii'), self.addr)
            log.debug(f"→ PD: {msg.strip()}")
        except Exception as e:
            log.error(f"UDP send error: {e}")

    def close(self):
        self.sock.close()


# ── ENCODER ──────────────────────────────────────────────────────────────────

class Encoder:
    """
    Rotary Encoder EC11E — Liest Drehrichtung + Button.

    IMPLEMENTIERUNG AUSSTEHEND:
    Benötigt RPi.GPIO oder gpiozero.
    EC11E: Quadratur-Encoder mit 24 Rastpunkten/Umdrehung.
    Interrupt-basiert (GPIO.RISING) statt polling für Genauigkeit.

    TODO:
    1. import RPi.GPIO as GPIO (oder: from gpiozero import RotaryEncoder)
    2. GPIO.setup(clk_pin, GPIO.IN, pull_up_down=GPIO.PUD_UP)
    3. GPIO.setup(dt_pin,  GPIO.IN, pull_up_down=GPIO.PUD_UP)
    4. GPIO.setup(sw_pin,  GPIO.IN, pull_up_down=GPIO.PUD_UP)
    5. GPIO.add_event_detect(clk_pin, GPIO.FALLING, callback=self._update)
    6. Callback: vergleiche dt-Zustand mit clk-Zustand → Richtung

    MAPPING:
    Encoder 0 (BPM):   Wert 60-200, Schritt 1 BPM
    Encoder 1 (Mood):  Wert 200-1200 Hz, exponentiell, Schritt 10 Hz
    Encoder 2 (Dense): Wert 0.0-0.7, Schritt 0.02

    ANTI-BOUNCE:
    EC11E bounced stark. Min. 5ms debounce nötig:
    if time.time() - self.last_time < 0.005: return
    """

    def __init__(self, clk_pin=None, dt_pin=None, sw_pin=None, pd_name='',
                 clk=None, dt=None, sw=None,
                 min_val=0.0, max_val=1.0, step=0.02, initial=0.5):
        # Support both explicit *_pin arguments and ENCODER_PINS dict keys.
        if clk_pin is None:
            clk_pin = clk
        if dt_pin is None:
            dt_pin = dt
        if sw_pin is None:
            sw_pin = sw

        self.clk = clk_pin
        self.dt  = dt_pin
        self.sw  = sw_pin
        self.pd_name  = pd_name
        self.min_val  = min_val
        self.max_val  = max_val
        self.step     = step
        self.value    = initial
        self.last_clk = 0          # letzter CLK-Zustand
        self.last_press = 0        # debounce für Button

        # TODO: GPIO setup hier
        # GPIO.setup(self.clk, GPIO.IN, pull_up_down=GPIO.PUD_UP)
        # GPIO.setup(self.dt,  GPIO.IN, pull_up_down=GPIO.PUD_UP)
        # GPIO.setup(self.sw,  GPIO.IN, pull_up_down=GPIO.PUD_UP)
        # GPIO.add_event_detect(self.clk, GPIO.FALLING, callback=self._on_rotate)
        # GPIO.add_event_detect(self.sw, GPIO.FALLING,  callback=self._on_press)

        log.info(f"Encoder [{pd_name}] clk={clk_pin} dt={dt_pin} sw={sw_pin} (SIMULATED)")

    def _on_rotate(self, channel=None):
        """Interrupt-Callback für Rotation. TODO: GPIO aktivieren."""
        # TODO:
        # dt_state = GPIO.input(self.dt)
        # if dt_state == 1:
        #     self.value = min(self.max_val, self.value + self.step)
        # else:
        #     self.value = max(self.min_val, self.value - self.step)
        pass

    def _on_press(self, channel=None):
        """Interrupt-Callback für Button-Druck. TODO: GPIO aktivieren."""
        # TODO:
        # now = time.time()
        # if now - self.last_press < 0.05: return  # 50ms debounce
        # self.last_press = now
        # Encoder-Button kann Reset oder Mode-Wechsel triggern
        pass

    def get_value(self):
        """Gibt aktuellen Wert zurück (0.0-1.0 normiert oder absolut)."""
        return self.value


# ── ADC / FADER ──────────────────────────────────────────────────────────────

class MCP3008:
    """
    MCP3008 10-bit ADC via SPI — liest 4 Fader PTA6043.

    IMPLEMENTIERUNG AUSSTEHEND:
    Benötigt spidev.

    TODO:
    1. import spidev
    2. spi = spidev.SpiDev()
    3. spi.open(0, 0)  # Bus 0, Device 0 (CS=GPIO8)
    4. spi.max_speed_hz = 1350000
    5. Read: spi.xfer2([1, (8+channel)<<4, 0])
             result = ((data[1] & 3) << 8) + data[2]

    KALIBRIERUNG:
    PTA6043 Fader haben mechanischen Bereich 0-100%.
    Rauschen am ADC: ~5-10 LSB. Hysterese von 3 LSB nötig.
    Mapping: ADC 0-1023 → Zielwert linear oder logarithmisch.

    LOGARITHMISCHES MAPPING für Lautstärke:
    # dB = -60 * (1 - raw/ADC_MAX)  (linear im log-Domain)
    # gain = 10^(dB/20)

    SMOOTHING im Software (Exponential):
    smooth = alpha * new + (1-alpha) * old
    alpha = 0.05 → langsam (ca 60ms bei 60Hz polling)
    alpha = 0.2  → schnell
    """

    def __init__(self):
        self.smooth = {ch: 0.0 for ch in ADC_CHANNELS}
        self.alpha  = 0.08   # Exponential smoothing factor
        # TODO:
        # import spidev
        # self.spi = spidev.SpiDev()
        # self.spi.open(0, 0)
        # self.spi.max_speed_hz = 1350000
        log.info("MCP3008 ADC (SIMULATED — SPI not initialized)")

    def read_raw(self, channel):
        """Liest rohen ADC-Wert 0-1023. TODO: SPI aktivieren."""
        # TODO:
        # data = self.spi.xfer2([1, (8 + channel) << 4, 0])
        # return ((data[1] & 3) << 8) + data[2]
        return 512  # Simulation: Mitte

    def read_smooth(self, channel):
        """Geglätteter ADC-Wert 0.0-1.0 (exponential smoothing)."""
        raw = self.read_raw(channel) / ADC_MAX
        self.smooth[channel] = (self.alpha * raw
                                + (1 - self.alpha) * self.smooth[channel])
        return self.smooth[channel]

    def read_log(self, channel, min_db=-60.0):
        """
        Logarithmisches Mapping für Lautstärke-Fader.
        0.0 ADC → -60dB (fast Stille), 1.0 ADC → 0dB (full).
        """
        linear = self.read_smooth(channel)
        if linear < 0.001:
            return 0.0
        db = min_db * (1.0 - linear)
        return 10 ** (db / 20.0)


# ── BUTTONS ──────────────────────────────────────────────────────────────────

class ButtonArray:
    """
    Kailh Choc V1 Taster (4×) — digitale Eingänge mit Debounce.

    TODO:
    1. GPIO.setup(pin, GPIO.IN, pull_up_down=GPIO.PUD_UP)
    2. GPIO.add_event_detect(pin, GPIO.FALLING, callback=self._on_press,
                             bouncetime=50)

    MAPPING:
    Taster 1 → 'pent'     (Preset Cosmic)
    Taster 2 → 'min'      (Preset Hopeful)
    Taster 3 → 'lydi'     (Preset Wonder)
    Taster 4 → 'play'     (Play/Stop Toggle, sendet: "transport 0/1;")

    TODO für Scale-Select:
    Wenn Skala gewechselt wird, soll auch root-hz geändert werden:
    pent → root-hz 256
    min  → root-hz 288
    lydi → root-hz 320
    """

    def __init__(self, pd: PDSender, oled):
        self.pd = pd
        self.oled = oled
        self.states = {pin: False for pin in BUTTON_PINS}
        self.transport_state = 1  # Startet aktiv (synced mit PD loadbang)

        # TODO: GPIO setup für alle Buttons
        # for pin in BUTTON_PINS:
        #     GPIO.setup(pin, GPIO.IN, pull_up_down=GPIO.PUD_UP)
        #     GPIO.add_event_detect(pin, GPIO.FALLING,
        #         callback=lambda ch: self._on_press(ch), bouncetime=50)

        log.info(f"Buttons (SIMULATED): {list(BUTTON_PINS.values())}")

    def _on_press(self, channel):
        """GPIO Interrupt-Callback. TODO: GPIO aktivieren."""
        action = BUTTON_PINS.get(channel)
        if not action:
            return

        if action == 'play':
            # Toggle transport
            self.transport_state = 1 - self.transport_state
            self.pd.send('transport', self.transport_state)
            log.info(f"Transport → {self.transport_state}")

        elif action == 'pent':
            self.pd.send('cosmic-w', 100)
            self.pd.send('wonder-w', 0)
            self.pd.send('hopeful-w', 0)
            self.pd.send('koto-w', 0)
            self.pd.send('raga-w', 0)
            self.pd.send('pelog-w', 0)
            self.pd.send('safir16-w', 0)
            self.pd.send('root-hz', 256)
            self.oled.update(scale_label='COSMIC')
            log.info("Preset → Cosmic (C4)")

        elif action == 'min':
            self.pd.send('cosmic-w', 0)
            self.pd.send('wonder-w', 0)
            self.pd.send('hopeful-w', 100)
            self.pd.send('koto-w', 0)
            self.pd.send('raga-w', 0)
            self.pd.send('pelog-w', 0)
            self.pd.send('safir16-w', 0)
            self.pd.send('root-hz', 288)
            self.oled.update(scale_label='HOPEFUL')
            log.info("Preset → Hopeful (D4)")

        elif action == 'lydi':
            self.pd.send('cosmic-w', 0)
            self.pd.send('wonder-w', 100)
            self.pd.send('hopeful-w', 0)
            self.pd.send('koto-w', 0)
            self.pd.send('raga-w', 0)
            self.pd.send('pelog-w', 0)
            self.pd.send('safir16-w', 0)
            self.pd.send('root-hz', 320)
            self.oled.update(scale_label='WONDER')
            log.info("Preset → Wonder (E4)")


# ── TOUCH SENSOR ─────────────────────────────────────────────────────────────

class TouchSensor:
    """
    TTP223 kapazitiver Touch-Sensor — Single-Touch.

    TODO:
    GPIO.setup(TOUCH_PIN, GPIO.IN)
    # TTP223 OUTPUT: HIGH bei Touch, LOW bei kein Touch (Standard-Modus)
    # Alternativ-Modus (AHLB Pin): LOW bei Touch

    VERWENDUNG (Ideen):
    - Kurzer Touch: randomize (neuen Zufalls-Seed setzen)
    - Langer Touch (>1s): Patch-Reset (alle Gates auf default)
    - Sehr langer Touch (>3s): Shutdown-Sequence
    """

    def __init__(self, pd: PDSender):
        self.pd       = pd
        self.pressed  = False
        self.press_t  = 0.0

        # TODO:
        # GPIO.setup(TOUCH_PIN, GPIO.IN)
        # GPIO.add_event_detect(TOUCH_PIN, GPIO.BOTH, callback=self._on_event)

        log.info(f"Touch sensor pin {TOUCH_PIN} (SIMULATED)")

    def _on_event(self, channel):
        """TODO: GPIO aktivieren."""
        # TODO:
        # state = GPIO.input(TOUCH_PIN)
        # now = time.time()
        # if state:  # Touch
        #     self.pressed = True
        #     self.press_t = now
        # else:      # Release
        #     duration = now - self.press_t
        #     self.pressed = False
        #     if duration > 3.0:
        #         self._shutdown()
        #     elif duration > 1.0:
        #         self._reset()
        #     else:
        #         self.pd.send('randomize')
        pass

    def _reset(self):
        """
        Sanfter Reset ohne harte Pegelspruenge.
        Triggert nur musikalische Zustandswechsel in PD.
        """
        self.pd.send('macro-gate', 0)
        self.pd.send('randomize')
        log.info("Touch long -> gentle reset")

    def _shutdown(self):
        """Fährt PD sanft herunter bevor systemd stoppt."""
        log.info("Touch very long → SHUTDOWN")
        self.pd.send('transport', 0)   # Audio stoppen
        time.sleep(2.0)                # 2s Fade-out abwarten
        # TODO: subprocess.run(['sudo', 'shutdown', '-h', 'now'])


# ── HP DETECT ────────────────────────────────────────────────────────────────

class HPDetect:
    """
    Kopfhörer-Erkennung via TRRS Sleeve.

    IMPLEMENTIERUNG AUSSTEHEND:
    TRRS-Buchse: Tip=L, Ring1=R, Ring2=Mic, Sleeve=GND (bei HP eingesteckt).
    Wenn HP eingesteckt: Sleeve zieht GPIO auf GND → LOW.
    Wenn kein HP: Pull-up hält GPIO auf HIGH.

    TODO:
    GPIO.setup(HP_DETECT_PIN, GPIO.IN, pull_up_down=GPIO.PUD_UP)
    GPIO.add_event_detect(HP_DETECT_PIN, GPIO.BOTH, callback=self._on_change,
                          bouncetime=100)

    BEI HP-INSERT:
    1. Optionales Status-Flag an PD senden (falls Patch es verwendet)
    2. Lautsprecher-Amp (MAX98357A via GPIO) ausschalten → Strom sparen
       TODO: MAX98357A SD-Pin (Shutdown) → GPIO → LOW = Amp aus

    BEI HP-REMOVE:
    1. Optionales Status-Flag zurücksetzen (falls Patch es verwendet)
    2. MAX98357A wieder aktivieren
    """

    def __init__(self, pd: PDSender):
        self.pd      = pd
        self.hp_in   = False
        # TODO: amp_shutdown_pin definieren (MAX98357A SD)
        # self.amp_pin = 19  # Beispiel

        # TODO:
        # GPIO.setup(HP_DETECT_PIN, GPIO.IN, pull_up_down=GPIO.PUD_UP)
        # GPIO.add_event_detect(HP_DETECT_PIN, GPIO.BOTH,
        #                       callback=self._on_change, bouncetime=100)
        # self._on_change(HP_DETECT_PIN)  # Initial state

        log.info(f"HP detect pin {HP_DETECT_PIN} (SIMULATED)")

    def _on_change(self, channel):
        """TODO: GPIO aktivieren."""
        # TODO:
        # state = GPIO.input(HP_DETECT_PIN)
        # hp_inserted = (state == 0)  # LOW = HP eingesteckt (Pull-up)
        # if hp_inserted != self.hp_in:
        #     self.hp_in = hp_inserted
        #     self.pd.send('hp-state', 1 if hp_inserted else 0)
        #     # MAX98357A Amp:
        #     # GPIO.output(self.amp_pin, GPIO.LOW if hp_inserted else GPIO.HIGH)
        #     log.info(f"HP {'inserted' if hp_inserted else 'removed'}")
        pass


# ── OLED DISPLAY ─────────────────────────────────────────────────────────────

class OLEDDisplay:
    """
    SSD1306 128×64 OLED via I²C.

    IMPLEMENTIERUNG AUSSTEHEND:
    Benötigt: luma.oled, Pillow

    TODO:
    from luma.core.interface.serial import i2c
    from luma.oled.device import ssd1306
    from luma.core.render import canvas
    from PIL import ImageFont

    serial = i2c(port=1, address=I2C_ADDRESS)
    device = ssd1306(serial)

    LAYOUT IDEEN:
    Zeile 1: "SHIFT K.O. v1"  (statisch)
    Zeile 2: "BPM: 120  PENT" (aktuell)
    Zeile 3: "Drn ▓▓▓░░ 75%"  (Fader)
    Zeile 4: "Nts ▓▓░░░ 55%"
    Zeile 5: "Spc ▓▓▓░░ 55%"  (Reverb)
    Zeile 6: "Vol ▓▓░░░ 50%"

    REFRESH-RATE: max 10 FPS (OLED via I²C ist langsam)
    → separate thread mit time.sleep(0.1)

    SCREENSAVER:
    Nach 60s Inaktivität: Helligkeit reduzieren oder ausschalten.
    device.contrast(0) oder device.hide()
    """

    def __init__(self):
        self.state = {
            'bpm': 120,
            'scale': 'PENT',
            'scale_label': 'COSMIC',
            'root_hz': 256.0,
            'drone': 0.75,
            'notes': 0.55,
            'space': 0.55,
            'vol':   0.50,
            'transport': True,
        }
        # TODO:
        # from luma.core.interface.serial import i2c
        # from luma.oled.device import ssd1306
        # from luma.core.render import canvas
        # serial = i2c(port=1, address=I2C_ADDRESS)
        # self.device = ssd1306(serial)
        log.info("OLED SSD1306 (SIMULATED — luma.oled not loaded)")

    def update(self, **kwargs):
        """Update State-Dictionary und neu zeichnen."""
        self.state.update(kwargs)
        self._draw()

    def _draw(self):
        """Zeichnet aktuelles State auf OLED. TODO: luma.oled aktivieren."""
        s = self.state

        # TODO:
        # with canvas(self.device) as draw:
        #     draw.text((0, 0),  "SHIFT K.O.",          fill='white')
        #     draw.text((0, 10), f"BPM {s['bpm']:3d}  {s['scale_label']}",
        #               fill='white')
        #     draw.text((0, 20), f"Root {s['root_hz']:.1f} Hz", fill='white')
        #     draw.text((0, 30), f"Drn {self._bar(s['drone'])} {s['drone']:.0%}",
        #               fill='white')
        #     draw.text((0, 40), f"Nts {self._bar(s['notes'])} {s['notes']:.0%}",
        #               fill='white')
        #     draw.text((0, 50), f"Spc {self._bar(s['space'])} {s['space']:.0%}",
        #               fill='white')
        #     draw.text((0, 60), f"Vol {self._bar(s['vol'])}  {s['vol']:.0%}",
        #               fill='white')

        # Simulationsmodus: Root-Updates sichtbar machen, ohne das Log zu fluten.
        root_hz = s.get('root_hz', 0.0)
        if not hasattr(self, '_last_root_hz'):
            self._last_root_hz = None
        if self._last_root_hz is None or abs(root_hz - self._last_root_hz) >= 0.1:
            self._last_root_hz = root_hz
            log.info(f"OLED {s.get('scale_label', 'N/A')} @ {root_hz:.1f} Hz")

    def _bar(self, value, width=5):
        """ASCII-Progressbar: ▓▓▓░░ für 0.6."""
        filled = round(value * width)
        return '▓' * filled + '░' * (width - filled)


class PDListener:
    """Lauscht auf UDP-Nachrichten von Pure Data (Port 7401)."""

    def __init__(self, oled, port=7401):
        self.oled = oled
        self.sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        self.sock.bind(('127.0.0.1', port))
        self.sock.settimeout(1.0)
        self.running = True

    def listen(self):
        log.info(f"Listening for PD updates on port {self.sock.getsockname()[1]}")
        while self.running:
            try:
                data, _ = self.sock.recvfrom(1024)
                msg = data.decode('ascii').strip().replace(';', '')
                parts = msg.split()
                if len(parts) >= 2:
                    key, val = parts[0], parts[1]
                    if key == 'root_hz':
                        hz_val = float(val)
                        self.oled.update(root_hz=hz_val)
                        log.debug(f"PD update: root_hz={hz_val}")
            except socket.timeout:
                continue
            except OSError:
                # Socket closed while stopping.
                break
            except Exception as e:
                log.error(f"PD listener error: {e}")

    def stop(self):
        self.running = False
        try:
            self.sock.close()
        except Exception:
            pass


# ── HAUPT-SCHLEIFE ────────────────────────────────────────────────────────────

class ShiftKO:
    """
    Hauptklasse — initialisiert alle Hardware-Module und startet Polling.

    POLLING-STRATEGIE:
    - Encoder:  Interrupt-basiert (kein Polling nötig sobald GPIO aktiv)
    - ADC/Fader: 60 Hz Polling (16ms) — bei 50Hz Last zu hoch → 30Hz
    - OLED: 10 Hz Refresh (100ms)
    - HP-Detect: Interrupt (kein Polling)

    PERFORMANCE AUF PI4:
    Python bei 60Hz Polling: ~5% CPU. Mit GPIO-Interrupts: ~1%.
    DSP in PD (pd headless): ~15-30% CPU @ 44100Hz, blocksize 64.
    Gesamt: ca. 35-40% CPU → ausreichend Headroom.
    """

    def __init__(self):
        self.pd      = PDSender()
        self.adc     = MCP3008()
        self.touch   = TouchSensor(self.pd)
        self.hp      = HPDetect(self.pd)
        self.oled    = OLEDDisplay()
        self.buttons = ButtonArray(self.pd, self.oled)
        self.pd_listener = PDListener(self.oled)

        # Encoder für BPM, Mood, Dense
        self.encoders = [
            Encoder(**ENCODER_PINS[0], pd_name='bpm',
                    min_val=60, max_val=200, step=1, initial=120),
            Encoder(**ENCODER_PINS[1], pd_name='mood-raw',
                    min_val=0.0, max_val=1.0, step=0.05, initial=0.3),
            Encoder(**ENCODER_PINS[2], pd_name='noise-level',
                    min_val=0.0, max_val=0.7, step=0.02, initial=0.35),
        ]

        self.running = False
        log.info("Shift K.O. hardware bridge initialized (SIMULATION MODE)")

    def _send_initial_state(self):
        """
        Sendet alle initialen Werte an PD nach Verbindungsaufbau.
        Synchronisiert Hardware-State mit PD-State.
        """
        time.sleep(0.5)  # Warten bis PD geladen hat
        self.pd.send('transport',      1)
        self.pd.send('root-hz',    256)
        self.pd.send('whole_time',  2000)
        self.pd.send('randomize')
        log.info("Initial state sent to PD")

    def _adc_loop(self):
        """
        ADC Polling-Loop (läuft in eigenem Thread).
        TODO: Aktivieren sobald SPI initialisiert.
        """
        THRESHOLD = 0.005  # Mindest-Änderung vor dem Senden (anti-rauschen)
        last_sent = {ch: -1.0 for ch in ADC_CHANNELS}

        while self.running:
            for ch, pd_name in ADC_CHANNELS.items():
                # TODO: Fader-Mapping (linear oder log) je nach Parameter
                val = self.adc.read_smooth(ch)

                # Nur senden wenn Änderung > Schwellenwert
                if abs(val - last_sent[ch]) > THRESHOLD:
                    self.pd.send(pd_name, round(val, 3))
                    last_sent[ch] = val

                    # OLED update with explicit bridge mapping.
                    oled_key = 'space' if pd_name == 'reverb-room' else pd_name.split('-')[0]
                    if oled_key in self.oled.state:
                        self.oled.update(**{oled_key: val})

            time.sleep(1.0 / POLL_HZ)

    def _oled_loop(self):
        """OLED Refresh-Loop (10 Hz). TODO: luma.oled aktivieren."""
        while self.running:
            self.oled._draw()
            time.sleep(0.1)  # 10 Hz

    def start(self):
        """Startet alle Threads und Haupt-Loop."""
        self.running = True

        # Initial state
        t_init = threading.Thread(target=self._send_initial_state, daemon=True)
        t_init.start()

        # ADC polling (TODO: aktivieren wenn SPI läuft)
        # t_adc = threading.Thread(target=self._adc_loop, daemon=True)
        # t_adc.start()

        # OLED (TODO: aktivieren wenn luma.oled installiert)
        # t_oled = threading.Thread(target=self._oled_loop, daemon=True)
        # t_oled.start()

        # PD Listener starten
        t_listener = threading.Thread(target=self.pd_listener.listen, daemon=True)
        t_listener.start()

        log.info("Bridge running — CTRL+C to stop")
        log.info("Sending heartbeat every 5s to PD...")

        try:
            while self.running:
                # Heartbeat: hält UDP-Verbindung warm
                # TODO: entfernen wenn GPIO-Interrupts aktiv
                self.pd.send('randomize')
                time.sleep(5.0)
        except KeyboardInterrupt:
            self.stop()

    def run_pd_route_test(self, duration=10.0):
        """
        Sendet für kurze Zeit Testwerte an alle zentralen PD-Routen.
        Hilfreich, um netreceive/route/s-Dispatcher ohne Hardware zu prüfen.
        """
        end_t = time.time() + max(1.0, float(duration))
        phase = 0
        log.info(f"PD route test started ({duration:.1f}s)")
        self._send_initial_state()

        while time.time() < end_t:
            x = 0.5 + 0.5 * math.sin(phase * 0.25)
            y = 0.5 + 0.5 * math.sin(phase * 0.19 + 1.2)

            # Core mixer + transport
            self.pd.send('transport', 1)
            self.pd.send('drone-level', round(0.15 + 0.55 * x, 3))
            self.pd.send('notes-level', round(0.12 + 0.50 * y, 3))
            self.pd.send('noise-level', round(0.01 + 0.10 * (1.0 - x), 3))
            self.pd.send('reverb-room', round(0.25 + 0.45 * y, 3))
            self.pd.send('master-vol', round(0.35 + 0.30 * x, 3))
            self.pd.send('bpm', int(72 + 48 * x))
            self.pd.send('mood-raw', round(y, 3))

            # Timing / gating control (matches active receivers in PD patches)
            self.pd.send('drone-gate', 1)
            self.pd.send('notes-gate', 1)
            self.pd.send('noise-gate', 1 if (phase % 4) != 0 else 0)
            self.pd.send('texture-gate', 1)
            self.pd.send('macro-gate', 1)
            self.pd.send('whole_time', int(1500 + 2600 * (1.0 - y)))
            if phase % 6 == 0:
                self.pd.send('randomize')

            # Weight presets rotieren
            preset = phase % 3
            if preset == 0:
                self.pd.send('cosmic-w', 100)
                self.pd.send('wonder-w', 0)
                self.pd.send('hopeful-w', 0)
                self.pd.send('koto-w', 0)
                self.pd.send('raga-w', 0)
                self.pd.send('pelog-w', 0)
                self.pd.send('safir16-w', 0)
                self.pd.send('root-hz', 256)
            elif preset == 1:
                self.pd.send('cosmic-w', 0)
                self.pd.send('wonder-w', 100)
                self.pd.send('hopeful-w', 0)
                self.pd.send('koto-w', 0)
                self.pd.send('raga-w', 0)
                self.pd.send('pelog-w', 0)
                self.pd.send('safir16-w', 0)
                self.pd.send('root-hz', 320)
            else:
                self.pd.send('cosmic-w', 0)
                self.pd.send('wonder-w', 0)
                self.pd.send('hopeful-w', 100)
                self.pd.send('koto-w', 0)
                self.pd.send('raga-w', 0)
                self.pd.send('pelog-w', 0)
                self.pd.send('safir16-w', 0)
                self.pd.send('root-hz', 288)

            # Optional buses that may exist
            self.pd.send('chord-level', round(0.25 + 0.35 * y, 3))
            self.pd.send('pedal-level', round(0.03 + 0.08 * x, 3))

            phase += 1
            time.sleep(0.25)

        self.pd.send('transport', 0)
        log.info("PD route test finished")

    def stop(self):
        """Sauberes Herunterfahren."""
        log.info("Stopping bridge...")
        self.running = False
        self.pd_listener.stop()
        self.pd.send('transport', 0)
        time.sleep(0.5)
        self.pd.close()

        # TODO: GPIO cleanup
        # GPIO.cleanup()

        log.info("Bridge stopped")


# ── ENTRY POINT ───────────────────────────────────────────────────────────────

if __name__ == '__main__':
    """
    STARTEN:
    python3 shiftko-hw.py

    ALS SYSTEMD SERVICE:
    sudo systemctl start shiftko
    sudo systemctl enable shiftko  (autostart)

    DEBUG MIT PD:
    In PD-Patch: [netreceive 7400 1 udp] → [print]
    Zeigt alle empfangenen Messages in der Konsole.

    SIMULATION OHNE PI:
    Aktuell sendet bridge nur heartbeat "randomize" alle 5s.
    Alle Hardware-Module sind Scaffolds ohne GPIO-Zugriff.
    """

    parser = argparse.ArgumentParser(description='Shift K.O. hardware bridge')
    parser.add_argument(
        '--route-test',
        type=float,
        default=0.0,
        metavar='SECONDS',
        help='Run UDP route test for N seconds and exit',
    )
    args = parser.parse_args()

    bridge = ShiftKO()
    if args.route_test > 0:
        try:
            bridge.run_pd_route_test(args.route_test)
        finally:
            bridge.stop()
    else:
        bridge.start()
