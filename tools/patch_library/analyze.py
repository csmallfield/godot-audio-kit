"""Measure every patch in the library (docs/plans/patch-library.md, Analysis):

    python tools/patch_library/analyze.py [--library D:/12_library/gak/library] [--jobs 12] [--chunk 1000]
        [--limit n] [--godot path] [--tags-only]

Renders each patch through GAK (render_batch.gd: notes 36, 60 and 84, each held 2 s and released for
1.5 s), measures the renders with numpy (envelope, brightness and its movement, noise, harmonicity,
low end, pitch and level movement, onsets), and keeps the measurements with the patch's settings in
<library>/analysis/features.json, by patch ID, with the patch file's hash and the renderer's version:
a rerun measures only new or changed patches. Renders go to a temporary folder a chunk at a time and
are deleted once measured; features.json is written after every chunk, so a stopped run resumes.
Descriptive tags come from the thresholds in tags.json; --tags-only reapplies them without rendering.
Then run index.py to put the tags (and, after classify.py, the categories) into the index.
"""
import argparse
import hashlib
import json
import os
import shutil
import subprocess
import sys
import tempfile
import time

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(os.path.dirname(HERE))
GODOT = "D:/08_godot/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64_console.exe"
RENDERER = 1          # render_batch.gd's layout; bump to re-render everything
MEASURE = 4           # this file's measurements; bump to re-measure (needs renders again)
SR = 24000
NOTES = [36, 60, 84]
HOLD_S = 2.0
NOTE_S = 3.5
NOTE_N = int(NOTE_S * SR)


def hz(note):
	return 440.0 * 2.0 ** ((note - 69) / 12.0)


def db(x):
	return 20.0 * np.log10(np.maximum(x, 1e-9))


def frames_rms(x, hop=240, win=480):
	n = max(1, (len(x) - win) // hop + 1)
	idx = np.arange(win)[None, :] + hop * np.arange(n)[:, None]
	return np.sqrt(np.mean(x[idx] ** 2, axis=1))


def autocorr_f0(seg, f_lo=30.0, f_hi=2000.0):
	"""(f0, clarity): the strongest normalised autocorrelation peak's lag, and its height (0..1)."""
	seg = seg - np.mean(seg)
	if np.max(np.abs(seg)) < 1e-6:
		return 0.0, 0.0
	n = len(seg)
	spec = np.fft.rfft(seg, 2 * n)
	ac = np.fft.irfft(spec * np.conj(spec))[:n]
	ac /= ac[0] + 1e-12
	lo, hi = max(2, int(SR / f_hi)), min(n - 1, int(SR / f_lo))
	if hi <= lo:
		return 0.0, 0.0
	k = lo + int(np.argmax(ac[lo:hi]))
	# Between samples: a parabola through the peak and its neighbours (whole-sample lags step about
	# 19 cents at middle C).
	lag = float(k)
	if 0 < k < n - 1:
		a, b, c = ac[k - 1], ac[k], ac[k + 1]
		den = a - 2.0 * b + c
		if abs(den) > 1e-12:
			lag = k + 0.5 * (a - c) / den
	return (float(SR / lag) if lag > 0 else 0.0), float(ac[k])


def measure_note(x, note):
	"""One note's measurements: the held part (0..2 s) and the release (2..3.5 s)."""
	m = {}
	env = frames_rms(x)                       # 10 ms frames
	t = np.arange(len(env)) * 0.01
	peak = float(np.max(env)) if len(env) else 0.0
	m["peak_db"] = float(db(peak))
	if peak < 1e-5:
		m["silent"] = True
		return m
	m["silent"] = False
	pk = int(np.argmax(env))
	start = int(np.argmax(env > peak * 0.001))  # -60 dB under the peak
	reach = int(np.argmax(env >= peak * 0.9))
	m["attack_s"] = float(max(0.0, t[reach] - t[start]))
	m["peak_s"] = float(t[pk])
	def level_at(s):
		i = min(len(env) - 1, int(s / 0.01))
		return float(db(env[i] / peak))
	m["lvl_05"] = level_at(0.5)
	m["lvl_10"] = level_at(1.0)
	m["lvl_hold"] = level_at(HOLD_S - 0.05)
	# Release: from note-off until 40 dB under the level there (or the end).
	off = int(HOLD_S / 0.01)
	ref = env[max(0, off - 1)]
	tail = env[off:]
	if ref < peak * 0.001:
		m["release_s"] = 0.0
	else:
		below = np.nonzero(tail < ref * 0.01)[0]
		m["release_s"] = float(below[0] * 0.01) if len(below) else NOTE_S - HOLD_S
	# Spectrum over the held part (skipping the first 50 ms), frames of 2048.
	hold = x[int(0.05 * SR):int(HOLD_S * SR)]
	n_fft, hop = 2048, 1024
	nfr = max(1, (len(hold) - n_fft) // hop + 1)
	win = np.hanning(n_fft)
	idx = np.arange(n_fft)[None, :] + hop * np.arange(nfr)[:, None]
	mag = np.abs(np.fft.rfft(hold[idx] * win, axis=1)) + 1e-12
	freqs = np.fft.rfftfreq(n_fft, 1.0 / SR)
	power = mag ** 2
	tot = power.sum(axis=1)
	live = tot > tot.max() * 1e-4
	if not np.any(live):
		live = tot >= 0
	# Brightness weighs each frequency by its magnitude (by power, the fundamental would decide it).
	amag = mag.sum(axis=1)
	cent = (mag * freqs).sum(axis=1) / amag
	m["centroid_hz"] = float(np.median(cent[live]))
	lc = np.log2(np.maximum(cent[live], 20.0))
	m["centroid_move"] = float(np.percentile(lc, 90) - np.percentile(lc, 10)) if len(lc) > 2 else 0.0
	flat = np.exp(np.mean(np.log(power), axis=1)) / np.mean(power, axis=1)
	m["flatness"] = float(np.median(flat[live]))
	m["low_share"] = float(np.median((power[:, freqs < 120.0].sum(axis=1) / tot)[live]))
	m["high_share"] = float(np.median((power[:, freqs > 4000.0].sum(axis=1) / tot)[live]))
	# Harmonicity: the share of power within 40 cents of a harmonic of the detected pitch.
	# Where the note is loud: just after its peak (a short sound is silent by 0.3 s).
	a0 = int(min(max(t[pk] + 0.03, 0.05), HOLD_S - 0.2) * SR)
	seg = x[a0:a0 + 4096]
	f0, clarity = autocorr_f0(seg)
	m["f0_hz"] = f0
	m["clarity"] = clarity
	if f0 > 0:
		avg = power[live].mean(axis=0)
		hn = np.round(freqs / f0)
		near = (hn >= 1) & (np.abs(1200.0 * np.log2(np.maximum(freqs, 1.0) / np.maximum(hn * f0, 1.0))) < 40.0)
		m["harmonic_share"] = float(avg[near].sum() / avg.sum())
		m["f0_ratio"] = float(f0 / hz(note))
	else:
		m["harmonic_share"] = None
		m["f0_ratio"] = 0.0
	# The spectrum's shape: octave bands (63 Hz .. 8 kHz) as log shares of the held part's power, and
	# the first 12 harmonics of the note's pitch in the held part and in the first 80 ms (dB under the
	# strongest), which tell organs, brass, strings and the rest apart.
	avg_p = power[live].mean(axis=0)
	bands = []
	for lo in (44.0, 88.0, 177.0, 354.0, 707.0, 1414.0, 2828.0, 5657.0):
		sel = (freqs >= lo) & (freqs < 2 * lo)
		bands.append(float(np.log10(avg_p[sel].sum() / avg_p.sum() + 1e-6)))
	m["bands"] = bands
	fh = f0 if f0 > 0 and 0.2 < m.get("f0_ratio", 0) < 5 else hz(note)
	def harmonics(spec):
		hs = []
		for h in range(1, 13):
			fq = h * fh
			if fq >= SR / 2 - 200:
				hs.append(-80.0)
				continue
			i = int(round(fq / (SR / n_fft)))
			hs.append(float(db(np.sqrt(spec[max(0, i - 2):i + 3].max()))))
		top = max(hs)
		return [round(max(-80.0, v - top), 2) for v in hs]
	m["harm"] = harmonics(avg_p)
	a_seg = x[start * 240:start * 240 + n_fft]
	if len(a_seg) == n_fft:
		a_spec = np.abs(np.fft.rfft(a_seg * win)) ** 2 + 1e-12
		m["harm_attack"] = harmonics(a_spec)
		m["centroid_attack_hz"] = float((np.sqrt(a_spec) * freqs).sum() / np.sqrt(a_spec).sum())
	else:
		m["harm_attack"] = m["harm"]
		m["centroid_attack_hz"] = m["centroid_hz"]
	# How fast it falls over the first second after its peak (dB a second; 0 when it holds).
	e1 = env[pk:pk + 100]
	m["decay_db_s"] = float((db(e1[0]) - db(e1[-1])) / max(0.01, len(e1) * 0.01)) if len(e1) > 10 else 0.0

	# Pitch movement over the hold (autocorrelation pitch in 40 ms windows every 20 ms).
	if clarity > 0.5 and f0 > 0:
		pitches = []
		for s in np.arange(0.1, HOLD_S - 0.05, 0.02):
			a = int(s * SR)
			fx, cl = autocorr_f0(x[a:a + 960], f0 / 1.5, f0 * 1.5)
			if cl > 0.4 and fx > 0:
				pitches.append(1200.0 * np.log2(fx / f0))
		p = np.array(pitches)
		if len(p) > 20:
			m["pitch_spread_cents"] = float(np.percentile(p, 90) - np.percentile(p, 10))
			d = p - np.mean(p)
			sp = np.abs(np.fft.rfft(d * np.hanning(len(d))))
			f = np.fft.rfftfreq(len(d), 0.02)
			band = (f >= 3.0) & (f <= 9.0)
			m["vibrato"] = float(sp[band].max() / (sp[1:].mean() + 1e-9)) if np.any(band) else 0.0
		else:
			m["pitch_spread_cents"] = 0.0
			m["vibrato"] = 0.0
	else:
		m["pitch_spread_cents"] = 0.0
		m["vibrato"] = 0.0
	# Level movement and onsets during the hold.
	he = env[int(0.2 / 0.01):off]
	if len(he) > 10 and he.max() > peak * 0.001:
		hd = db(he / peak)
		rises = np.nonzero((hd[5:] - hd[:-5]) > 6.0)[0]
		onsets = 0
		last = -100
		for r in rises:
			if r - last > 8:
				onsets += 1
			last = r
		m["onsets"] = int(onsets)
		m["level_move_db"] = float(np.percentile(hd, 90) - np.percentile(hd, 10))
	else:
		m["onsets"] = 0
		m["level_move_db"] = 0.0
	return m


def measure(raw_path):
	x = np.fromfile(raw_path, dtype="<i2").astype(np.float32) / 32768.0
	notes = {}
	for i, n in enumerate(NOTES):
		notes[str(n)] = measure_note(x[i * NOTE_N:(i + 1) * NOTE_N], n)
	return notes


def file_sha(path):
	with open(path, "rb") as f:
		return hashlib.sha256(f.read()).hexdigest()[:16]


def library_patches(library):
	out = []
	for source in sorted(os.listdir(library)):
		top = os.path.join(library, source)
		if not os.path.isdir(top) or source == "analysis":
			continue
		for bank in sorted(os.listdir(top)):
			bdir = os.path.join(top, bank)
			if not os.path.isdir(bdir):
				continue
			for fn in sorted(os.listdir(bdir)):
				if fn.endswith(".json"):
					tres = os.path.join(bdir, fn[:-5] + ".tres")
					if os.path.exists(tres):
						with open(os.path.join(bdir, fn), encoding="utf-8") as f:
							pid = json.load(f)["id"]
						out.append((pid, tres))
	return out


def load_features(path):
	if os.path.exists(path):
		with open(path, encoding="utf-8") as f:
			return json.load(f)
	return {"renderer": RENDERER, "measure": MEASURE, "patches": {}}


def save_features(path, data):
	os.makedirs(os.path.dirname(path), exist_ok=True)
	tmp = path + ".tmp"
	with open(tmp, "w", encoding="utf-8", newline="\n") as f:
		json.dump(data, f, separators=(",", ":"), sort_keys=True)
	os.replace(tmp, path)


# ------------------------------------------------------------------ tags

def apply_tags(entry, rules):
	"""Descriptive tags from one patch's measurements and settings, by the thresholds in tags.json."""
	notes = entry.get("notes") or {}
	mid = notes.get("60") or {}
	low = notes.get("36") or {}
	prm = entry.get("params") or {}
	if not mid or mid.get("silent", True):
		return ["silent"] if mid.get("silent") else []
	tags = []
	r = rules
	if mid.get("lvl_10", 0) < r["short_lvl_10_db"] and mid.get("release_s", 0) < r["short_release_s"]:
		tags.append("short")
	if mid.get("release_s", 0) >= r["long_release_s"] or (mid.get("lvl_hold", -99) > r["long_hold_db"] and mid.get("release_s", 0) >= r["long_release_hold_s"]):
		tags.append("long")
	if mid.get("attack_s", 0) >= r["slow_attack_s"]:
		tags.append("slow-attack")
	if mid.get("centroid_hz", 0) >= r["bright_centroid_hz"]:
		tags.append("bright")
	elif mid.get("centroid_hz", 1e9) <= r["dark_centroid_hz"]:
		tags.append("dark")
	if mid.get("centroid_move", 0) >= r["evolving_octaves"] or mid.get("level_move_db", 0) >= r["evolving_level_db"]:
		tags.append("evolving")
	if mid.get("flatness", 0) >= r["noisy_flatness"] or prm.get("noise_share", 0) >= r["noisy_share"]:
		tags.append("noisy")
	hs = mid.get("harmonic_share")
	if hs is not None and hs <= r["metallic_harmonic_share"] and mid.get("clarity", 0) > 0.2 and mid.get("flatness", 1) < r["noisy_flatness"]:
		tags.append("metallic")
	if prm.get("fm", 0) >= r["fm_index"]:
		tags.append("fm")
	# Detuned unison or a chorus (the Synth1 converter writes stacks even when they aren't detuned).
	if (prm.get("unison", 1) > 1 and prm.get("detune", 0) >= r["wide_detune_cents"]) or prm.get("chorus", 0) > 0:
		tags.append("wide")
	if low.get("low_share", 0) >= r["sub_low_share_36"] and mid.get("low_share", 0) >= r["sub_low_share_60"]:
		tags.append("sub-heavy")
	if mid.get("onsets", 0) >= r["gated_onsets"]:
		tags.append("gated")
	if mid.get("vibrato", 0) >= r["vibrato_peak"] and mid.get("pitch_spread_cents", 0) >= r["vibrato_cents"]:
		tags.append("vibrato")
	if prm.get("mono"):
		tags.append("mono")
	if prm.get("arp"):
		tags.append("arp")
	return tags


def retag(data):
	with open(os.path.join(HERE, "tags.json"), encoding="utf-8") as f:
		rules = json.load(f)["thresholds"]
	for e in data["patches"].values():
		e["tags"] = apply_tags(e, rules)


# ------------------------------------------------------------------ driver

def main():
	ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
	ap.add_argument("--library", default="D:/12_library/gak/library")
	ap.add_argument("--jobs", type=int, default=12)
	ap.add_argument("--chunk", type=int, default=1000)
	ap.add_argument("--limit", type=int, default=0, help="measure at most this many patches (a trial run)")
	ap.add_argument("--godot", default=GODOT)
	ap.add_argument("--tags-only", action="store_true")
	a = ap.parse_args()
	fpath = os.path.join(a.library, "analysis", "features.json")
	data = load_features(fpath)
	if data.get("renderer") != RENDERER or data.get("measure") != MEASURE:
		data = {"renderer": RENDERER, "measure": MEASURE, "patches": {}}
	patches = library_patches(a.library)
	ids = {pid for pid, _ in patches}
	# Forget patches no longer in the library.
	for pid in list(data["patches"]):
		if pid not in ids:
			del data["patches"][pid]
	if a.tags_only:
		retag(data)
		save_features(fpath, data)
		print("retagged %d patches" % len(data["patches"]))
		return
	todo = []
	for pid, tres in patches:
		sha = file_sha(tres)
		e = data["patches"].get(pid)
		if not e or e.get("sha") != sha:
			todo.append((pid, tres, sha))
	if a.limit:
		todo = todo[:a.limit]
	print("%d patches, %d to measure" % (len(patches), len(todo)), flush=True)
	with open(os.path.join(HERE, "tags.json"), encoding="utf-8") as f:
		rules = json.load(f)["thresholds"]
	t0 = time.time()
	for c in range(0, len(todo), a.chunk):
		chunk = todo[c:c + a.chunk]
		tmp = tempfile.mkdtemp(prefix="gak_analysis_")
		try:
			lst = os.path.join(tmp, "list.txt")
			with open(lst, "w", encoding="utf-8", newline="\n") as f:
				for pid, tres, _ in chunk:
					f.write("%s\t%s\n" % (pid, tres.replace("\\", "/")))
			procs = []
			jobs = max(1, min(a.jobs, len(chunk)))
			for part in range(jobs):
				procs.append(subprocess.Popen([a.godot, "--headless", "--path", REPO, "--script",
					"res://tools/patch_library/render_batch.gd", "--", lst, tmp, "%d/%d" % (part, jobs)],
					stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL))
			for p in procs:
				p.wait()
			sha_of = {pid: sha for pid, _, sha in chunk}
			done = 0
			for part in range(jobs):
				mp = os.path.join(tmp, "meta_%d.jsonl" % part)
				if not os.path.exists(mp):
					continue
				with open(mp, encoding="utf-8") as f:
					for line in f:
						row = json.loads(line)
						if "file" not in row:
							continue
						rp = os.path.join(tmp, row["file"])
						if not os.path.exists(rp):
							continue
						try:
							notes = measure(rp)
						except (ValueError, ZeroDivisionError, FloatingPointError, IndexError) as err:
							print("couldn't measure %s: %s" % (row["id"], err), flush=True)
							os.remove(rp)
							continue
						e = {"sha": sha_of.get(row["id"], ""), "params": row["params"], "notes": notes}
						e["tags"] = apply_tags(e, rules)
						data["patches"][row["id"]] = e
						done += 1
						os.remove(rp)
			save_features(fpath, data)
			el = time.time() - t0
			print("chunk %d: %d measured (%d/%d, %.0f s so far)" % (c // a.chunk + 1, done, c + len(chunk), len(todo), el), flush=True)
		finally:
			shutil.rmtree(tmp, ignore_errors=True)
	print("features for %d patches in %s" % (len(data["patches"]), fpath))


if __name__ == "__main__":
	main()
