"""Korg M3R program and combination dumps, and Casio CZ tone dumps.

M3R: from the M3R owner's manual, "MIDI EXCLUSIVE" (pp. 86-95). An ALL PROGRAM
PARAMETER DUMP is F0 42 3n 24 4C <bank>, Korg 7-bit packed data (each group of 8
bytes: one byte of high bits, then 7 bytes), F7. It unpacks to 100 programs of 75
bytes (Table 1). An ALL COMBINATION PARAMETER DUMP (function 4D) unpacks to 100
combinations of 126 bytes (Table 2). Hex ranges like 9D..63 are signed bytes (-99..99).

CZ: a "send tone" dump is F0 44 00 00 7n 20 60, 256 nibbles (low nibble first) making
128 bytes of tone data, F7.
"""

PROGRAM_SIZE = 75
COMBI_SIZE = 126

MULTISOUNDS = [
    "Piano", "E.Piano 1", "Soft E.P.", "Hard E.P.", "Clav", "Harpsicord", "Perc.Organ",
    "MagicOrgan", "Guitar 1", "Guitar 2", "ElecGuitar", "JazzGuitar", "MuteGuitar", "Harmonics",
    "Sitar", "A.Bass", "Slap Bass", "Round Bass", "Fretless", "Pick Bass", "SynthBass1",
    "SynthBass2", "Digi.Bell1", "Digi.Bell2", "Tubular", "Bell Ring", "Vibe", "Kalimba",
    "Marimba", "Music Box", "Gamelan", "Clicker", "SynMallet", "Flute", "Pan Flute", "Bottles",
    "Voices", "Choir", "Strings", "Analog", "SoloString", "TubaFlugel", "DoubleReed", "Brass 1",
    "Brass 2", "Tenor Sax", "Hard Sax", "Mute Tp", "Tromb&Tp", "Clarinet", "Koto Trem", "Lore",
    "Wind Bells", "Pole", "Pluck", "Hammer", "Metal Hit", "Pop", "Vibe Hit", "Block",
    "Spectrum 1", "Spectrum 2", "Spectrum 3", "Spectrum 4", "Voice Wave", "Fv Wave", "Perc.Wave",
    "Ep Wave", "Wire 1", "Wire 2", "S&H Wave", "Digital 1", "Digital 2", "Digital 3", "Digital 6",
    "Digital 7", "Sine", "SquareWave", "Saw Wave", "10% Pulse", "20% Pulse", "DWGS Clav",
    "DWGSOrgan1", "DWGSOrgan2", "DWGS E.P.1", "DWGS Voice", "DWGS Vibe", "DWGS Bell1",
    "DWGS Bass1", "DWGS Bass2",
]
# Multisounds that are plain waveforms: a program on one of these converts directly.
BASIC_WAVES = {76: "sine", 77: "square", 78: "saw", 79: "pulse", 80: "pulse"}
BASIC_WIDTH = {79: 0.10, 80: 0.20}
DRUM_KITS = 8
MG_WAVES = ["triangle", "up saw", "down saw", "rectangle"]
COMBI_TYPES = ["single", "layer", "split", "velocity switch", "multi"]


def unpack7(data):
    out = bytearray()
    for i in range(0, len(data), 8):  # the last group may be short
        group = data[i:i + 8]
        hi = group[0]
        for j, b in enumerate(group[1:]):
            out.append(b | (((hi >> j) & 1) << 7))
    return bytes(out)


def messages(data):
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


def is_m3r(data):
    return len(data) > 8 and data[0] == 0xF0 and data[1] == 0x42 and data[3] == 0x24


def is_cz_tone(data):
    return (len(data) == 264 and data[:2] == b"\xF0\x44" and data[5:7] == b"\x20\x60"
            and data[-1] == 0xF7)


def cz_tone_bytes(data):
    body = data[7:-1]
    return bytes((body[i] & 0x0F) | ((body[i + 1] & 0x0F) << 4) for i in range(0, len(body), 2))


def read_m3r(data):
    """-> (programs, combinations): lists of {index, name, packed}."""
    progs, combis = [], []
    for m in messages(data):
        if len(m) < 8 or m[1] != 0x42 or m[3] != 0x24:
            continue
        func, body = m[4], unpack7(m[6:-1])
        size, target, tag = {0x4C: (PROGRAM_SIZE, progs, "P"),
                             0x4D: (COMBI_SIZE, combis, "C")}.get(func, (None, None, None))
        if not size:
            continue
        for i in range(len(body) // size):
            raw = body[i * size:(i + 1) * size]
            target.append({"index": i, "number": f"{tag}{i:02d}", "name": _name(raw[:10]),
                           "packed": raw})
    return progs, combis


def _name(b):
    return "".join(chr(c) if 32 <= c < 127 else " " for c in b).strip()


def s8(v):
    return v - 256 if v > 127 else v


def _bits_sw_pol(v):
    names = ["attack", "decay", "slope", "release"]
    return {n: {"on": bool(v >> i & 1), "negative": bool(v >> (i + 4) & 1)}
            for i, n in enumerate(names)}


def _mg(raw, base):
    w = raw[base]
    return {"wave": MG_WAVES[w & 3], "enabled": bool(w >> 5 & 1), "key_sync": bool(w >> 7 & 1),
            "frequency": raw[base + 1], "delay": raw[base + 2], "intensity": raw[base + 3]}


def program_params(raw):
    """75 program bytes -> named parameters (Table 1). Values stay in the M3R's own units."""
    mode = "drum" if raw[10] == 2 else "multisound"
    ms = raw[12]
    osc = {"mode": mode, "assign": "mono" if raw[11] & 1 else "poly", "hold": bool(raw[11] >> 1 & 1),
           "octave_feet": {0xFF: 16, 0: 8, 1: 4}.get(raw[13], raw[13]),
           "octave_shift": s8(raw[13]), "delay_start": raw[14]}
    if mode == "multisound":
        osc["multisound"] = ms
        if ms < len(MULTISOUNDS):
            osc["multisound_name"] = MULTISOUNDS[ms]
            osc["source"] = "internal"
        else:
            osc["source"] = "card"
            osc["card_multisound"] = ms - 0x5A
    else:
        osc["drum_kit"] = ms
        osc["source"] = "internal" if ms < 4 else "card"
    return {
        "name": _name(raw[:10]),
        "oscillator": osc,
        "pitch_mg": _mg(raw, 15),
        "cutoff_mg": _mg(raw, 19),
        "aftertouch": {"pitch": s8(raw[23]), "pitch_mg": raw[24], "vdf_cutoff": s8(raw[25]),
                       "vdf_mg": raw[26], "vda_amplitude": s8(raw[27])},
        "controller": {"pitch_bend": s8(raw[28]), "vdf_sweep_int": s8(raw[29]),
                       "pitch_mg_int": raw[30], "pitch_mg_frequency": raw[31],
                       "vdf_mg_int": raw[32], "vdf_mg_frequency": raw[33]},
        "pitch_eg": {"start_level": s8(raw[34]), "attack_time": raw[35],
                     "attack_level": s8(raw[36]), "decay_time": raw[37],
                     "release_time": raw[38], "release_level": s8(raw[39]),
                     "time_velocity_sense": s8(raw[40]), "level_velocity_sense": s8(raw[41])},
        "vdf": {"cutoff": raw[42], "kbd_track_center_key": raw[43],
                "cutoff_kbd_track": s8(raw[44]), "eg_intensity": raw[45],
                "eg_time_kbd_track": raw[46], "eg_time_velocity_sense": raw[47],
                "eg_intensity_velocity_sense": s8(raw[48])},
        "vdf_eg": {"attack_time": raw[49], "attack_level": s8(raw[50]), "decay_time": raw[51],
                   "break_point": s8(raw[52]), "slope_time": raw[53],
                   "sustain_level": s8(raw[54]), "release_time": raw[55],
                   "release_level": s8(raw[56]),
                   "time_kbd_track_switches": _bits_sw_pol(raw[70]),
                   "time_velocity_switches": _bits_sw_pol(raw[71])},
        "vda": {"oscillator_level": raw[57], "kbd_track_center_key": raw[58],
                "amp_kbd_track": s8(raw[59]), "amp_velocity_sense": s8(raw[60]),
                "eg_time_kbd_track": raw[61], "eg_time_velocity_sense": raw[62]},
        "vda_eg": {"attack_time": raw[63], "attack_level": raw[64], "decay_time": raw[65],
                   "break_point": raw[66], "slope_time": raw[67], "sustain_level": raw[68],
                   "release_time": raw[69],
                   "time_kbd_track_switches": _bits_sw_pol(raw[72]),
                   "time_velocity_switches": _bits_sw_pol(raw[73])},
    }


def combi_params(raw):
    """126 combination bytes -> named parameters (Table 2)."""
    ctype = raw[10]
    timbres = []
    for t in range(8):
        b = 36 + t * 11
        prog = raw[b]
        if ctype == 4:  # MULTI: 00 = timbre off, 01..64 = I00..I99, 65..C8 = C00..C99
            ref = None if prog == 0 else (f"I{prog - 1:02d}" if prog <= 0x64 else
                                          f"C{prog - 0x65:02d}")
        else:
            ref = f"I{prog:02d}" if prog < 0x64 else f"C{prog - 0x64:02d}"
        timbres.append({
            "timbre": t + 1, "program": ref, "output_level": raw[b + 1],
            "transpose": s8(raw[b + 2]), "detune": s8(raw[b + 3]),
            "timbre_or_inst": "inst" if raw[b + 4] >> 7 & 1 else "timbre",
            "pan": raw[b + 4] & 0x0F, "key_window": [raw[b + 6], raw[b + 5]],
            "velocity_window": [raw[b + 8], raw[b + 7]], "control_filter": raw[b + 9] & 0x0F,
            "on": not (raw[b + 10] >> 4 & 1), "midi_channel": (raw[b + 10] & 0x0F) + 1,
        })
    return {
        "name": _name(raw[:10]),
        "type": COMBI_TYPES[ctype] if ctype < len(COMBI_TYPES) else ctype,
        "effects_raw_hex": raw[11:36].hex(),
        "timbres": timbres,
    }
