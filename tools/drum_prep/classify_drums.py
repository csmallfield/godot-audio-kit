#!/usr/bin/env python3
"""Tag drum samples by how they sound: trains on the files whose names say what they are,
then guesses the rest and checks the names. Reads <collection>/tags.json (tag_names.py) and
<collection>/analysis/features.json (measure_drums.py); writes an `analysis` and a `final`
section into tags.json, and analysis/report.md. See README.md (Analysis)."""

import argparse
import hashlib
import json
import math
import os
import sys
from collections import Counter, defaultdict

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from dp import models  # noqa: E402
from dp.names import CATEGORIES  # noqa: E402

# Training weight by how the name tag was decided.
WEIGHT = {("file", "high"): 1.0, ("map", "high"): 1.0, ("map", "medium"): 0.7, ("file", "medium"): 0.7,
          ("folder", "medium"): 0.5}
TARGET = 0.8
KIND_CATS = {"hat": 30, "cymbal": 30, "perc": 40}     # categories with a kind model, and the fewest examples a kind needs
BRIGHT_CATS = {"snare", "rim", "clap", "hat", "cymbal", "perc"}
NOTE_NAMES = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]


def lg(v, floor=1e-4):
    return math.log(max(float(v), floor))


def vector(m):
    """A file's feature vector, or None when it's silent."""
    if not m or m.get("silent", True):
        return None
    v = [lg(m["seconds"]), lg(m["attack_s"] + 1e-3), lg(m["decay20_s"] + 1e-3), lg(m["decay40_s"] + 1e-3),
         m["lvl_20"] / 60.0, m["lvl_50"] / 60.0, m["lvl_100"] / 60.0, m["lvl_200"] / 60.0, m["lvl_400"] / 60.0,
         m["lvl_800"] / 60.0, math.log1p(m["onsets"]), lg(m["bandwidth_hz"] + 1, 1.0) / 10.0, m["width"]]
    for part in ("hit", "body"):
        sil = 1.0 if m.get(part + "_silent") else 0.0
        v += [sil, lg(m[part + "_centroid"] + 1, 1.0) / 10.0, lg(m[part + "_rolloff"] + 1, 1.0) / 10.0,
              lg(m[part + "_flatness"] + 1e-6, 1e-6) / 10.0, lg(m[part + "_zcr"] + 1, 1.0) / 10.0]
        v += [math.sqrt(m["%s_b%d" % (part, i)]) for i in range(8)]
    for part in ("early", "late"):
        f = m["f0_" + part]
        v += [lg(f + 1, 1.0) / 10.0 if f > 0 else 0.0, m["clarity_" + part]]
    v.append(max(-24.0, min(24.0, m["pitch_drop"])) / 12.0)
    for wi in range(3):
        v += [d / 40.0 for d in m.get("sp%d" % wi, [-80.0] * 16)]
        v.append(max(-80.0, m.get("lv%d" % wi, -80.0)) / 40.0)
    return v


def fold_of(machine, folds):
    return int(hashlib.md5(machine.encode("utf-8")).hexdigest(), 16) % folds


def held_out(make, X, y, w, fold, folds, k):
    P = np.zeros((len(X), k))
    for f in range(folds):
        tr, te = fold != f, fold == f
        if te.any() and tr.any():
            P[te] = make(k).fit(X[tr], y[tr], w[tr]).proba(X[te])
    return P


def pick_model(X, y, w, fold, folds, k, log, label):
    makers = {"logistic": models.LogReg, "mlp": models.MLP, "knn": models.KNN}
    best = None
    for name, make in makers.items():
        P = held_out(make, X, y, w, fold, folds, k)
        acc = float(np.average(P.argmax(axis=1) == y, weights=w))
        log.append("- %s, %s: held-out accuracy %.1f%%" % (label, name, 100 * acc))
        print("  %s %s: %.1f%%" % (label, name, 100 * acc), flush=True)
        if best is None or acc > best[1]:
            best = (name, acc, P)
    return best


def note_name(hz):
    if hz <= 0:
        return ""
    n = int(round(69 + 12 * math.log2(hz / 440.0)))
    return "%s%d" % (NOTE_NAMES[n % 12], n // 12 - 1)


def descriptors(m, cat, pct):
    """Plain words for how a sound sounds, from its measurements (brightness is judged
    against its own category)."""
    d = []
    dec = m["decay40_s"]
    d.append("short" if dec < 0.25 else "long" if dec > 1.0 else "medium")
    if m["seconds"] > 4.0:
        d.append("very long")
    c = m["hit_centroid"] or m["body_centroid"]
    lo, hi = pct.get(cat, pct["*"])
    if c and c < lo:
        d.append("dark")
    elif c and c > hi:
        d.append("bright")
    if m["attack_s"] < 0.005 and m["decay20_s"] < 0.15:
        d.append("punchy")
    if m["clarity_late"] > 0.8 and m["f0_late"] > 0:
        d.append("pitched")
    if m["pitch_drop"] > 3.0 and m["clarity_early"] > 0.4:
        d.append("falling pitch")
    if m["body_flatness"] > 0.3 or m["hit_flatness"] > 0.4:
        d.append("noisy")
    # Lo-fi: a low sample rate, or no highs in a sound that should have them (a kick has none anyway).
    if m["rate"] < 30000 or (cat in BRIGHT_CATS and m["bandwidth_hz"] and m["bandwidth_hz"] < 8000):
        d.append("lo-fi")
    if m["width"] > 0.05:
        d.append("stereo")
    if m["decay40_s"] > 0.4 and m["decay40_s"] > 4 * max(m["decay20_s"], 0.01):
        d.append("roomy")
    if m["onsets"] >= 2:
        d.append("several hits")
    return d


def brightness_bounds(cats_of, feats):
    """Per category, the 25th and 75th percentile of the hit's centroid ('*': all)."""
    cents = defaultdict(list)
    for p, c in cats_of.items():
        cents[c].append(feats[p]["hit_centroid"] or feats[p]["body_centroid"])
    pct = {c: (float(np.percentile(v, 25)), float(np.percentile(v, 75))) for c, v in cents.items() if len(v) >= 20}
    allc = [x for v in cents.values() for x in v]
    pct["*"] = (float(np.percentile(allc, 25)), float(np.percentile(allc, 75)))
    return pct


def describe_only(tags, feats, tpath):
    cats_of = {p: e["analysis"]["category"] for p, e in tags["files"].items() if "analysis" in e}
    pct = brightness_bounds(cats_of, feats)
    for p, c in cats_of.items():
        tags["files"][p]["analysis"]["describe"] = descriptors(feats[p], c, pct)
    with open(tpath, "w", encoding="utf-8", newline="\n") as fh:
        json.dump(tags, fh, indent=1, ensure_ascii=False)
    print("described %d files" % len(cats_of))
    return 0


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--out", required=True, help="the converted collection")
    ap.add_argument("--folds", type=int, default=5)
    ap.add_argument("--describe-only", action="store_true",
                    help="only recompute the descriptive words from the categories already there (no training)")
    a = ap.parse_args(argv)
    tpath = os.path.join(a.out, "tags.json")
    with open(tpath, encoding="utf-8") as fh:
        tags = json.load(fh)
    with open(os.path.join(a.out, "analysis", "features.json"), encoding="utf-8") as fh:
        feats = json.load(fh)["files"]
    if a.describe_only:
        return describe_only(tags, feats, tpath)

    paths, vecs = [], []
    for p in tags["files"]:
        v = vector(feats.get(p))
        if v is not None:
            paths.append(p)
            vecs.append(v)
    V = np.array(vecs)
    mu, sd = V.mean(axis=0), V.std(axis=0) + 1e-6
    Z = (V - mu) / sd
    machine = [p.split("/", 1)[0] for p in paths]
    names = [tags["files"][p]["name"] for p in paths]
    k = len(CATEGORIES)
    lab = [i for i, n in enumerate(names) if n["category"] in CATEGORIES and (n["by"], n.get("confidence", "")) in WEIGHT]
    X = Z[lab]
    y = np.array([CATEGORIES.index(names[i]["category"]) for i in lab])
    w = np.array([WEIGHT[(names[i]["by"], names[i]["confidence"])] for i in lab])
    fold = np.array([fold_of(machine[i], a.folds) for i in lab])
    log = ["# Drum analysis report", "", "%d sounding files, %d with a name tag to learn from (%d machines held out "
           "in %d folds: a machine is only ever judged by a model that never heard it)." % (
               len(paths), len(lab), len(set(machine)), a.folds), ""]
    print("%d files, %d labelled" % (len(paths), len(lab)), flush=True)

    name, acc, P = pick_model(X, y, w, fold, a.folds, k, log, "category")
    thr = models.thresholds(P, y, CATEGORIES, TARGET)
    log += ["", "Kept: **%s** (%.1f%%). Per category, held out:" % (name, 100 * acc), "",
            "| category | files | precision | recall | sure above |", "|---|---|---|---|---|"]
    pred = P.argmax(axis=1)
    for c, cn in enumerate(CATEGORIES):
        n_c = int((y == c).sum())
        tp = int(((pred == c) & (y == c)).sum())
        prec = tp / max(1, int((pred == c).sum()))
        rec = tp / max(1, n_c)
        log.append("| %s | %d | %.0f%% | %.0f%% | %s |" % (cn, n_c, 100 * prec, 100 * rec,
                                                         "%.2f" % thr[cn] if thr[cn] <= 1 else "never"))
    conf = np.zeros((k, k), dtype=int)
    for t, p_ in zip(y, pred):
        conf[t, p_] += 1
    log += ["", "Confusion (rows: the name says, columns: the sound says):", "",
            "| | " + " | ".join(c[:5] for c in CATEGORIES) + " |", "|---" * (k + 1) + "|"]
    for i, cn in enumerate(CATEGORIES):
        log.append("| %s | " % cn[:5] + " | ".join(str(v) for v in conf[i]) + " |")

    final_model = {"logistic": models.LogReg, "mlp": models.MLP, "knn": models.KNN}[name](k).fit(X, y, w)
    PA = final_model.proba(Z)
    # Labelled files get their held-out probabilities, so a name is checked by a model that didn't learn it.
    for j, i in enumerate(lab):
        PA[i] = P[j]

    # Kind models, one per category that has kinds.
    kind_pred = {}
    for cat, min_n in KIND_CATS.items():
        idx = [i for i in lab if names[i]["category"] == cat and names[i]["kind"]]
        kinds = Counter(names[i]["kind"].split(":")[0] for i in idx)
        keep = sorted(kd for kd, n in kinds.items() if n >= min_n)
        if len(keep) < 2:
            continue
        idx = [i for i in idx if names[i]["kind"].split(":")[0] in keep]
        Xk = Z[idx]
        yk = np.array([keep.index(names[i]["kind"].split(":")[0]) for i in idx])
        wk = np.array([WEIGHT[(names[i]["by"], names[i]["confidence"])] for i in idx])
        fk = np.array([fold_of(machine[i], a.folds) for i in idx])
        kname, kacc, KP = pick_model(Xk, yk, wk, fk, a.folds, len(keep), log, cat + " kind")
        kthr = models.thresholds(KP, yk, keep, TARGET)
        km = {"logistic": models.LogReg, "mlp": models.MLP, "knn": models.KNN}[kname](len(keep)).fit(Xk, yk, wk)
        kind_pred[cat] = (keep, km, kthr)
        log.append("- %s kinds kept: %s, %s (%.1f%%)" % (cat, ", ".join(keep), kname, 100 * kacc))

    # Brightness is judged within a category: the 25th and 75th percentile of the hit's centroid.
    pct = brightness_bounds({p: CATEGORIES[int(PA[i].argmax())] for i, p in enumerate(paths)}, feats)

    stats = Counter()
    disagree = []
    for i, p in enumerate(paths):
        pr = PA[i]
        order = np.argsort(-pr)
        c1, c2 = CATEGORIES[order[0]], CATEGORIES[order[1]]
        conf1 = models.rescale(float(pr[order[0]]), thr[c1])
        an = {"category": c1, "confidence": conf1, "second": c2, "second_p": round(float(pr[order[1]]), 3)}
        m = feats[p]
        if c1 in kind_pred:
            keep, km, kthr = kind_pred[c1]
            kp = km.proba(Z[i:i + 1])[0]
            kk = int(kp.argmax())
            an["kind"] = keep[kk]
            an["kind_confidence"] = models.rescale(float(kp[kk]), kthr[keep[kk]])
        if m["f0_late"] > 0 and m["clarity_late"] > 0.6:
            an["pitch_hz"] = m["f0_late"]
            an["note"] = note_name(m["f0_late"])
        an["describe"] = descriptors(m, c1, pct)
        nm = names[i]
        if nm["category"]:
            an["agrees"] = nm["category"] == c1
        entry = tags["files"][p]
        entry["analysis"] = an
        # The final tag: a name wins unless the sound says otherwise with confidence and the name
        # was only a guess (folder, word piece, letter code, a low-confidence map).
        sure = conf1 >= 0.8
        weak_name = nm.get("confidence") != "high"
        if nm["category"] and (nm["category"] == c1 or not (sure and weak_name)):
            fin = {"category": nm["category"], "kind": nm["kind"] or (an.get("kind", "") if nm["category"] == c1 else ""),
                   "from": "both" if nm["category"] == c1 else "name", "sure": nm["category"] == c1 or nm.get("confidence") == "high"}
            if nm["category"] != c1:
                disagree.append((p, nm["category"], nm.get("by"), nm.get("confidence"), c1, conf1))
        elif nm["category"]:
            fin = {"category": c1, "kind": an.get("kind", ""), "from": "analysis (over a weak name)", "sure": True}
            disagree.append((p, nm["category"], nm.get("by"), nm.get("confidence"), c1, conf1))
        else:
            fin = {"category": c1 if conf1 >= 0.5 else "", "kind": an.get("kind", "") if conf1 >= 0.5 else "",
                   "from": "analysis", "sure": sure}
        entry["final"] = fin
        stats[(fin["from"].split(" ")[0], fin["sure"])] += 1
    for p, e in tags["files"].items():
        if "final" not in e or p not in feats or feats[p].get("silent"):
            e["final"] = {"category": e["name"]["category"], "kind": e["name"]["kind"], "from": "name",
                          "sure": e["name"].get("confidence") == "high", "silent": bool(feats.get(p, {}).get("silent"))}
            e.pop("analysis", None)
    fin_cats = Counter(e["final"]["category"] or "unknown" for e in tags["files"].values())
    sure = sum(1 for e in tags["files"].values() if e["final"]["category"] and e["final"]["sure"])
    tags["summary"]["final"] = {"category": dict(fin_cats), "sure": sure, "how": {"%s/%s" % kv[0]: kv[1] for kv in stats.items()}}
    with open(tpath, "w", encoding="utf-8", newline="\n") as fh:
        json.dump(tags, fh, indent=1, ensure_ascii=False)

    n = len(tags["files"])
    log += ["", "## Result", "", "%d files: %d with a category (%d sure), %d without." % (
        n, n - fin_cats.get("unknown", 0), sure, fin_cats.get("unknown", 0)), "",
        "| category | files |", "|---|---|"] + ["| %s | %d |" % kv for kv in fin_cats.most_common()]
    log += ["", "How the final tags were reached (from / sure): " + ", ".join(
        "%s %s: %d" % (f, "sure" if s else "unsure", c) for (f, s), c in sorted(stats.items())), "",
        "## Names the sound disagrees with (%d)" % len(disagree), "",
        "Name tag, how it was read, and what the sound says. Where the name was only a guess and the sound "
        "was sure, the sound's tag was kept; otherwise the name's. The 60 the sound is surest about:", "",
        "| file | name says | read by | sound says | confidence |", "|---|---|---|---|---|"]
    for p, nc, by, nconf, ac, cf in sorted(disagree, key=lambda r: -r[5])[:60]:
        log.append("| %s | %s | %s %s | %s | %.2f |" % (p, nc, by, nconf, ac, cf))
    with open(os.path.join(a.out, "analysis", "report.md"), "w", encoding="utf-8", newline="\n") as fh:
        fh.write("\n".join(log) + "\n")
    print("final: %d of %d with a category (%d sure); %d names disagree with the sound" % (
        n - fin_cats.get("unknown", 0), n, sure, len(disagree)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
