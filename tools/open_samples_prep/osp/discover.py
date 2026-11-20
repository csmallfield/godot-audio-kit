"""Walk the collection and list every instrument in it (read only)."""

import os
import re
from dataclasses import dataclass, field

from .slug import is_noise

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
NOTE_FILE_RE = re.compile(r"^(readme|license|licence)(\..*)?$", re.I)
# Under these top-level folders every WAV is its own patch (one sound per file).
PER_FILE_FAMILIES = {"synthesizers", "oneshotsamples"}
SKIP_DIRS = {".git", "__ni_smpl_add__", "docs"}



@dataclass
class Candidate:
    rel: str                 # source path relative to the collection root, '/' separated
    kind: str                # kontakt | exs24 | sf2 | wav-folder | wav-file | unsupported
    fmt: str                 # human label of the original format
    is_file: bool
    cwm_source: str = None   # ConvertWithMoss source format id, for convertible kinds
    files: list = field(default_factory=list)  # member files (rel), for WAV entries
    out_rel: str = None      # assigned later

    @property
    def kind_suffix(self):
        """Suffix used to tell this entry apart when its output path collides."""
        if self.kind.startswith("wav"):
            return "wav"
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


def discover(root):
    root = os.path.abspath(root)
    candidates, ncw, resources, notes, scripts = [], [], [], [], []
    for dirpath, dirnames, filenames in os.walk(root):
        rel_dir = _rel(root, dirpath)
        rel_dir = "" if rel_dir == "." else rel_dir
        dirnames[:] = sorted(d for d in dirnames
                             if d.lower() not in SKIP_DIRS or (rel_dir and d.lower() == "docs"))
        wavs = []
        for name in sorted(filenames):
            rel = f"{rel_dir}/{name}" if rel_dir else name
            ext = os.path.splitext(name)[1].lower()
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
