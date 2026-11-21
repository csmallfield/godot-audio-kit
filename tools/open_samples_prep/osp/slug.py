"""Deterministic slugs and output paths.

Output paths depend only on the source path (relative to the collection root)
and, for collisions, on the other source paths that land on the same slug.
"""

import hashlib
import re
import unicodedata

# Folder names that only say what kind of file sits inside; dropped from output paths.
NOISE_DIRS = {"instruments", "instrument", "samples", "sample", "exs24", "sfz", "sf2", "nki",
              "img", "hfe"}

_WINDOWS_RESERVED = {"con", "prn", "aux", "nul"} | {f"com{i}" for i in range(1, 10)} | {
    f"lpt{i}" for i in range(1, 10)}

MAX_SEGMENT = 64


def short_hash(text, n=6):
    return hashlib.sha1(text.encode("utf-8")).hexdigest()[:n]


def slugify(text, max_len=MAX_SEGMENT):
    """Lower-case ASCII words joined by '-'. Same input, same output, always."""
    original = text
    t = unicodedata.normalize("NFKD", text)
    t = t.encode("ascii", "ignore").decode("ascii")
    t = re.sub(r"(?<=[a-z])(?=[A-Z])", " ", t)  # camelCase -> camel Case
    t = t.replace("&", " and ")
    t = t.lower()
    t = re.sub(r"[^a-z0-9]+", "-", t).strip("-")
    if not t:
        t = "x-" + short_hash(original)
    if len(t) > max_len:
        t = t[:max_len].rstrip("-")
    if t in _WINDOWS_RESERVED:
        t += "-x"
    return t


def is_noise(name):
    return name.strip().lower() in NOISE_DIRS


def base_parts(source_rel, is_file):
    """Slug segments for a source: <family>/<folders...>/<leaf>.

    source_rel uses '/' separators. For files the leaf is the file stem.
    Noise folders are dropped and a segment equal to its parent is collapsed
    (PercussionInstruments/Cuica/Cuica.nki -> percussion-instruments/cuica).
    """
    parts = [p for p in source_rel.split("/") if p]
    dirs, leaf = parts[:-1], parts[-1]
    if "#" in leaf:  # one entry inside a file (a DX7 voice): <file stem>/<entry>
        container, leaf = leaf.split("#", 1)
        if not container.lower().endswith(".sy1"):  # a Synth1 file holds one patch
            dirs = dirs + [container.rsplit(".", 1)[0] if "." in container else container]
    elif is_file:
        leaf = leaf.rsplit(".", 1)[0] if "." in leaf else leaf
    segs = []
    for i, d in enumerate(dirs):
        if is_noise(d):
            continue
        if i > 0:
            # "RolandSynthesizers" -> "Roland": the family folder already says synthesizers.
            d = re.sub(r"(?<=[a-z])Synthesizers?$", "", d) or d
        s = slugify(d)
        if not segs or segs[-1] != s:
            segs.append(s)
    leaf_slug = slugify(leaf)
    if not segs or segs[-1] != leaf_slug:
        segs.append(leaf_slug)
    if len(segs) == 1:
        segs.insert(0, "uncategorized")
    return segs


KIND_RANK = {"kontakt": 0, "exs24": 1, "sf2": 2, "dx7-voice": 3, "m3r-program": 3,
             "m3r-combination": 3, "cz-tone": 3, "synth1-patch": 3, "unsupported": 4, "wav-folder": 5,
             "wav-file": 6}


def assign_out_paths(items):
    """items: iterable of (source_rel, is_file, kind, suffix). Returns {source_rel: out_rel}.

    Rules, applied to the whole collection so the result never depends on input order:
    1. Every source gets its base path (see base_parts).
    2. Same base path: entries are ranked by kind (sampler instruments first), then source
       path; the first keeps the base, the others get '-<suffix>' (file extension or 'wav'),
       or '-<hash of source path>' if that is taken too.
    3. An output folder never contains another one: a path that is the parent of another
       gets '-<suffix>' (or the hash) until no folder is nested in another.
    """
    items = sorted(items, key=lambda it: (KIND_RANK.get(it[2], 9), it[0]))
    bases = {rel: "/".join(base_parts(rel, is_file)) for rel, is_file, _, _ in items}
    suffix_of = {rel: suf for rel, _, _, suf in items}
    result = {}
    taken = set()

    def free(path):
        return path.lower() not in taken

    def bump(rel, path):
        for cand in (f"{path}-{suffix_of[rel]}" if suffix_of[rel] else None,
                     f"{path}-{short_hash(rel)}"):
            if cand and free(cand):
                return cand
        n = 2
        while not free(f"{path}-{short_hash(rel)}-{n}"):
            n += 1
        return f"{path}-{short_hash(rel)}-{n}"

    for rel, _, _, _ in items:
        out = bases[rel]
        if not free(out):
            out = bump(rel, out)
        taken.add(out.lower())
        result[rel] = out
    changed = True
    while changed:
        changed = False
        paths = sorted(result.items(), key=lambda kv: (kv[1].lower(), kv[0]))
        lowered = [p.lower() for _, p in paths]
        for idx, (rel, out) in enumerate(paths):
            prefix = out.lower() + "/"
            if any(o.startswith(prefix) for o in lowered):
                new = bump(rel, out)
                taken.discard(out.lower())
                taken.add(new.lower())
                result[rel] = new
                changed = True
                break
    return result
