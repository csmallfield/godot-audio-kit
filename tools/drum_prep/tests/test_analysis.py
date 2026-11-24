"""Tests for the drum measurements and classifier pieces: python -m unittest discover -s tools/drum_prep/tests"""

import math
import os
import random
import sys
import tempfile
import unittest

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, ".."))

from dp import audio, features, models  # noqa: E402
import classify_drums  # noqa: E402

SR = 44100


def write(path, x, rate=SR, stereo=None):
    a = np.clip(np.round(np.asarray(x) * 32767), -32768, 32767).astype("<i2")
    ch = 1
    if stereo is not None:
        b = np.clip(np.round(np.asarray(stereo) * 32767), -32768, 32767).astype("<i2")
        a = np.stack([a, b], axis=1).ravel()
        ch = 2
    with open(path, "wb") as fh:
        fh.write(audio.write_wav(audio.Sound(rate, ch, 16, a.tobytes())))


def kick(seconds=0.5):
    t = np.arange(int(seconds * SR)) / SR
    f = 50.0 + 100.0 * np.exp(-t / 0.03)               # 150 Hz falling to 50 Hz
    phase = 2 * np.pi * np.cumsum(f) / SR
    return 0.9 * np.sin(phase) * np.exp(-t / 0.12)


def hat(seconds=0.12):
    rng = np.random.default_rng(1)
    n = int(seconds * SR)
    x = np.diff(rng.normal(0, 1, n + 1))               # differenced noise: mostly high frequencies
    x = np.diff(np.concatenate([[0.0], x]))
    return 0.3 * x / np.max(np.abs(x)) * np.exp(-np.arange(n) / SR / 0.02)


class FeatureTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)

    def measure(self, x, **kw):
        p = os.path.join(self.tmp.name, "s.wav")
        write(p, x, **kw)
        return features.measure(p)

    def test_kick(self):
        m = self.measure(kick())
        self.assertFalse(m["silent"])
        self.assertLess(m["attack_s"], 0.01)
        self.assertLess(m["hit_centroid"], 400)
        self.assertGreater(m["hit_b1"] + m["hit_b0"], 0.5)      # most energy under 200 Hz
        self.assertTrue(40 < m["f0_late"] < 65, m["f0_late"])
        self.assertGreater(m["pitch_drop"], 3)
        self.assertEqual(m["onsets"], 0)
        self.assertEqual(len(m["sp0"]), 16)
        self.assertEqual(max(m["sp1"]), 0.0)

    def test_hat_and_stereo(self):
        x = hat()
        m = self.measure(x, stereo=-0.5 * x)
        self.assertGreater(m["hit_centroid"], 5000)
        self.assertLess(m["decay40_s"], 0.2)
        self.assertGreater(m["width"], 0.85)                  # right inverted at half level: mostly side
        self.assertEqual(m["channels"], 2)

    def test_silence_and_several_hits(self):
        self.assertTrue(self.measure(np.zeros(4410))["silent"])
        k = kick(0.25)
        pattern = np.concatenate([k, k, k])
        self.assertGreaterEqual(self.measure(pattern)["onsets"], 2)

    def test_low_rate_and_24_bit(self):
        p = os.path.join(self.tmp.name, "lo.wav")
        x = kick()
        v = np.round(x * 8388607).astype(np.int64)
        b = bytearray()
        for s in v:
            b += int(s & 0xFFFFFF).to_bytes(3, "little")
        with open(p, "wb") as fh:
            fh.write(audio.write_wav(audio.Sound(22050, 1, 24, bytes(b))))
        m = features.measure(p)
        self.assertEqual(m["rate"], 22050)
        self.assertLessEqual(m["bandwidth_hz"], 11025)


class ClassifierPieceTests(unittest.TestCase):
    def test_vector_and_descriptors(self):
        with tempfile.TemporaryDirectory() as d:
            p = os.path.join(d, "k.wav")
            write(p, kick())
            m = features.measure(p)
        v = classify_drums.vector(m)
        self.assertEqual(len(v), len(classify_drums.vector(m)))
        self.assertTrue(all(math.isfinite(x) for x in v))
        self.assertIsNone(classify_drums.vector({"silent": True}))
        words = classify_drums.descriptors(m, "kick", {"*": (500.0, 3000.0)})
        self.assertIn("falling pitch", words)
        self.assertIn("medium", words)
        self.assertEqual(classify_drums.note_name(440.0), "A4")
        self.assertEqual(classify_drums.note_name(55.0), "A1")

    def test_models_learn_a_separable_problem(self):
        rng = np.random.default_rng(0)
        X = np.concatenate([rng.normal(-2, 1, (200, 4)), rng.normal(2, 1, (200, 4))])
        y = np.array([0] * 200 + [1] * 200)
        w = np.ones(400)
        for make in (models.LogReg, models.MLP, models.KNN):
            P = make(2).fit(X, y, w).proba(X)
            self.assertGreater((P.argmax(1) == y).mean(), 0.95, make.__name__)
        thr = models.thresholds(P, y, ["a", "b"])
        self.assertLessEqual(thr["a"], 1.0)
        self.assertEqual(models.rescale(thr["a"], thr["a"]), 0.8)
        self.assertLess(models.rescale(0.1, 0.9), 0.8)


if __name__ == "__main__":
    unittest.main()
