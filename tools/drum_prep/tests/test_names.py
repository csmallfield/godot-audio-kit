"""Tests for the name tagger: python -m unittest discover -s tools/drum_prep/tests"""

import json
import os
import sys
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, ".."))

from dp import names  # noqa: E402
import tag_names  # noqa: E402

MAPS = names.load_name_maps(os.path.join(HERE, "..", "name_maps"))


def cat(path, machine=None):
    r = names.classify(path, MAPS.get(machine))
    return r["category"], r["kind"], r["by"]


class NameTests(unittest.TestCase):
    def test_plain_words_and_abbreviations(self):
        self.assertEqual(cat("Kick 1.wav")[:2], ("kick", ""))
        self.assertEqual(cat("BassDrum_3.wav")[:2], ("kick", ""))
        self.assertEqual(cat("SD 004.wav")[:2], ("snare", ""))
        self.assertEqual(cat("HH Open 2.wav")[:2], ("hat", "open"))
        self.assertEqual(cat("Hat08_C.wav")[:2], ("hat", "closed"))
        self.assertEqual(cat("Tom05-HiThrash.wav")[:2], ("tom", "high"))
        self.assertEqual(cat("Ride Bell.wav")[:2], ("cymbal", "ride_bell"))
        self.assertEqual(cat("Conga Hi Open.wav")[:2], ("perc", "conga:high"))
        self.assertEqual(cat("Rimshot.wav")[:2], ("rim", "rimshot"))
        self.assertEqual(cat("Hand Clap.wav")[:2], ("clap", ""))
        self.assertEqual(cat("Fx 12 Laser.wav")[0], "fx")
        # model names aren't drums; drum words beat fx/perc words; loops stay loops
        self.assertEqual(cat("01-Kicks/CR-78 Kick 2.wav")[0], "kick")
        self.assertEqual(cat("CR8000 Clap.wav")[0], "clap")
        self.assertEqual(cat("Zap kick.wav")[0], "kick")
        self.assertEqual(cat("Tam Kick.wav")[0], "kick")
        self.assertEqual(cat("Groove Loop Kick.wav")[0], "loop")
        # a folder's two-letter words count only alone
        self.assertEqual(cat("U110_RockDrums(Card_SN_U110_10)/RockDrums_B0.wav")[0], "")
        self.assertEqual(cat("BD/x 1.wav")[0], "kick")

    def test_folders_and_run_together_names(self):
        self.assertEqual(cat("Snares/Classic 05.wav"), ("snare", "", "folder"))
        self.assertEqual(cat("Ambcrsh1.wav")[:2], ("cymbal", "crash"))
        self.assertEqual(cat("20rdbel1.wav")[:2], ("cymbal", "ride_bell"))
        self.assertEqual(cat("Atttomh.wav")[:2], ("tom", "high"))
        self.assertEqual(cat("Ophat.wav")[:2], ("hat", "open"))
        self.assertEqual(cat("Nothing here 3.wav"), ("", "", ""))

    def test_letter_codes(self):
        self.assertEqual(cat("78_K.wav")[0], "kick")
        self.assertEqual(cat("Amb S.wav")[0], "snare")
        self.assertEqual(cat("Clsd_H5.wav")[:2], ("hat", "closed"))
        self.assertEqual(cat("Brrd_C1.wav")[0], "")        # no C code: 'Drums_C1' is a note
        self.assertEqual(cat("Drums_C1.wav")[0], "")
        # never a bare slot number, never a note name
        self.assertEqual(cat("INTERNAL/T03.wav")[0], "")
        self.assertEqual(cat("RockDrums_C2.wav")[0], "")
        # a folder that says otherwise beats a one-letter code
        self.assertEqual(cat("04 s - Electric Snare/24 Brsh H.wav")[0], "snare")

    def test_yamaha_voices_are_not_vocals(self):
        self.assertEqual(cat("13 m - misc voices/13 SBrass 4.wav")[0], "")

    def test_tr909_readme_scheme(self):
        self.assertEqual(cat("Set1/BT3A0D7.wav", "Roland TR-909"), ("kick", "", "map"))
        r = names.classify("Set1/ST3T0S3.wav", MAPS["Roland TR-909"])
        self.assertEqual((r["category"], r["settings"]), ("snare", {"tune": 3, "tone": 0, "snappy": 3}))
        self.assertEqual(cat("Set1/LTAD7.wav", "Roland TR-909")[:2], ("tom", "low"))
        self.assertEqual(cat("Set1/HHODA.wav", "Roland TR-909")[:2], ("hat", "open"))
        self.assertEqual(cat("Set1/BT0A0A7.wav", "Roland TR-909")[0], "kick")   # the readme's odd one

    def test_gm_keys(self):
        # Korg: C2 = 36 (kick), F#2 = 42 (closed hat); Yamaha: C1 = 36.
        self.assertEqual(cat("Standard Kit/20070829180206_c27f0000.wav", "Korg Triton")[:2], ("kick", ""))
        self.assertEqual(cat("hip hop kit/20080613015910_f#27f0000.wav", "Korg Triton")[:2], ("hat", "closed"))
        self.assertEqual(cat("Analog Kit 1/20070830194201_c17f0000.wav", "Yamaha RS-7000")[:2], ("kick", ""))
        r = names.classify("hip hop kit/20080613015508_a07f0000.wav", MAPS["Korg Triton"])
        self.assertEqual((r["category"], r["key"]), ("", 21))
        self.assertEqual(cat("BD kit/20080613011919_g27f0000.wav", "Korg Triton")[0], "kick")

    def test_mv8800_codes(self):
        self.assertEqual(cat("DRM_DIRTY 9/V9Hcl1.wav", "Roland MV8800")[:2], ("hat", "closed"))
        self.assertEqual(cat("DRM_MV-8008/808TL2 1.wav", "Roland MV8800")[:2], ("tom", "low"))
        self.assertEqual(cat("DRM_MV-8008/808Clp1    1.wav", "Roland MV8800")[0], "clap")
        self.assertEqual(cat("DRM_MV-8008/808CH12    1.wav", "Roland MV8800")[0], "hat")
        self.assertEqual(cat("DRM_X/Thump 1.wav", "Roland MV8800")[0], "")
        self.assertEqual(cat("Additional Kits/Kit HipHop2/HH2-01.wav", "Roland MC-505"), ("", "", "map"))

    def test_confidence_and_runner(self):
        self.assertEqual(names.classify("Kick 1.wav")["confidence"], "high")
        self.assertEqual(names.classify("Snares/Classic.wav")["confidence"], "medium")
        with tempfile.TemporaryDirectory() as d:
            cat_json = {"entries": [{"machine": "M", "path": "M/Kick 1.wav"}, {"machine": "M", "path": "M/x.wav"}]}
            with open(os.path.join(d, "catalog.json"), "w", encoding="utf-8") as fh:
                json.dump(cat_json, fh)
            with open(os.path.join(d, "tags.json"), "w", encoding="utf-8") as fh:
                json.dump({"files": {"M/x.wav": {"analysis": {"category": "snare"}}}}, fh)
            t = tag_names.tag_collection(d)
            self.assertEqual(t["files"]["M/Kick 1.wav"]["name"]["category"], "kick")
            self.assertEqual(t["files"]["M/x.wav"]["analysis"], {"category": "snare"})   # kept


if __name__ == "__main__":
    unittest.main()
