"""Yamaha DX7 voice banks: read 32-voice bulk SysEx, unpack, and name every parameter.

Format reference: Dexed doc/sysex-format.txt (from the DX7 MIDI data format sheet).
A bank file is F0 43 0n 09 20 00, 32 packed voices of 128 bytes, a checksum and F7
(4104 bytes). Unpacked (VCED) order is 155 bytes: operators 6..1 (21 bytes each), then the
pitch envelope, algorithm, feedback, oscillator sync, LFO, transpose and the 10-char name.
"""

HEADER = bytes([0xF0, 0x43])
BANK_SIZE = 4104
OP_FIELDS = ["eg_rate_1", "eg_rate_2", "eg_rate_3", "eg_rate_4", "eg_level_1", "eg_level_2",
             "eg_level_3", "eg_level_4", "kbd_break_point", "kbd_left_depth", "kbd_right_depth",
             "kbd_left_curve", "kbd_right_curve", "kbd_rate_scaling", "amp_mod_sensitivity",
             "key_velocity_sensitivity", "output_level", "osc_mode", "freq_coarse", "freq_fine",
             "detune"]
CURVES = ["-LIN", "-EXP", "+EXP", "+LIN"]
LFO_WAVES = ["triangle", "saw down", "saw up", "square", "sine", "sample and hold"]
NOTE_NAMES = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]


def is_bank(data):
    return (len(data) >= BANK_SIZE and data[:2] == HEADER and data[3] == 0x09
            and data[4] == 0x20 and data[5] == 0x00)


def checksum_ok(data):
    body = data[6:6 + 4096]
    return ((-sum(body)) & 0x7F) == data[6 + 4096]


def unpack_voice(p):
    """128 packed bytes -> 155 VCED bytes (Dexed's unpack, with its masks)."""
    v = bytearray(155)
    for op in range(6):
        s, d = op * 17, op * 21
        v[d:d + 11] = bytes(b & 0x7F for b in p[s:s + 11])
        v[d + 0:d + 8] = bytes(min(b, 99) for b in v[d:d + 8])
        v[d + 11] = p[s + 11] & 0x03          # left curve
        v[d + 12] = (p[s + 11] >> 2) & 0x03   # right curve
        v[d + 13] = p[s + 12] & 0x07          # rate scaling
        v[d + 20] = (p[s + 12] >> 3) & 0x0F   # detune
        v[d + 14] = p[s + 13] & 0x03          # amp mod sensitivity
        v[d + 15] = (p[s + 13] >> 2) & 0x07   # key velocity sensitivity
        v[d + 16] = p[s + 14] & 0x7F          # output level
        v[d + 17] = p[s + 15] & 0x01          # osc mode
        v[d + 18] = (p[s + 15] >> 1) & 0x1F   # freq coarse
        v[d + 19] = p[s + 16] & 0x7F          # freq fine
    v[126:134] = bytes(min(b & 0x7F, 99) for b in p[102:110])  # pitch EG rates, levels
    v[134] = p[110] & 0x1F                    # algorithm 0..31
    v[135] = p[111] & 0x07                    # feedback
    v[136] = (p[111] >> 3) & 0x01             # osc key sync
    v[137:141] = bytes(b & 0x7F for b in p[112:116])  # lfo speed, delay, pmd, amd
    v[141] = p[116] & 0x01                    # lfo key sync
    v[142] = (p[116] >> 1) & 0x07             # lfo wave
    v[143] = (p[116] >> 4) & 0x07             # lfo pitch mod sensitivity
    v[144] = p[117] & 0x7F                    # transpose (24 = C3, no shift)
    v[145:155] = bytes(b & 0x7F for b in p[118:128])
    return bytes(v)


def voice_name(vced):
    return "".join(chr(b) if 32 <= b < 127 else " " for b in vced[145:155]).rstrip()


def read_bank(data):
    """-> list of 32 dicts {index, name, packed, vced}. Raises ValueError if not a DX7 bank."""
    if not is_bank(data):
        raise ValueError("not a DX7 32-voice bulk dump")
    voices = []
    for i in range(32):
        packed = data[6 + i * 128:6 + (i + 1) * 128]
        vced = unpack_voice(packed)
        voices.append({"index": i + 1, "name": voice_name(vced), "packed": packed, "vced": vced})
    return voices


def _note(n):
    return f"{NOTE_NAMES[n % 12]}{n // 12 - 2}"  # DX7 break point 0 = A-1 ... shown as MIDI name


def named_params(vced):
    """VCED bytes -> readable dict. Operators listed 1..6 (the file stores 6..1)."""
    ops = []
    for op in range(6):
        d = (5 - op) * 21
        raw = {k: vced[d + i] for i, k in enumerate(OP_FIELDS)}
        mode = "fixed" if raw["osc_mode"] else "ratio"
        coarse, fine = raw["freq_coarse"], raw["freq_fine"]
        if mode == "ratio":
            freq = {"ratio": round((coarse if coarse else 0.5) * (1 + fine / 100), 4)}
        else:
            freq = {"fixed_hz": round(10 ** (coarse % 4) * 10 ** (fine / 100), 3)}
        raw.update({
            "operator": op + 1,
            "osc_mode_name": mode,
            **freq,
            "detune_cents_steps": raw["detune"] - 7,
            "kbd_left_curve_name": CURVES[raw["kbd_left_curve"]],
            "kbd_right_curve_name": CURVES[raw["kbd_right_curve"]],
            "kbd_break_point_midi": raw["kbd_break_point"] + 21,
        })
        ops.append(raw)
    return {
        "name": voice_name(vced),
        "algorithm": vced[134] + 1,
        "feedback": vced[135],
        "osc_key_sync": vced[136],
        "pitch_eg": {"rates": list(vced[126:130]), "levels": list(vced[130:134])},
        "lfo": {"speed": vced[137], "delay": vced[138], "pitch_mod_depth": vced[139],
                "amp_mod_depth": vced[140], "key_sync": vced[141], "wave": vced[142],
                "wave_name": LFO_WAVES[vced[142]] if vced[142] < 6 else None,
                "pitch_mod_sensitivity": vced[143]},
        "transpose": vced[144],
        "transpose_semitones": vced[144] - 24,
        "operators": ops,
    }


# Carriers per algorithm (1-based operator numbers), from the DX7 algorithm chart.
CARRIERS = {
    1: [1, 3], 2: [1, 3], 3: [1, 4], 4: [1, 4], 5: [1, 3, 5], 6: [1, 3, 5], 7: [1, 3], 8: [1, 3],
    9: [1, 3], 10: [1, 4], 11: [1, 4], 12: [1, 3], 13: [1, 3], 14: [1, 3], 15: [1, 3], 16: [1],
    17: [1], 18: [1], 19: [1, 4, 5], 20: [1, 2, 4], 21: [1, 2, 4, 5], 22: [1, 3, 4, 5],
    23: [1, 2, 4, 5], 24: [1, 2, 3, 4, 5], 25: [1, 2, 3, 4, 5], 26: [1, 2, 4], 27: [1, 2, 4],
    28: [1, 3, 6], 29: [1, 2, 3, 5], 30: [1, 2, 3, 6], 31: [1, 2, 3, 4, 5], 32: [1, 2, 3, 4, 5, 6],
}
