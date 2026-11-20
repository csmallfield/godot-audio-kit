"""DX7 banks: unpacking, discovery, and the render pipeline (with a fake renderer)."""

import json
import logging
import os
import shutil
import sys
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.dirname(HERE))

from osp import dx7  # noqa: E402
from osp.runner import Run  # noqa: E402
from prep import parse_args  # noqa: E402


def packed_voice(name, algorithm, coarse_op1=1, transpose=24):
    p = bytearray(128)
    for op in range(6):  # stored OP6..OP1
        s = op * 17
        p[s:s + 8] = bytes([99, 50, 40, 60, 99, 80, 70, 0])
        p[s + 11] = 0b1110         # left curve 2, right curve 3
        p[s + 12] = (9 << 3) | 5   # detune 9, rate scaling 5
        p[s + 13] = (6 << 2) | 1   # velocity sens 6, AMS 1
        p[s + 14] = 90 - op
        coarse = coarse_op1 if op == 5 else 2
        p[s + 15] = (coarse << 1) | (1 if op == 0 else 0)  # OP6 fixed frequency
        p[s + 16] = 50
    p[102:110] = bytes([99, 99, 99, 99, 50, 50, 50, 50])
    p[110] = algorithm - 1
    p[111] = (1 << 3) | 7          # osc sync, feedback 7
    p[112:116] = bytes([35, 0, 5, 0])
    p[116] = (3 << 4) | (4 << 1) | 1   # pms 3, wave sine, lfo sync
    p[117] = transpose
    p[118:128] = name.ljust(10).encode("ascii")
    return bytes(p)


def bank(voices):
    body = b"".join(voices)
    return bytes([0xF0, 0x43, 0x00, 0x09, 0x20, 0x00]) + body + bytes([(-sum(body)) & 0x7F, 0xF7])


class UnpackTests(unittest.TestCase):
    def test_unpack_fields(self):
        data = bank([packed_voice(f"VOICE {i:02d}", 1 + i % 32) for i in range(32)])
        self.assertTrue(dx7.is_bank(data))
        self.assertTrue(dx7.checksum_ok(data))
        voices = dx7.read_bank(data)
        self.assertEqual(len(voices), 32)
        v = voices[4]
        self.assertEqual(v["name"], "VOICE 04")
        self.assertEqual(len(v["vced"]), 155)
        p = dx7.named_params(v["vced"])
        self.assertEqual(p["algorithm"], 5)
        self.assertEqual((p["feedback"], p["osc_key_sync"]), (7, 1))
        self.assertEqual(p["lfo"]["wave_name"], "sine")
        self.assertEqual(p["lfo"]["pitch_mod_sensitivity"], 3)
        op1, op6 = p["operators"][0], p["operators"][5]
        self.assertEqual(op1["output_level"], 85)      # stored last
        self.assertEqual(op6["output_level"], 90)
        self.assertEqual(op1["ratio"], 1.5)            # coarse 1, fine 50
        self.assertEqual(op6["osc_mode_name"], "fixed")
        self.assertEqual((op1["kbd_left_curve_name"], op1["kbd_right_curve_name"]), ("+EXP", "+LIN"))
        self.assertEqual((op1["detune"], op1["kbd_rate_scaling"]), (9, 5))
        self.assertEqual((op1["key_velocity_sensitivity"], op1["amp_mod_sensitivity"]), (6, 1))
        self.assertEqual(p["transpose_semitones"], 0)

    def test_not_a_bank(self):
        self.assertFalse(dx7.is_bank(b"\xf0\x43\x00\x00\x01\x1b" + bytes(200)))


class Dx7PipelineTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.mkdtemp(prefix="osp_dx7_")
        self.src = os.path.join(self.tmp, "Archive")
        self.out = os.path.join(self.tmp, "out")
        os.makedirs(os.path.join(self.src, "Yamaha DX7", "Factory"))
        voices = [packed_voice("BRASS   1", 22), packed_voice("E.PIANO 1", 5)] + [
            packed_voice(f"PAD {i}", 2, coarse_op1=i + 2) for i in range(30)]
        voices[31] = voices[0][:118] + b"BRASS COPY"  # same sound, other name
        with open(os.path.join(self.src, "Yamaha DX7", "Factory", "ROM 1A.syx"), "wb") as f:
            f.write(bank(voices))
        logging.getLogger("osp").handlers.clear()

    def tearDown(self):
        shutil.rmtree(self.tmp, ignore_errors=True)

    def run_tool(self, *extra):
        args = parse_args(["--source", self.src, "--out", self.out, "--collection-name", "Test",
                           "--dx7render", os.path.join(HERE, "fake_dx7render.py"),
                           "--dx7-notes", "48,60,72", "--dx7-hold", "0.1", "--dx7-release",
                           "0.1", "--dx7-gap", "0.05", *extra])
        return Run(args).main()

    def test_render_and_sidecar(self):
        self.assertEqual(self.run_tool(), 0)
        with open(os.path.join(self.out, "catalog.json"), encoding="utf-8") as f:
            cat = json.load(f)
        self.assertEqual(cat["counts_by_status"], {"rendered": 32})
        ids = [e["id"] for e in cat["entries"]]
        self.assertIn("yamaha-dx7/factory/rom-1a/02-e-piano-1", ids)
        dup = [e for e in cat["entries"] if e.get("duplicate_of")]
        self.assertEqual([(e["id"], e["duplicate_of"]) for e in dup],
                         [("yamaha-dx7/factory/rom-1a/32-brass-copy",
                           "yamaha-dx7/factory/rom-1a/01-brass-1")])
        base = os.path.join(self.out, "yamaha-dx7/factory/rom-1a/02-e-piano-1")
        with open(os.path.join(base, "instrument.json"), encoding="utf-8") as f:
            sc = json.load(f)
        self.assertEqual(sc["identity"]["patch"], "E.PIANO 1")
        self.assertEqual(sc["identity"]["category"], "keys")
        r = sc["content"]["render"]
        self.assertEqual((r["first_note"], r["step"]), (48, 12))
        self.assertEqual(r["note_onsets_s"], [0.0, 0.25, 0.5])
        self.assertEqual(sc["content"]["dx7"]["params"]["algorithm"], 5)
        self.assertIn("algorithm-5", sc["tags"])
        with open(os.path.join(base, "voice.syx"), "rb") as f:
            syx = f.read()
        self.assertEqual((len(syx), syx[:6]), (163, bytes([0xF0, 0x43, 0, 0, 1, 0x1B])))
        self.assertTrue(os.path.isfile(os.path.join(base, "render_v100.wav")))
        # unchanged -> skipped; new render settings -> redone
        os.utime(os.path.join(base, "instrument.json"), (1, 1))
        self.run_tool()
        self.assertEqual(os.stat(os.path.join(base, "instrument.json")).st_mtime, 1)
        self.run_tool("--dx7-velocities", "100,40")
        self.assertTrue(os.path.isfile(os.path.join(base, "render_v040.wav")))


if __name__ == "__main__":
    unittest.main()
