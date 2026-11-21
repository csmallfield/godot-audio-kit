# SPDX-License-Identifier: Apache-2.0
"""Renders each Synth1 patch in a prep-tool library with Synth1 itself (through
DawDreamer): the reference GAK's Synth1 conversion is checked against.

    D:\\tools\\dawdreamer\\venv\\Scripts\\python.exe -I tools/patch_convert/render_synth1.py [library] [--force]

For each instrument.json with content.synth1 it writes render_synth1_v<vel>.wav (16-bit
stereo) beside it and adds content.render_synth1 to the sidecar: the layout (held notes
in order, each held, released, left to ring, then a gap; as the DX7 references), the
tempo, and per file its peak and scale (a render past full scale is scaled down to fit:
divide the file by scale for Synth1's real level).

Every note gets a fresh Synth1 instance, rendered alone for its slot (hold, release and
gap; a longer tail is cut there), and the slots are joined: Synth1 under DawDreamer crashes
(an access violation) as soon as two voices sound at once, even a plain chord on a fresh
instance, and a voice still releasing counts. A fresh instance per note also means
nothing (a delay's buffer, a held voice) carries over. Each patch renders in its own
process, so a crash costs that patch only; it is reported as failed. Synth1 itself isn't reproducible sample by sample:
its oscillators run free unless "osc phase" is set, and noise, unison and S&H are
random. The values come from the sidecar (Synth1's defaults filled in), written into
Synth1's own state as tools/synth1_ref/synth1.py does, with the file's version (100 for a
file without one), so Synth1 converts an old patch's values as it does on loading the file.
The values it then holds are recorded (content.render_synth1.values); the converter uses them.
"""
import argparse
import concurrent.futures
import hashlib
import json
import os
import subprocess
import pathlib
import sys
import wave

import numpy as np

HERE = pathlib.Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent / "synth1_ref"))
import synth1 as s1ref  # noqa: E402

LIB = "D:/12_library/gak/processed_synth1"
LAYOUT = dict(notes=[36, 48, 60, 72, 84], velocities=[100], hold_s=2.0, release_s=2.5, gap_s=0.25,
	sample_rate=48000, bpm=120.0)
VERSION = 3
# A .sy1 without a ver= line predates 1.05; Synth1 reads it with its oldest conversion
# (its gain knob sits at 64 where versioned files sit at 107, and version 100 turns 64 into 93).
NO_VERSION = 100


def sha256(path):
	h = hashlib.sha256()
	with open(path, "rb") as f:
		for chunk in iter(lambda: f.read(1 << 20), b""):
			h.update(chunk)
	return h.hexdigest()


def write_wav16(path, stereo):
	"""(2, n) floats -> 16-bit stereo WAV. A render louder than full scale (Synth1 goes past
	it) is scaled down to fit rather than clipped. Returns (peak, scale): the file holds the
	render times scale, so the real level is the file's divided by scale."""
	peak = float(np.max(np.abs(stereo))) if stereo.size else 0.0
	scale = 1.0 if peak <= 0.999 else 0.999 / peak
	pcm = np.clip(np.round(stereo.T * (scale * 32767.0)), -32768, 32767).astype("<i2")
	with wave.open(str(path), "wb") as w:
		w.setnchannels(2)
		w.setsampwidth(2)
		w.setframerate(LAYOUT["sample_rate"])
		w.writeframes(pcm.tobytes())
	return peak, scale


def render_one(sidecar, dll, force, mono=False):
	"""Render one sidecar's patch. Returns (sidecar, status)."""
	d = json.loads(sidecar.read_text(encoding="utf-8"))
	c = d.get("content", {})
	if "synth1" not in c:
		return sidecar, "skip"
	st = LAYOUT
	key = {"layout": st, "dll_sha256": file_sha(dll), "version": VERSION, "mono": mono}
	old = c.get("render_synth1")
	if (not force and old and old.get("key") == key
			and all((sidecar.parent / f["file"]).is_file() for f in old.get("files", []))):
		return sidecar, "unchanged"
	params = c["synth1"]["params"]
	values = {s1ref.P[k] if k in s1ref.P else None: v for k, v in params.items()}
	values.pop(None, None)
	if "polyphony" in params:
		values[94] = params["polyphony"]
	version = c["synth1"].get("version") or NO_VERSION
	# The values Synth1 holds once it has converted them from the file's version: what it plays,
	# and what the converter reads.
	probe = s1ref.Synth1(dll, st["sample_rate"])
	probe.load(values, version)
	held = probe.values()
	probe.close()
	del probe
	if mono:
		held[s1ref.P["play_mode"]] = 1
	per = st["hold_s"] + st["release_s"] + st["gap_s"]
	notes = st["notes"]
	files = []
	for vel in st["velocities"]:
		slots = []
		for n in notes:
			syn = s1ref.Synth1(dll, st["sample_rate"])
			syn.engine.set_bpm(st["bpm"])
			syn.load(held)
			slots.append(syn.render([(n, vel, 0.0, st["hold_s"])], per)[:, :round(per * st["sample_rate"])])
			syn.close()
			del syn
		audio = np.concatenate(slots, axis=1)
		name = "render_synth1_v%03d.wav" % vel
		peak, scale = write_wav16(sidecar.parent / name, audio)
		files.append({"file": name, "velocity": vel, "sha256": sha256(sidecar.parent / name),
			"peak": round(peak, 4), "scale": scale})
	c["render_synth1"] = {
		**st,
		"layout": "held notes in this order, each held hold_s, released and left to ring release_s, "
			"then gap_s; each note rendered alone (a fresh instance), its tail cut at the end of "
			"its slot; stereo",
		"first_note": notes[0], "step": notes[1] - notes[0],
		"note_onsets_s": [round(i * per, 6) for i in range(len(notes))],
		"note_off_s": [round(i * per + st["hold_s"], 6) for i in range(len(notes))],
		"renderer": {"plugin": "Synth1 1.13 (VST2, Daichi Laboratory)", "dll": str(dll),
			"host": "DawDreamer 0.9", "script": "tools/patch_convert/render_synth1.py %d" % VERSION},
		"note": "Synth1 itself: the reference for GAK conversions. Free-running oscillators and "
			"random sources make it unrepeatable sample by sample; controllers stay at rest.",
		"key": key,
		"version_loaded_as": version,
		"values": {name: held[i] for name, i in list(s1ref.P.items()) + [("polyphony", 94)]},
		"files": files,
		"forced_mono": mono,
	}
	if mono:
		c["render_synth1"]["note"] += (" Rendered in mono mode: in poly the patch crashed Synth1 (its "
			"arpeggiator's notes overlap), so each step here cuts the last one's release.")
	sidecar.write_text(json.dumps(d, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
	return sidecar, "rendered"


_SHA = {}


def file_sha(path):
	if path not in _SHA:
		_SHA[path] = sha256(path)
	return _SHA[path]


def main():
	ap = argparse.ArgumentParser()
	ap.add_argument("library", nargs="?", default=LIB)
	ap.add_argument("--list", help="a text file of patch folders (or their instrument.json), one per line, instead of the library")
	ap.add_argument("--dll", default=s1ref.DLL)
	ap.add_argument("--force", action="store_true", help="render again even when unchanged")
	ap.add_argument("--jobs", type=int, default=max(1, min(6, (os.cpu_count() or 4) // 2)))
	ap.add_argument("--one", help=argparse.SUPPRESS)  # a worker: render this one sidecar
	ap.add_argument("--mono", action="store_true", help=argparse.SUPPRESS)
	a = ap.parse_args()
	if a.one:
		print(render_one(pathlib.Path(a.one), a.dll, a.force, a.mono)[1])
		return 0
	if a.list:
		lines = [x.strip() for x in pathlib.Path(a.list).read_text(encoding="utf-8").splitlines() if x.strip()]
		cars = sorted(str(pathlib.Path(x) if x.endswith("instrument.json") else pathlib.Path(x) / "instrument.json") for x in lines)
	else:
		cars = sorted(str(p) for p in pathlib.Path(a.library).rglob("instrument.json"))
	counts = {}
	failed = []
	def run(car, extra):
		cmd = [sys.executable, "-I", str(pathlib.Path(__file__).resolve()), "--one", car, "--dll", a.dll]
		r = subprocess.run(cmd + (["--force"] if a.force else []) + extra, capture_output=True, text=True)
		out = (r.stdout.strip().splitlines() or [""])[-1]
		if r.returncode == 0 and out:
			return out
		err = (r.stderr.strip().splitlines() or ["no output"])[-1]
		return "failed: exit %d, %s" % (r.returncode, err[:200])

	def work(car):
		status = run(car, [])
		if status.startswith("failed"):
			# Overlapping voices crash Synth1 (a poly arpeggiator): try again in mono.
			again = run(car, ["--mono", "--force"])
			status = again.replace("rendered", "rendered-mono") if not again.startswith("failed") else status
		return status

	with concurrent.futures.ThreadPoolExecutor(a.jobs) as ex:
		results = ex.map(work, cars)
	for i, (car, status) in enumerate(zip(cars, results)):
		k = status.split(":")[0]
		counts[k] = counts.get(k, 0) + 1
		if k == "failed":
			failed.append("%s: %s" % (car, status))
		if (i + 1) % 100 == 0:
			print("%d / %d" % (i + 1, len(cars)), flush=True)
	print(", ".join("%s %d" % kv for kv in sorted(counts.items())))
	for f in failed:
		print(f)
	return 1 if failed else 0


if __name__ == "__main__":
	sys.exit(main())
