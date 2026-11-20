"""End-to-end runs on a hand-made mini collection, with a fake ConvertWithMoss."""

import hashlib
import json
import logging
import os
import shutil
import struct
import sys
import tempfile
import unittest
import wave

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.dirname(HERE))

from prep import parse_args  # noqa: E402
from osp.runner import Run  # noqa: E402

FAKE_CWM = os.path.join(HERE, "fake_cwm.py")


def write_wav(path, frames=2205, channels=1, rate=44100, seed=3):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with wave.open(path, "wb") as w:
        w.setnchannels(channels)
        w.setsampwidth(2)
        w.setframerate(rate)
        w.writeframes(b"".join(struct.pack("<h", (i * seed) % 3000) * channels
                               for i in range(frames)))


def write(path, data):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "wb") as f:
        f.write(data if isinstance(data, bytes) else data.encode("utf-8"))


def tree_digest(root):
    h = hashlib.sha256()
    for dirpath, dirnames, files in os.walk(root):
        dirnames.sort()
        for fn in sorted(files):
            p = os.path.join(dirpath, fn)
            h.update(os.path.relpath(p, root).encode())
            with open(p, "rb") as f:
                h.update(f.read())
    return h.hexdigest()


class PipelineTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.mkdtemp(prefix="osp_test_")
        self.src = os.path.join(self.tmp, "Open Samples")
        self.out = os.path.join(self.tmp, "out")
        s = self.src
        write(f"{s}/README.MD", "# Open Samples\n[badge](https://img.shields.io/badge/Patch%20Number-v9.99-x)\n")
        write(f"{s}/docs/LICENSE.md", "TEST SAMPLE LICENSE\n  Version 2, 2030\n\nBe nice.\n")
        write(f"{s}/Keys/Test Keys/Test Keys.nki", b"fake nki v1")
        write(f"{s}/Keys/Test Keys/README.md", "Recorded in a cupboard.\n")
        write(f"{s}/Keys/Locked/Locked.nki", b"ENCRYPTED stuff")
        write_wav(f"{s}/Synthesizers/AcmeSynthesizers/Acme X1/Samples/Pad_C3.wav", channels=2)
        write_wav(f"{s}/Percussion/Shaker/shake_1.wav", seed=5)
        write_wav(f"{s}/Percussion/Shaker/shake_2.wav", seed=7)
        write(f"{s}/Percussion/Kit/kit.phaseplant", b"pp")
        logging.getLogger("osp").handlers.clear()

    def tearDown(self):
        logging.getLogger("osp").handlers.clear()
        shutil.rmtree(self.tmp, ignore_errors=True)

    def run_tool(self, *extra):
        args = parse_args(["--source", self.src, "--out", self.out, "--cwm", FAKE_CWM,
                           "--workers", "2", *extra])
        rc = Run(args).main()
        logging.getLogger("osp").handlers.clear()
        return rc

    def sidecar(self, rel):
        with open(os.path.join(self.out, rel, "instrument.json"), encoding="utf-8") as f:
            return json.load(f)

    def catalog(self):
        with open(os.path.join(self.out, "catalog.json"), encoding="utf-8") as f:
            return json.load(f)

    def test_full_run(self):
        before = tree_digest(self.src)
        self.assertEqual(self.run_tool(), 0)
        self.assertEqual(tree_digest(self.src), before, "source collection must not change")

        cat = self.catalog()
        self.assertEqual(cat["schema"], 1)
        self.assertEqual(cat["counts_by_status"],
                         {"converted": 1, "encrypted": 1, "skipped-wav": 2, "unsupported": 1})
        for name in ("catalog.csv", "failures.txt", "LICENSE-open-samples.md"):
            self.assertTrue(os.path.isfile(os.path.join(self.out, name)), name)
        with open(os.path.join(self.out, "failures.txt"), encoding="utf-8") as f:
            failures = f.read()
        self.assertIn("encrypted\tKeys/Locked/Locked.nki", failures)
        self.assertIn("unsupported\tPercussion/Kit/kit.phaseplant", failures)
        self.assertTrue(os.listdir(os.path.join(self.out, "logs")))

        sc = self.sidecar("keys/test-keys")
        self.assertEqual(sc["schema"], 1)
        self.assertEqual(sc["status"], "converted")
        o = sc["origin"]
        self.assertEqual(o["source_path"], "Keys/Test Keys/Test Keys.nki")
        self.assertEqual(o["source_sha256"], hashlib.sha256(b"fake nki v1").hexdigest())
        self.assertEqual(o["collection"]["version"], "v9.99")
        self.assertEqual(o["license"]["name"], "Test Sample License v2")
        self.assertEqual([n["path"] for n in o["notes"]][0], "Keys/Test Keys/README.md")
        self.assertIn("cupboard", o["notes"][0]["text"])
        i = sc["identity"]
        self.assertEqual((i["family"], i["category"], i["creator"]), ("Keys", "Keys", "Tester"))
        self.assertEqual(i["keywords"], ["warm", "soft"])
        c = sc["content"]
        self.assertEqual(c["zones_summary"]["zone_count"], 3)
        self.assertEqual(c["zones_summary"]["root_notes"], [60])
        self.assertTrue(c["zones_summary"]["looped"])
        self.assertTrue(c["zones_summary"]["round_robin"]["likely"])
        self.assertEqual(c["zones_summary"]["release_trigger_zones"], 1)
        self.assertEqual(c["samples_summary"]["sample_rates"], [44100])
        self.assertEqual(c["samples_summary"]["bit_depths"], [16])
        z0 = c["presets"][0]["zones"][0]
        self.assertEqual(z0["sample"], "Fake Inst Samples/c4_soft.wav")
        self.assertEqual(z0["loop"]["start"], 20000)
        p = sc["processing"]
        self.assertEqual(p["convertwithmoss_version"], "9.9.9")
        self.assertEqual(len(p["commands"]), 3)  # analysis, sfz, decentsampler
        self.assertTrue(any("Kontakt scripts" in x for x in p["lost"]))
        self.assertTrue(any("audible step" in x for x in p["warnings"]))
        for t in ("keys", "kontakt-converted", "looped", "velocity-layered", "round-robin"):
            self.assertIn(t, sc["tags"])
        base = os.path.join(self.out, "keys/test-keys")
        for f in ("Fake Inst.sfz", "Fake Inst.dspreset", "README.txt", "cwm/analysis.txt",
                  "Fake Inst Samples/c4_soft.wav"):
            self.assertTrue(os.path.exists(os.path.join(base, f)), f)
        self.assertFalse(os.path.exists(os.path.join(base, "decentsampler")))  # samples shared

        wf = self.sidecar("synthesizers/acme/acme-x1/pad-c3")
        self.assertEqual(wf["status"], "skipped-wav")
        self.assertEqual((wf["identity"]["manufacturer"], wf["identity"]["model"]), ("Acme", "Acme X1"))
        self.assertEqual(wf["content"]["notes_from_names"], [48])
        self.assertTrue(wf["content"]["samples_summary"]["stereo"])
        folder = self.sidecar("percussion/shaker")
        self.assertEqual(folder["content"]["samples_summary"]["sample_count"], 2)
        self.assertAlmostEqual(folder["content"]["samples_summary"]["total_duration_s"], 0.1)

    def test_skip_if_unchanged_then_redo(self):
        self.run_tool()
        first = self.sidecar("keys/test-keys")["processing"]["date"]
        wav_first = self.sidecar("percussion/shaker")["processing"]["date"]
        os.utime(os.path.join(self.out, "keys/test-keys/instrument.json"), (1, 1))
        self.run_tool()  # nothing changed: nothing redone
        self.assertEqual(os.stat(os.path.join(self.out, "keys/test-keys/instrument.json")).st_mtime, 1)
        # source changes -> redone
        write(f"{self.src}/Keys/Test Keys/Test Keys.nki", b"fake nki v2")
        self.run_tool()
        sc = self.sidecar("keys/test-keys")
        self.assertEqual(sc["origin"]["source_sha256"], hashlib.sha256(b"fake nki v2").hexdigest())
        self.assertNotEqual(os.stat(os.path.join(self.out, "keys/test-keys/instrument.json")).st_mtime, 1)
        # an option change redoes only the entries it affects
        os.utime(os.path.join(self.out, "keys/test-keys/instrument.json"), (1, 1))
        self.run_tool("--copy-wav")
        self.assertEqual(os.stat(os.path.join(self.out, "keys/test-keys/instrument.json")).st_mtime, 1)
        shaker = self.sidecar("percussion/shaker")
        self.assertEqual(shaker["outputs"]["samples_dir"], "samples")
        self.assertTrue(os.path.isfile(os.path.join(self.out, "percussion/shaker/samples/shake_1.wav")))
        self.assertGreaterEqual(shaker["processing"]["date"], wav_first)
        # --force redoes everything
        self.run_tool("--copy-wav", "--force")
        self.assertNotEqual(os.stat(os.path.join(self.out, "keys/test-keys/instrument.json")).st_mtime, 1)
        self.assertTrue(first)

    def test_dry_run_and_only(self):
        self.assertEqual(self.run_tool("--dry-run"), 0)
        self.assertFalse(os.path.exists(self.out))
        self.run_tool("--only", "Percussion")
        cat = self.catalog()
        by_path = {e["source_path"]: e["status"] for e in cat["entries"]}
        self.assertEqual(by_path["Percussion/Shaker"], "skipped-wav")
        self.assertEqual(by_path["Keys/Test Keys/Test Keys.nki"], "pending")
        self.assertFalse(os.path.exists(os.path.join(self.out, "keys")))

    def test_exclude_and_additions(self):
        write(f"{self.src}/.open_samples_additions.json", json.dumps({"additions": [{
            "source": "https://github.com/x/y", "commit": "abc123", "date": "2030-01-01",
            "files": [{"path": "Keys/Test Keys/Test Keys.nki", "sha256": "s"}]}]}))
        self.run_tool("--exclude", "Percussion/Shaker", "--exclude", "keys/locked/*.nki")
        by_path = {e["source_path"]: e["status"] for e in self.catalog()["entries"]}
        self.assertEqual(by_path["Percussion/Shaker"], "excluded")
        self.assertEqual(by_path["Keys/Locked/Locked.nki"], "excluded")
        self.assertFalse(os.path.exists(os.path.join(self.out, "percussion/shaker")))
        added = self.sidecar("keys/test-keys")["origin"]["added_from"]
        self.assertEqual(added["commit"], "abc123")
        self.assertIsNone(self.sidecar("percussion/kit")["origin"]["added_from"])

    def test_out_inside_source_is_refused(self):
        args = parse_args(["--source", self.src, "--out", os.path.join(self.src, "x"),
                           "--cwm", FAKE_CWM])
        with self.assertRaises(SystemExit):
            Run(args).main()


if __name__ == "__main__":
    unittest.main()
