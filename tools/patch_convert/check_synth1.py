# SPDX-License-Identifier: Apache-2.0
"""Compares each converted Synth1 patch's GAK render with Synth1's own.

    D:\\tools\\dawdreamer\\venv\\Scripts\\python.exe -I tools/patch_convert/check_synth1.py [library] [--list chunk.txt]

Needs render_synth1_v100.wav (render_synth1.py) and gak_render_v100.wav with
gak_convert.json (synth1_batch.gd) beside each sidecar. Synth1 isn't repeatable sample by
sample, so per note (its hold and release; not the gap) it measures:
- level_db: the GAK render's level against Synth1's (median over 10 ms frames, in dB;
  both floored 60 dB under Synth1's peak);
- env_err_db: the loudness envelope's mean error once that level is taken out;
- spec_err_db: the spectral shape's mean error, per frame across third-octave bands
  (50 Hz to 16 kHz), each frame's own level taken out.
Writes gak_report.json beside each patch and gak_synth1_summary.json in the library. With
--list, it checks only the folders listed; patches whose renders have been deleted (see
synth1_chunks.py) count in the summary from their gak_report.json.
"""
import json
import pathlib
import sys
import wave

import numpy as np

LIB = "D:/12_library/gak/processed_synth1"
BANDS = 50.0 * 2 ** (np.arange(0, 29) / 3.0)   # 50 Hz .. 12.7 kHz centres
FRAME = 480
NFFT = 4096


def read16(path, scale):
	with wave.open(str(path), "rb") as w:
		x = np.frombuffer(w.readframes(w.getnframes()), "<i2").reshape(-1, w.getnchannels()).astype(np.float64)
	return x.mean(axis=1) / 32768.0 / scale


def frames_db(x):
	n = len(x) // FRAME
	return 10 * np.log10(np.mean(x[:n * FRAME].reshape(n, FRAME) ** 2, axis=1) + 1e-14)


def band_db(x, sr):
	"""Third-octave band levels (dB) per frame: (frames, bands)."""
	win = np.hanning(NFFT)
	f = np.fft.rfftfreq(NFFT, 1 / sr)
	edges = [(np.searchsorted(f, b * 2 ** (-1 / 6)), max(np.searchsorted(f, b * 2 ** (1 / 6)), np.searchsorted(f, b * 2 ** (-1 / 6)) + 1)) for b in BANDS]
	out = []
	for i in range(0, len(x) - NFFT, NFFT // 2):
		P = np.abs(np.fft.rfft(x[i:i + NFFT] * win)) ** 2
		out.append([10 * np.log10(np.sum(P[a:b]) + 1e-14) for a, b in edges])
	return np.array(out)


def compare(ref, gak, sr):
	"""One note's metrics, or None when Synth1 is silent there."""
	fr, fg = frames_db(ref), frames_db(gak)
	if fr.max() < -70:
		return None
	# Both floored 60 dB under Synth1's peak: silence against a quiet tail isn't a 100 dB error.
	floor = fr.max() - 60
	fr, fg = np.maximum(fr, floor), np.maximum(fg, floor)
	m = fr > fr.max() - 40
	diff = fg[m] - fr[m]
	level = float(np.median(diff))
	env = float(np.mean(np.abs(diff - level)))
	br, bg = band_db(ref, sr), band_db(gak, sr)
	errs = []
	if len(br):
		loud = br.max(axis=1)
		keep = loud > loud.max() - 40
		for r, g in zip(br[keep], bg[keep]):
			ok = r > r.max() - 50
			d = (np.maximum(g, r.max() - 60) - r)[ok]
			errs.append(float(np.mean(np.abs(d - np.median(d)))))
	return {"level_db": round(level, 2), "env_err_db": round(env, 2),
		"spec_err_db": round(float(np.mean(errs)), 2) if errs else None,
		"ref_peak_db": round(float(fr.max()), 1), "gak_peak_db": round(float(fg.max()), 1)}


def row_of(sc, rep):
	c = sc["content"]
	return {"id": sc.get("id"), "name": c["synth1"].get("name"), "error": rep.get("error"),
		"level_db": rep.get("level_db_median"), "env_err_db": rep.get("env_err_db_median"),
		"spec_err_db": rep.get("spec_err_db_median"), "spec_err_db_worst": rep.get("spec_err_db_worst"),
		"caveats": rep.get("caveats", []), "forced_mono": rep.get("forced_mono", False),
		"features": c["synth1"].get("features", [])}


def check(folder, reuse=False):
	"""Compare one patch's renders; with reuse, a patch whose renders are gone counts from its report."""
	sc = json.loads((folder / "instrument.json").read_text(encoding="utf-8"))
	c = sc.get("content", {})
	st = c.get("render_synth1")
	conv_path = folder / "gak_convert.json"
	if not st or not conv_path.is_file():
		return None
	rep_path = folder / "gak_report.json"
	if reuse and rep_path.is_file() and not (folder / st["files"][0]["file"]).is_file():
		return row_of(sc, json.loads(rep_path.read_text(encoding="utf-8")))
	conv = json.loads(conv_path.read_text(encoding="utf-8"))
	if conv.get("scale") is None:  # the GAK render wasn't finite
		rep = {"converter": conv["converter"], "error": "GAK render not finite (NaN)", "caveats": conv.get("caveats", [])}
		(folder / "gak_report.json").write_text(json.dumps(rep, indent=2) + "\n", encoding="utf-8")
		return {"id": sc.get("id"), "name": c["synth1"].get("name"), "error": rep["error"], "level_db": None,
			"env_err_db": None, "spec_err_db": None, "spec_err_db_worst": None, "caveats": rep["caveats"],
			"forced_mono": st.get("forced_mono", False), "features": c["synth1"].get("features", [])}
	sr = int(st["sample_rate"])
	ref = read16(folder / st["files"][0]["file"], float(st["files"][0].get("scale", 1.0)))
	gak = read16(folder / conv["render"], float(conv.get("scale", 1.0)))
	per = int(round((st["hold_s"] + st["release_s"] + st["gap_s"]) * sr))
	span = int(round((st["hold_s"] + st["release_s"]) * sr))
	notes = []
	for i, n in enumerate(st["notes"]):
		r = compare(ref[i * per:i * per + span], gak[i * per:i * per + span], sr)
		notes.append(dict({"note": n}, **(r or {"silent": True})))
	sounding = [x for x in notes if "level_db" in x]
	med = (lambda k: round(float(np.median([x[k] for x in sounding if x.get(k) is not None])), 2) if sounding else None)
	worst = (lambda k: round(float(max(abs(x[k]) for x in sounding if x.get(k) is not None)), 2) if sounding else None)
	rep = {"converter": conv["converter"], "engine": conv["engine"], "reference": st["files"][0]["file"],
		"forced_mono": st.get("forced_mono", False), "notes": notes,
		"level_db_median": med("level_db"), "env_err_db_median": med("env_err_db"), "spec_err_db_median": med("spec_err_db"),
		"env_err_db_worst": worst("env_err_db"), "spec_err_db_worst": worst("spec_err_db"), "caveats": conv.get("caveats", [])}
	(folder / "gak_report.json").write_text(json.dumps(rep, indent=2) + "\n", encoding="utf-8")
	return row_of(sc, rep)


def pct(vals, q):
	vals = sorted(v for v in vals if v is not None)
	return round(float(np.percentile(vals, q)), 2) if vals else None


def main():
	args = sys.argv[1:]
	listed = None
	if "--list" in args:
		i = args.index("--list")
		listed = {str(pathlib.Path(x.strip().removesuffix("instrument.json"))).lower()
			for x in pathlib.Path(args[i + 1]).read_text(encoding="utf-8").splitlines() if x.strip()}
		del args[i:i + 2]
	lib = pathlib.Path(args[0] if args else LIB)
	rows = []
	for car in sorted(lib.rglob("instrument.json")):
		# Listed folders are checked again; the rest count from their reports (renders may be gone).
		fresh = listed is None or str(car.parent).lower() in listed
		r = check(car.parent, reuse=not fresh)
		if r:
			rows.append(r)
	clean = [r for r in rows if not r["caveats"]]
	summ = {"patches": len(rows), "without_caveats": len(clean),
		"level_db_median": pct([r["level_db"] for r in rows], 50),
		"env_err_db": {"median": pct([r["env_err_db"] for r in rows], 50), "p90": pct([r["env_err_db"] for r in rows], 90)},
		"spec_err_db": {"median": pct([r["spec_err_db"] for r in rows], 50), "p90": pct([r["spec_err_db"] for r in rows], 90)},
		"clean_spec_err_db": {"median": pct([r["spec_err_db"] for r in clean], 50), "p90": pct([r["spec_err_db"] for r in clean], 90)},
		"clean_env_err_db": {"median": pct([r["env_err_db"] for r in clean], 50), "p90": pct([r["env_err_db"] for r in clean], 90)},
		"rows": rows}
	(lib / "gak_synth1_summary.json").write_text(json.dumps(summ, indent=2) + "\n", encoding="utf-8")
	print("%d patches (%d without caveats): level %s dB (median); envelope error median %s, p90 %s dB; "
		"spectral error median %s, p90 %s dB; without caveats: envelope %s, spectral %s dB" % (
		len(rows), len(clean), summ["level_db_median"], summ["env_err_db"]["median"], summ["env_err_db"]["p90"],
		summ["spec_err_db"]["median"], summ["spec_err_db"]["p90"], summ["clean_env_err_db"]["median"],
		summ["clean_spec_err_db"]["median"]))


if __name__ == "__main__":
	main()
