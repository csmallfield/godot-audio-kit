"""Walk the collection and list every instrument in it (read only)."""

import os
import re
from dataclasses import dataclass, field

from . import dx7, helm, korg, obxd, surge, synth1, tal
from .slug import is_noise

# Synth preset formats read here (named parameters in the sidecar; references come from
# the synth itself, through tools/patch_convert).
SYNTH_PATCH_KINDS = ("synth1-patch", "helm-patch", "tal-patch", "obxf-patch", "surge-patch")

# Source formats ConvertWithMoss reads, by extension -> (kind, CWM source id, format label).
CONVERTIBLE = {
    ".nki": ("kontakt", "nki", "Kontakt instrument (.nki)"),
    ".nkm": ("kontakt", "nki", "Kontakt multi (.nkm)"),
    ".exs": ("exs24", "exs24", "Logic EXS24 (.exs)"),
    ".sf2": ("sf2", "sf2", "SoundFont 2 (.sf2)"),
}
# Instrument/preset files nothing here can read. Listed in the catalog as "unsupported".
UNSUPPORTED = {
    ".phaseplant": "Kilohearts Phase Plant preset (.phaseplant)",
    ".sitala": "Sitala drum kit (.sitala)",
    ".nbkt": "Native Instruments Battery/Maschine kit (.nbkt)",
    ".nkx": "Kontakt encrypted sample container (.nkx)",
}
# Kontakt resource files: not instruments, but a sign the instrument relies on scripts/UI.
RESOURCE_EXTS = {".nkc", ".nkr", ".nckp", ".nkp"}
WAV_EXTS = {".wav"}
NOTE_FILE_RE = re.compile(r"^(readme|license|licence|sound_list|soundarchive)(\..*)?$", re.I)
# Disk-image extensions, read by ConvertWithMoss when --disk-images names the sampler.
DISK_IMAGE_EXTS = {".img", ".hfe", ".edm", ".ede", ".eda", ".iso"}
DISK_IMAGE_FORMATS = {"mirage": "Ensoniq Mirage disk image", "ensoniq": "Ensoniq EPS/ASR disk image",
                      "emax": "E-mu Emax disk image", "s1000": "Akai S1000/S3000 disk image"}
# Under these top-level folders every WAV is its own patch (one sound per file).
PER_FILE_FAMILIES = {"synthesizers", "oneshotsamples"}
SKIP_DIRS = {".git", "__ni_smpl_add__", "docs"}



@dataclass
class Candidate:
    rel: str                 # source path relative to the collection root, '/' separated;
                             # a DX7 voice is "<bank file>#<NN> <name>"
    kind: str                # kontakt | exs24 | sf2 | mirage.. | dx7-voice | synth1-patch | helm-patch | tal-patch |
                             # obxf-patch | wav-folder | wav-file | unsupported
    fmt: str                 # human label of the original format
    is_file: bool
    cwm_source: str = None   # ConvertWithMoss source format id, for convertible kinds
    files: list = field(default_factory=list)  # member files (rel), for WAV entries
    out_rel: str = None      # assigned later
    voice: dict = None       # DX7 voice: {index, name, packed, vced, bank}

    @property
    def source_file(self):
        """The file on disk this entry comes from (the bank, for a DX7 voice)."""
        return self.rel.split("#", 1)[0]

    @property
    def kind_suffix(self):
        """Suffix used to tell this entry apart when its output path collides."""
        if self.kind.startswith("wav"):
            return "wav"
        if self.kind == "dx7-voice":
            return f"v{self.voice['index']:02d}"
        if self.kind in ("m3r-program", "m3r-combination") or self.kind in SYNTH_PATCH_KINDS:
            return self.voice["number"].lower()
        return self.rel.rsplit(".", 1)[-1].lower() if "." in self.rel else self.kind


@dataclass
class Collection:
    root: str
    candidates: list
    ncw_files: list          # every .ncw (rel), to report samples no instrument uses
    resource_files: list     # Kontakt resource files (rel)
    note_files: list         # README / LICENSE files (rel)
    script_files: list       # files that look like Kontakt script sources (rel)


def _rel(root, path):
    return os.path.relpath(path, root).replace("\\", "/")


def discover(root, disk_images=None):
    """disk_images: a ConvertWithMoss source id (e.g. "mirage") for .img/.hfe/... files."""
    root = os.path.abspath(root)
    candidates, ncw, resources, notes, scripts = [], [], [], [], []
    obx_seen = set()  # OB-Xd banks repeat programs across banks and slots: keep the first
    for dirpath, dirnames, filenames in os.walk(root):
        rel_dir = _rel(root, dirpath)
        rel_dir = "" if rel_dir == "." else rel_dir
        dirnames[:] = sorted(d for d in dirnames
                             if d.lower() not in SKIP_DIRS or (rel_dir and d.lower() == "docs"))
        wavs = []
        # A folder of Synth1 patches: every text file in it is the bank's notes.
        sy1_bank = any(synth1.is_sy1(n) for n in filenames)
        for name in sorted(filenames):
            rel = f"{rel_dir}/{name}" if rel_dir else name
            ext = os.path.splitext(name)[1].lower()
            if ext == ".syx":
                candidates += _syx_entries(root, rel)
                continue
            if ext == ".sy1":
                candidates.append(_sy1_entry(root, rel))
                continue
            if ext == ".helm":
                candidates.append(_helm_entry(root, rel))
                continue
            if ext in (".vstpreset", ".noisemakerpreset"):
                candidates.append(_tal_entry(root, rel))
                continue
            if ext == ".fxp" and _is_surge_file(root, rel):
                candidates.append(_surge_entry(root, rel))
                continue
            if ext in (".fxb", ".fxp"):
                candidates += _obx_entries(root, rel, obx_seen)
                continue
            if sy1_bank and ext == ".txt":
                notes.append(rel)
                continue
            if disk_images and ext in DISK_IMAGE_EXTS:
                candidates.append(Candidate(rel, disk_images, DISK_IMAGE_FORMATS.get(
                    disk_images, f"{disk_images} disk image") + f" ({ext})", True,
                    cwm_source=disk_images))
                continue
            if ext in CONVERTIBLE:
                kind, src, label = CONVERTIBLE[ext]
                candidates.append(Candidate(rel, kind, label, True, cwm_source=src))
            elif ext in UNSUPPORTED:
                candidates.append(Candidate(rel, "unsupported", UNSUPPORTED[ext], True))
            elif ext in WAV_EXTS:
                wavs.append(rel)
            elif ext == ".ncw":
                ncw.append(rel)
            elif ext in RESOURCE_EXTS:
                resources.append(rel)
            elif NOTE_FILE_RE.match(name):
                notes.append(rel)
            elif "ksp" in name.lower() or ext == ".ksp":
                scripts.append(rel)
        if wavs:
            family = rel_dir.split("/")[0].lower() if rel_dir else ""
            if family in PER_FILE_FAMILIES or not rel_dir:
                for w in wavs:
                    candidates.append(Candidate(w, "wav-file", "WAV file", True, files=[w]))
            else:
                candidates.append(Candidate(rel_dir, "wav-folder", "folder of WAV files", False,
                                            files=wavs))
    # The collection's own docs/ folder holds the licence; keep it as a note file.
    lic = os.path.join(root, "docs", "LICENSE.md")
    if os.path.isfile(lic):
        notes.append("docs/LICENSE.md")
    candidates.sort(key=lambda c: c.rel)
    return Collection(root, candidates, sorted(ncw), sorted(resources), sorted(notes),
                      sorted(scripts))


def _sy1_entry(root, rel):
    """One Synth1 patch file -> its entry ("<file>#<NNN> <name>"), or unsupported."""
    try:
        with open(os.path.join(root, rel), "rb") as f:
            data = f.read(1 << 16)
        parsed = synth1.read(data)
    except (OSError, ValueError) as e:
        return Candidate(rel, "unsupported", f"Synth1 patch (.sy1) that can't be read: {e}", True)
    stem = rel.rsplit("/", 1)[-1].rsplit(".", 1)[0]
    e = {"index": int(stem) if stem.isdigit() else None, "number": stem,
         "name": parsed["name"], "packed": data, "parsed": parsed, "bank": rel}
    return Candidate(f"{rel}#{stem} {parsed['name'] or 'unnamed'}", "synth1-patch",
                     "Synth1 patch (.sy1)", True, voice=e)


def _read_file(root, rel, limit=1 << 24):
    with open(os.path.join(root, rel), "rb") as f:
        return f.read(limit)


def _helm_entry(root, rel):
    try:
        data = _read_file(root, rel)
        d = helm.read(data)
    except (OSError, ValueError) as e:
        return Candidate(rel, "unsupported", f"Helm patch (.helm) that can't be read: {e}", True)
    stem = rel.rsplit("/", 1)[-1].rsplit(".", 1)[0]
    name = d.get("patch_name") or stem
    e = {"index": None, "number": "helm", "name": name, "packed": data, "parsed": d, "bank": rel}
    return Candidate(rel, "helm-patch", "Helm patch (.helm)", True, voice=e)


def _tal_entry(root, rel):
    ext = rel.rsplit(".", 1)[-1].lower()
    try:
        data = _read_file(root, rel)
        if not tal.is_tal(rel, data):
            return Candidate(rel, "unsupported", f"preset of another plugin (.{ext})", True)
        parsed = tal.read(data)
    except (OSError, ValueError) as e:
        return Candidate(rel, "unsupported", f"TAL-NoiseMaker preset that can't be read: {e}", True)
    e = {"index": parsed["curprogram"], "number": "tal", "name": parsed["name"], "packed": data,
         "parsed": parsed, "bank": rel}
    return Candidate(rel, "tal-patch", f"TAL-NoiseMaker preset (.{ext})", True, voice=e)


def _is_surge_file(root, rel):
    try:
        with open(os.path.join(root, rel), "rb") as f:
            head = f.read(64)
    except OSError:
        return False
    return surge.is_surge(rel, head + b"\0")


def _surge_entry(root, rel):
    try:
        data = _read_file(root, rel)
        parsed = surge.read(data)
    except (OSError, ValueError, Exception) as e:  # ElementTree's ParseError is an Exception
        return Candidate(rel, "unsupported", f"Surge XT patch (.fxp) that can't be read: {e}", True)
    stem = rel.rsplit("/", 1)[-1].rsplit(".", 1)[0]
    e = {"index": None, "number": "surge", "name": parsed["name"] or stem, "packed": data,
         "parsed": parsed, "bank": rel}
    return Candidate(rel, "surge-patch", "Surge XT patch (.fxp)", True, voice=e)


def _obx_entries(root, rel, seen):
    """An OB-Xd bank's programs (empty slots and repeats left out), or one OB-X program."""
    ext = rel.rsplit(".", 1)[-1].lower()
    try:
        data = _read_file(root, rel)
        if obxd.detect(data) is None:
            return [Candidate(rel, "unsupported", f"bank or preset of another plugin (.{ext})", True)]
        progs = obxd.read(data)
    except (OSError, ValueError) as e:
        return [Candidate(rel, "unsupported", f"OB-Xd/OB-Xf file that can't be read: {e}", True)]
    out = []
    bank = progs[0]["kind"] == "obxd-bank"
    for p in progs:
        if obxd.is_init(p):
            continue
        vals, warns = obxd.values(p)
        h = obxd.sound_sha256(vals)
        if h in seen:
            continue
        seen.add(h)
        num = "%03d" % p["index"]
        packed = "\n".join('%s="%s"' % kv for kv in sorted(p["raw"].items())).encode("utf-8")
        e = {"index": p["index"], "number": num if bank else "obx", "name": p["name"], "packed": packed,
             "parsed": p, "values": vals, "warnings": warns, "sound_sha256": h, "bank": rel}
        label = ("OB-Xd bank program (.fxb)" if bank else
                 "OB-Xf patch (.fxp)" if p["kind"] == "obxf" else "OB-Xd program (.fxp)")
        out.append(Candidate(f"{rel}#{num} {p['name'] or 'unnamed'}" if bank else rel, "obxf-patch", label,
                             True, voice=e))
    return out


def _syx_entries(root, rel):
    """One SysEx file -> its entries: DX7 voices, M3R programs and combinations, a CZ tone."""
    try:
        with open(os.path.join(root, rel), "rb") as f:
            data = f.read(1 << 20)
    except OSError:
        return []
    if korg.is_m3r(data):
        progs, combis = korg.read_m3r(data)
        out = []
        for kind, items, label in (("m3r-program", progs, "Korg M3R program"),
                                   ("m3r-combination", combis, "Korg M3R combination")):
            for e in items:
                e["bank"] = rel
                out.append(Candidate(f"{rel}#{e['number']} {e['name'] or 'unnamed'}", kind,
                                     label + " (all-data SysEx dump)", True, voice=e))
        return out
    if korg.is_cz_tone(data):
        stem = rel.rsplit("/", 1)[-1].rsplit(".", 1)[0]
        e = {"index": 1, "number": "T", "name": stem, "packed": korg.cz_tone_bytes(data),
             "bank": rel}
        return [Candidate(rel, "cz-tone", "Casio CZ tone (single-tone SysEx dump)", True,
                          voice=e)]
    if not dx7.is_bank(data):
        return [Candidate(rel, "unsupported", "SysEx file (no known format)", True)]
    out = []
    for v in dx7.read_bank(data):
        v["bank"] = rel
        out.append(Candidate(f"{rel}#{v['index']:02d} {v['name'].strip() or 'unnamed'}",
                             "dx7-voice", "Yamaha DX7 voice (32-voice bulk SysEx bank)", True,
                             voice=v))
    return out


def instrument_root(rel):
    """Folder that holds an instrument and its satellites (Samples/, Resources/, README).

    For <X>/Instruments/<...>/a.nki this is <X>; otherwise the file's folder.
    """
    parts = rel.split("/")[:-1]
    for i in range(len(parts) - 1, -1, -1):
        if is_noise(parts[i]):
            return "/".join(parts[:i])
    return "/".join(parts)


def notes_for(rel, is_file, note_files):
    """README/LICENSE files in the source's folder and every folder above it."""
    folder = (rel.rsplit("/", 1)[0] if "/" in rel else "") if is_file else rel
    chain = set()
    parts = folder.split("/") if folder else []
    for i in range(len(parts), -1, -1):
        chain.add("/".join(parts[:i]))
    found = []
    for n in note_files:
        d = n.rsplit("/", 1)[0] if "/" in n else ""
        if d in chain:
            found.append(n)
    # nearest first
    found.sort(key=lambda n: (-n.count("/"), n))
    return found
