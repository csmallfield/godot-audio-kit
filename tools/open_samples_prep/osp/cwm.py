"""Driving ConvertWithMoss (by Juergen Mossgraber) from the command line.

CLI reference (ConvertWithMoss 20.3.0, `ConvertWithMossCLI.exe -h`):
  -s SOURCE -d DESTINATION [-f] [-a|-ad] [-p key=value,...] SOURCE... DESTINATION_FOLDER
Processing (-Z..., resampling/bit-depth/loop fixes) only happens with -Ze, which we never pass.
"""

import os
import re
import shutil
import subprocess
import sys

DEFAULT_PATHS = [
    r"D:\tools\ConvertWithMoss\ConvertWithMoss\ConvertWithMossCLI.exe",
    r"C:\Program Files\ConvertWithMoss\ConvertWithMossCLI.exe",
]
ANSI_RE = re.compile(r"\x1b\[[0-9;]*m")

# Destination parameters. WAV chunks: write the sampler (smpl) and instrument (inst)
# chunks so root key and loops also live inside each WAV; skip the broadcast (bext)
# chunk, which carries a date and would make files differ from run to run; never
# strip chunks; never convert to FLAC.
DEST_PARAMS = {
    "sfz": {"SFZWriteInstrumentChunk": "true", "SFZWriteSampleChunk": "true",
            "SFZWriteBroadcastAudioChunk": "false", "SFZRemoveJunkChunk": "false",
            "SFZConvertToFlac": "false"},
    "decentsampler": {"DecentSamplerWriteInstrumentChunk": "true",
                      "DecentSamplerWriteSampleChunk": "true",
                      "DecentSamplerWriteBroadcastAudioChunk": "false",
                      "DecentSamplerRemoveJunkChunk": "false",
                      "DecentSamplerOutputCreateBundle": "false",
                      "DecentSamplerOutputMakeMonophonic": "false",
                      "DecentSamplerAddFilterToGroups": "false"},
}


def find_cwm(explicit=None):
    cands = [explicit] if explicit else []
    if os.environ.get("OSP_CWM"):
        cands.append(os.environ["OSP_CWM"])
    if not explicit:
        cands += DEFAULT_PATHS
        for name in ("ConvertWithMossCLI", "ConvertWithMossCLI.exe"):
            w = shutil.which(name)
            if w:
                cands.append(w)
    for c in cands:
        if c and os.path.isfile(c):
            return os.path.abspath(c)
    return None


def base_command(exe):
    # A .py "ConvertWithMoss" is the test double; run it with this interpreter.
    if exe.lower().endswith(".py"):
        return [sys.executable, "-I", exe]
    return [exe]


def run(exe, args, timeout=None):
    cmd = base_command(exe) + list(args)
    flags = getattr(subprocess, "CREATE_NO_WINDOW", 0)
    try:
        p = subprocess.run(cmd, capture_output=True, timeout=timeout, creationflags=flags)
        out = (p.stdout or b"") + (b"\n" + p.stderr if p.stderr else b"")
        return p.returncode, ANSI_RE.sub("", out.decode("utf-8", "replace")), cmd
    except subprocess.TimeoutExpired as e:
        out = (e.stdout or b"").decode("utf-8", "replace")
        return -1, ANSI_RE.sub("", out) + f"\n[timeout after {timeout} s]", cmd


def version(exe):
    rc, text, _ = run(exe, ["-V"], timeout=120)
    m = re.search(r"ConvertWithMoss\s+([\w.\-]+)", text)
    return m.group(1) if m else None


def param_arg(dest):
    params = DEST_PARAMS.get(dest, {})
    return ["-p" + ",".join(f"{k}={v}" for k, v in params.items())] if params else []


def analyze_args(source_fmt, source_file, scratch_dir):
    return ["-s", source_fmt, "-d", "sfz", "-ad", source_file, scratch_dir]


def convert_args(source_fmt, dest, source_file, out_dir):
    return ["-s", source_fmt, "-d", dest, "-f"] + param_arg(dest) + [source_file, out_dir]


def display_command(cmd):
    return " ".join(f'"{c}"' if (" " in c or not c) else c for c in cmd)


# --- reading ConvertWithMoss's console output ------------------------------------

_META_RE = re.compile(r"Metadata:\s*(.*)")
_META_ITEM_RE = re.compile(r"(\w+) '([^']*)'")
_ANALYSIS_RE = re.compile(r"^Analysis of '(.*)':\s*$")
_DETECTED_RE = re.compile(r"^Detected (.*)$")
_GROUP_RE = re.compile(r"^\s+Group (\d+) '(.*)': (\d+) zones?(?:, gain ([+\-\d.]+) dB)?")
WARN_RE = re.compile(
    r"(^Note:|warn|not supported|unsupported|could not|couldn't|cannot|can't|ignor|"
    r"unknown|not mapped|error|exception|failed|encrypt|missing|not found|using default)", re.I)


def parse_analysis(text):
    """Pull the per-instrument facts out of `-ad` output.

    Returns a list (one per multi-sample found in the file) of
    {"name", "detected", "metadata": {...}, "groups": [{"index","name","zones","gain_db"}]}.
    """
    found = []
    cur = None
    detected = None
    for line in text.splitlines():
        m = _DETECTED_RE.match(line)
        if m:
            detected = m.group(1).strip()
            continue
        m = _ANALYSIS_RE.match(line)
        if m:
            cur = {"name": m.group(1), "detected": detected, "metadata": {}, "groups": []}
            found.append(cur)
            continue
        if cur is None:
            continue
        m = _META_RE.search(line)
        if m and line.startswith("  Metadata"):
            cur["metadata"] = {k: v for k, v in _META_ITEM_RE.findall(m.group(1))}
            continue
        m = _GROUP_RE.match(line)
        if m:
            cur["groups"].append({"index": int(m.group(1)), "name": m.group(2),
                                  "zones": int(m.group(3)),
                                  "gain_db": float(m.group(4)) if m.group(4) else None})
    return found


def warning_lines(text):
    out = []
    for line in text.splitlines():
        s = line.strip()
        if not s or s.startswith(("Analyzing:", "Storing:", "Analyze:", "Zone '", "Metadata:",
                                  "Analysis of ", "Group ")):
            continue
        if WARN_RE.search(s) and s not in out:
            out.append(s)
    return out


def feature_lines(text):
    """Distinct feature descriptions from -ad output (numbers masked), for 'what it uses'."""
    feats = set()
    for line in text.splitlines():
        s = line.strip()
        m = re.match(r"^([A-Z][A-Za-z\- ]+?):", s)
        if m and line.startswith("      "):
            feats.add(m.group(1))
        elif line.startswith("      ") and s in ("One-shot", "Reversed"):
            feats.add(s)
    return sorted(feats)
