# SPDX-License-Identifier: Apache-2.0
"""Renders each patch in a prep-tool library with its own synth (through DawDreamer): the
references GAK's conversions of TAL-NoiseMaker, Helm and OB-Xd/OB-Xf patches are checked against.

    D:\\tools\\dawdreamer\\venv\\Scripts\\python.exe -I tools/patch_convert/render_vsynth.py <tal|helm|obxf> [library] [--jobs n] [--force] [--list file]

For each instrument.json with content.<synth> it writes render_<synth>_v<vel>.wav (16-bit
stereo) beside it and adds content.render_<synth> to the sidecar: the layout (as the DX7 and
Synth1 references: notes 36, 48, 60, 72 and 84 at velocity 100, each held 2 s, released for
2.5 s, then 0.25 s, at 48 kHz and 120 bpm), the plugin, and per file its peak and scale (a
render past full scale is scaled down to fit: divide the file by scale for the real level).

How each synth gets its patch:
- TAL-NoiseMaker (VST2): its state is a VST2 bank chunk holding its XML. The renderer saves a
  fresh instance's state, puts the preset's program in it (as program 0) and loads that back.
- Helm (VST2): the same, with the .helm file's JSON as the chunk.
- OB-Xf (VST3): its parameters 0..101 are set one by one from the sidecar's values (OB-Xd
  programs were already converted to OB-Xf's by the prep tool, as OB-Xf's own importer does).

Each note renders on a fresh instance, alone for its slot (a longer tail is cut there), and the
slots are joined, as the Synth1 references do: nothing (a delay's buffer, a held voice, an
LFO's phase) carries over between notes, and GAK's side renders the same way. Unlike Synth1,
these plugins play overlapping voices fine. Each note starts 0.1 s into its render and that
pre-roll is trimmed off (Helm's arpeggiator stays silent for a note at time 0). Each patch renders in its own process, several at
once, so a crash costs that patch only.
"""
import argparse
import concurrent.futures
import hashlib
import json
import os
import pathlib
import re
import struct
import subprocess
import sys
import tempfile
import wave

import numpy as np

LAYOUT = dict(notes=[36, 48, 60, 72, 84], velocities=[100], hold_s=2.0, release_s=2.5, gap_s=0.25,
	sample_rate=48000, bpm=120.0)
VERSION = 2
# Each note starts this long into its render, which is then trimmed off: Helm's arpeggiator
# stays silent for a note at time 0.
PREROLL_S = 0.1
SYNTHS = {
	"tal": dict(dll="D:/tools/tal-noisemaker/TAL-NoiseMaker-64.dll", lib="D:/12_library/gak/processed_tal",
		plugin="TAL-NoiseMaker 5.0.6 (VST2, TAL Software)"),
	"helm": dict(dll="D:/tools/helm/Steinberg/VstPlugins/helm64.dll", lib="D:/12_library/gak/processed_helm",
		plugin="Helm 0.9.0 (VST2, Matt Tytel)"),
	"obxf": dict(dll="D:/tools/obxf/obxf_products/OB-Xf.vst3", lib="D:/12_library/gak/processed_obx",
		plugin="OB-Xf 1.0.3 (VST3, Surge Synth Team)"),
}
sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent.parent / "open_samples_prep"))


def sha256(path):
	h = hashlib.sha256()
	with open(path, "rb") as f:
		for chunk in iter(lambda: f.read(1 << 20), b""):
			h.update(chunk)
	return h.hexdigest()


_SHA = {}


def file_sha(path):
	if path not in _SHA:
		p = pathlib.Path(path)
		# A VST3 is a folder: hash its binary.
		if p.is_dir():
			p = next(iter(sorted(p.rglob("*.vst3"), key=lambda q: -q.stat().st_size if q.is_file() else 0)), p)
		_SHA[path] = sha256(p) if p.is_file() else "folder"
	return _SHA[path]


def write_wav16(path, stereo):
	peak = float(np.max(np.abs(stereo))) if stereo.size else 0.0
	scale = 1.0 if peak <= 0.999 else 0.999 / peak
	pcm = np.clip(np.round(stereo.T * (scale * 32767.0)), -32768, 32767).astype("<i2")
	with wave.open(str(path), "wb") as w:
		w.setnchannels(2)
		w.setsampwidth(2)
		w.setframerate(LAYOUT["sample_rate"])
		w.writeframes(pcm.tobytes())
	return peak, scale


def _bank_chunk(template, payload):
	"""A VST2 bank state (CcnK/FBCh, as the plugin saves it) with its chunk replaced."""
	head = template[:156]
	if head[:4] != b"CcnK" or head[8:12] != b"FBCh":
		raise RuntimeError("unexpected state layout")
	return head + struct.pack(">I", len(payload)) + payload


def tal_state(template, program_xml):
	"""TAL's saved state, with the preset's program as its only one."""
	i = template.find(b"VC2!")
	x = template[i + 8:].split(b"\0", 1)[0].decode("utf-8")
	x = re.sub(r"<programs>.*</programs>", lambda m: "<programs>" + program_xml + "</programs>", x, flags=re.S)
	x = re.sub(r'curprogram="\d+"', 'curprogram="0"', x)
	xb = x.encode("utf-8") + b"\0"
	return _bank_chunk(template, b"VC2!" + struct.pack("<I", len(xb)) + xb)


def helm_state(template, text):
	return _bank_chunk(template, text.encode("utf-8") + b"\0")


class Synth:
	"""One fresh plugin instance with the patch loaded."""

	def __init__(self, synth, dll, content, tmpdir):
		import dawdreamer as daw
		self.engine = daw.RenderEngine(LAYOUT["sample_rate"], 512)
		self.engine.set_bpm(LAYOUT["bpm"])
		self.p = self.engine.make_plugin_processor("s", dll)
		if synth == "obxf":
			from osp import obxd
			vals = content["params"]
			for i, k in enumerate(obxd.KEYS):
				self.p.set_parameter(i, float(vals[k]))
			return
		tpl = os.path.join(tmpdir, "template.state")
		self.p.save_state(tpl)
		template = pathlib.Path(tpl).read_bytes()
		state = tal_state(template, content["program_xml"]) if synth == "tal" else helm_state(template, content["file_text"])
		st = os.path.join(tmpdir, "patch.state")
		pathlib.Path(st).write_bytes(state)
		self.p.load_state(st)

	def render(self, note, vel, hold, secs):
		self.p.add_midi_note(note, vel, PREROLL_S, hold)
		self.engine.load_graph([(self.p, [])])
		self.engine.render(secs + PREROLL_S)
		a = self.engine.get_audio()
		if a.shape[0] == 1:
			a = np.vstack([a, a])
		return a[:2, round(PREROLL_S * LAYOUT["sample_rate"]):]


def render_one(synth, sidecar, dll, force):
	d = json.loads(sidecar.read_text(encoding="utf-8"))
	c = d.get("content", {})
	if synth not in c:
		return sidecar, "skip"
	st = LAYOUT
	key = {"layout": st, "plugin_sha256": file_sha(dll), "version": VERSION}
	rk = "render_" + synth
	old = c.get(rk)
	if (not force and old and old.get("key") == key
			and all((sidecar.parent / f["file"]).is_file() for f in old.get("files", []))):
		return sidecar, "unchanged"
	per = st["hold_s"] + st["release_s"] + st["gap_s"]
	n_per = round(per * st["sample_rate"])
	files = []
	with tempfile.TemporaryDirectory() as tmp:
		for vel in st["velocities"]:
			slots = []
			for n in st["notes"]:
				s = Synth(synth, dll, c[synth], tmp)
				a = s.render(n, vel, st["hold_s"], per)[:, :n_per]
				if a.shape[1] < n_per:
					a = np.pad(a, ((0, 0), (0, n_per - a.shape[1])))
				slots.append(a)
				del s
			audio = np.concatenate(slots, axis=1)
			if not np.all(np.isfinite(audio)):
				return sidecar, "failed: the render isn't finite"
			name = "render_%s_v%03d.wav" % (synth, vel)
			peak, scale = write_wav16(sidecar.parent / name, audio)
			files.append({"file": name, "velocity": vel, "sha256": sha256(sidecar.parent / name),
				"peak": round(peak, 4), "scale": scale})
	notes = st["notes"]
	c[rk] = {
		**st,
		"layout": "held notes in this order, each held hold_s, released and left to ring release_s, "
			"then gap_s; each note rendered alone (a fresh instance), its tail cut at the end of "
			"its slot; stereo",
		"first_note": notes[0], "step": notes[1] - notes[0],
		"note_onsets_s": [round(i * per, 6) for i in range(len(notes))],
		"note_off_s": [round(i * per + st["hold_s"], 6) for i in range(len(notes))],
		"renderer": {"plugin": SYNTHS[synth]["plugin"], "path": str(dll), "host": "DawDreamer 0.9",
			"script": "tools/patch_convert/render_vsynth.py %s %d" % (synth, VERSION)},
		"note": "The synth itself: the reference for GAK conversions. Controllers stay at rest.",
		"key": key,
		"files": files,
	}
	sidecar.write_text(json.dumps(d, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
	return sidecar, "rendered"


def main():
	ap = argparse.ArgumentParser()
	ap.add_argument("synth", choices=sorted(SYNTHS))
	ap.add_argument("library", nargs="?")
	ap.add_argument("--list", help="a text file of patch folders (or their instrument.json), one per line, instead of the library")
	ap.add_argument("--dll")
	ap.add_argument("--force", action="store_true", help="render again even when unchanged")
	ap.add_argument("--jobs", type=int, default=max(1, min(8, (os.cpu_count() or 4) // 2)))
	ap.add_argument("--one", help=argparse.SUPPRESS)
	a = ap.parse_args()
	dll = a.dll or SYNTHS[a.synth]["dll"]
	if a.one:
		print(render_one(a.synth, pathlib.Path(a.one), dll, a.force)[1])
		return 0
	if a.list:
		lines = [x.strip() for x in pathlib.Path(a.list).read_text(encoding="utf-8").splitlines() if x.strip()]
		cars = sorted(str(pathlib.Path(x) if x.endswith("instrument.json") else pathlib.Path(x) / "instrument.json") for x in lines)
	else:
		cars = sorted(str(p) for p in pathlib.Path(a.library or SYNTHS[a.synth]["lib"]).rglob("instrument.json"))

	def work(car):
		cmd = [sys.executable, "-I", str(pathlib.Path(__file__).resolve()), a.synth, "--one", car, "--dll", dll]
		r = subprocess.run(cmd + (["--force"] if a.force else []), capture_output=True, text=True)
		out = (r.stdout.strip().splitlines() or [""])[-1]
		if r.returncode == 0 and out:
			return out
		err = (r.stderr.strip().splitlines() or ["no output"])[-1]
		return "failed: exit %d, %s" % (r.returncode, err[:200])

	counts, failed = {}, []
	with concurrent.futures.ThreadPoolExecutor(a.jobs) as ex:
		for i, (car, status) in enumerate(zip(cars, ex.map(work, cars))):
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
