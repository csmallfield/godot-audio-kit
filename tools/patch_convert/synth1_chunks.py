# SPDX-License-Identifier: Apache-2.0
"""Runs the whole Synth1 pipeline over a prep-tool library in chunks, deleting each chunk's
audio once it is checked, so a library of 16,706 patches never holds more than one chunk
of renders (about 9 MB a patch):

    D:\\tools\\dawdreamer\\venv\\Scripts\\python.exe -I tools/patch_convert/synth1_chunks.py [library] [--size 1000] [--chunks n] [--keep-renders]

Per chunk: render_synth1.py (Synth1's references), synth1_batch.gd (convert, render with GAK),
check_synth1.py (compare; the library's summary counts every patch done so far), then delete
render_synth1_v100.wav and gak_render_v100.wav. Kept beside each sidecar: instrument.json
(with content.render_synth1: the values Synth1 held, the layout), gak_patch.tres,
gak_convert.json and gak_report.json. A patch with a gak_report.json is done and skipped, so
a stopped run picks up where it left off. Rendering a chunk again later (for a better
converter) takes render_synth1.py and synth1_batch.gd with the chunk's list.
"""
import argparse
import json
import pathlib
import subprocess
import sys
import time

HERE = pathlib.Path(__file__).resolve().parent
REPO = HERE.parent.parent
LIB = "D:/12_library/gak/processed_synth1"
GODOT = "D:/08_godot/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64_console.exe"
RENDERS = ("render_synth1_v100.wav", "gak_render_v100.wav")


def log(lib, text):
	line = "%s %s" % (time.strftime("%Y-%m-%d %H:%M:%S"), text)
	print(line, flush=True)
	with open(lib / "gak_synth1_chunks.log", "a", encoding="utf-8") as f:
		f.write(line + "\n")


def patches(lib):
	"""Every folder whose sidecar is a Synth1 patch, sorted."""
	out = []
	for car in sorted(lib.rglob("instrument.json")):
		try:
			d = json.loads(car.read_text(encoding="utf-8"))
		except (OSError, ValueError):
			continue
		if "synth1" in d.get("content", {}):
			out.append(car.parent)
	return out


def drop_renders(folders):
	n = 0
	for f in folders:
		if (f / "gak_report.json").is_file():
			for name in RENDERS:
				p = f / name
				if p.is_file():
					p.unlink()
					n += 1
	return n


def _tail(text):
	# Godot's own noise (a missing autoload of the project's, "at:" lines) left out.
	keep = [x for x in text.strip().splitlines() if x.strip() and "motion_kit" not in x and not x.strip().startswith("at:")
		and "autoload" not in x]
	return " | ".join(keep[-3:])[:600]


def run(cmd, lib, what):
	t0 = time.time()
	r = subprocess.run(cmd, capture_output=True, text=True, cwd=REPO)
	log(lib, "  %s: exit %d in %.0f s; %s" % (what, r.returncode, time.time() - t0, _tail(r.stdout + r.stderr)))
	return r.returncode


def run_parallel(cmds, lib, what):
	"""Several processes at once (the chunk split between them)."""
	t0 = time.time()
	procs = [subprocess.Popen(c, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, cwd=REPO) for c in cmds]
	outs = [pr.communicate()[0] for pr in procs]
	codes = [pr.returncode for pr in procs]
	log(lib, "  %s: %d processes, exit %s in %.0f s; %s" % (what, len(cmds), codes, time.time() - t0,
		" || ".join(_tail(o) for o in outs)[:900]))
	return max(codes) if codes else 0


def main():
	ap = argparse.ArgumentParser()
	ap.add_argument("library", nargs="?", default=LIB)
	ap.add_argument("--size", type=int, default=1000)
	ap.add_argument("--chunks", type=int, default=0, help="stop after this many chunks (0: all)")
	ap.add_argument("--keep-renders", action="store_true")
	ap.add_argument("--godot", default=GODOT)
	ap.add_argument("--jobs", type=int, default=16, help="Synth1 renders and Godot processes at once")
	a = ap.parse_args()
	lib = pathlib.Path(a.library)
	py = sys.executable
	every = patches(lib)
	done = [f for f in every if (f / "gak_report.json").is_file()]
	todo = [f for f in every if not (f / "gak_report.json").is_file()]
	log(lib, "%d Synth1 patches: %d done, %d to go, in chunks of %d" % (len(every), len(done), len(todo), a.size))
	if not a.keep_renders:
		n = drop_renders(done)
		if n:
			log(lib, "deleted %d renders of patches already done" % n)
	(lib / ".chunks").mkdir(exist_ok=True)
	count = 0
	for start in range(0, len(todo), a.size):
		if a.chunks and count >= a.chunks:
			break
		chunk = todo[start:start + a.size]
		k = start // a.size + 1
		lst = lib / ".chunks" / ("chunk_%03d.txt" % k)
		lst.write_text("\n".join(str(f).replace("\\", "/") for f in chunk) + "\n", encoding="utf-8")
		log(lib, "chunk %d: %d patches (%s .. %s)" % (k, len(chunk), chunk[0].name, chunk[-1].name))
		run([py, "-I", str(HERE / "render_synth1.py"), "--list", str(lst), "--jobs", str(a.jobs)], lib, "Synth1 references")
		parts = []
		for j in range(a.jobs):
			part = chunk[j::a.jobs]
			if part:
				pl = lib / ".chunks" / ("chunk_%03d_part%02d.txt" % (k, j))
				pl.write_text("\n".join(str(f).replace("\\", "/") for f in part) + "\n", encoding="utf-8")
				parts.append([a.godot, "--headless", "--path", str(REPO), "--script", "res://tools/patch_convert/synth1_batch.gd",
					"--", str(pl).replace("\\", "/")])
		run_parallel(parts, lib, "convert and render")
		run([py, "-I", str(HERE / "check_synth1.py"), str(lib), "--list", str(lst)], lib, "check")
		if not a.keep_renders:
			log(lib, "  deleted %d renders" % drop_renders(chunk))
		count += 1
	left = sum(1 for f in every if not (f / "gak_report.json").is_file())
	log(lib, "finished: %d chunk(s) this run, %d patches still to go" % (count, left))


if __name__ == "__main__":
	main()
