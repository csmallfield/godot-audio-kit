"""Synth1 patches (.sy1): read, fill in Synth1's defaults, and name every parameter.

Synth1 is Daichi Laboratory's freeware VST (closed source). A .sy1 file is text: the
program name, then "color=" and "ver=" lines (older files have neither), then one
"index,value" line per parameter. The index is the VST parameter index and the value is
the integer Synth1 keeps (mostly 0-127, some enums, a few signed). Older versions write
fewer lines; Synth1 then keeps its initial value, listed in DEFAULTS.

What the values mean (units, curves) was measured from Synth1 itself by
tools/synth1_ref/ (see docs/plans/synth-expansion-phase0-synth1.md). Only what is
certain is named here; the converter reads the measured tables.
"""

import hashlib

# (index, key, Synth1's own parameter name). Index 94 has no name in Synth1's parameter
# list; its values (1-32, default 16) are the polyphony that became a per-patch setting in 1.09.
PARAMS = [
    (0, "osc1_shape", "osc1 shape"), (1, "osc2_shape", "osc2 shape"),
    (2, "osc2_pitch", "osc2 pitch"), (3, "osc2_fine", "osc2 fine tune"),
    (4, "osc2_track", "osc2 kbd track"), (5, "osc_mix", "osc mix"),
    (6, "osc2_sync", "osc2 sync"), (7, "osc2_ring", "osc2 ring modulation"),
    (8, "pulse_width", "osc pulse width"), (9, "key_shift", "osc key shift"),
    (10, "modenv_on", "osc mod env on/off"), (11, "modenv_amount", "osc mod env amount"),
    (12, "modenv_attack", "osc mod env attack"), (13, "modenv_decay", "osc mod env decay"),
    (14, "filter_type", "filter type"), (15, "f_attack", "filter attack"),
    (16, "f_decay", "filter decay"), (17, "f_sustain", "filter sustain"),
    (18, "f_release", "filter release"), (19, "f_freq", "filter freq"),
    (20, "f_res", "filter resonance"), (21, "f_amount", "filter amount"),
    (22, "f_track", "filter kbd track"), (23, "f_sat", "filter saturation"),
    (24, "f_vel", "filter velocity switch"), (25, "a_attack", "amp attack"),
    (26, "a_decay", "amp decay"), (27, "a_sustain", "amp sustain"),
    (28, "a_release", "amp release"), (29, "a_gain", "amp gain"),
    (30, "a_vel", "amp velocity sens"), (31, "arp_type", "arpeggiator type"),
    (32, "arp_oct", "arpeggiator oct range"), (33, "arp_beat", "arpeggiator beat"),
    (34, "arp_gate", "arpeggiator gate"), (35, "delay_time", "delay time"),
    (36, "delay_fb", "delay feedback"), (37, "delay_mix", "delay dry/wet"),
    (38, "play_mode", "play mode type"), (39, "porta_time", "portament time"),
    (40, "bend_range", "pitch bend range"), (41, "lfo1_dest", "lfo1 destination"),
    (42, "lfo1_type", "lfo1 type"), (43, "lfo1_speed", "lfo1 speed"),
    (44, "lfo1_depth", "lfo1 depth"), (45, "osc1_fm", "osc1 FM"),
    (46, "lfo2_dest", "lfo2 destination"), (47, "lfo2_type", "lfo2 type"),
    (48, "lfo2_speed", "lfo2 speed"), (49, "lfo2_depth", "lfo2 depth"),
    (50, "ctrl_sens1", "midi ctrl sens1"), (51, "ctrl_sens2", "midi ctrl sens2"),
    (52, "ch_delay", "chorus delay time"), (53, "ch_depth", "chorus depth"),
    (54, "ch_rate", "chorus rate"), (55, "ch_fb", "chorus feedback"),
    (56, "ch_level", "chorus level"), (57, "lfo1_on", "lfo1 on/off"),
    (58, "lfo2_on", "lfo2 on/off"), (59, "arp_on", "arpeggiator on/off"),
    (60, "eq_tone", "equalizer tone"), (61, "eq_freq", "equalizer freq"),
    (62, "eq_level", "equalizer level"), (63, "eq_q", "equalizer Q"),
    (64, "ch_type", "chorus type"), (65, "delay_on", "delay on/off"),
    (66, "chorus_on", "chorus on/off"), (67, "lfo1_sync", "lfo1 tempo sync"),
    (68, "lfo1_keysync", "lfo1 key sync"), (69, "lfo2_sync", "lfo2 tempo sync"),
    (70, "lfo2_keysync", "lfo2 key sync"), (71, "modenv_dest", "osc mod dest"),
    (72, "osc_tune", "osc1,2 fine tune"), (73, "unison_on", "unison mode"),
    (74, "porta_auto", "portament auto mode"), (75, "unison_detune", "unison detune"),
    (76, "osc1_detune", "osc1 detune"), (77, "fx_on", "effect on/off"),
    (78, "fx_type", "effect type"), (79, "fx_ctl1", "effect control1"),
    (80, "fx_ctl2", "effect control2"), (81, "fx_mix", "effect level/mix"),
    (82, "delay_type", "delay type"), (83, "delay_spread", "delay time spread"),
    (84, "unison_spread", "unison pan spread"), (85, "unison_pitch", "unison pitch"),
    (86, "ctrl_src1", "midi ctrl src1"), (87, "ctrl_assign1", "midi ctrl assign1"),
    (88, "ctrl_src2", "midi ctrl src2"), (89, "ctrl_assign2", "midi ctrl assign2"),
    (90, "pan", "pan"), (91, "osc_phase", "osc phase shift"),
    (92, "unison_phase", "unison phase shift"), (93, "unison_voices", "unison voice num"),
    (94, "polyphony", "(unnamed: polyphony)"), (95, "sub_gain", "osc1 sub gain"),
    (96, "sub_shape", "osc1 sub shape"), (97, "sub_octave", "osc1 sub octave"),
    (98, "delay_tone", "delay tone"),
]
N_PARAMS = len(PARAMS)
KEY = {i: k for i, k, _ in PARAMS}
INDEX = {k: i for i, k, _ in PARAMS}

# Synth1 1.13's initial values (read from a fresh instance's state through DawDreamer).
DEFAULTS = [2, 1, 64, 81, 1, 64, 0, 0, 64, 0, 0, 64, 0, 0, 1, 0, 64, 32, 64, 81, 14, 128, 64,
            0, 1, 64, 64, 107, 64, 107, 64, 1, 0, 11, 64, 8, 40, 20, 0, 0, 12, 2, 1, 64, 0, 0,
            5, 1, 64, 64, 74, 74, 64, 64, 50, 64, 40, 1, 1, 0, 64, 64, 64, 64, 2, 1, 1, 0, 0, 0,
            0, 0, 64, 0, 0, 22, 0, 0, 0, 64, 64, 64, 0, 66, 64, 24, 45057, 44, 45057, 43, 64, 0,
            0, 2, 16, 0, 1, 1, 64]

# Measured meanings of the enums (tools/synth1_ref).
ENUMS = {
    "osc1_shape": {0: "sine", 1: "saw", 2: "pulse", 3: "triangle"},
    "osc2_shape": {1: "saw", 2: "pulse", 3: "triangle", 4: "noise"},
    "filter_type": {0: "LP12", 1: "LP24", 2: "HP12", 3: "BP", 4: "LPDL", 5: "LPDL"},
    "lfo1_type": {0: "saw", 1: "triangle", 2: "square", 3: "sample and hold",
                  4: "smooth random", 5: "sine"},
    "lfo1_dest": {0: "osc2 pitch", 1: "osc2 pitch", 2: "osc1+2 pitch", 3: "filter cutoff",
                  4: "amp", 5: "pulse width", 6: "FM", 7: "pan"},
    "modenv_dest": {0: "osc2 pitch", 1: "FM", 2: "pulse width"},
    "play_mode": {0: "poly", 1: "mono", 2: "legato"},
    "delay_type": {0: "stereo", 1: "cross", 2: "ping-pong"},
    "ch_type": {0: "1 tap", 1: "1 tap", 2: "2 taps", 3: "2 taps, more dry", 4: "4 taps"},
    "fx_type": {0: "analog distortion 1", 1: "analog distortion 2", 2: "digital distortion",
                3: "decimator", 4: "ring modulator", 5: "compressor", 6: "phaser 1",
                7: "phaser 2", 8: "phaser 3", 9: "phaser 4"},
    "sub_shape": {0: "sine", 1: "triangle", 2: "saw", 3: "square"},
    "sub_octave": {0: "same", 1: "-1 octave"},
}
ENUMS["lfo2_type"], ENUMS["lfo2_dest"] = ENUMS["lfo1_type"], ENUMS["lfo1_dest"]
SWITCHES = {"osc2_track", "osc2_sync", "osc2_ring", "modenv_on", "f_vel", "arp_on", "delay_on",
            "chorus_on", "lfo1_on", "lfo2_on", "lfo1_sync", "lfo2_sync", "lfo1_keysync",
            "lfo2_keysync", "unison_on", "porta_auto", "fx_on"}

# osc2 pitch: semitones per stored value (measured; seven values repeat a neighbour).
OSC2_SEMITONES = [
    -60, -60, -59, -58, -57, -56, -55, -54, -53, -52, -51, -50, -49, -48, -47, -46, -45, -44,
    -43, -43, -42, -41, -40, -39, -38, -37, -36, -35, -34, -33, -32, -31, -30, -29, -28, -27,
    -26, -26, -25, -24, -23, -22, -21, -20, -19, -18, -17, -16, -15, -14, -13, -12, -11, -10,
    -9, -9, -8, -7, -6, -5, -4, -3, -2, -1, 0, 1, 2, 3, 4, 5, 6, 7, 8, 8, 9, 10, 11, 12, 13, 14,
    15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 25, 26, 27, 28, 29, 30, 31, 32, 33, 34, 35, 36,
    37, 38, 39, 40, 41, 42, 42, 43, 44, 45, 46, 47, 48, 49, 50, 51, 52, 53, 54, 55, 56, 57, 58,
    59, 60]
# Delay time (stored 0-40) as a share of a whole note at the host tempo; 20 and up stop
# at the buffer (about 2.7 s), as does anything longer.
DELAY_NOTES = {1: "1/64t", 2: "1/32t", 3: "1/32", 4: "1/16t", 5: "1/16", 6: "1/8t", 7: "1/16.",
               8: "1/8", 9: "1/4t", 10: "1/8.", 11: "1/8..", 12: "1/4", 13: "1/2t", 14: "1/4.",
               15: "1/4..", 16: "1/2", 17: "1/2.", 18: "1/2..", 19: "1/1"}


def is_sy1(name):
    return name.lower().endswith(".sy1")


def read(data):
    """Bytes of a .sy1 file -> {name, color, version, values {index: int}, unknown}.

    Raises ValueError when nothing in it looks like a Synth1 patch."""
    text = data.decode("latin-1")
    lines = text.splitlines()
    if not lines:
        raise ValueError("empty file")
    out = {"name": lines[0].strip(), "color": None, "version": None, "values": {},
           "unknown": []}
    for line in lines[1:]:
        s = line.strip()
        if not s:
            continue
        if s.startswith("color="):
            out["color"] = s[6:]
        elif s.startswith("ver="):
            try:
                out["version"] = int(s[4:])
            except ValueError:
                out["unknown"].append(s)
        elif "," in s:
            a, _, b = s.partition(",")
            try:
                i, v = int(a), int(b)
            except ValueError:
                out["unknown"].append(s)
                continue
            if 0 <= i < N_PARAMS:
                out["values"][i] = v
            else:
                out["unknown"].append(s)
        else:
            out["unknown"].append(s)
    if not out["values"]:
        raise ValueError("no parameter lines")
    return out


def full_values(values):
    """All N_PARAMS values, Synth1's defaults where the file has none."""
    return [values.get(i, DEFAULTS[i]) for i in range(N_PARAMS)]


def sound_sha256(values):
    """Same sound, other name or bank: the hash of every value, defaults filled in."""
    return hashlib.sha256(",".join(str(v) for v in full_values(values)).encode()).hexdigest()


def midi_source(code):
    """A MIDI-control source as Synth1 stores it (status byte << 8 | data byte)."""
    if code is None or code <= 0:
        return None
    status, data = (code >> 8) & 0xFF, code & 0xFF
    if status & 0xF0 == 0xB0:
        return f"CC {data}"
    if status & 0xF0 == 0xD0:
        return "channel aftertouch"
    return f"status 0x{status:02X} data {data}"


def named_params(parsed):
    """-> {params: {key: value}, names: {key: meaning}, defaulted: [keys], features: [...]}."""
    vals = full_values(parsed["values"])
    p = {KEY[i]: vals[i] for i in range(N_PARAMS)}
    names = {}
    for k, table in ENUMS.items():
        if p[k] in table:
            names[k] = table[p[k]]
    names["osc2_pitch_semitones"] = OSC2_SEMITONES[min(127, max(0, p["osc2_pitch"]))]
    names["osc2_fine_cents"] = round((p["osc2_fine"] - 64) * 0.969, 1)
    names["osc_tune_cents"] = round((p["osc_tune"] - 64) * 0.969, 1)
    names["delay_note"] = DELAY_NOTES.get(p["delay_time"],
                                          "0.1 ms" if p["delay_time"] == 0 else "buffer limit")
    names["modenv_amount_signed"] = p["modenv_amount"] - 64
    for n in (1, 2):
        names[f"midi_ctrl{n}_source"] = midi_source(p[f"ctrl_src{n}"])

    on = lambda k: bool(p[k])  # noqa: E731
    feats = []
    if on("unison_on"):
        feats.append(f"unison x{p['unison_voices']}")
    if p["osc1_detune"]:
        feats.append("osc1 detune")
    if p["sub_gain"]:
        feats.append("sub oscillator")
    if p["osc1_fm"]:
        feats.append("fm")
    for k, label in (("osc2_sync", "sync"), ("osc2_ring", "ring"), ("arp_on", "arpeggiator"),
                     ("delay_on", "delay"), ("chorus_on", "chorus")):
        if on(k):
            feats.append(label)
    if on("fx_on"):
        feats.append(names.get("fx_type", "effect"))
    if on("modenv_on") and p["modenv_amount"] != 64:
        feats.append("mod envelope -> " + names.get("modenv_dest", "?"))
    for n in (1, 2):
        if on(f"lfo{n}_on") and p[f"lfo{n}_depth"]:
            feats.append(f"lfo{n} -> " + names.get(f"lfo{n}_dest", "?")
                         + (" (tempo sync)" if on(f"lfo{n}_sync") else ""))
    if p["play_mode"]:
        feats.append(names.get("play_mode", "mono"))
    if p["osc2_shape"] == 4 and p["osc_mix"]:
        feats.append("noise")
    defaulted = [KEY[i] for i in range(N_PARAMS) if i not in parsed["values"]]
    return {"params": p, "names": names, "defaulted": defaulted, "features": feats}
