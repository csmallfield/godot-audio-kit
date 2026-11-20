# SPDX-License-Identifier: Apache-2.0
"""Renders each DX7 voice in a prep-tool library with msfa's FM engine (Dexed's
"Modern" engine, Apache-2.0): the reference GAK's DX7 conversion matches.

    python tools/patch_convert/render_msfa.py [library folder] [--dx7render path] [--jobs n]

Writes render_msfa_v<vel>.wav beside each voice's Mark I render (left as it is), in
the same layout (content.render: notes, velocities, hold, release, gap, rate), and
adds content.render_msfa to the sidecar.
"""
import argparse
import concurrent.futures
import hashlib
import json
import os
import pathlib
import subprocess
import tempfile

LIB = "D:/12_library/gak/processed_soundarchive/yamaha-dx7"
EXE = "D:/tools/dx7render/dx7render.exe"


def sha256(path):
	h = hashlib.sha256()
	with open(path, "rb") as f:
		for chunk in iter(lambda: f.read(1 << 20), b""):
			h.update(chunk)
	return h.hexdigest()


def render(sidecar, exe):
	d = json.loads(sidecar.read_text(encoding="utf-8"))
	c = d.get("content", {})
	if "dx7" not in c or "render" not in c:
		return None
	st = c["render"]
	vced = bytes.fromhex(c["dx7"]["vced_hex"])
	files = []
	with tempfile.TemporaryDirectory() as tmp:
		vb = os.path.join(tmp, "voice.bin")
		with open(vb, "wb") as f:
			f.write(vced + bytes([0x3F]))
		for vel in st["velocities"]:
			name = "render_msfa_v%03d.wav" % vel
			out = sidecar.parent / name
			args = [exe, vb, str(out), "--notes", ",".join(map(str, st["notes"])), "--velocity", str(vel),
					"--hold", str(st["hold_s"]), "--release", str(st["release_s"]), "--gap", str(st["gap_s"]),
					"--rate", str(st["sample_rate"]), "--engine", "msfa"]
			subprocess.run(args, check=True, capture_output=True)
			files.append({"file": name, "velocity": vel, "sha256": sha256(out)})
	c["render_msfa"] = {"engine": "msfa", "renderer_sha256": sha256(exe), "files": files,
		"note": "same layout as content.render; msfa's own FM engine (Apache-2.0), the reference for GAK conversions"}
	sidecar.write_text(json.dumps(d, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
	return sidecar


def main():
	ap = argparse.ArgumentParser()
	ap.add_argument("library", nargs="?", default=LIB)
	ap.add_argument("--dx7render", default=EXE)
	ap.add_argument("--jobs", type=int, default=os.cpu_count() or 4)
	a = ap.parse_args()
	cars = sorted(pathlib.Path(a.library).rglob("instrument.json"))
	done = 0
	with concurrent.futures.ThreadPoolExecutor(a.jobs) as ex:
		for r in ex.map(lambda s: render(s, a.dx7render), cars):
			done += r is not None
	print("%d of %d sidecars rendered with msfa" % (done, len(cars)))


main()
