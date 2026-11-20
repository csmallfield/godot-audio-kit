"""Korg M3R dumps and Casio CZ tones: unpacking and parameter naming."""

import os
import sys
import unittest

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from osp import korg  # noqa: E402


def pack7(data):
    out = bytearray()
    for i in range(0, len(data), 7):
        chunk = data[i:i + 7]
        hi = 0
        for j, b in enumerate(chunk):
            hi |= ((b >> 7) & 1) << j
        out.append(hi)
        out += bytes(b & 0x7F for b in chunk)
    return bytes(out)


def program(name, multisound, cutoff):
    p = bytearray(75)
    p[:10] = name.ljust(10).encode()
    p[10], p[11], p[12], p[13] = 0, 1, multisound, 0xFF   # multisound, mono, 16'
    p[15] = (1 << 7) | (1 << 5) | 3                      # key sync, enabled, rectangle
    p[16], p[17], p[18] = 40, 10, 20
    p[23] = 0xF4                                          # aftertouch pitch -12
    p[34] = 0x9D                                          # pitch EG start -99
    p[42], p[44] = cutoff, 0x9D
    p[63:70] = bytes([0, 99, 30, 80, 50, 70, 20])
    p[72] = 0b00010001                                    # attack time KT on, negative
    return bytes(p)


class M3rTests(unittest.TestCase):
    def test_program_dump_roundtrip(self):
        progs = b"".join(program(f"PROG {i:02d}", i % 90, i) for i in range(100))
        msg = bytes([0xF0, 0x42, 0x30, 0x24, 0x4C, 0x00]) + pack7(progs) + b"\xF7"
        self.assertTrue(korg.is_m3r(msg))
        p, c = korg.read_m3r(msg)
        self.assertEqual((len(p), len(c)), (100, 0))
        self.assertEqual((p[78]["number"], p[78]["name"]), ("P78", "PROG 78"))
        q = korg.program_params(p[78]["packed"])
        self.assertEqual(q["oscillator"]["multisound_name"], "Saw Wave")
        self.assertEqual((q["oscillator"]["assign"], q["oscillator"]["octave_feet"]), ("mono", 16))
        self.assertEqual(q["pitch_mg"], {"wave": "rectangle", "enabled": True, "key_sync": True,
                                         "frequency": 40, "delay": 10, "intensity": 20})
        self.assertEqual((q["aftertouch"]["pitch"], q["pitch_eg"]["start_level"]), (-12, -99))
        self.assertEqual((q["vdf"]["cutoff"], q["vdf"]["cutoff_kbd_track"]), (78, -99))
        self.assertEqual(q["vda_eg"]["sustain_level"], 70)
        self.assertEqual(q["vda_eg"]["time_kbd_track_switches"]["attack"],
                         {"on": True, "negative": True})

    def test_combination(self):
        combi = bytearray(126)
        combi[:10] = b"LAYER TEST"
        combi[10] = 1                       # layer
        for t in range(8):
            b = 36 + t * 11
            combi[b] = t
            combi[b + 5], combi[b + 6] = 0x7F, 0x00
            combi[b + 10] = 0x10 if t > 1 else 0x00   # only timbres 1 and 2 on
        msg = bytes([0xF0, 0x42, 0x30, 0x24, 0x4D, 0x00]) + pack7(bytes(combi) * 100) + b"\xF7"
        _, c = korg.read_m3r(msg)
        q = korg.combi_params(c[0]["packed"])
        self.assertEqual(q["type"], "layer")
        self.assertEqual([t["program"] for t in q["timbres"] if t["on"]], ["I00", "I01"])
        self.assertEqual(q["timbres"][0]["key_window"], [0, 127])


class CzTests(unittest.TestCase):
    def test_tone_nibbles(self):
        tone = bytes(range(128))
        body = b"".join(bytes([b & 0x0F, b >> 4]) for b in tone)
        msg = bytes([0xF0, 0x44, 0x00, 0x00, 0x70, 0x20, 0x60]) + body + b"\xF7"
        self.assertTrue(korg.is_cz_tone(msg))
        self.assertEqual(korg.cz_tone_bytes(msg), tone)


if __name__ == "__main__":
    unittest.main()
