"""Casio CZ-101 / CZ-1000 tones (SysEx): read the 128-byte tone data and name every parameter.

A tone travels as F0 44 00 00 7n 20 pp <256 nibbles> F7 (264 bytes; n = MIDI channel, 20 =
"receive request 1": tone data going *to* the CZ for program pp, 60 = the edit/temporary area). A
dump captured from the CZ's own reply is F0 44 00 00 7n 30 <256 nibbles> F7. Each data byte is
split into two nibbles, LOW nibble first (5F is sent 0F 05). The 128 bytes, in order:

  0  PFLAG   line select (bits 0-1: 1, 2, 1+1', 1+2') and octave (bits 2-3: 0, +1, -1)
  1  PDS     detune sign (0 +, 1 -)
  2  PDL     detune fine, stored << 2 (youngmonkey's 00..3F table, shifted; synprez noticed)
  3  PDH     detune octave*12 + note
  4  PVK     vibrato wave 08/04/20/02 = 1 triangle, 2 saw up, 3 saw down, 4 square
  5-13       vibrato delay, rate, depth: each the panel value then a 16-bit firmware value, low
             byte first (youngmonkey prints the pairs high byte first)
  14-70      line 1: waveform word (2), DCA key follow (2), DCW key follow (2), then the DCA,
             DCW and DCO envelopes, each an end step (0-7) and 8 x (rate, level)
  71-127     line 2, same layout

There is no name in the tone data. Most bytes are the uPD933 sound chip's register values, ready
to write (MAME src/devices/sound/upd933.cpp): the waveform word is register 68-6f bit for bit
(wave 1, wave 2, second-wave enable, 3-bit window, ring, pitch-mod enable, pitch-mod source =
noise); an envelope rate byte is the step register's direction bit + 7-bit rate, a level byte its
sustain bit + 7-bit level; a DCO level keeps the chip's units bit (bit 6: 2 semitones, else 1/16
semitone). The panel's 0-99 values are the firmware's mapping onto those. What the firmware does
beyond writing them (key follow, the vibrato LFO, release) is not documented; the notes file
(cz-sysex.md) lists what is known and what is guessed.

Sources: youngmonkey.ca "Casio CZ MIDI/SYSEX" (layout, panel tables, rate/level formulas, key
follow tables); coffeeshopped/casio-cz-editor (Max patches: byte2alevel = byte - 28, envelope
conversions); synprez/Mame-cz101-and-Behringer-CZ-1-Mini-resources cz/czpatch.py (detune fine
<< 2, DCA level + 28, DCO level fold, firmware display quirks seen through MAME with the real ROM);
CZ-101 Operation Manual pp. 19, 28-35 (vibrato waves, resonance waves, key follow, ring/noise only
in 1+1'/1+2', DCO level 66 + 6n = n+1 octaves); MAME upd933.cpp (chip registers, rates, volume).
"""

import hashlib
import math

HEADER = bytes([0xF0, 0x44, 0x00, 0x00])
TONE_BYTES = 128
LINE_SELECT = ["1", "2", "1+1'", "1+2'"]
OCTAVES = [0, 1, -1]
VIBRATO_WAVE_CODES = {0x08: 1, 0x04: 2, 0x20: 3, 0x02: 4}
VIBRATO_WAVES = {1: "triangle", 2: "saw up", 3: "saw down", 4: "square"}
# Chip wave codes (uPD933, MAME); the CZ-101 panel uses all but 3 and 7.
CHIP_WAVES = ["saw", "square", "pulse", "silent", "double sine", "saw pulse", "resonance", "double pulse"]
CHIP_WINDOWS = ["none", "saw", "triangle", "trapezoid", "pulse", "double saw", "window 6", "window 7"]
PANEL_WAVES = {1: "saw", 2: "square", 3: "pulse", 4: "double sine", 5: "saw pulse",
               6: "resonance (saw window)", 7: "resonance (triangle window)", 8: "resonance (trapezoid window)"}
CODE_TO_PANEL = {0: 1, 1: 2, 2: 3, 4: 4, 5: 5}
PROGRAMS = {**{0x00 + i: f"preset {i + 1}" for i in range(16)}, **{0x20 + i: f"internal {i + 1}" for i in range(16)},
            **{0x40 + i: f"cartridge {i + 1}" for i in range(16)}, 0x60: "temporary (edit) area"}
# Key follow: the panel 0-9 is stored with a firmware value (youngmonkey tables; every factory file agrees).
DCA_KEY_FOLLOW = [0x00, 0x08, 0x11, 0x1A, 0x24, 0x2F, 0x3A, 0x45, 0x52, 0x5F]
DCW_KEY_FOLLOW = [0x00, 0x1F, 0x2C, 0x39, 0x46, 0x53, 0x60, 0x6E, 0x92, 0xFF]
# Vibrato 16-bit values per panel value, youngmonkey's tables (0-24 by rule, 25-99 printed).
# Rate 47 is printed 0820 there; the factory tones store 0860, which also fits the table's steps.
_DELAY_HI = [0x19, 0x1a, 0x1b, 0x1c, 0x1d, 0x1e, 0x1f, 0x21, 0x23, 0x25, 0x27, 0x29, 0x2b, 0x2d, 0x2f, 0x31,
             0x33, 0x35, 0x37, 0x39, 0x3b, 0x3d, 0x3f, 0x43, 0x47, 0x4b, 0x4f, 0x53, 0x57, 0x5b, 0x5f, 0x63,
             0x67, 0x6b, 0x6f, 0x73, 0x77, 0x7b, 0x7f, 0x87, 0x8f, 0x97, 0x9f, 0xa7, 0xaf, 0xb7, 0xbf, 0xc7,
             0xcf, 0xd7, 0xdf, 0xe7, 0xef, 0xf7, 0xff, 0x10f, 0x11f, 0x12f, 0x13f, 0x14f, 0x15f, 0x16f,
             0x17f, 0x18f, 0x19f, 0x1af, 0x1bf, 0x1cf, 0x1df, 0x1ef, 0x1ff, 0x21f, 0x23f, 0x25f, 0x27f]
_RATE_HI = [0x340, 0x360, 0x380, 0x3a0, 0x3c0, 0x3e0, 0x400, 0x460, 0x4a0, 0x4e0, 0x520, 0x560, 0x5a0,
            0x5e0, 0x620, 0x660, 0x6a0, 0x6e0, 0x720, 0x760, 0x7a0, 0x7e0, 0x860, 0x8e0, 0x960, 0x9e0,
            0xa60, 0xae0, 0xb60, 0xbe0, 0xc60, 0xce0, 0xd60, 0xde0, 0xe60, 0xee0, 0xf60, 0xfe0, 0x1060,
            0x11e0, 0x12e0, 0x13e0, 0x14e0, 0x15e0, 0x16e0, 0x17e0, 0x18e0, 0x19e0, 0x1ae0, 0x1be0, 0x1ce0,
            0x1de0, 0x1ee0, 0x1fe0, 0x20e0, 0x23e0, 0x25e0, 0x27e0, 0x29e0, 0x2be0, 0x2de0, 0x2fe0, 0x31e0,
            0x33e0, 0x35e0, 0x37e0, 0x39e0, 0x3be0, 0x3de0, 0x3fe0, 0x41e0, 0x47e0, 0x4be0, 0x4fe0, 0x53e0]
_DEPTH_HI = [0x1a, 0x1b, 0x1c, 0x1d, 0x1e, 0x1f, 0x20, 0x23, 0x25, 0x27, 0x29, 0x2b, 0x2d, 0x2f, 0x31, 0x33,
             0x35, 0x37, 0x39, 0x3b, 0x3d, 0x3f, 0x41, 0x47, 0x4b, 0x4f, 0x53, 0x57, 0x5b, 0x5f, 0x63, 0x67,
             0x6b, 0x6f, 0x73, 0x77, 0x7b, 0x7f, 0x83, 0x8f, 0x97, 0x9f, 0xa7, 0xaf, 0xb7, 0xbf, 0xc7, 0xcf,
             0xd7, 0xdf, 0xe7, 0xef, 0xf7, 0xff, 0x107, 0x11f, 0x12f, 0x13f, 0x14f, 0x15f, 0x16f, 0x17f,
             0x18f, 0x19f, 0x1af, 0x1bf, 0x1cf, 0x1df, 0x1ef, 0x1ff, 0x20f, 0x23f, 0x25f, 0x27f, 0x300]
VIBRATO_DELAY = list(range(25)) + _DELAY_HI
VIBRATO_RATE = [(r + 1) * 0x20 for r in range(25)] + _RATE_HI
VIBRATO_DEPTH = [d + 1 for d in range(25)] + _DEPTH_HI

CHIP_SAMPLE_RATE = 40000  # 8.96 MHz / 2 / 112 (MAME cz101.cpp, upd933.h)
_VOLUME_DB_SPAN = 20 * math.log10(8192)  # MAME's log volume table spans 2^13 over 511 steps


# ---- panel <-> stored byte (forward formulas from the sources; inverse = exact table lookup) ----

def dca_rate_byte(p):   # youngmonkey, coffeeshopped arate2byte
    return 119 * p // 99


def dcw_rate_byte(p):   # youngmonkey ("+ 8"), coffeeshopped wrate2byte
    return 119 * p // 99 + 8


def dco_rate_byte(p):   # youngmonkey, coffeeshopped orate2byte
    return 127 * p // 99


def dca_level_byte(p):  # coffeeshopped alevel2byte, synprez (youngmonkey's 127*L/99 is not it)
    return 0 if p == 0 else p + 28


def dcw_level_byte(p):  # youngmonkey, coffeeshopped wlevel2byte
    return 127 * p // 99


def dco_level_byte(p):  # youngmonkey, coffeeshopped olevel2byte: 64-99 skip 0x40-0x43
    return p if p < 64 else p + 4


def _inverse(fwd):
    t = {}
    for p in range(100):
        t.setdefault(fwd(p), p)
    return t


_INV = {f.__name__: _inverse(f) for f in (dca_rate_byte, dcw_rate_byte, dco_rate_byte, dca_level_byte,
                                          dcw_level_byte, dco_level_byte)}


def _panel(kind, b):
    """7-bit stored value -> (panel 0-99, exact). Not exact: no panel value stores this byte; the
    published inverse formula is used instead (clamped to 0-99)."""
    t = _INV[kind]
    if b in t:
        return t[b], True
    if kind == "dca_rate_byte":
        p = 99 * b // 119 + 1
    elif kind == "dcw_rate_byte":
        p = 99 * (b - 8) // 119 + 1 if b >= 8 else 0
    elif kind in ("dco_rate_byte", "dcw_level_byte"):
        p = 99 * b // 127 + 1
    elif kind == "dca_level_byte":
        p = b - 28 if b >= 28 else 0
    else:  # dco level: 0x40-0x43 fold onto 60-63 (synprez), 0x44+ are 64+
        p = b - 4 if b >= 64 else b
    return max(0, min(99, p)), False


def chip_rate(r):
    """uPD933 envelope increment per 40 kHz sample for a 7-bit rate (MAME env_rate)."""
    return (8 | (r & 7)) << (r >> 3)


def dco_semitones(b):
    """DCO level byte -> pitch offset in semitones (chip: bit 6 = 2-semitone units, else 1/16)."""
    return (b & 0x3F) * (2.0 if b & 0x40 else 1.0 / 16)


def _chip_units(kind, b):
    """A level byte as the chip's internal envelope value (MAME's target shifts)."""
    if kind == "dca":
        return (b & 0x7F) << 18
    if kind == "dcw":
        return (b & 0x7F) << 19
    return (b & 0x3F) << (21 if b & 0x40 else 16)


def dca_db(level7):
    """DCA level (7-bit) -> dB relative to level 127 on MAME's log volume curve (None = silent)."""
    if level7 == 0:
        return None
    return round(_VOLUME_DB_SPAN * (4 * level7 - 4 * 127) / 511, 2)


# ---- message framing ----

def messages(data):
    """Split a file into SysEx messages (F0 .. F7)."""
    out, i = [], 0
    while True:
        s = data.find(b"\xF0", i)
        if s < 0:
            return out
        e = data.find(b"\xF7", s)
        if e < 0:
            return out
        out.append(data[s:e + 1])
        i = e + 1


def _frame(msg):
    """-> (command, channel, program or None, 256 nibbles) or None if not a CZ tone message."""
    if len(msg) < 263 or msg[:4] != HEADER or (msg[4] & 0xF0) != 0x70 or msg[-1] != 0xF7:
        return None
    cmd = msg[5]
    if cmd == 0x20 and len(msg) == 264:
        prog, nib = msg[6], msg[7:263]
    elif cmd == 0x30 and len(msg) == 263:
        prog, nib = None, msg[6:262]
    else:
        return None
    if any(b > 0x0F for b in nib):
        return None
    return cmd, msg[4] & 0x0F, prog, nib


def is_cz(name, data):
    """A CZ-101/1000 tone message (.syx), receive-request (20) or send-reply (30) form."""
    if not name.lower().endswith(".syx"):
        return False
    return any(_frame(m) is not None for m in messages(data))


def unpack(nib):
    """256 nibbles, low nibble first -> 128 tone bytes."""
    return bytes(nib[2 * i] | (nib[2 * i + 1] << 4) for i in range(TONE_BYTES))


# ---- tone decoding ----

def _fine_panel(pdl):
    """PDL -> (fine 0-60, exact). v = PDL >> 2 runs 00-0F, 11-1F, 21-2F, 31-3F (youngmonkey)."""
    v = (pdl >> 2) & 0x3F
    exact = (pdl & 3) == 0 and v not in (0x10, 0x20, 0x30)
    if v & 0x0F:
        f = v - (v >> 4)
    else:  # 00 -> 0; the unused 10/20/30 read as the step below (15/30/45)
        f = v - (v >> 4) - 1 if v else 0
    return min(60, f), exact


def _lfo(panel, lo, hi, table):
    value = lo | (hi << 8)
    expected = table[panel] if panel < len(table) else None
    return {"panel": panel, "value": value, "expected": expected, "match": value == expected}


def _wave(code, window):
    if code == 6:
        p = 5 + window if 1 <= window <= 3 else None
    else:
        p = CODE_TO_PANEL.get(code)
    return {"code": code, "chip_name": CHIP_WAVES[code], "panel": p,
            "name": PANEL_WAVES.get(p, CHIP_WAVES[code])}


def _waveform(b0, b1):
    word = (b0 << 8) | b1
    window = ((b0 & 1) << 2) | (b1 >> 6)
    second_on = bool(b0 & 0x02)
    w1 = _wave(b0 >> 5, window)
    w2 = _wave((b0 >> 2) & 7, window) if second_on else None
    return {"word": word, "wave1": w1, "wave2": w2, "second_enabled": second_on,
            "window": window, "window_name": CHIP_WINDOWS[window],
            "ring": bool(b1 & 0x20), "pitch_mod": bool(b1 & 0x10), "pitch_mod_noise": bool(b1 & 0x08),
            "noise": (b1 & 0x18) == 0x18, "mute_other": bool(b1 & 0x04), "low_bits": b1 & 0x03}


def _key_follow(b, table):
    exp = table[b[0]] if b[0] < len(table) else None
    return {"panel": b[0], "value": b[1], "expected": exp, "match": b[1] == exp}


def _envelope(kind, d):
    """d: 17 bytes (end, then 8 x rate, level) -> dict with raw and panel values per step."""
    end_raw = d[0]
    end = end_raw & 7
    rk, lk = f"{kind}_rate_byte", f"{kind}_level_byte"
    steps, issues, sustain = [], [], None
    prev_units = 0
    for i in range(8):
        r, l = d[1 + 2 * i], d[2 + 2 * i]
        rate, rate_exact = _panel(rk, r & 0x7F)
        level, level_exact = _panel(lk, l & 0x7F)
        units = _chip_units(kind, l)
        inc = chip_rate(r & 0x7F)
        s = {"step": i + 1, "rate_raw": r, "level_raw": l, "down": bool(r & 0x80), "sustain": bool(l & 0x80),
             "rate7": r & 0x7F, "level7": l & 0x7F, "rate": rate, "level": level,
             "rate_exact": rate_exact, "level_exact": level_exact, "active": i <= end,
             "chip_increment": inc}
        if i <= end:
            # MAME model, no key follow: time to move from the previous step's level to this one
            s["chip_seconds"] = round(abs(units - prev_units) / inc / CHIP_SAMPLE_RATE, 5)
            prev_units = units
            if s["sustain"]:
                if i == end:
                    issues.append(f"{kind}: sustain flag on the end step {i + 1}")
                elif sustain is None:
                    sustain = i + 1
                else:
                    issues.append(f"{kind}: second sustain flag at step {i + 1}")
            if not rate_exact:
                issues.append(f"{kind}: step {i + 1} rate byte {r & 0x7F:#04x} is no panel value")
            if not level_exact:
                issues.append(f"{kind}: step {i + 1} level byte {l & 0x7F:#04x} is no panel value")
        if kind == "dco":
            s["semitones"] = dco_semitones(l)
        elif kind == "dca":
            s["db"] = dca_db(l & 0x7F)
        else:
            s["amount"] = round((l & 0x7F) / 127, 4)
        steps.append(s)
    if end_raw > 7:
        issues.append(f"{kind}: end byte {end_raw:#04x} > 7 (read as step {end + 1})")
    if steps[end]["level7"] != 0:
        issues.append(f"{kind}: end step {end + 1} level {steps[end]['level']} is not 0")
    # direction bit vs the level change (step 1 starts from 0)
    prev = 0
    for s in steps[:end + 1]:
        lv = _chip_units(kind, s["level_raw"])
        if lv != prev and s["down"] != (lv < prev):
            issues.append(f"{kind}: step {s['step']} direction bit {'down' if s['down'] else 'up'} "
                          f"but level goes {'down' if lv < prev else 'up'}")
        prev = lv
    return {"end_raw": end_raw, "end_step": end + 1, "sustain_step": sustain, "steps": steps, "issues": issues}


def _line(n, d):
    issues = []
    wf = _waveform(d[0], d[1])
    dca_kf, dcw_kf = _key_follow(d[2:4], DCA_KEY_FOLLOW), _key_follow(d[4:6], DCW_KEY_FOLLOW)
    envs = {k: _envelope(k, d[6 + 17 * j:6 + 17 * (j + 1)]) for j, k in enumerate(("dca", "dcw", "dco"))}
    if wf["wave1"]["panel"] is None or (wf["wave2"] and wf["wave2"]["panel"] is None):
        issues.append(f"line {n}: chip wave/window combination the panel cannot set")
    if wf["window"] and wf["wave1"]["code"] != 6 and not (wf["wave2"] and wf["wave2"]["code"] == 6):
        issues.append(f"line {n}: window {wf['window']} set without a resonance wave")
    if wf["mute_other"] or wf["low_bits"]:
        issues.append(f"line {n}: unused waveform bits set ({wf['word']:#06x})")
    if n == 2 and (wf["ring"] or wf["pitch_mod"]):
        issues.append("line 2: modulation bits set (youngmonkey: ignored on line 2)")
    for k, kf in (("dca", dca_kf), ("dcw", dcw_kf)):
        if not kf["match"]:
            issues.append(f"line {n}: {k} key follow {kf['panel']} stored with {kf['value']:#04x}, "
                          f"table says {kf['expected']}")
    for e in envs.values():
        issues.extend(f"line {n} {x}" for x in e["issues"])
    return {"raw": bytes(d), "waveform": wf, "dca_key_follow": dca_kf, "dcw_key_follow": dcw_kf,
            **envs, "issues": issues}


def decode(tone):
    """128 tone bytes -> named fields (raw bytes and panel values side by side)."""
    if len(tone) != TONE_BYTES:
        raise ValueError("CZ tone data is 128 bytes")
    t = tone
    issues = []
    ls, octv = t[0] & 3, (t[0] >> 2) & 3
    if t[0] & 0xF0 or octv == 3:
        issues.append(f"PFLAG {t[0]:#04x}: unused bits or octave code 3")
    fine, fine_exact = _fine_panel(t[2])
    det_oct, det_note = divmod(t[3] & 0x3F, 12)
    sign = -1 if t[1] else 1
    if t[1] > 1 or not fine_exact or t[3] > 47:
        issues.append(f"detune bytes {t[1]:#04x} {t[2]:#04x} {t[3]:#04x} out of the panel's range")
    detune = {"sign_raw": t[1], "sign": sign, "fine_raw": t[2], "fine": fine, "fine_exact": fine_exact,
              "coarse_raw": t[3], "octave": det_oct, "note": det_note,
              # manual: fine is 1/60 semitone. Guess: the firmware adds PDH.PDL as 8.8 semitones.
              "semitones_panel": sign * (t[3] + fine / 60.0),
              "semitones_raw_guess": sign * (t[3] + t[2] / 256.0)}
    vw = VIBRATO_WAVE_CODES.get(t[4])
    if vw is None:
        issues.append(f"vibrato wave byte {t[4]:#04x} unknown")
    vib = {"wave_raw": t[4], "wave": vw, "wave_name": VIBRATO_WAVES.get(vw),
           "delay": _lfo(t[5], t[6], t[7], VIBRATO_DELAY), "rate": _lfo(t[8], t[9], t[10], VIBRATO_RATE),
           "depth": _lfo(t[11], t[12], t[13], VIBRATO_DEPTH)}
    for k in ("delay", "rate", "depth"):
        v = vib[k]
        if v["panel"] > 99:
            issues.append(f"vibrato {k} {v['panel']} > 99")
        elif not v["match"]:
            issues.append(f"vibrato {k} {v['panel']} stored with {v['value']:#06x}, table says {v['expected']:#06x}")
    lines = [_line(1, t[14:71]), _line(2, t[71:128])]
    for ln in lines:
        issues.extend(ln["issues"])
    return {"raw": bytes(t), "pflag": t[0], "line_select_raw": ls, "line_select": LINE_SELECT[ls],
            "octave_raw": octv, "octave": OCTAVES[octv] if octv < 3 else None,
            "detune": detune, "vibrato": vib, "lines": lines, "issues": issues}


def read(data):
    """Bytes of a .syx (its first CZ tone message) -> decode()'s fields, the framing and named()."""
    for m in messages(data):
        f = _frame(m)
        if f:
            break
    else:
        raise ValueError("no CZ-101 tone message (F0 44 00 00 7n 20 pp | 30, 256 nibbles, F7)")
    cmd, ch, prog, nib = f
    d = decode(unpack(nib))
    d.update({"command": cmd, "channel": ch + 1, "program": prog,
              "program_name": PROGRAMS.get(prog) if prog is not None else None, "message": m})
    d["named"] = named(d)
    return d


def read_all(data):
    """Every CZ tone message in a file (banks saved as concatenated tones)."""
    return [read(m) for m in messages(data) if _frame(m)]


def sound_sha256(parsed):
    """The 128 tone bytes: the same tone under another name or program hashes the same."""
    return hashlib.sha256(parsed["raw"]).hexdigest()


def _env_summary(e):
    act = e["steps"][:e["end_step"]]
    return {"end": e["end_step"], "sustain": e["sustain_step"],
            "rates": [s["rate"] for s in act], "levels": [s["level"] for s in act]}


def _wave_label(wf):
    a = wf["wave1"]["panel"]
    b = wf["wave2"]["panel"] if wf["wave2"] else 0
    return f"{a}+{b}" if b else f"{a}"


def params(d):
    """decode()'s fields as plain JSON (raw bytes as hex): what a sidecar keeps for the converter."""
    def plain(v):
        if isinstance(v, (bytes, bytearray)):
            return bytes(v).hex()
        if isinstance(v, dict):
            return {k: plain(x) for k, x in v.items()}
        if isinstance(v, (list, tuple)):
            return [plain(x) for x in v]
        return v
    return plain(d)


def named(d):
    """Compact, readable summary: panel values only, sounding lines and active steps only."""
    ls = d["line_select_raw"]
    used = {0: [1], 1: [2], 2: [1, 1], 3: [1, 2]}[ls]
    two = ls in (2, 3)
    l1 = d["lines"][0]["waveform"]
    out = {"line_select": d["line_select"], "octave": d["octave"], "voices": 4 if two else 8,
           "lines_sounding": used,
           # manual p.35: ring/noise act on the primed line, only in 1+1' and 1+2'
           "modulation": ("ring" if l1["ring"] else "noise" if l1["noise"] else "none") if two else "none",
           "vibrato": {"wave": d["vibrato"]["wave_name"], "delay": d["vibrato"]["delay"]["panel"],
                       "rate": d["vibrato"]["rate"]["panel"], "depth": d["vibrato"]["depth"]["panel"]}}
    if two:
        dt = d["detune"]
        out["detune"] = {"sign": "+" if dt["sign"] > 0 else "-", "octave": dt["octave"], "note": dt["note"],
                         "fine": dt["fine"]}
    for n in sorted(set(used)):
        ln = d["lines"][n - 1]
        wf = ln["waveform"]
        out[f"line{n}"] = {
            "waves": _wave_label(wf),
            "wave_names": [wf["wave1"]["name"]] + ([wf["wave2"]["name"]] if wf["wave2"] else []),
            "dca_key_follow": ln["dca_key_follow"]["panel"], "dcw_key_follow": ln["dcw_key_follow"]["panel"],
            "dca": _env_summary(ln["dca"]), "dcw": _env_summary(ln["dcw"]), "dco": _env_summary(ln["dco"])}
    if d["issues"]:
        out["issues"] = list(d["issues"])
    return out
