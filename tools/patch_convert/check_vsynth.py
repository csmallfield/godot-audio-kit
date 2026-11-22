# SPDX-License-Identifier: Apache-2.0
"""Compares each converted TAL-NoiseMaker, Helm or OB-Xd/OB-Xf patch's GAK render with the synth's own.

    D:\\tools\\dawdreamer\\venv\\Scripts\\python.exe -I tools/patch_convert/check_vsynth.py <tal|helm|obxf> [library] [--list file]

Needs render_<synth>_v100.wav (render_vsynth.py) and gak_render_v100.wav with gak_convert.json
(vsynth_batch.gd) beside each sidecar. The metrics are check_synth1.py's, per note (its hold
and release): level_db (GAK against the synth, median over 10 ms frames), env_err_db (the
loudness envelope's mean error once that level is out), spec_err_db (the spectral shape's mean
error across third-octave bands, per frame, each frame's level out); all floored 60 dB under
the reference's peak. Writes gak_report.json beside each patch and gak_<synth>_summary.json in
the library.
"""
import json
import pathlib
import sys

import numpy as np

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from check_synth1 import compare, pct, read16  # noqa: E402

LIBS = {"tal": "D:/12_library/gak/processed_tal", "helm": "D:/12_library/gak/processed_helm",
	"obxf": "D:/12_library/gak/processed_obx"}


def row_of(synth, sc, rep):
	c = sc["content"][synth]
	return {"id": sc.get("id"), "name": c.get("name"), "error": rep.get("error"),
		"level_db": rep.get("level_db_median"), "env_err_db": rep.get("env_err_db_median"),
		"spec_err_db": rep.get("spec_err_db_median"), "spec_err_db_worst": rep.get("spec_err_db_worst"),
		"caveats": rep.get("caveats", []), "features": c.get("features", [])}


def check(synth, folder):
	sc = json.loads((folder / "instrument.json").read_text(encoding="utf-8"))
	c = sc.get("content", {})
	st = c.get("render_" + synth)
	conv_path = folder / "gak_convert.json"
	if not st or not conv_path.is_file():
		return None
	conv = json.loads(conv_path.read_text(encoding="utf-8"))
	if conv.get("scale") is None:
		rep = {"converter": conv["converter"], "error": "GAK render not finite (NaN)", "caveats": conv.get("caveats", [])}
		(folder / "gak_report.json").write_text(json.dumps(rep, indent=2) + "\n", encoding="utf-8")
		return row_of(synth, sc, rep)
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

	def med(k):
		v = [x[k] for x in sounding if x.get(k) is not None]
		return round(float(np.median(v)), 2) if v else None

	def worst(k):
		v = [abs(x[k]) for x in sounding if x.get(k) is not None]
		return round(float(max(v)), 2) if v else None

	rep = {"converter": conv["converter"], "engine": conv["engine"], "reference": st["files"][0]["file"],
		"notes": notes, "level_db_median": med("level_db"), "env_err_db_median": med("env_err_db"),
		"spec_err_db_median": med("spec_err_db"), "env_err_db_worst": worst("env_err_db"),
		"spec_err_db_worst": worst("spec_err_db"), "caveats": conv.get("caveats", [])}
	(folder / "gak_report.json").write_text(json.dumps(rep, indent=2) + "\n", encoding="utf-8")
	return row_of(synth, sc, rep)


def main():
	args = sys.argv[1:]
	synth = args.pop(0)
	listed = None
	if "--list" in args:
		i = args.index("--list")
		listed = [pathlib.Path(x.strip().removesuffix("instrument.json"))
			for x in pathlib.Path(args[i + 1]).read_text(encoding="utf-8").splitlines() if x.strip()]
		del args[i:i + 2]
	lib = pathlib.Path(args[0] if args else LIBS[synth])
	folders = listed if listed is not None else sorted(p.parent for p in lib.rglob("instrument.json"))
	rows = [r for r in (check(synth, f) for f in folders) if r]
	clean = [r for r in rows if not r["caveats"]]
	summ = {"patches": len(rows), "without_caveats": len(clean),
		"level_db_median": pct([r["level_db"] for r in rows], 50),
		"env_err_db": {"median": pct([r["env_err_db"] for r in rows], 50), "p90": pct([r["env_err_db"] for r in rows], 90)},
		"spec_err_db": {"median": pct([r["spec_err_db"] for r in rows], 50), "p90": pct([r["spec_err_db"] for r in rows], 90)},
		"clean_spec_err_db": {"median": pct([r["spec_err_db"] for r in clean], 50), "p90": pct([r["spec_err_db"] for r in clean], 90)},
		"clean_env_err_db": {"median": pct([r["env_err_db"] for r in clean], 50), "p90": pct([r["env_err_db"] for r in clean], 90)},
		"rows": rows}
	if listed is None:
		(lib / ("gak_%s_summary.json" % synth)).write_text(json.dumps(summ, indent=2) + "\n", encoding="utf-8")
	print("%d patches (%d without caveats): level %s dB (median); envelope error median %s, p90 %s dB; "
		"spectral error median %s, p90 %s dB; without caveats: envelope %s, spectral %s dB" % (
		len(rows), len(clean), summ["level_db_median"], summ["env_err_db"]["median"], summ["env_err_db"]["p90"],
		summ["spec_err_db"]["median"], summ["spec_err_db"]["p90"], summ["clean_env_err_db"]["median"],
		summ["clean_spec_err_db"]["median"]))


if __name__ == "__main__":
	main()
