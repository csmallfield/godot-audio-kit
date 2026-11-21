"""Synth1 patches (.sy1): reading, defaults, naming, and a catalogue run."""

import json
import logging
import os
import shutil
import sys
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.dirname(HERE))

from osp import synth1  # noqa: E402
from osp.runner import Run  # noqa: E402
from prep import parse_args  # noqa: E402


def sy1(name, values, ver=113, color="default"):
    head = [name] + ([f"color={color}", f"ver={ver}"] if ver else [])
    return ("\r\n".join(head + [f"{i},{v}" for i, v in sorted(values.items())]) + "\r\n").encode()


FULL = dict(enumerate(synth1.DEFAULTS))


class Synth1Tests(unittest.TestCase):
    def test_read_and_name(self):
        vals = dict(FULL)
        vals.update({0: 3, 1: 4, 2: 76, 14: 4, 41: 5, 42: 4, 73: 1, 93: 4, 77: 1, 78: 4,
                     95: 40, 35: 12, 9: -12, 86: 45057})
        p = synth1.read(sy1("Fat Lead", vals))
        self.assertEqual((p["name"], p["version"], p["color"]), ("Fat Lead", 113, "default"))
        n = synth1.named_params(p)
        self.assertEqual(n["defaulted"], [])
        self.assertEqual(n["params"]["key_shift"], -12)
        names = n["names"]
        self.assertEqual((names["osc1_shape"], names["osc2_shape"], names["filter_type"]),
                         ("triangle", "noise", "LPDL"))
        self.assertEqual((names["lfo1_dest"], names["lfo1_type"]), ("pulse width", "smooth random"))
        self.assertEqual((names["osc2_pitch_semitones"], names["delay_note"]), (11, "1/4"))
        self.assertEqual(names["fx_type"], "ring modulator")
        self.assertEqual(names["midi_ctrl1_source"], "CC 1")
        self.assertIn("unison x4", n["features"])
        self.assertIn("sub oscillator", n["features"])
        self.assertIn("ring modulator", n["features"])

    def test_old_version_takes_defaults(self):
        old = {i: v for i, v in FULL.items() if i < 67}
        p = synth1.read(sy1("Old One", old, ver=None))
        self.assertIsNone(p["version"])
        n = synth1.named_params(p)
        self.assertEqual(n["defaulted"][0], "lfo1_sync")
        self.assertEqual(len(n["defaulted"]), synth1.N_PARAMS - 67)
        self.assertEqual(n["params"]["sub_gain"], 0)
        # Same values, filled in or written out: the same sound.
        self.assertEqual(synth1.sound_sha256(p["values"]), synth1.sound_sha256(FULL))

    def test_unknown_lines_and_garbage(self):
        p = synth1.read(b"Odd\nver=112\n0,1\nfoo\n150,3\n")
        self.assertEqual(p["values"], {0: 1})
        self.assertEqual(p["unknown"], ["foo", "150,3"])
        with self.assertRaises(ValueError):
            synth1.read(b"just a name\n")


class Synth1PipelineTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.mkdtemp(prefix="osp_sy1_")
        self.src = os.path.join(self.tmp, "Synth1")
        self.out = os.path.join(self.tmp, "out")
        bank = os.path.join(self.src, "kvr", "Test Bank")
        os.makedirs(bank)
        pad = dict(FULL)
        pad[27] = 120
        files = {"001.sy1": sy1("Warm Pad", pad), "002.SY1": sy1("Deep Bass", FULL),
                 "003.sy1": sy1("Warm Pad copy", pad, color="red"), "004.sy1": b"\n\n"}
        for name, data in files.items():
            with open(os.path.join(bank, name), "wb") as f:
                f.write(data)
        with open(os.path.join(bank, "Bank notes.txt"), "w", encoding="utf-8", newline="\n") as f:
            f.write("Made for testing.\n")
        logging.getLogger("osp").handlers.clear()

    def tearDown(self):
        logging.getLogger("osp").handlers.clear()
        shutil.rmtree(self.tmp, ignore_errors=True)

    def test_catalogue(self):
        args = parse_args(["--source", self.src, "--out", self.out, "--collection-name", "Test"])
        self.assertEqual(Run(args).main(), 0)
        with open(os.path.join(self.out, "catalog.json"), encoding="utf-8") as f:
            cat = json.load(f)
        self.assertEqual(cat["counts_by_status"], {"decoded": 3, "unsupported": 1})
        ids = sorted(e["id"] for e in cat["entries"] if e["status"] == "decoded")
        self.assertEqual(ids, ["kvr/test-bank/001-warm-pad", "kvr/test-bank/002-deep-bass",
                               "kvr/test-bank/003-warm-pad-copy"])
        dup = [(e["id"], e["duplicate_of"]) for e in cat["entries"] if e.get("duplicate_of")]
        self.assertEqual(dup, [("kvr/test-bank/003-warm-pad-copy", "kvr/test-bank/001-warm-pad")])
        with open(os.path.join(self.out, "kvr/test-bank/002-deep-bass/instrument.json"),
                  encoding="utf-8") as f:
            sc = json.load(f)
        self.assertEqual(sc["status"], "decoded")
        self.assertEqual((sc["identity"]["model"], sc["identity"]["instrument"],
                          sc["identity"]["patch"], sc["identity"]["category"]),
                         ("Synth1", "Test Bank", "Deep Bass", "bass"))
        self.assertEqual(sc["origin"]["notes"][0]["text"], "Made for testing.\n")
        s1 = sc["content"]["synth1"]
        self.assertEqual(s1["params"]["osc1_shape"], 2)
        self.assertEqual(s1["names"]["osc1_shape"], "pulse")
        self.assertTrue(s1["file_text"].startswith("Deep Bass"))
        self.assertIn("synth1", sc["tags"])


if __name__ == "__main__":
    unittest.main()
