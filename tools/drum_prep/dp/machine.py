"""One machine's ZIP to a folder of WAVs and a manifest.

Steps, in order: read every sound (by content, not extension); fold channels that are
identical to mono; join split stereo pairs (`Kick 1-L` + `Kick 1-R`, same format and
length) into one stereo file; apply the machine's quirks (dropping known short copies);
drop exact duplicates within a folder; then write each sound as WAV with what is known
about it: velocity-layer group, loop-or-one-shot guess, root note and loop points.
Nothing is dropped without a line in the manifest saying why and what was kept.
"""

import hashlib
import math
import os
import posixpath
import re
import zipfile

from . import audio

AUDIO_EXT = {".wav", ".wave", ".aif", ".aiff", ".aifc"}
JUNK_NAMES = {".ds_store", "thumbs.db", "desktop.ini"}
LOOP_WORDS = re.compile(r"loop|bpm|groove|pattern|\bbreak|\bbeat\b|\bfill\b", re.I)
LAYER_TAG = re.compile(r"\s*\[V(\d+)\]", re.I)
LR_SPLIT = re.compile(r"^(?P<stem>.*?)(?:(?P<sep>[\s_\-]+)(?P<side>[LRlr])|(?<=\d)(?P<side2>[LR]))$")
MAX_LR_GAP = 16          # frames two halves of a split stereo file may differ by (trims differ)
WIN_BAD = re.compile(r'[<>:"|?*\x00-\x1f]')


def safe_component(name):
    n = WIN_BAD.sub("_", name).rstrip(" .")
    return n or "_"


def safe_relpath(rel):
    return "/".join(safe_component(p) for p in rel.split("/") if p not in ("", ".", ".."))


def _is_junk(member):
    parts = member.split("/")
    base = parts[-1]
    return "__MACOSX" in parts or base.startswith("._") or base.lower() in JUNK_NAMES


def _strip_root(names, machine):
    """Paths inside the machine: drop a single top folder all members share."""
    tops = {n.split("/")[0] for n in names if "/" in n}
    if len(tops) == 1 and all("/" in n for n in names):
        top = tops.pop()
        return {n: n[len(top) + 1:] for n in names}, top
    return {n: n for n in names}, ""


# ------------------------------------------------------------------ quirks

def _d4_short_copies(entries):
    """Alesis D4: the root folder holds a short cut of each sound in a category folder
    (Snr25-Piccolo-38.wav beside Snr/Snr25-Piccolo.wav). Drop the short cut."""
    def key(rel):
        m = re.match(r"([A-Za-z]+)-?0*(\d+)", posixpath.basename(rel))
        return (m.group(1).lower()[:3], int(m.group(2))) if m else None
    full = {}
    for e in entries:
        if "/" in e["rel"]:
            k = key(e["rel"])
            if k:
                full.setdefault(k, e)
    drops = []
    for e in entries:
        if "/" not in e["rel"]:
            k = key(e["rel"])
            if k in full:
                drops.append((e, full[k], "short copy (the root folder's cut of a category-folder sound)"))
    return drops


QUIRKS = {
    "Alesis D4": [_d4_short_copies],
}


# ------------------------------------------------------------------ the machine

def process(zip_path, out_dir, write=True):
    """Convert one ZIP. Returns the manifest (and writes files when `write`)."""
    machine = os.path.splitext(os.path.basename(zip_path))[0]
    zf = zipfile.ZipFile(zip_path)
    members = [i for i in zf.infolist() if not i.is_dir()]
    names = [i.filename for i in members if not _is_junk(i.filename)]
    inner, top = _strip_root(names, machine)
    man = {"machine": machine, "source_zip": os.path.basename(zip_path),
           "source_zip_bytes": os.path.getsize(zip_path), "source_root": top,
           "files": [], "dropped": [], "failed": [], "extra": [],
           "junk_skipped": sum(1 for i in members if _is_junk(i.filename))}
    entries = []
    for name in names:
        raw = zf.read(name)
        rel = inner[name]
        ext = posixpath.splitext(rel)[1].lower()
        kind = audio.sniff(raw[:12])
        if not kind and ext not in AUDIO_EXT:
            man["extra"].append({"source": name, "path": "_extra/" + safe_relpath(rel), "bytes": len(raw)})
            if write:
                _put(out_dir, "_extra/" + safe_relpath(rel), raw)
            continue
        src = {"member": name, "sha256": hashlib.sha256(raw).hexdigest(), "bytes": len(raw)}
        try:
            s = audio.read(raw)
        except Exception as ex:  # noqa: BLE001 - every failure is recorded
            man["failed"].append({"source": name, "error": str(ex)})
            continue
        notes = []
        if kind == "aiff" and ext not in (".aif", ".aiff", ".aifc"):
            notes.append("aiff named %s" % ext)
        if kind == "wav" and ext in (".aif", ".aiff", ".aifc"):
            notes.append("wav named %s" % ext)
        if s.source_format.startswith("aif"):
            notes.append("from " + s.source_format)
        if s.source_format == "wav-pcm-tagged-float":
            notes.append("read as PCM: the header says float at %d bits" % s.bits)
        if s.source_format == "wav-msadpcm":
            notes.append("decoded from MS ADPCM to 16-bit")
        if s.channels > 2:
            notes.append("%d channels kept as they are" % s.channels)
        if s.channels_identical():
            s = s.to_mono_from(0)
            notes.append("identical channels folded to mono")
        entries.append({"rel": rel, "sound": s, "sources": [src], "notes": notes})

    _join_pairs(entries, man)
    for quirk in QUIRKS.get(machine, []):
        for e, kept, why in quirk(entries):
            if e in entries:
                entries.remove(e)
                man["dropped"].append({"source": [x["member"] for x in e["sources"]], "reason": why,
                                       "kept": kept["rel"]})
    _dedupe(entries, man)

    used = set()
    for e in sorted(entries, key=lambda x: x["rel"].lower()):
        s = e["sound"]
        base = posixpath.splitext(safe_relpath(e["rel"]))[0]
        path = base + ".wav"
        n = 2
        while path.lower() in used:
            path = "%s (%d).wav" % (base, n)
            n += 1
        used.add(path.lower())
        rec = describe(s, path, e)
        man["files"].append(rec)
        if write:
            _put(out_dir, path, audio.write_wav(s))
    _layer_groups(man["files"])
    return man


def describe(s, path, e):
    peak = s.peak()
    kind, why = guess_kind(path, s.seconds)
    rec = {"path": path, "sources": e["sources"], "rate": s.rate, "bits": s.bits,
           "float": s.is_float, "channels": s.channels, "frames": s.frames,
           "seconds": round(s.seconds, 4),
           "peak_dbfs": round(20.0 * math.log10(peak), 2) if peak > 0 else None,
           "kind": kind, "kind_reason": why, "content_sha256": s.content_hash(),
           "source_format": s.source_format}
    if s.root_note >= 0:
        rec["root_note"] = s.root_note
    if s.loop:
        rec["loop"] = list(s.loop)
    if e["notes"]:
        rec["notes"] = e["notes"]
    if e.get("duplicates"):
        rec["duplicates"] = e["duplicates"]
    return rec


def guess_kind(path, seconds):
    if LOOP_WORDS.search(path):
        return "loop", "name"
    if seconds >= 8.0:
        return "long", "over 8 s"
    return "oneshot", ""


def _join_pairs(entries, man):
    by_key = {}
    for e in entries:
        stem, ext = posixpath.splitext(e["rel"])
        folder, base = posixpath.split(stem)
        m = LR_SPLIT.match(base)
        if not m:
            continue
        side = (m.group("side") or m.group("side2")).upper()
        by_key.setdefault((folder, m.group("stem").rstrip(" _-"), m.group("sep") or ""), {})[side] = e
    for (folder, stem, sep), pair in by_key.items():
        if set(pair) != {"L", "R"}:
            continue
        le, re_ = pair["L"], pair["R"]
        ls, rs = le["sound"], re_["sound"]
        gap = abs(ls.frames - rs.frames)
        if ls.channels != 1 or rs.channels != 1 or gap > max(MAX_LR_GAP, 0.001 * max(ls.frames, rs.frames)):
            man.setdefault("lr_not_joined", []).append(
                {"left": le["rel"], "right": re_["rel"],
                 "why": "not both mono" if ls.channels != 1 or rs.channels != 1 else "lengths differ (%d, %d frames)" % (ls.frames, rs.frames)})
            continue
        try:
            st = audio.join_stereo(ls, rs)
        except audio.AudioError as ex:
            man.setdefault("lr_not_joined", []).append({"left": le["rel"], "right": re_["rel"], "why": str(ex)})
            continue
        name = stem if stem else posixpath.basename(posixpath.splitext(le["rel"])[0])
        rel = posixpath.join(folder, name + posixpath.splitext(le["rel"])[1])
        notes = sorted(set(le["notes"] + re_["notes"])) + ["joined from split L/R files"]
        if gap:
            notes.append("L/R lengths differed by %d frames; the shorter padded with silence" % gap)
        if st.channels_identical():
            st = st.to_mono_from(0)
            notes.append("identical channels folded to mono")
        joined = {"rel": rel, "sound": st, "sources": le["sources"] + re_["sources"], "notes": notes}
        entries.remove(le)
        entries.remove(re_)
        entries.append(joined)


def _dedupe(entries, man):
    """Exact duplicates in one folder go; copies in other folders stay (a machine's kit
    folders share sounds, and step 6 builds kits from them). The catalog's `same_as`
    links copies anywhere in the collection."""
    seen = {}
    for e in sorted(entries, key=lambda x: (len(x["rel"]), x["rel"].lower())):   # keep the plainest name
        h = (posixpath.dirname(e["rel"]), e["sound"].content_hash())
        if h in seen:
            kept = seen[h]
            entries.remove(e)
            kept.setdefault("duplicates", []).extend(x["member"] for x in e["sources"])
            man["dropped"].append({"source": [x["member"] for x in e["sources"]],
                                   "reason": "exact duplicate", "kept": kept["rel"]})
        else:
            seen[h] = e


def _layer_groups(files):
    """`Name [V2].wav` files are velocity layers of `Name`: group, index and count."""
    groups = {}
    for f in files:
        stem = posixpath.splitext(f["path"])[0]
        m = LAYER_TAG.search(stem)
        if m:
            key = LAYER_TAG.sub("", stem).strip()
            groups.setdefault(key, []).append((int(m.group(1)), f))
    for key, items in groups.items():
        items.sort(key=lambda x: x[0])
        for n, f in items:
            f["layer"] = {"group": key, "index": n, "of": len(items), "tag": "[V%d]" % n}


def _put(root, rel, data):
    path = os.path.join(root, *rel.split("/"))
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "wb") as fh:
        fh.write(data)
