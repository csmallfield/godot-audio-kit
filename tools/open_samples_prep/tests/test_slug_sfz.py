import os
import random
import sys
import unittest

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from osp.sfz import note_number, zones_from_sfz_text  # noqa: E402
from osp.slug import assign_out_paths, base_parts, slugify  # noqa: E402

FIXTURES = os.path.join(os.path.dirname(os.path.abspath(__file__)), "fixtures")


class SlugTests(unittest.TestCase):
    def test_known_values(self):
        cases = {
            "Roland JV-2080": "roland-jv-2080",
            "Adufe Afinação": "adufe-afinacao",
            "PercussionInstruments": "percussion-instruments",
            "Timp&Bells": "timp-and-bells",
            "Wosh_Cliff-1": "wosh-cliff-1",
            "Bambu Trem#50": "bambu-trem-50",
            "Hold.......": "hold",
            "con": "con-x",
        }
        for src, want in cases.items():
            self.assertEqual(slugify(src), want, src)

    def test_stable_and_never_empty(self):
        for text in ["!!!", "日本", "Korg M1", "Glass Bowl - Struck"]:
            a, b = slugify(text), slugify(text)
            self.assertEqual(a, b)
            self.assertTrue(a)
        self.assertEqual(slugify("!!!"), slugify("!!!"))
        self.assertNotEqual(slugify("!!!"), slugify("???"))

    def test_base_parts(self):
        self.assertEqual(
            base_parts("Synthesizers/RolandSynthesizers/Roland JV-2080/Samples/101_Bass.wav", True),
            ["synthesizers", "roland", "roland-jv-2080", "101-bass"])
        self.assertEqual(base_parts("PercussionInstruments/Cuica/Cuica.nki", True),
                         ["percussion-instruments", "cuica"])
        self.assertEqual(base_parts("Keyboards/Electric Pianos/Instruments/Wurli.nki", True),
                         ["keyboards", "electric-pianos", "wurli"])

    def test_collisions_and_nesting_are_order_independent(self):
        items = [
            ("PercussionInstruments/Cuica", False, "wav-folder", "wav"),
            ("PercussionInstruments/Cuica/Cuica.nki", True, "kontakt", "nki"),
            ("Pianos/Archive LoFi Piano/Archive LoFi Piano.nki", True, "kontakt", "nki"),
            ("Pianos/Archive LoFi Piano/Samples", False, "wav-folder", "wav"),
            ("Kits/Kit/Kit.nbkt", True, "unsupported", "nbkt"),
            ("Kits/Kit/Kit.sitala", True, "unsupported", "sitala"),
            ("Synths/A/Wild Drums.wav", True, "wav-file", "wav"),
            ("Synths/A/Wild_Drums.wav", True, "wav-file", "wav"),
        ]
        first = assign_out_paths(items)
        for seed in range(5):
            shuffled = items[:]
            random.Random(seed).shuffle(shuffled)
            self.assertEqual(assign_out_paths(shuffled), first)
        self.assertEqual(first["PercussionInstruments/Cuica/Cuica.nki"], "percussion-instruments/cuica")
        self.assertEqual(first["PercussionInstruments/Cuica"], "percussion-instruments/cuica-wav")
        self.assertEqual(first["Kits/Kit/Kit.sitala"], "kits/kit-sitala")
        self.assertEqual(first["Synths/A/Wild_Drums.wav"], "synths/a/wild-drums-wav")
        # no output folder may sit inside another
        outs = sorted(first.values())
        for a in outs:
            for b in outs:
                self.assertFalse(b.startswith(a + "/"), (a, b))
        self.assertEqual(len(set(outs)), len(outs))


class SfzTests(unittest.TestCase):
    def setUp(self):
        with open(os.path.join(FIXTURES, "sample.sfz"), encoding="utf-8") as f:
            self.parsed, self.zones = zones_from_sfz_text(f.read())

    def test_note_names(self):
        self.assertEqual(note_number("c4"), 60)
        self.assertEqual(note_number("C#4"), 61)
        self.assertEqual(note_number("c-1"), 0)
        self.assertEqual(note_number("69"), 69)

    def test_header_and_count(self):
        self.assertEqual(self.parsed["comments"]["creator"], "Test Maker")
        self.assertEqual(self.parsed["comments"]["category"], "Keys")
        self.assertEqual(len(self.zones), 3)

    def test_first_zone_fields(self):
        z = self.zones[0]
        self.assertEqual(z["sample"], "Test Samples/c4_soft.wav")
        self.assertEqual(z["root_key"], 60)
        self.assertEqual(z["key_range"], [58, 62])
        self.assertEqual(z["velocity_range"], [1, 63])
        self.assertEqual(z["fine_tune_cents"], -12)
        self.assertEqual(z["gain_db"], -3.5)  # inherited from <global>
        self.assertEqual(z["pan"], -20)
        self.assertEqual(z["sample_start"], 10)
        self.assertEqual(z["sample_end"], 44099)
        self.assertEqual(z["loop"], {"looped": True, "mode": "loop_continuous", "start": 20000,
                                     "end": 44000, "crossfade": 0.05})
        self.assertEqual(z["group_label"], "rr1")
        self.assertEqual(z["filter"], {"fil_type": "lpf_2p", "cutoff": 8000, "resonance": 1.5})
        self.assertEqual(z["filter_envelope"], {"fileg_attack": 0.2, "fileg_depth": 1200})
        self.assertEqual(z["amp_envelope"]["ampeg_release"], 0.4)
        self.assertEqual(z["opcodes"]["amp_veltrack"], "50")

    def test_key_shorthand_and_override(self):
        z = self.zones[1]
        self.assertEqual((z["root_key"], z["key_range"]), (60, [60, 60]))
        self.assertEqual(z["velocity_range"], [64, 127])
        self.assertEqual(z["gain_db"], -1)  # region beats global; trailing comment ignored
        self.assertFalse(z["loop"]["looped"])  # global loop_mode=no_loop

    def test_group_change_and_release(self):
        z = self.zones[2]
        self.assertEqual(z["sample"], "Test Samples/c4_soft rr2.wav")  # spaces kept
        self.assertEqual(z["group_label"], "rr2")
        self.assertEqual(z["group_index"], 1)
        self.assertEqual((z["seq_length"], z["seq_position"]), (2, 2))
        self.assertTrue(z["release_trigger"])
        self.assertEqual((z["exclusive_group"], z["off_by"]), (3, 4))
        self.assertEqual(z["transpose_semitones"], -1)
        self.assertEqual(z["filter"], {})  # group settings don't leak into the next group


if __name__ == "__main__":
    unittest.main()
