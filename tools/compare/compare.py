#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Compare a render with a reference soundtrack, cue by cue.

    python3 tools/compare/compare.py ours.wav reference.wav cues.json out_dir [--label E1]

"Close enough" is a judgement, so nothing here passes or fails. It reports:
loudness of both; for each cue, whether each side has a hit there (level jump
around the cue), and the energy balance in low / mid / high bands; and a
side-by-side spectrogram with cue markers. Writes compare.md, compare.json and
compare.png to out_dir. Needs numpy, scipy and matplotlib.
"""
import argparse, json, math, os, sys
import numpy as np
from scipy import signal

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "analyze"))
from analyze import read, integrated_lufs  # noqa: E402

BANDS = [("low", 20, 250), ("mid", 250, 4000), ("high", 4000, 20000)]


def window_stats(m, sr, t, pre=0.06, post=0.25):
    a = max(0, int((t - pre) * sr))
    c = int(t * sr)
    b = min(len(m), int((t + post) * sr))
    before = m[a:c]
    after = m[c:b]
    rms = lambda x: float(np.sqrt(np.mean(x ** 2))) if len(x) else 0.0
    rb, ra = rms(before), rms(after)
    jump = 20 * math.log10((ra + 1e-9) / (rb + 1e-9))
    bands = {}
    if len(after) > 256:
        f, p = signal.welch(after, sr, nperseg=min(2048, len(after)))
        tot = np.sum(p) + 1e-20
        for name, lo, hi in BANDS:
            bands[name] = round(10 * math.log10((np.sum(p[(f >= lo) & (f < hi)]) + 1e-20) / tot), 1)
        cen = float(np.sum(f * p) / tot)
    else:
        cen = 0.0
    return {"jump_db": round(jump, 1), "level_dbfs": round(20 * math.log10(ra + 1e-9), 1), "bands": bands, "centroid_hz": round(cen)}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("ours")
    ap.add_argument("reference")
    ap.add_argument("cues")
    ap.add_argument("out")
    ap.add_argument("--label", default="")
    a = ap.parse_args()
    os.makedirs(a.out, exist_ok=True)
    sr1, x1 = read(a.ours)
    sr2, x2 = read(a.reference)
    if sr1 != sr2:
        x2 = signal.resample_poly(x2, sr1, sr2, axis=0)
    sr = sr1
    sheet = json.load(open(a.cues))
    fps = float(sheet.get("fps", 30))
    cues = sheet["cues"]
    m1, m2 = x1.mean(axis=1), x2.mean(axis=1)
    l1, l2 = integrated_lufs(x1, sr), integrated_lufs(x2, sr)

    rows = []
    agree = 0
    for c in cues:
        t = float(c["time"]) if "time" in c else float(c["frame"]) / fps
        s1, s2 = window_stats(m1, sr, t), window_stats(m2, sr, t)
        hit1, hit2 = s1["jump_db"] >= 3.0, s2["jump_db"] >= 3.0
        agree += hit1 == hit2
        rows.append({"name": c["name"], "time": round(t, 3), "ours": s1, "reference": s2, "both_hit": hit1 and hit2,
                     "only_ours": hit1 and not hit2, "only_reference": hit2 and not hit1})

    def band_mean(side, name):
        v = [r[side]["bands"].get(name) for r in rows if r[side]["bands"]]
        return round(float(np.mean(v)), 1) if v else None

    summary = {"label": a.label, "lufs_ours": round(l1, 1), "lufs_reference": round(l2, 1),
               "length_ours_s": round(len(m1) / sr, 2), "length_reference_s": round(len(m2) / sr, 2),
               "cues": len(rows), "hit_agreement": "%d/%d" % (agree, len(rows)),
               "bands_ours": {b[0]: band_mean("ours", b[0]) for b in BANDS},
               "bands_reference": {b[0]: band_mean("reference", b[0]) for b in BANDS}}
    json.dump({"summary": summary, "cues": rows}, open(os.path.join(a.out, "compare.json"), "w"), indent=2)

    md = ["# Compare: %s" % (a.label or os.path.basename(a.ours)), "",
          "Ours %.1f LUFS, %.2f s · reference %.1f LUFS, %.2f s · hits agree on %s cues" % (
              l1, len(m1) / sr, l2, len(m2) / sr, summary["hit_agreement"]), "",
          "Average band balance at the cues (dB of each window's energy): ours %s · reference %s" % (
              summary["bands_ours"], summary["bands_reference"]), "",
          "| Cue | Time s | Jump ours dB | Jump ref dB | Centroid ours Hz | Centroid ref Hz | Note |", "| --- | --- | --- | --- | --- | --- | --- |"]
    for r in rows:
        note = "only ours" if r["only_ours"] else ("only reference" if r["only_reference"] else "")
        md.append("| %s | %s | %s | %s | %s | %s | %s |" % (r["name"], r["time"], r["ours"]["jump_db"], r["reference"]["jump_db"],
                  r["ours"]["centroid_hz"], r["reference"]["centroid_hz"], note))
    md += ["", "A jump of 3 dB or more counts as a hit. The reference may carry music under its effects, which lowers its jumps; judge by ear."]
    open(os.path.join(a.out, "compare.md"), "w").write("\n".join(md) + "\n")

    try:
        import matplotlib
        matplotlib.use("Agg")
        import matplotlib.pyplot as plt
        bg, fg = "#111418", "#d8dde3"
        fig, axs = plt.subplots(2, 1, figsize=(14, 6.5), facecolor=bg, sharex=True)
        for ax, m, title in ((axs[0], m2, "reference"), (axs[1], m1, "ours")):
            f, t, S = signal.spectrogram(m, sr, nperseg=1024, noverlap=768, scaling="spectrum")
            S = 10 * np.log10(np.maximum(S, 1e-12))
            ax.pcolormesh(t, f, S, shading="auto", cmap="magma", vmin=S.max() - 90, vmax=S.max())
            ax.set_yscale("symlog", linthresh=500)
            ax.set_ylim(20, sr / 2)
            ax.set_facecolor(bg)
            ax.tick_params(colors=fg, labelsize=7)
            ax.set_title("%s %s" % (a.label, title), color=fg, fontsize=9, loc="left")
            for c in rows:
                ax.axvline(c["time"], color="#8eef97", lw=0.5, alpha=0.6)
        axs[1].set_xlabel("seconds", color=fg, fontsize=8)
        fig.tight_layout()
        fig.savefig(os.path.join(a.out, "compare.png"), dpi=105, facecolor=bg)
        plt.close(fig)
    except Exception as e:
        print("picture skipped:", e, file=sys.stderr)
    print("\n".join(md[:5]))


if __name__ == "__main__":
    main()
