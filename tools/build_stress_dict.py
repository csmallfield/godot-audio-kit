#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Build the pseudo-speech English stress dictionary.

    python3 tools/build_stress_dict.py                      # CMUdict only, every word
    python3 tools/build_stress_dict.py --freq eng_news_2023_1M-words.txt --top 20000
    python3 tools/build_stress_dict.py --freq eng_news_2023_1M-words.txt --top 20000 \
        --moby-pron mpron.txt                           # the shipped build

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
      its piece count matches CMU's syllable count. Not used for the shipped
      build: its splits are typographic (nev|er, ac|cept|ed) and drop the
      onsets the voices build syllables from.
  A frequency list, optional (Leipzig Corpora, CC BY 4.0; a "<id>\t<word>\t<count>"
      or "<word>\t<count>" file): with --top N, only the N most frequent
      word forms ship. Without one, every plain-letter CMU word ships.
  Moby Pronunciator II (public domain), optional: a cross-check. Every word
      where it puts the primary stress on another syllable than CMU is listed
      in the report (CMU wins); words CMU lacks take Moby's stress.
  Words in neither are left to the runtime's fallback rules and listed.

With --top, the next 3,000 known words past the cut (two or more syllables)
go to docs/stress/held_out.txt, which tools/stress_report.gd measures the
rules on: real words the shipped dictionary doesn't hold.

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
HELD_OUT = os.path.join(ROOT, "docs", "stress", "held_out.txt")
HELD_OUT_WORDS = 3000

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


def _moby_lines(path):
    """The non-blank lines of a Moby file (Mac Roman, CRLF). The readers keep a
    lowercase headword over a capitalised one (polish over Polish)."""
    with open(path, "rb") as f:
        text = f.read().decode("mac_roman")
    for line in text.splitlines():
        line = line.strip()
        if line:
            yield line


def read_moby_hyph(path):
    """word -> its spelling pieces. Moby Hyphenator II separates pieces with
    Mac Roman 0xA5 (a bullet, U+2022, once decoded; not the yen sign); entries with spaces (phrases),
    hyphens, apostrophes or accents are skipped."""
    out = {}
    for line in _moby_lines(path):
        if " " in line:
            continue
        pieces = line.split("\u2022")
        w = "".join(pieces)
        if not (w.isascii() and w.isalpha()):
            continue
        lw = w.lower()
        if lw not in out or w == lw:
            out[lw] = [p.lower() for p in pieces]
    return out


# Moby Pronunciator II: "word pronunciation", e.g. "haircut 'h/(@)/r,k/@/t".
# Symbols between slashes are vowels or special consonants; plain letters
# outside are consonants (and, in some foreign words, vowels); ' marks the
# primary-stressed syllable and , a secondary one, before its onset; _ joins
# the words of a phrase.
MOBY_VOWELS = {"@", "I", "i", "E", "&", "A", "oU", "eI", "aI", "u", "O", "U", "AU", "(@)", "[@]", "-",
               "Oi", "Ou", "ju", "y", "(@)f"}
MOBY_PLAIN_VOWELS = "aeiouAEIOU"


def moby_stress(pron):
    """Stress digits, one per vowel, or None for phrases and unparsable entries."""
    if "_" in pron or " " in pron:
        return None
    parts = pron.split("/")
    digits = []
    pending = "0"
    prev_vowel = False
    for k, part in enumerate(parts):
        if k % 2 == 1:
            if part in MOBY_VOWELS:
                digits.append(pending)
                pending = "0"
                prev_vowel = True
            elif part:
                prev_vowel = False
            continue
        for c in part:
            if c == "'":
                pending = "1"
            elif c == ",":
                pending = "2"
            elif c in MOBY_PLAIN_VOWELS:
                if not prev_vowel:
                    digits.append(pending)
                    pending = "0"
                prev_vowel = True
            else:
                prev_vowel = False
    if not digits:
        return None
    if len(digits) == 1:
        return "1"
    return "".join(digits) if "1" in digits else None


def read_moby_pron(path):
    """word -> its stress digits under each casing Moby Pronunciator II lists
    (plain-letter single words), the lowercase headword's first: Moby has
    both Canada and a foreign canada, Roman and roman."""
    out = {}
    for line in _moby_lines(path):
        w, _, pron = line.partition(" ")
        if not (w.isascii() and w.isalpha()):
            continue
        digits = moby_stress(pron.strip())
        if digits is None:
            continue
        readings = out.setdefault(w.lower(), [])
        if w == w.lower():
            readings.insert(0, digits)
        else:
            readings.append(digits)
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

def show(groups, digits):
    """haircut: HAIR·cut (capitals: the primary stress)."""
    return "·".join(g.upper() if d == "1" else g for g, d in zip(groups, digits))


def compare(cmu, readings):
    """CMU vs Moby on one word: 'agree' (one of Moby's readings puts the primary
    stress on CMU's syllable), 'differ', or 'uncompared' (one syllable, or no
    reading with CMU's syllable count)."""
    same = [m for m in readings if len(m) == len(cmu)]
    if len(cmu) < 2 or not same or "1" not in cmu:
        return "uncompared"
    return "agree" if any(cmu.index("1") == m.index("1") for m in same) else "differ"


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--cmu", help="a local cmudict.dict (default: download it into the cache)")
    ap.add_argument("--moby-hyph", help="Moby Hyphenator II (mhyph.txt), optional")
    ap.add_argument("--moby-pron", help="Moby Pronunciator II (mpron.txt), optional: the cross-check, and words CMU lacks")
    ap.add_argument("--freq", help="a word-frequency list, optional")
    ap.add_argument("--top", type=int, default=0, help="with --freq: ship only the N most frequent forms")
    ap.add_argument("--cache", default=os.path.join(ROOT, "tools", "stress_cache"), help="where downloads go")
    ap.add_argument("--out", default=OUT_DIR)
    ap.add_argument("--report", default=REPORT)
    ap.add_argument("--held-out", default=HELD_OUT, help="where the held-out words go ('' for nowhere)")
    a = ap.parse_args()

    cmu_path = a.cmu or fetch(CMU_URL, os.path.join(a.cache, "cmudict.dict"))
    if not a.cmu:
        fetch(CMU_LICENSE_URL, os.path.join(a.cache, "LICENSE"))
    cmu, cmu_skipped = read_cmu(cmu_path)
    hyph = read_moby_hyph(a.moby_hyph) if a.moby_hyph else {}
    moby = read_moby_pron(a.moby_pron) if a.moby_pron else {}

    ranked = []
    if a.freq:
        ranked = read_freq(a.freq)
        wanted = ranked[:a.top] if a.top > 0 else ranked
    else:
        wanted = sorted(cmu)
    stats = collections.Counter()

    def entry(w):
        """(groups, digits, source) or None."""
        digits, source = cmu.get(w), "CMU"
        if digits is None:
            digits, source = moby[w][0] if w in moby else None, "Moby"
        if digits is None:
            return None
        if w in hyph and len(hyph[w]) == len(digits):
            stats["Moby Hyphenator split"] += 1
            return hyph[w], digits, source
        groups = align(w, len(digits), stats)
        return (groups, digits, source) if groups is not None else None

    missing = []
    from_moby = []
    differ = []
    lines = []
    for w in wanted:
        e = entry(w)
        if e is None:
            if w not in cmu and w not in moby:
                missing.append(w)
            continue
        groups, digits, source = e
        if source == "Moby":
            from_moby.append(w)
        elif w in moby and compare(digits, moby[w]) == "differ":
            m = next(m for m in moby[w] if len(m) == len(digits))
            differ.append("%s: %s / %s" % (w, show(groups, digits), show(groups, m)))
        lines.append("%s %s %s" % (w, "|".join(groups), digits))
    lines.sort()
    overall = collections.Counter(compare(cmu[w], moby[w]) for w in moby if w in cmu)

    # Held out: the next most frequent words past the cut that the sources know
    # (two or more syllables), for tools/stress_report.gd to test the rules on.
    held = []
    if a.held_out and a.top > 0:
        held_stats = stats.copy()
        for w in ranked[a.top:]:
            if len(held) >= HELD_OUT_WORDS:
                break
            e = entry(w)
            if e is not None and len(e[1]) >= 2 and "1" in e[1]:
                held.append("%s %s %s" % (w, "|".join(e[0]), e[1]))
        stats = held_stats  # the build report counts the shipped words only

    os.makedirs(a.out, exist_ok=True)
    out_path = os.path.join(a.out, "en_stress.txt")
    sources = ["CMUdict (BSD 2-clause, Carnegie Mellon University; see NOTICE)"]
    if moby:
        sources.append("Moby Pronunciator II (public domain)")
    if hyph:
        sources.append("Moby Hyphenator II (public domain)")
    if a.freq:
        sources.append("ranked by the Leipzig Corpora Collection's word frequencies (CC BY 4.0)")
    with open(out_path, "w", encoding="utf-8", newline="\n") as f:
        f.write("# English stress for the Godot Audio Kit's pseudo-speech: word, syllables, stress (1 primary, 2 secondary, 0 none).\n")
        f.write("# Built by tools/build_stress_dict.py from %s.\n" % ", ".join(sources))
        for line in lines:
            f.write(line + "\n")
    if a.held_out:
        if held:
            with open(a.held_out, "w", encoding="utf-8", newline="\n") as f:
                f.write("# Words just past the dictionary's frequency cut (most frequent first), for tools/stress_report.gd.\n")
                f.write("# Built by tools/build_stress_dict.py; same sources and format as en_stress.txt.\n")
                for line in held:
                    f.write(line + "\n")
        elif os.path.exists(a.held_out):
            os.remove(a.held_out)

    # The report.
    multi = sum(1 for line in lines if len(line.split()[2]) > 1)
    compared = overall["agree"] + overall["differ"]
    rep = ["# Stress dictionary: build report", "",
           "Written by `tools/build_stress_dict.py` on %s. Regenerate rather than edit." % datetime.date.today().isoformat(), "",
           "| | |", "| --- | --- |",
           "| CMUdict entries read (first pronunciations, plain letters) | %d |" % len(cmu),
           "| CMUdict entries skipped (apostrophes, digits, punctuation) | %d |" % cmu_skipped,
           "| Frequency list | %s |" % (("%s, top %d forms" % (os.path.basename(a.freq), a.top)) if a.freq else "none: every CMU word ships"),
           "| Moby Hyphenator | %s |" % (("%d words" % len(hyph)) if hyph else "not used"),
           "| Moby Pronunciator | %s |" % (("%d words with a usable stress mark" % len(moby)) if moby else "not used"),
           "| Words shipped | %d |" % len(lines),
           "| ... with more than one syllable | %d |" % multi,
           "| ... from Moby (not in CMU) | %d |" % len(from_moby),
           "| ... where CMU and Moby put the primary stress on different syllables (CMU kept) | %d |" % len(differ),
           "| Wanted but in neither (left to the fallback rules) | %d |" % len(missing),
           "| Held-out words written for the fallback report | %s |" % (len(held) if held else "none (no frequency cut)")]
    if moby:
        rep += ["", "Over every word both know: %d compared (two or more syllables, same count), %d agree on the primary "
                "stress, %d differ (%.1f%%); %d not comparable (one syllable or different syllable counts)."
                % (compared, overall["agree"], overall["differ"], 100.0 * overall["differ"] / max(1, compared),
                   overall["uncompared"])]
    rep += ["", "## How the spellings were split", "", "| Adjustment | Words |", "| --- | --- |"]
    for k, v in sorted(stats.items(), key=lambda x: (-x[1], x[0])):
        rep.append("| %s | %d |" % (k, v))
    if differ:
        rep += ["", "## CMU vs Moby: primary stress disagreements in the shipped words", "",
                "CMU wins. word: CMU / Moby (capitals: the primary stress). Most are noun/verb homographs "
                "(CMU's first reading) and names.", ""]
        rep += ["- %s" % d for d in differ]
    if from_moby:
        rep += ["", "## From Moby (not in CMU)", "", ", ".join(sorted(from_moby))]
    if missing:
        rep += ["", "## Wanted but in neither CMU nor Moby (the fallback rules read these)", "",
                "Most frequent first. Names a project uses belong in its lexicon.", "", ", ".join(missing)]
    os.makedirs(os.path.dirname(a.report), exist_ok=True)
    with open(a.report, "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(rep) + "\n")
    print("wrote %s (%d words) and %s" % (os.path.relpath(out_path, ROOT), len(lines), os.path.relpath(a.report, ROOT)))


if __name__ == "__main__":
    main()
