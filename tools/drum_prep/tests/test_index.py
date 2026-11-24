"""Tests for the browser index: python -m unittest discover -s tools/drum_prep/tests"""

import json
import os
import sys
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, ".."))

import index_drums  # noqa: E402


class IndexTests(unittest.TestCase):
    def test_index(self):
        with tempfile.TemporaryDirectory() as root:
            col = os.path.join(root, "col")
            os.makedirs(os.path.join(col, "kits"))
            cat = {"entries": [{"machine": "M", "path": "M/Kits/K1/Kick.wav", "seconds": 0.3, "channels": 2, "rate": 44100,
                                "kind": "oneshot", "layer_group": "Kits/K1/Kick", "layer_index": 2},
                               {"machine": "M", "path": "M/Groove.wav", "seconds": 4.0, "channels": 1, "rate": 22050,
                                "kind": "loop"}]}
            tags = {"files": {"M/Kits/K1/Kick.wav": {"final": {"category": "kick", "kind": "", "from": "both", "sure": True},
                                                      "analysis": {"describe": ["short"], "note": "A1"}}}}
            kits = {"kits": [{"path": "M/K1.json", "name": "K1", "machine": "M", "from": "folder", "folder": "Kits/K1",
                              "pieces": 5, "sure_share": 0.8, "layered": 1}]}
            for name, d in (("catalog.json", cat), ("tags.json", tags), ("kits/index.json", kits)):
                with open(os.path.join(col, *name.split("/")), "w", encoding="utf-8") as fh:
                    json.dump(d, fh)
            os.makedirs(os.path.join(root, "not a collection"))
            d = index_drums.build(root)
            self.assertEqual([c["name"] for c in d["collections"]], ["col"])
            kick, groove = d["sounds"]
            self.assertEqual((kick["id"], kick["name"], kick["folder"], kick["category"], kick["sure"], kick["note"]),
                             ("col/M/Kits/K1/Kick.wav", "Kick", "Kits/K1", "kick", True, "A1"))
            self.assertEqual(kick["layer"], "Kick [V2]")
            self.assertEqual((groove["category"], groove["tags"], groove["sure"]), ("", ["loop"], False))
            self.assertEqual(d["kits"][0]["path"], "col/kits/M/K1.json")
            self.assertTrue(os.path.exists(os.path.join(root, "gak_drums.json")))


if __name__ == "__main__":
    unittest.main()
