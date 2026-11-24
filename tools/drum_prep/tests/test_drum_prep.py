"""Tests for drum_prep: python -m unittest discover -s tools/drum_prep/tests"""

import array
import io
import json
import math
import os
import struct
import sys
import tempfile
import unittest
import zipfile

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))

from dp import audio  # noqa: E402
from dp import machine as dm  # noqa: E402
import prep_drums  # noqa: E402


def tone(n, hz, rate=44100, amp=0.5, phase=0.0):
    return [amp * math.sin(2 * math.pi * hz * i / rate + phase) for i in range(n)]


def pcm16(*chans):
    """Interleaved little-endian 16-bit PCM of float channels."""
    a = array.array("h")
    for frame in zip(*chans):
        for v in frame:
            a.append(max(-32768, min(32767, int(round(v * 32767)))))
    return a.tobytes()


def wav(chans, rate=44100, bits=16, root=None):
    s = audio.Sound(rate, len(chans), bits, pcm16(*chans) if bits == 16 else b"")
    if root is not None:
        s.root_note = root
    return audio.write_wav(s)


def ext80(rate):
    e = int(math.floor(math.log2(rate)))
    return struct.pack(">HII", 16383 + e, int(rate * 2 ** (31 - e)) & 0xFFFFFFFF, 0)


def aiff(data_be, ch, bits, rate, frames, comp=None):
    comm = struct.pack(">HIH", ch, frames, bits) + ext80(rate)
    if comp:
        comm += comp + b"\x00\x00"
    def chunk(cid, body):
        return cid + struct.pack(">I", len(body)) + body + (b"\0" if len(body) & 1 else b"")
    body = (b"AIFC" if comp else b"AIFF") + chunk(b"COMM", comm) + chunk(b"SSND", b"\0" * 8 + data_be)
    return b"FORM" + struct.pack(">I", len(body)) + body


def make_zip(files):
    buf = io.BytesIO()
    with zipfile.ZipFile(buf, "w") as z:
        for name, data in files.items():
            z.writestr(name, data)
    return buf.getvalue()


class AudioTests(unittest.TestCase):
    def test_wav_round_trip_keeps_bytes_and_smpl(self):
        l, r = tone(500, 220), tone(500, 330)
        s = audio.read(wav([l, r], 32000, root=62))
        self.assertEqual((s.rate, s.channels, s.bits, s.frames, s.root_note), (32000, 2, 16, 500, 62))
        again = audio.read(audio.write_wav(s))
        self.assertEqual(again.data, s.data)
        self.assertEqual(again.root_note, 62)

    def test_aiff_converts_to_identical_pcm(self):
        l = tone(300, 440)
        le = pcm16(l)
        be = bytearray(len(le))
        be[0::2], be[1::2] = le[1::2], le[0::2]
        s = audio.read(aiff(bytes(be), 1, 16, 39579, 300))
        self.assertEqual((s.rate, s.channels, s.bits), (39579, 1, 16))
        self.assertEqual(s.data, le)
        self.assertEqual(audio.read(aiff(le, 1, 16, 39579, 300, b"sowt")).data, le)
        # 24-bit big-endian and signed 8-bit
        v24 = [0, 0x123456, -0x123456 & 0xFFFFFF]
        be24 = b"".join(x.to_bytes(3, "big") for x in v24)
        self.assertEqual(audio.read(aiff(be24, 1, 24, 44100, 3)).data, b"".join(x.to_bytes(3, "little") for x in v24))
        s8 = audio.read(aiff(bytes([0, 127, 128]), 1, 8, 22050, 3))
        self.assertEqual(s8.data, bytes([128, 255, 0]))
        with self.assertRaises(audio.AudioError):
            audio.read(aiff(le, 1, 16, 44100, 300, b"ima4"))

    def test_join_and_fold(self):
        a = audio.read(wav([tone(100, 220)]))
        b = audio.read(wav([tone(90, 330)]))
        st = audio.join_stereo(a, b)
        self.assertEqual((st.channels, st.frames), (2, 100))
        self.assertEqual(st.channel(0), a.data)
        self.assertEqual(st.channel(1)[:180], b.data)
        self.assertEqual(st.channel(1)[180:], b"\0" * 20)
        same = audio.join_stereo(a, a)
        self.assertTrue(same.channels_identical())
        self.assertEqual(same.to_mono_from(0).data, a.data)

    def test_pcm_tagged_as_float_reads_as_pcm(self):
        le = pcm16(tone(50, 300))
        fmt = struct.pack("<HHIIHH", 3, 1, 44100, 88200, 2, 16)
        body = b"WAVE" + b"fmt " + struct.pack("<I", 16) + fmt + b"data" + struct.pack("<I", len(le)) + le
        s = audio.read(b"RIFF" + struct.pack("<I", len(body)) + body)
        self.assertEqual((s.is_float, s.bits, s.data, s.source_format), (False, 16, le, "wav-pcm-tagged-float"))

    def test_ms_adpcm_decodes_a_constant(self):
        # One block, mono: header (predictor 0, delta 16, samples 1000, 1000) then nibbles 0.
        ch, block = 1, 7 + 8
        hdr = bytes([0]) + struct.pack("<hhh", 16, 1000, 1000)
        raw = hdr + b"\0" * 8
        fmt_extra = struct.pack("<HHH", 32, 32, 7) + b"".join(struct.pack("<hh", *c) for c in audio._COEF)
        fmt = struct.pack("<HHIIHH", 2, ch, 22050, 11025, block, 4) + struct.pack("<H", len(fmt_extra)) + fmt_extra
        body = b"WAVE" + b"fmt " + struct.pack("<I", len(fmt)) + fmt + b"data" + struct.pack("<I", len(raw)) + raw
        s = audio.read(b"RIFF" + struct.pack("<I", len(body)) + body)
        a = array.array("h")
        a.frombytes(s.data)
        self.assertEqual(s.bits, 16)
        self.assertEqual(len(a), 2 + 16)
        # predictor 0 is (2*s1 - s2): a constant stays constant
        self.assertTrue(all(x == 1000 for x in a), list(a))


class MachineTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)

    def run_zip(self, name, files):
        p = os.path.join(self.tmp.name, name + ".zip")
        with open(p, "wb") as fh:
            fh.write(make_zip(files))
        out = os.path.join(self.tmp.name, "out", name)
        os.makedirs(out)
        return dm.process(p, out), out

    def test_pairs_folds_layers_dupes_and_extras(self):
        l, r = tone(400, 200), tone(400, 300, phase=1.0)
        kick = wav([tone(300, 60)])
        files = {
            "Box/Kick 1-L.wav": wav([l]), "Box/Kick 1-R.wav": wav([r]),
            "Box/Hat L.wav": wav([tone(400, 500)]),           # no partner: stays
            "Box/Clap L.wav": wav([tone(400, 150)]), "Box/Clap R.wav": wav([tone(397, 160)]),   # trims differ a little
            "Box/Far L.wav": wav([tone(400, 150)]), "Box/Far R.wav": wav([tone(300, 160)]),     # too far apart
            "Box/Dual.wav": wav([l, l]),                       # identical channels
            "Box/Kit A/Kick.wav": kick, "Box/Kit B/Kick.wav": kick, "Box/Kit A/Kick copy.wav": kick,
            "Box/Sn [V1].wav": wav([tone(200, 180, amp=0.2)]), "Box/Sn [V2].wav": wav([tone(200, 180)]),
            "Box/Groove Loop 120.wav": wav([tone(100, 100)]),
            "Box/Odd.wav": aiff(b"\0\1" * 50, 1, 16, 44100, 50),   # AIFF named .wav
            "Box/readme.txt": b"hello",
            "__MACOSX/Box/._Dual.wav": b"junk",
        }
        man, out = self.run_zip("Box", files)
        paths = {f["path"]: f for f in man["files"]}
        self.assertIn("Kick 1.wav", paths)
        self.assertEqual(paths["Kick 1.wav"]["channels"], 2)
        self.assertEqual(len(paths["Kick 1.wav"]["sources"]), 2)
        self.assertIn("Hat L.wav", paths)
        self.assertEqual(paths["Clap.wav"]["frames"], 400)
        self.assertTrue(any("differed by 3" in n for n in paths["Clap.wav"]["notes"]))
        self.assertIn("Far L.wav", paths)
        self.assertEqual(len(man["lr_not_joined"]), 1)
        self.assertEqual(paths["Dual.wav"]["channels"], 1)
        # one copy per folder: Kit A's second copy goes, Kit B's stays
        self.assertIn("Kit A/Kick.wav", paths)
        self.assertIn("Kit B/Kick.wav", paths)
        self.assertNotIn("Kit A/Kick copy.wav", paths)
        self.assertEqual(man["dropped"][0]["reason"], "exact duplicate")
        self.assertEqual(paths["Sn [V2].wav"]["layer"], {"group": "Sn", "index": 2, "of": 2, "tag": "[V2]"})
        self.assertEqual(paths["Groove Loop 120.wav"]["kind"], "loop")
        self.assertIn("aiff named .wav", paths["Odd.wav"]["notes"])
        self.assertEqual(man["extra"][0]["path"], "_extra/readme.txt")
        self.assertEqual(man["junk_skipped"], 1)
        # files written match the manifest
        for p, f in paths.items():
            with open(os.path.join(out, *p.split("/")), "rb") as fh:
                s = audio.read(fh.read())
            self.assertEqual(s.content_hash(), f["content_sha256"])

    def test_d4_short_copies_go(self):
        full = wav([tone(2000, 200)])
        short = wav([tone(500, 200)])
        man, _ = self.run_zip("Alesis D4", {"Alesis D4/Snr/Snr25-Piccolo.wav": full,
                                            "Alesis D4/Snr25-Piccolo-38.wav": short,
                                            "Alesis D4/Snr99-Lonely-38.wav": short})
        paths = [f["path"] for f in man["files"]]
        self.assertEqual(sorted(paths), ["Snr/Snr25-Piccolo.wav", "Snr99-Lonely-38.wav"])
        self.assertTrue(man["dropped"][0]["reason"].startswith("short copy"))

    def test_runner_catalog_and_skip(self):
        src = os.path.join(self.tmp.name, "src")
        os.makedirs(src)
        same = wav([tone(300, 90)])
        for name in ("A", "B"):
            with open(os.path.join(src, name + ".zip"), "wb") as fh:
                fh.write(make_zip({name + "/x.wav": same, name + "/y.wav": wav([tone(300, 100 + ord(name))])}))
        out = os.path.join(self.tmp.name, "lib")
        self.assertEqual(prep_drums.main(["--source", src, "--out", out, "--workers", "1"]), 0)
        with open(os.path.join(out, "catalog.json"), encoding="utf-8") as fh:
            cat = json.load(fh)
        self.assertEqual(cat["files"], 4)
        x = [e for e in cat["entries"] if e["path"] == "A/x.wav"][0]
        self.assertEqual(x["same_as"], "B/x.wav")
        self.assertTrue(prep_drums.up_to_date(out, os.path.join(src, "A.zip")))


if __name__ == "__main__":
    unittest.main()
