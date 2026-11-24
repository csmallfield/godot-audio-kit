"""Guess a category for the patches nothing else names (docs/plans/patch-library.md, Classifier):

    python tools/patch_library/classify.py [--library D:/12_library/gak/library] [--folds 5]

Trains on the patches whose category came from their source's folder, their name, their bank or the
arpeggiator (index.py's categories), using analyze.py's measurements and settings. Two models, numpy
only: multinomial logistic regression and k-nearest-neighbours. Each is tested with whole banks held
out (so a bank's near-copies never test it), the better one is kept, and for each category the
probability above which its held-out precision reaches 80% becomes its threshold. Writes:
- <library>/analysis/categories.json: for each patch without a category, the guess, a confidence and
  the second guess. The confidence is the probability rescaled so that the category's threshold sits
  at 0.8, the browser's "sure" line (below it, the guess shows as unsure).
- <library>/gak_library_report.json and <library>/analysis/report.md: accuracy, per-category
  precision and recall, the confusion matrix, thresholds and counts.
Run index.py afterwards to put the guesses into the index.
"""
import argparse
import hashlib
import json
import os
from collections import Counter

import numpy as np

CATS = ["bass", "lead", "pad", "keys", "pluck", "bell", "strings", "brass", "organ", "woodwind", "arp", "perc", "fx", "voice"]
WEIGHT = {"source": 1.0, "patch": 0.8, "name": 0.7, "bank": 0.5}
TARGET_PRECISION = 0.8
FILTERS = ["lowpass", "highpass", "bandpass", "ladder", "mix", "off"]
NOTE_KEYS = ["attack_s", "lvl_05", "lvl_10", "lvl_hold", "release_s", "centroid_hz", "centroid_move", "flatness",
	"low_share", "high_share", "harmonic_share", "clarity", "pitch_spread_cents", "vibrato", "onsets", "level_move_db", "peak_db"]
LOG_KEYS = {"attack_s", "release_s", "centroid_hz", "pitch_spread_cents", "vibrato", "onsets", "level_move_db"}


def vector(e):
	"""A patch's feature vector, or None when it's silent."""
	notes = e.get("notes") or {}
	if not notes or (notes.get("60") or {}).get("silent", True):
		return None
	v = []
	for n in ("36", "60", "84"):
		m = notes.get(n) or {}
		for k in NOTE_KEYS:
			x = m.get(k)
			x = float(x) if x is not None else (0.5 if k == "harmonic_share" else 0.0)
			if k in LOG_KEYS:
				x = np.log1p(max(x, 0.0))
			v.append(x)
	for n in ("36", "60", "84"):
		m = notes.get(n) or {}
		v += list(m.get("bands") or [-6.0] * 8)
		v.append(np.log1p(max(0.0, float(m.get("decay_db_s", 0.0) or 0.0))))
		v.append(np.log2(max(20.0, float(m.get("centroid_attack_hz", 20.0) or 20.0))) - np.log2(max(20.0, float(m.get("centroid_hz", 20.0) or 20.0))))
	m = notes["60"]
	v += [h / 20.0 for h in (m.get("harm") or [-80.0] * 12)]
	v += [h / 20.0 for h in (m.get("harm_attack") or [-80.0] * 12)]
	p = notes["60"].get("peak_db", -90.0)
	v.append(float((notes.get("84") or {}).get("peak_db", p)) - float((notes.get("36") or {}).get("peak_db", p)))
	q = e.get("params") or {}
	v += [q.get("n_osc", 1), q.get("noise_share", 0.0), np.log1p(q.get("fm", 0.0)), q.get("unison", 1), np.log1p(q.get("detune", 0.0)),
		q.get("stack", 1), float(bool(q.get("mono"))), q.get("glide", 0.0), float(bool(q.get("arp"))), np.log1p(q.get("env_cut", 0.0)),
		np.log1p(q.get("lfo_pitch", 0.0)), np.log1p(q.get("lfo_amp", 0.0)), np.log1p(q.get("lfo_cut", 0.0)), q.get("reverb", 0.0),
		q.get("delay", 0.0), q.get("chorus", 0.0), np.log2(max(20.0, q.get("cutoff", 18000.0)))]
	f = q.get("filter", "lowpass")
	v += [float(f == t) for t in FILTERS]
	return np.array(v, dtype=np.float64)


def softmax(z):
	z = z - z.max(axis=1, keepdims=True)
	e = np.exp(z)
	return e / e.sum(axis=1, keepdims=True)


class LogReg:
	def __init__(self, l2=1e-3, iters=600, lr=0.5):
		self.l2, self.iters, self.lr = l2, iters, lr

	def fit(self, X, y, w):
		n, d = X.shape
		k = len(CATS)
		Y = np.zeros((n, k))
		Y[np.arange(n), y] = 1.0
		W = np.zeros((d, k))
		b = np.zeros(k)
		sw = w / w.sum()
		for _ in range(self.iters):
			P = softmax(X @ W + b)
			G = (P - Y) * sw[:, None]
			W -= self.lr * (X.T @ G + self.l2 * W)
			b -= self.lr * G.sum(axis=0)
		self.W, self.b = W, b
		return self

	def proba(self, X):
		return softmax(X @ self.W + self.b)


class MLP:
	"""One hidden layer (tanh), softmax out, trained full-batch with Adam and weight decay."""

	def __init__(self, hidden=96, iters=500, lr=0.01, l2=1e-3, seed=1):
		self.hidden, self.iters, self.lr, self.l2, self.seed = hidden, iters, lr, l2, seed

	def fit(self, X, y, w):
		rng = np.random.default_rng(self.seed)
		n, d = X.shape
		k = len(CATS)
		Y = np.zeros((n, k))
		Y[np.arange(n), y] = 1.0
		sw = (w / w.sum())[:, None]
		params = [rng.normal(0, 1 / np.sqrt(d), (d, self.hidden)), np.zeros(self.hidden),
			rng.normal(0, 1 / np.sqrt(self.hidden), (self.hidden, k)), np.zeros(k)]
		m = [np.zeros_like(p) for p in params]
		v = [np.zeros_like(p) for p in params]
		for t in range(1, self.iters + 1):
			W1, b1, W2, b2 = params
			H = np.tanh(X @ W1 + b1)
			P = softmax(H @ W2 + b2)
			G = (P - Y) * sw
			gW2 = H.T @ G + self.l2 * W2
			gb2 = G.sum(axis=0)
			GH = (G @ W2.T) * (1 - H ** 2)
			gW1 = X.T @ GH + self.l2 * W1
			gb1 = GH.sum(axis=0)
			for i, g in enumerate((gW1, gb1, gW2, gb2)):
				m[i] = 0.9 * m[i] + 0.1 * g
				v[i] = 0.999 * v[i] + 0.001 * g * g
				params[i] -= self.lr * (m[i] / (1 - 0.9 ** t)) / (np.sqrt(v[i] / (1 - 0.999 ** t)) + 1e-8)
		self.params = params
		return self

	def proba(self, X):
		W1, b1, W2, b2 = self.params
		return softmax(np.tanh(X @ W1 + b1) @ W2 + b2)


class KNN:
	def __init__(self, k=25):
		self.k = k

	def fit(self, X, y, w):
		self.X = X / (np.linalg.norm(X, axis=1, keepdims=True) + 1e-9)
		self.y, self.w = y, w
		return self

	def proba(self, X):
		Xn = X / (np.linalg.norm(X, axis=1, keepdims=True) + 1e-9)
		out = np.zeros((len(X), len(CATS)))
		for s in range(0, len(X), 2000):
			sim = Xn[s:s + 2000] @ self.X.T
			idx = np.argpartition(-sim, self.k, axis=1)[:, :self.k]
			for i in range(idx.shape[0]):
				for j in idx[i]:
					out[s + i, self.y[j]] += self.w[j] * max(sim[i, j], 0.0)
		out += 1e-6
		return out / out.sum(axis=1, keepdims=True)


def fold_of(bank, folds):
	return int(hashlib.md5(bank.encode("utf-8")).hexdigest(), 16) % folds


def thresholds(P, y):
	"""Per category: the lowest probability above which held-out precision reaches the target."""
	pred = P.argmax(axis=1)
	conf = P.max(axis=1)
	out = {}
	for c in range(len(CATS)):
		sel = pred == c
		if sel.sum() < 10:
			out[CATS[c]] = 1.01
			continue
		order = np.argsort(-conf[sel])
		correct = (y[sel][order] == c).astype(float)
		prec = np.cumsum(correct) / np.arange(1, len(correct) + 1)
		ok = np.nonzero(prec >= TARGET_PRECISION)[0]
		# The largest prefix (lowest probability) still at the target, needing at least 10 patches.
		ok = ok[ok >= 9]
		out[CATS[c]] = float(conf[sel][order][ok[-1]]) if len(ok) else 1.01
	return out


def rescale(p, thr):
	if thr > 1.0:
		return round(0.79 * p, 3)
	if p >= thr:
		return round(min(0.99, 0.8 + 0.19 * (p - thr) / max(1e-6, 1.0 - thr)), 3)
	return round(0.8 * p / thr, 3)


def main():
	ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
	ap.add_argument("--library", default="D:/12_library/gak/library")
	ap.add_argument("--folds", type=int, default=5)
	a = ap.parse_args()
	with open(os.path.join(a.library, "gak_library.json"), encoding="utf-8") as f:
		index = json.load(f)["patches"]
	with open(os.path.join(a.library, "analysis", "features.json"), encoding="utf-8") as f:
		feats = json.load(f)["patches"]
	lab_ids, X, y, w, banks = [], [], [], [], []
	unl_ids, U = [], []
	silent = 0
	for e in index:
		fe = feats.get(e["id"])
		v = vector(fe) if fe else None
		if v is None:
			silent += 1 if fe else 0
			continue
		cf = e.get("category_from", "")
		if cf in WEIGHT and e["category"] in CATS:
			lab_ids.append(e["id"])
			X.append(v)
			y.append(CATS.index(e["category"]))
			ww = WEIGHT[cf] * (0.6 if cf == "name" and e.get("category_conf", 0.9) < 0.9 else 1.0)
			w.append(ww)
			banks.append(e["source"] + "/" + e["bank"])
		elif cf in ("", "analysis"):
			unl_ids.append(e["id"])
			U.append(v)
	X, y, w = np.array(X), np.array(y), np.array(w)
	U = np.array(U) if U else np.zeros((0, X.shape[1]))
	mu, sd = X.mean(axis=0), X.std(axis=0) + 1e-6
	Xs, Us = (X - mu) / sd, (U - mu) / sd
	print("%d labelled, %d to guess, %d silent" % (len(X), len(U), silent), flush=True)
	fold = np.array([fold_of(b, a.folds) for b in banks])
	results = {}
	makers = {"logistic": LogReg, "mlp": MLP, "knn": KNN}
	for name, make in makers.items():
		P = np.zeros((len(X), len(CATS)))
		for k in range(a.folds):
			tr, te = fold != k, fold == k
			if te.sum() == 0:
				continue
			P[te] = make().fit(Xs[tr], y[tr], w[tr]).proba(Xs[te])
		acc = float((P.argmax(axis=1) == y).mean())
		wacc = float(((P.argmax(axis=1) == y) * w).sum() / w.sum())
		na = y != CATS.index("arp")
		acc_na = float((P.argmax(axis=1)[na] == y[na]).mean())
		results[name] = {"P": P, "acc": acc, "wacc": wacc, "acc_no_arp": acc_na}
		print("%s: held-out accuracy %.3f (weighted %.3f; without arp %.3f)" % (name, acc, wacc, acc_na), flush=True)
	best = max(results, key=lambda n: results[n]["wacc"])
	P = results[best]["P"]
	pred = P.argmax(axis=1)
	thr = thresholds(P, y)
	conf_m = np.zeros((len(CATS), len(CATS)), dtype=int)
	for t, p in zip(y, pred):
		conf_m[t, p] += 1
	per = {}
	for c, cat in enumerate(CATS):
		tp = conf_m[c, c]
		per[cat] = {"labelled": int(conf_m[c].sum()), "precision": round(tp / max(1, conf_m[:, c].sum()), 3),
			"recall": round(tp / max(1, conf_m[c].sum()), 3), "threshold": round(thr[cat], 3)}
		sure = (pred == c) & (P.max(axis=1) >= thr[cat])
		per[cat]["sure_held_out"] = int(sure.sum())
		per[cat]["sure_precision"] = round(float((y[sure] == c).mean()) if sure.any() else 0.0, 3)
	# Train on every label and guess the rest.
	model = makers[best]().fit(Xs, y, w)
	guesses = {}
	cnt = Counter()
	sure_cnt = Counter()
	if len(Us):
		PU = model.proba(Us)
		order = np.argsort(-PU, axis=1)
		for i, pid in enumerate(unl_ids):
			c1, c2 = order[i, 0], order[i, 1]
			cat = CATS[c1]
			c = rescale(float(PU[i, c1]), thr[cat])
			guesses[pid] = {"category": cat, "confidence": c, "alt": CATS[c2]}
			cnt[cat] += 1
			if c >= 0.8:
				sure_cnt[cat] += 1
	os.makedirs(os.path.join(a.library, "analysis"), exist_ok=True)
	with open(os.path.join(a.library, "analysis", "categories.json"), "w", encoding="utf-8", newline="\n") as f:
		json.dump({"model": best, "thresholds": thr, "patches": guesses}, f, separators=(",", ":"), sort_keys=True)
	report = {
		"labelled": int(len(X)), "guessed": len(guesses), "silent": silent, "folds": a.folds, "held_out_by": "bank",
		"models": {n: {"accuracy": round(r["acc"], 3), "weighted_accuracy": round(r["wacc"], 3), "accuracy_without_arp": round(r["acc_no_arp"], 3)} for n, r in results.items()},
		"chosen": best, "target_precision": TARGET_PRECISION, "per_category": per,
		"confusion": {"rows_true_cols_predicted": CATS, "matrix": conf_m.tolist()},
		"guesses": dict(cnt), "sure_guesses": dict(sure_cnt),
	}
	with open(os.path.join(a.library, "gak_library_report.json"), "w", encoding="utf-8", newline="\n") as f:
		json.dump(report, f, indent=1)
	lines = ["# Category classifier report", "",
		"%d labelled patches (from source folders, names, banks and the arpeggiator) trained it; %d patches had no category and got a guess; %d render silent." % (len(X), len(guesses), silent),
		"Tested with whole banks held out (%d folds). Held-out accuracy: %s. Kept: **%s**. Most arp labels come from the arpeggiator setting, which is easy to tell; without them, %s." % (a.folds,
			", ".join("%s %.1f%%" % (n, 100 * r["acc"]) for n, r in results.items()), best,
			", ".join("%s %.1f%%" % (n, 100 * r["acc_no_arp"]) for n, r in results.items())),
		"", "A guess is *sure* when its probability passes its category's threshold: the lowest at which held-out precision was still %d%%. A category that never reached it has no sure guesses." % int(100 * TARGET_PRECISION),
		"", "| Category | Labelled | Precision | Recall | Threshold | Sure (held out) | Their precision | Guessed | Sure guesses |",
		"| --- | --- | --- | --- | --- | --- | --- | --- | --- |"]
	for cat in CATS:
		p = per[cat]
		lines.append("| %s | %d | %.0f%% | %.0f%% | %s | %d | %.0f%% | %d | %d |" % (cat, p["labelled"], 100 * p["precision"], 100 * p["recall"],
			"%.2f" % p["threshold"] if p["threshold"] <= 1 else "never", p["sure_held_out"], 100 * p["sure_precision"], cnt[cat], sure_cnt[cat]))
	lines += ["", "Confusion (rows: the label, columns: the guess):", "", "| | " + " | ".join(c[:5] for c in CATS) + " |", "|" + " --- |" * (len(CATS) + 1)]
	for c, cat in enumerate(CATS):
		lines.append("| %s | " % cat + " | ".join(str(v) for v in conf_m[c]) + " |")
	with open(os.path.join(a.library, "analysis", "report.md"), "w", encoding="utf-8", newline="\n") as f:
		f.write("\n".join(lines) + "\n")
	print("\n".join(lines))


if __name__ == "__main__":
	main()
