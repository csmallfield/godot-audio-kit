#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Build the pseudo-speech English stress dictionary.

    python3 tools/build_stress_dict.py                      # CMUdict only, every word
    python3 tools/build_stress_dict.py --freq eng_news_2023_1M-words.txt --top 20000
    python3 tools/build_stress_dict.py --moby-hyph mhyph.txt

Writes addons/audio_kit/speech/data/en_stress.txt, one word a line:

    haircut hair|cut 12

the word, its letters split into syllables, and each syllable's stress
(1 primary, 2 secondary, 0 none). Then run, in Godot,
addons/audio_kit/tools/make_stress_dict.gd, which packs the text into the
resource the kit loads (en_stress.res), and tools/stress_report.gd for the
fallback rules' accuracy.

Sources (see docs/plans/pseudo-speech.md):
  CMUdict (2-clause BSD): the stress, from each word's first pronunciation.
      Downloaded from GitHub unless --cmu points at a local cmudict.dict.
  Moby Hyphenator II (public domain), optional: spelling splits, used when
      its piece count matches CMU's syllable count.
  A frequency list, optional (Leipzig Corpora, CC BY 4.0; a "<id>\t<word>\t<count>"
      or "<word>\t<count>" file): with --top N, only the N most frequent
      word forms ship. Without one, every plain-letter CMU word ships.

Moby Pronunciator II (the doc's cross-check) is not read yet: its format
hasn't been checked against the real file.

Without Moby, spellings are split by vowel groups as the kit's runtime does
(addons/audio_kit/speech/text.gd), then adjusted until the number of pieces
matches CMU's syllable count: a vowel pair split (create), a silent final e
put back (fire), a final syllabic consonant (rhythm), or the two closest
vowel groups merged (business). The build report counts each adjustment.

Pure standard library; deterministic (the same inputs give the same file).
"""
import argparse
import collections
import datetime
import os
import sys
import urllib.request

CMU_URL = "https://raw.githubusercontent.com/cmusphinx/cmudict/master/cmudict.dict"
CMU_LICENSE_URL = "https://raw.githubusercontent.com/cmusphinx/cmudict/master/LICENSE"
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT_DIR = os.path.join(ROOT, "addons", "audio_kit", "speech", "data")
REPORT = os.path.join(ROOT, "docs", "stress", "build_report.md")

VOWELS = "aeiou"
ONSETS = ["str", "spr", "scr", "spl", "thr", "shr", "squ", "bl", "br", "cl", "cr", "dr", "fl", "fr", "gl", "gr",
          "pl", "pr", "sc", "sk", "sl", "sm", "sn", "sp", "st", "sw", "tr", "tw", "th", "sh", "ch", "ph", "wh", "qu",
          "kn", "wr"]


# ------------------------------------------------------------------ spelling (mirrors text.gd)

def is_vowel_at(w, i):
    c = w[i]
    if c in VOWELS:
        return True
    if c == "y":
        if i == 0:
            return False
        return not (i + 1 < len(w) and w[i + 1] in VOWELS)
    return False


def raw_nuclei(w):
    out, i = [], 0
    while i < len(w):
        if is_vowel_at(w, i):
            s = i
            while i < len(w) and is_vowel_at(w, i):
                i += 1
            out.append([s, i])
        else:
            i += 1
    return out


def last_is_silent(w, nuc):
    """True when the last vowel group is the swallowed e of -e, -es or -ed."""
    if len(nuc) < 2:
        return False
    s = nuc[-1][0]
    tail = w[s:]
    before = w[s - 1] if s > 0 else ""
    if not before:
        return False
    if tail == "e" and before not in VOWELS:
        return not (before == "l" and s >= 2 and w[s - 2] not in VOWELS)
    if tail == "es" and before not in "sxzcgh":
        return True
    if tail == "ed" and before not in "td" and before not in VOWELS:
        return True
    return False


def cuts(w, nuc):
    out = [0]
    for k in range(1, len(nuc)):
        gs, ge = nuc[k - 1][1], nuc[k][0]
        run = w[gs:ge]
        keep = 0
        if len(run) > 1:
            keep = len(run) - 1
            for o in ONSETS:
                if run.endswith(o) and len(run) - len(o) < keep:
                    keep = len(run) - len(o)
            if run.endswith("ck") or run.endswith("ng"):
                keep = len(run)
        out.append(gs + keep)
    out.append(len(w))
    return out


def split(w, nuc):
    c = cuts(w, nuc)
    return [w[c[k]:c[k + 1]] for k in range(len(nuc))]


def runtime_split(w):
    """What the runtime's syllabifier gives without a dictionary."""
    nuc = raw_nuclei(w)
    if last_is_silent(w, nuc):
        nuc = nuc[:-1]
    if not nuc:
        return [w]
    return split(w, nuc)


def align(w, n, stats):
    """Split w into exactly n letter groups, or None."""
    raw = raw_nuclei(w)
    nuc = [list(x) for x in raw]
    removed = None
    if last_is_silent(w, nuc):
        removed = nuc.pop()
    if not nuc:
        if n == 1:
            stats["no vowel letters, one syllable"] += 1
            return [w]
        stats["dropped: no vowel letters"] += 1
        return None
    if len(nuc) == n:
        stats["as the runtime splits it"] += 1
        return split(w, nuc)
    while len(nuc) < n:
        # Split the longest vowel group (create: cre|ate).
        best = max(range(len(nuc)), key=lambda k: (nuc[k][1] - nuc[k][0], -k))
        if nuc[best][1] - nuc[best][0] >= 2:
            s, e = nuc[best]
            m = max(s + 1, e - 1)  # before the group's last vowel: see|ing, cre|ate
            nuc[best:best + 1] = [[s, m], [m, e]]
            stats["vowel pair split"] += 1
            continue
        # The final e wasn't silent after all (fire: fi|re).
        if removed is not None:
            nuc.append(removed)
            removed = None
            stats["silent e put back"] += 1
            continue
        # A syllabic consonant at the end (rhythm: rhy|thm).
        last_end = nuc[-1][1]
        if len(w) - last_end >= 2:
            nuc.append([len(w) - 1, len(w)])
            stats["final syllabic consonant"] += 1
            continue
        stats["dropped: fewer letter groups than syllables"] += 1
        return None
    while len(nuc) > n:
        # Merge the two closest vowel groups (business: busi|ness).
        gaps = [(nuc[k + 1][0] - nuc[k][1], k) for k in range(len(nuc) - 1)]
        _, k = min(gaps)
        nuc[k:k + 2] = [[nuc[k][0], nuc[k + 1][1]]]
        stats["vowel groups merged"] += 1
    return split(w, nuc)


# ------------------------------------------------------------------ sources

def fetch(url, path):
    if not os.path.exists(path):
        print("downloading %s" % url, file=sys.stderr)
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with urllib.request.urlopen(url, timeout=60) as r, open(path, "wb") as f:
            f.write(r.read())
    return path


def read_cmu(path):
    """word -> stress digits of its first pronunciation (plain-letter words only)."""
    out = {}
    skipped = 0
    with open(path, encoding="utf-8", errors="replace") as f:
        for line in f:
            line = line.split("#", 1)[0].strip()
            if not line:
                continue
            parts = line.split()
            head, phones = parts[0], parts[1:]
            if "(" in head:
                continue  # an alternative pronunciation: the first one wins
            w = head.lower()
            if not w.isascii() or not w.isalpha():
                skipped += 1
                continue
            digits = "".join(p[-1] for p in phones if p[-1].isdigit())
            if digits:
                out[w] = digits
    return out, skipped


def read_moby_hyph(path):
    out = {}
    with open(path, "rb") as f:
        data = f.read()
    text = data.decode("mac_roman") if b"\xa5" in data and b"\xc2\xa5" not in data else data.decode("utf-8", "replace")
    for line in text.splitlines():
        line = line.strip()
        if not line or " " in line:
            continue
        pieces = [p for p in line.replace("•", "¥").replace("·", "¥").split("¥")]
        w = "".join(pieces).lower()
        if w.isascii() and w.isalpha():
            out.setdefault(w, [p.lower() for p in pieces])
    return out


def read_freq(path):
    """Word forms in descending frequency."""
    counts = collections.Counter()
    with open(path, encoding="utf-8", errors="replace") as f:
        for line in f:
            parts = line.rstrip("\n").split("\t")
            if len(parts) >= 3 and parts[0].isdigit():
                w, c = parts[1], parts[2]
            elif len(parts) >= 2:
                w, c = parts[0], parts[1]
            else:
                continue
            w = w.lower()
            if w.isascii() and w.isalpha() and c.strip().isdigit():
                counts[w] += int(c)
    return [w for w, _ in sorted(counts.items(), key=lambda x: (-x[1], x[0]))]


# ------------------------------------------------------------------ main

def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--cmu", help="a local cmudict.dict (default: download it into the cache)")
    ap.add_argument("--moby-hyph", help="Moby Hyphenator II (mhyph.txt), optional")
    ap.add_argument("--freq", help="a word-frequency list, optional")
    ap.add_argument("--top", type=int, default=0, help="with --freq: ship only the N most frequent forms")
    ap.add_argument("--cache", default=os.path.join(ROOT, "tools", "stress_cache"), help="where downloads go")
    ap.add_argument("--out", default=OUT_DIR)
    a = ap.parse_args()

    cmu_path = a.cmu or fetch(CMU_URL, os.path.join(a.cache, "cmudict.dict"))
    if not a.cmu:
        fetch(CMU_LICENSE_URL, os.path.join(a.cache, "LICENSE"))
    cmu, cmu_skipped = read_cmu(cmu_path)
    hyph = read_moby_hyph(a.moby_hyph) if a.moby_hyph else {}

    if a.freq:
        ranked = read_freq(a.freq)
        wanted = ranked[:a.top] if a.top > 0 else ranked
    else:
        wanted = sorted(cmu)
    stats = collections.Counter()
    missing = []
    lines = []
    for w in wanted:
        digits = cmu.get(w)
        if digits is None:
            missing.append(w)
            continue
        groups = None
        if w in hyph and len(hyph[w]) == len(digits):
            groups = hyph[w]
            stats["Moby Hyphenator split"] += 1
        else:
            groups = align(w, len(digits), stats)
        if groups is None:
            continue
        lines.append("%s %s %s" % (w, "|".join(groups), digits))
    lines.sort()

    os.makedirs(a.out, exist_ok=True)
    out_path = os.path.join(a.out, "en_stress.txt")
    with open(out_path, "w", encoding="utf-8", newline="\n") as f:
        f.write("# English stress for the Godot Audio Kit's pseudo-speech: word, syllables, stress (1 primary, 2 secondary, 0 none).\n")
        f.write("# Built by tools/build_stress_dict.py from CMUdict (BSD 2-clause, Carnegie Mellon University; see NOTICE)%s.\n"
                % (" and Moby Hyphenator II (public domain)" if hyph else ""))
        for line in lines:
            f.write(line + "\n")

    # The report.
    multi = sum(1 for line in lines if len(line.split()[2]) > 1)
    rep = ["# Stress dictionary: build report", "",
           "Written by `tools/build_stress_dict.py` on %s. Regenerate rather than edit." % datetime.date.today().isoformat(), "",
           "| | |", "| --- | --- |",
           "| CMUdict entries read (first pronunciations, plain letters) | %d |" % len(cmu),
           "| CMUdict entries skipped (apostrophes, digits, punctuation) | %d |" % cmu_skipped,
           "| Frequency list | %s |" % (("%s, top %d" % (os.path.basename(a.freq), a.top)) if a.freq else "none: every CMU word ships"),
           "| Moby Hyphenator | %s |" % (("%d words" % len(hyph)) if hyph else "not used"),
           "| Moby Pronunciator cross-check | not done yet |",
           "| Words shipped | %d |" % len(lines),
           "| ... with more than one syllable | %d |" % multi,
           "| Wanted but not in CMU (left to the fallback rules) | %d |" % len(missing), "",
           "## How the spellings were split", "", "| Adjustment | Words |", "| --- | --- |"]
    for k, v in sorted(stats.items(), key=lambda x: -x[1]):
        rep.append("| %s | %d |" % (k, v))
    if missing:
        rep += ["", "## Wanted but not in CMU (first 200)", "", ", ".join(missing[:200])]
    os.makedirs(os.path.dirname(REPORT), exist_ok=True)
    with open(REPORT, "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(rep) + "\n")
    print("wrote %s (%d words) and %s" % (os.path.relpath(out_path, ROOT), len(lines), os.path.relpath(REPORT, ROOT)))


if __name__ == "__main__":
    main()
