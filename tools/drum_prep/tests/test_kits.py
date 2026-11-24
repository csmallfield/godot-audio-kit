"""Tests for the kit builder: python -m unittest discover -s tools/drum_prep/tests"""

import json
import os
import sys
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, ".."))

import build_kits  # noqa: E402


def entry(path, cat, kind="", frm="both", sure=True, pitch=0.0, decay=0.2, peak=-6.0, layer=None, kindof="oneshot"):
    machine = path.split("/", 1)[0]
    c = {"machine": machine, "path": path, "peak_dbfs": peak, "channels": 1, "seconds": 0.5, "kind": kindof,
         "layer_group": layer[0] if layer else "", "layer_index": layer[1] if layer else ""}
    t = {"name": {"category": cat, "kind": kind}, "final": {"category": cat, "kind": kind, "from": frm, "sure": sure},
         "analysis": {"category": cat, "pitch_hz": pitch}}
    f = {"silent": False, "decay40_s": decay, "f0_late": pitch, "f0_early": pitch}
    return c, t, f


def collection(d, entries):
    cat, tags, feats = [], {}, {}
    for c, t, f in entries:
        cat.append(c)
        tags[c["path"]] = t
        feats[c["path"]] = f
    os.makedirs(os.path.join(d, "analysis"), exist_ok=True)
    for name, data in (("catalog.json", {"entries": cat}), ("tags.json", {"files": tags}),
                       ("analysis/features.json", {"files": feats})):
        with open(os.path.join(d, *name.split("/")), "w", encoding="utf-8") as fh:
            json.dump(data, fh)


class KitTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.d = self.tmp.name

    def kit(self, rel):
        with open(os.path.join(self.d, "kits", *rel.split("/")), encoding="utf-8") as fh:
            return json.load(fh)

    def test_folder_kits_rows_toms_and_chokes(self):
        collection(self.d, [
            entry("Box/Kit A/03 tom.wav", "tom", pitch=200.0), entry("Box/Kit A/01 kick.wav", "kick"),
            entry("Box/Kit A/02 snare.wav", "snare"), entry("Box/Kit A/04 tom.wav", "tom", pitch=90.0),
            entry("Box/Kit A/05 hat.wav", "hat", "closed"), entry("Box/Kit A/06 hat.wav", "hat", decay=0.8),
            entry("Box/Kit A/07 conga.wav", "perc", "conga:high"), entry("Box/Kit A/08 tom.wav", "tom", pitch=140.0),
            entry("Box/FX/zap.wav", "fx"), entry("Box/FX/kick.wav", "kick"), entry("Box/FX/z2.wav", "fx"),
            entry("Box/FX/z3.wav", "fx"), entry("Box/FX/hat.wav", "hat"), entry("Box/FX/sn.wav", "snare"),
        ])
        index = build_kits.build(self.d)
        folders = [k for k in index if k["from"] == "folder"]
        self.assertEqual([k["folder"] for k in folders], ["Kit A"])      # FX is mostly not a kit
        k = self.kit(folders[0]["path"])
        names = [p["name"] for p in k["pieces"]]
        self.assertEqual(names, ["kick", "snare", "closed_hat", "open_hat", "tom_low", "tom_mid", "tom_high", "conga"])
        toms = {p["name"]: p["sound"] for p in k["pieces"] if p["name"].startswith("tom")}
        self.assertEqual(toms, {"tom_low": "Box/Kit A/04 tom.wav", "tom_mid": "Box/Kit A/08 tom.wav",
                                "tom_high": "Box/Kit A/03 tom.wav"})
        self.assertEqual({p["name"] for p in k["pieces"] if p.get("choke") == "hats"}, {"closed_hat", "open_hat"})
        self.assertEqual(k["root"], "../..")
        kick = k["pieces"][0]
        self.assertEqual(kick["gain_db"], -1.0 + (-3.0 + 6.0))          # peak to -3 dBFS, then the row's offset

    def test_assembled_kits_styles_layers_and_fallbacks(self):
        es = [entry("M/Kicks/Rock Kick 1.wav", "kick"), entry("M/Kicks/Pop Kick 1.wav", "kick"),
              entry("M/Kicks/Analog Kick.wav", "kick"),
              entry("M/Snares/Pop Snare 1 [V1].wav", "snare", layer=("Snares/Pop Snare 1", 1), peak=-12.0),
              entry("M/Snares/Pop Snare 1 [V2].wav", "snare", layer=("Snares/Pop Snare 1", 2), peak=-4.0),
              entry("M/Snares/Rock Snare.wav", "snare"), entry("M/Snares/Odd Snare.wav", "snare"),
              entry("M/Hats/Pop Closed HiHat.wav", "hat", "closed"), entry("M/Hats/Rock Closed HiHat.wav", "hat", "closed"),
              entry("M/Hats/Pop Open HiHat.wav", "hat", "open"), entry("M/Hats/Clop.wav", "hat", "closed_to_open"),
              entry("M/Loops/Kick Loop.wav", "kick", kindof="loop")]
        collection(self.d, es)
        index = build_kits.build(self.d)
        assembled = sorted((k for k in index if k["from"] == "assembled"), key=lambda k: k["name"])
        self.assertEqual(len(assembled), 3)
        k1 = self.kit(assembled[0]["path"])
        rows = {p["name"]: p for p in k1["pieces"]}
        # the Pop style fills the most rows, so it leads; the layered snare is one piece
        self.assertEqual(rows["kick"]["sound"], "M/Kicks/Pop Kick 1.wav")
        self.assertEqual([l["sound"] for l in rows["snare"]["layers"]],
                         ["M/Snares/Pop Snare 1 [V1].wav", "M/Snares/Pop Snare 1 [V2].wav"])
        self.assertEqual(rows["snare"]["layers"][1]["up_to"], 1.0)
        self.assertEqual(rows["snare"]["gain_db"], -3.0 + (-3.0 + 4.0))   # the loudest layer sets the level
        self.assertEqual(rows["open_hat"]["sound"], "M/Hats/Pop Open HiHat.wav")
        self.assertEqual(rows["pedal_hat"]["sound"], "M/Hats/Pop Closed HiHat.wav")   # none: a closed hat stands in
        for k in assembled:
            for p in self.kit(k["path"])["pieces"]:
                self.assertNotIn("Loop", p.get("sound", ""))                # loops stay out of kits

    def test_percussion_and_all_sounds_kits(self):
        es = [entry("P/c%d.wav" % i, "perc", kd) for i, kd in enumerate(
            ["conga", "conga", "bongo", "bongo", "shaker", "cowbell", "clave", "agogo", "triangle"])]
        es += [entry("Q/claps %d.wav" % i, "clap") for i in range(3)]
        collection(self.d, es)
        index = {k["machine"]: k for k in build_kits.build(self.d)}
        self.assertEqual(index["P"]["from"], "percussion")
        names = [p["name"] for p in self.kit(index["P"]["path"])["pieces"]]
        self.assertEqual(names[:7], ["agogo", "bongo", "clave", "conga", "cowbell", "shaker", "triangle"])
        self.assertIn("conga_2", names)
        self.assertEqual(index["Q"]["from"], "all")
        self.assertEqual(index["Q"]["pieces"], 3)


if __name__ == "__main__":
    unittest.main()
