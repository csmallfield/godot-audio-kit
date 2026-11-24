"""Small numpy classifiers (as tools/patch_library/classify.py): logistic regression, a one-layer
MLP and k-nearest-neighbours, each with fit(X, y, w) and proba(X); and the per-class threshold at
which held-out precision reaches a target."""

import numpy as np


def softmax(z):
    z = z - z.max(axis=1, keepdims=True)
    e = np.exp(z)
    return e / e.sum(axis=1, keepdims=True)


def _onehot(y, k):
    Y = np.zeros((len(y), k))
    Y[np.arange(len(y)), y] = 1.0
    return Y


class LogReg:
    def __init__(self, k, l2=1e-3, iters=800, lr=0.5):
        self.k, self.l2, self.iters, self.lr = k, l2, iters, lr

    def fit(self, X, y, w):
        n, d = X.shape
        Y = _onehot(y, self.k)
        W, b = np.zeros((d, self.k)), np.zeros(self.k)
        sw = w / w.sum()
        for _ in range(self.iters):
            G = (softmax(X @ W + b) - Y) * sw[:, None]
            W -= self.lr * (X.T @ G + self.l2 * W)
            b -= self.lr * G.sum(axis=0)
        self.W, self.b = W, b
        return self

    def proba(self, X):
        return softmax(X @ self.W + self.b)


class MLP:
    """One tanh hidden layer, softmax out, full-batch Adam with weight decay."""

    def __init__(self, k, hidden=96, iters=600, lr=0.01, l2=1e-3, seed=1):
        self.k, self.hidden, self.iters, self.lr, self.l2, self.seed = k, hidden, iters, lr, l2, seed

    def fit(self, X, y, w):
        rng = np.random.default_rng(self.seed)
        n, d = X.shape
        Y = _onehot(y, self.k)
        sw = (w / w.sum())[:, None]
        P = [rng.normal(0, 1 / np.sqrt(d), (d, self.hidden)), np.zeros(self.hidden),
             rng.normal(0, 1 / np.sqrt(self.hidden), (self.hidden, self.k)), np.zeros(self.k)]
        m = [np.zeros_like(p) for p in P]
        v = [np.zeros_like(p) for p in P]
        for t in range(1, self.iters + 1):
            W1, b1, W2, b2 = P
            H = np.tanh(X @ W1 + b1)
            G = (softmax(H @ W2 + b2) - Y) * sw
            GH = (G @ W2.T) * (1 - H ** 2)
            grads = (X.T @ GH + self.l2 * W1, GH.sum(axis=0), H.T @ G + self.l2 * W2, G.sum(axis=0))
            for i, g in enumerate(grads):
                m[i] = 0.9 * m[i] + 0.1 * g
                v[i] = 0.999 * v[i] + 0.001 * g * g
                P[i] -= self.lr * (m[i] / (1 - 0.9 ** t)) / (np.sqrt(v[i] / (1 - 0.999 ** t)) + 1e-8)
        self.P = P
        return self

    def proba(self, X):
        W1, b1, W2, b2 = self.P
        return softmax(np.tanh(X @ W1 + b1) @ W2 + b2)


class KNN:
    def __init__(self, k, neighbours=15):
        self.k, self.n = k, neighbours

    def fit(self, X, y, w):
        self.X, self.y, self.w = X, y, w
        return self

    def proba(self, X):
        out = np.zeros((len(X), self.k))
        for s in range(0, len(X), 1000):
            d = ((X[s:s + 1000, None, :] - self.X[None, :, :]) ** 2).sum(axis=2) if len(self.X) < 4000 else None
            if d is None:
                a = X[s:s + 1000]
                d = (a ** 2).sum(1)[:, None] - 2 * a @ self.X.T + (self.X ** 2).sum(1)[None, :]
            idx = np.argpartition(d, min(self.n, d.shape[1] - 1), axis=1)[:, :self.n]
            dist = np.sqrt(np.maximum(np.take_along_axis(d, idx, axis=1), 0.0))
            rows = np.repeat(np.arange(idx.shape[0]), idx.shape[1])
            np.add.at(out[s:s + idx.shape[0]], (rows, self.y[idx].ravel()), (self.w[idx] / (1.0 + dist)).ravel())
        out += 1e-9
        return out / out.sum(axis=1, keepdims=True)


def thresholds(P, y, classes, target=0.8, min_n=10):
    """Per class: the lowest top-probability above which held-out precision stays at `target`."""
    pred, conf = P.argmax(axis=1), P.max(axis=1)
    out = {}
    for c, name in enumerate(classes):
        sel = pred == c
        if sel.sum() < min_n:
            out[name] = 1.01
            continue
        order = np.argsort(-conf[sel])
        correct = (y[sel][order] == c).astype(float)
        prec = np.cumsum(correct) / np.arange(1, len(correct) + 1)
        ok = np.nonzero(prec >= target)[0]
        ok = ok[ok >= min_n - 1]
        out[name] = float(conf[sel][order][ok[-1]]) if len(ok) else 1.01
    return out


def rescale(p, thr):
    """A probability as a confidence where the class's threshold sits at 0.8 ('sure')."""
    if thr > 1.0:
        return round(0.79 * p, 3)
    if p >= thr:
        return round(min(0.99, 0.8 + 0.19 * (p - thr) / max(1e-6, 1.0 - thr)), 3)
    return round(0.8 * p / thr, 3)
