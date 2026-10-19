#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Measure a review render so sound can be checked without listening.

    python3 tools/analyze/analyze.py out/review/race_ident [--target-lufs -16] [--tolerance 1]

Reads mix.wav, stems/ and render.json (written by addons/audio_kit/tools/review.gd)
and writes report.json, report.md, spectrogram.png and cues.png next to them.
Exit code 1 when a check fails. Needs numpy, scipy and matplotlib.
"""
import argparse, json, math, os, sys
import numpy as np
from scipy.io import wavfile
from scipy import signal

SILENT_DBFS = -60.0
ONSET_THRESHOLD = 1e-4          # first sample above this is the onset (-80 dBFS)
ALIGN_TOLERANCE_MS = 1.0
PERCEIVED_NOTE_MS = 30.0
CLUTTER_MS = 40.0


def read(path):
    sr, x = wavfile.read(path)
    if x.dtype == np.int16:
        x = x.astype(np.float64) / 32768.0
    elif x.dtype == np.int32:
        x = x.astype(np.float64) / 2147483648.0
    else:
        x = x.astype(np.float64)
    if x.ndim == 1:
        x = x[:, None]
    return sr, x


def db(v):
    return 20.0 * math.log10(v) if v > 0 else -math.inf


# ---------------------------------------------------------------- loudness (ITU-R BS.1770-4)

def _biquad_shelf(sr):
    f0, G, Q = 1681.974450955533, 3.999843853973347, 0.7071752369554196
    K = math.tan(math.pi * f0 / sr)
    Vh = 10 ** (G / 20)
    Vb = Vh ** 0.4996667741545416
    a0 = 1 + K / Q + K * K
    b = [(Vh + Vb * K / Q + K * K) / a0, 2 * (K * K - Vh) / a0, (Vh - Vb * K / Q + K * K) / a0]
    a = [1.0, 2 * (K * K - 1) / a0, (1 - K / Q + K * K) / a0]
    return b, a


def _biquad_hp(sr):
    f0, Q = 38.13547087602444, 0.5003270373238773
    K = math.tan(math.pi * f0 / sr)
    a0 = 1 + K / Q + K * K
    b = [1.0, -2.0, 1.0]
    a = [1.0, 2 * (K * K - 1) / a0, (1 - K / Q + K * K) / a0]
    return b, a


def integrated_lufs(x, sr):
    b1, a1 = _biquad_shelf(sr)
    b2, a2 = _biquad_hp(sr)
    y = signal.lfilter(b2, a2, signal.lfilter(b1, a1, x, axis=0), axis=0)
    block, step = int(0.4 * sr), int(0.1 * sr)
    if len(y) < block:
        z = np.mean(np.sum(y ** 2, axis=0) / max(1, len(y)))
        return -0.691 + 10 * math.log10(max(z * y.shape[1], 1e-12)) if z > 0 else -math.inf
    zs = np.array([np.sum(np.mean(y[i:i + block] ** 2, axis=0)) for i in range(0, len(y) - block + 1, step)])
    ls = -0.691 + 10 * np.log10(np.maximum(zs, 1e-12))
    zs = zs[ls > -70.0]
    if len(zs) == 0:
        return -math.inf
    rel = -0.691 + 10 * math.log10(np.mean(zs)) - 10.0
    zs2 = zs[(-0.691 + 10 * np.log10(zs)) > rel]
    return -0.691 + 10 * math.log10(np.mean(zs2 if len(zs2) else zs))


def true_peak(x):
    return float(np.max(np.abs(signal.resample_poly(x, 4, 1, axis=0)))) if len(x) else 0.0


# ---------------------------------------------------------------- per cue

def rms_env(m, sr, win_s=0.005):
    w = max(1, int(win_s * sr))
    return np.sqrt(np.convolve(m ** 2, np.ones(w) / w, mode="same"))


def measure_cues(out, cues, sr, mix):
    stems = {}
    rows = []
    for c in cues:
        if c.get("missing"):
            rows.append({"name": c["name"], "time": c["time"], "missing": True})
            continue
        path = os.path.join(out, c.get("stem", "mix.wav"))
        if path not in stems:
            stems[path] = read(path)[1].mean(axis=1) if os.path.exists(path) else mix.mean(axis=1)
        m = stems[path]
        start = int(c["sample"])
        n = int(c["frames"])
        pre = max(0, start - int(0.002 * sr))
        row = {"name": c["name"], "time": round(c["time"], 4), "intensity": c.get("intensity", 1.0)}
        if start >= len(m):
            row["note"] = "starts after the end of the render"
            rows.append(row)
            continue
        if np.max(np.abs(m[pre:max(pre + 1, start)])) > ONSET_THRESHOLD:
            row["alignment_ms"] = None
            row["note"] = "overlaps the previous hit; onset not measured"
        else:
            seg = np.abs(m[start:start + n])
            above = np.nonzero(seg > ONSET_THRESHOLD)[0]
            lead = int(c.get("lead_in", 0))
            row["lead_in_ms"] = round(lead / sr * 1000.0, 2)
            # Placement error: where the hit starts in the mix minus where it starts in its own render.
            row["alignment_ms"] = round((float(above[0]) - lead) / sr * 1000.0, 3) if len(above) else None
        seg = m[start:start + n]
        if len(seg):
            env = rms_env(seg, sr)
            pk = int(np.argmax(env))
            cue_sample = int(c["cue_sample"])
            row["perceived_ms"] = round((start + pk - cue_sample) / sr * 1000.0, 1)
            row["peak_dbfs"] = round(db(float(np.max(np.abs(seg)))), 1)
        rows.append(row)
    return rows


def clutter(cues):
    hits = sorted((c["time"], c["name"]) for c in cues if not c.get("missing"))
    out = []
    for (t1, n1), (t2, n2) in zip(hits, hits[1:]):
        if (t2 - t1) * 1000.0 < CLUTTER_MS:
            out.append({"a": n1, "b": n2, "time": round(t1, 3), "gap_ms": round((t2 - t1) * 1000.0, 1)})
    return out


# ---------------------------------------------------------------- pictures

def pictures(out, mix, sr, cues, duration):
    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.pyplot as plt
    m = mix.mean(axis=1)
    if len(m) < 1024:
        return
    bg, fg, grid = "#111418", "#d8dde3", "#2a3038"

    def spec(ax, x, t0=0.0, nper=1024):
        f, t, S = signal.spectrogram(x, sr, nperseg=nper, noverlap=nper * 3 // 4, scaling="spectrum")
        S = 10 * np.log10(np.maximum(S, 1e-12))
        ax.pcolormesh(t + t0, f, S, shading="auto", cmap="magma", vmin=S.max() - 90, vmax=S.max())
        ax.set_yscale("symlog", linthresh=500)
        ax.set_ylim(20, sr / 2)
        ax.set_facecolor(bg)
        ax.tick_params(colors=fg, labelsize=7)
        for s in ax.spines.values():
            s.set_color(grid)

    fig = plt.figure(figsize=(14, 6), facecolor=bg)
    ax0 = fig.add_axes([0.05, 0.72, 0.93, 0.2], facecolor=bg)
    t = np.arange(len(m)) / sr
    ax0.plot(t, mix[:, 0], color="#7fd1ff", lw=0.4)
    ax0.set_xlim(0, t[-1])
    ax0.set_ylim(-1, 1)
    ax0.tick_params(colors=fg, labelsize=7, labelbottom=False)
    for s in ax0.spines.values():
        s.set_color(grid)
    ax0.set_title(os.path.basename(os.path.normpath(out)) + " · waveform (L) and spectrogram", color=fg, fontsize=10, loc="left")
    ax1 = fig.add_axes([0.05, 0.08, 0.93, 0.6])
    spec(ax1, m)
    ax1.set_xlim(0, t[-1])
    ax1.set_xlabel("seconds", color=fg, fontsize=8)
    ax1.set_ylabel("Hz", color=fg, fontsize=8)
    for i, c in enumerate(cues):
        if c.get("missing"):
            continue
        for a in (ax0, ax1):
            a.axvline(c["time"], color="#8eef97", lw=0.7, alpha=0.8)
        ax1.text(c["time"], sr / 2 * 0.8, " " + c["name"], color="#8eef97", fontsize=7, rotation=90, va="top")
    if duration:
        for a in (ax0, ax1):
            a.axvline(duration, color="#ff6b6b", lw=1.0, ls="--")
    fig.savefig(os.path.join(out, "spectrogram.png"), dpi=110, facecolor=bg)
    plt.close(fig)

    shown = [c for c in cues if not c.get("missing")][:24]
    if not shown:
        return
    cols = min(6, len(shown))
    rows = math.ceil(len(shown) / cols)
    fig, axs = plt.subplots(rows, cols, figsize=(2.4 * cols, 2.0 * rows), facecolor=bg, squeeze=False)
    for ax in axs.flat:
        ax.set_visible(False)
    for ax, c in zip(axs.flat, shown):
        ax.set_visible(True)
        a = max(0, int((c["time"] - 0.05) * sr))
        b = min(len(m), int(c["sample"]) + min(int(c["frames"]), sr))
        if b - a > 300:
            spec(ax, m[a:b], a / sr, 256)   # short window: onsets smear less than 3 ms
        ax.axvline(c["time"], color="#8eef97", lw=0.8)
        ax.set_title("%s @ %.2fs" % (c["name"], c["time"]), color=fg, fontsize=8)
    fig.tight_layout()
    fig.savefig(os.path.join(out, "cues.png"), dpi=100, facecolor=bg)
    plt.close(fig)


# ---------------------------------------------------------------- report

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("out")
    ap.add_argument("--target-lufs", type=float, default=-16.0)
    ap.add_argument("--tolerance", type=float, default=1.0)
    a = ap.parse_args()
    out = a.out
    render = json.load(open(os.path.join(out, "render.json")))
    sr, mix = read(os.path.join(out, "mix.wav"))
    cues = render.get("cues", [])
    mode = render.get("mode", "cues")
    fps = float(render.get("fps", 30.0))
    duration = float(render.get("duration", 0.0)) if mode == "cues" else 0.0

    lufs = integrated_lufs(mix, sr)
    tp = true_peak(mix)
    sp = float(np.max(np.abs(mix))) if len(mix) else 0.0
    clips = int(np.sum(np.abs(mix) >= 0.9999))
    dc = [round(float(v), 5) for v in mix.mean(axis=0)]
    rows = measure_cues(out, cues, sr, mix)
    clut = clutter(cues)

    checks = []

    def check(name, ok, value, rule):
        checks.append({"check": name, "status": ("pass" if ok else "FAIL") if ok is not None else "info", "value": value, "rule": rule})

    if mode in ("cues", "song"):
        check("Integrated loudness", abs(lufs - a.target_lufs) <= a.tolerance, "%.1f LUFS" % lufs, "%.0f ±%.0f LUFS" % (a.target_lufs, a.tolerance))
    else:
        check("Integrated loudness", None, "%.1f LUFS" % lufs, "reported (single recipe)")
    check("True peak", db(tp) <= -1.0 + 1e-6, "%.2f dBTP" % db(tp), "≤ −1 dBTP")
    check("Clipping", clips == 0, "%d samples" % clips, "none")
    check("DC offset", max(abs(v) for v in dc) < 0.001, str(dc), "< 0.001")
    measured = [r for r in rows if r.get("alignment_ms") is not None]
    worst = max((abs(r["alignment_ms"]) for r in measured), default=0.0)
    check("Cue alignment", worst <= ALIGN_TOLERANCE_MS, "worst %.3f ms over %d hits" % (worst, len(measured)), "≤ %.0f ms" % ALIGN_TOLERANCE_MS)
    late = [r for r in rows if r.get("perceived_ms", 0) > PERCEIVED_NOTE_MS]
    check("Perceived onset", None, "%d hits peak later than %.0f ms" % (len(late), PERCEIVED_NOTE_MS), "reported")
    check("Clutter", None, "%d pairs within %.0f ms" % (len(clut), CLUTTER_MS), "reported")
    if duration > 0:
        n0 = int((duration - 1.0 / fps) * sr)
        n1 = int(duration * sr)
        last = mix[n0:n1]
        lr = db(float(np.sqrt(np.mean(last ** 2)))) if len(last) else -math.inf
        check("Clean ending", lr <= SILENT_DBFS, "last frame %.1f dBFS" % lr, "≤ %.0f dBFS" % SILENT_DBFS)
        over = len(mix) / sr - duration
        if over > 1e-3:
            check("Tail past picture", None, "%.2f s" % over, "reported")
    missing = [r["name"] for r in rows if r.get("missing")]
    if missing:
        check("Unmapped cues", False, ", ".join(sorted(set(missing))), "every cue has a recipe")

    failed = [c for c in checks if c["status"] == "FAIL"]
    report = {"render": {k: v for k, v in render.items() if k != "cues"}, "sample_rate": sr,
              "length_s": round(len(mix) / sr, 3), "lufs": round(lufs, 2), "true_peak_dbtp": round(db(tp), 2),
              "sample_peak_dbfs": round(db(sp), 2), "checks": checks, "cues": rows, "clutter": clut,
              "status": "FAIL" if failed else "pass"}
    json.dump(report, open(os.path.join(out, "report.json"), "w"), indent=2)

    md = ["# Review: %s" % os.path.basename(os.path.normpath(out)), "",
          "**%s** · %.2f s at %d Hz · %.1f LUFS · %.2f dBTP" % (report["status"].upper(), len(mix) / sr, sr, lufs, db(tp)), "",
          "| Check | Status | Value | Rule |", "| --- | --- | --- | --- |"]
    md += ["| %s | %s | %s | %s |" % (c["check"], c["status"], c["value"], c["rule"]) for c in checks]
    md += ["", "| Cue | Time s | Intensity | Placement error ms | Lead-in ms | Peak at ms | Peak dBFS | Note |", "| --- | --- | --- | --- | --- | --- | --- | --- |"]
    for r in rows:
        md.append("| %s | %s | %s | %s | %s | %s | %s | %s |" % (r["name"], r.get("time", ""), r.get("intensity", ""),
                  "" if r.get("alignment_ms") is None else r["alignment_ms"], r.get("lead_in_ms", ""), r.get("perceived_ms", ""),
                  r.get("peak_dbfs", ""), "missing recipe" if r.get("missing") else r.get("note", "")))
    if clut:
        md += ["", "Close pairs: " + "; ".join("%s + %s at %.2fs (%.0f ms)" % (c["a"], c["b"], c["time"], c["gap_ms"]) for c in clut)]
    md += ["", "Timing and level are measured; whether it sounds right is a listening call."]
    open(os.path.join(out, "report.md"), "w").write("\n".join(md) + "\n")

    try:
        pictures(out, mix, sr, cues, duration)
    except Exception as e:  # pictures are a convenience; the report stands without them
        print("pictures skipped:", e, file=sys.stderr)
    print("\n".join(md))
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
