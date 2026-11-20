"""Small SFZ reader: headers, opcode inheritance, and a normalized zone list.

Every zone keeps the full merged opcode dict ("opcodes") so nothing the SFZ
says is dropped; the named fields are a convenience on top of it.
"""

import re

_TOKEN_RE = re.compile(r"<(\w+)>|([A-Za-z0-9_$]+)=")
_NOTE_RE = re.compile(r"^([a-gA-G])([#b]?)(-?\d+)$")
_NOTE_BASE = {"c": 0, "d": 2, "e": 4, "f": 5, "g": 7, "a": 9, "b": 11}
_HEADER_COMMENT_RE = re.compile(r"^/{2,}\s*([A-Za-z][A-Za-z ]*?)\s*:\s*(.*?)\s*$")


def note_number(value):
    """SFZ key value -> MIDI number. Accepts numbers and names (c4 = 60, c-1 = 0)."""
    if value is None:
        return None
    v = str(value).strip()
    try:
        return int(float(v))
    except ValueError:
        pass
    m = _NOTE_RE.match(v)
    if not m:
        return None
    n = _NOTE_BASE[m.group(1).lower()] + {"#": 1, "b": -1, "": 0}[m.group(2)]
    return n + (int(m.group(3)) + 1) * 12


def _strip_comment(line):
    # A comment starts at '//' that begins the line or follows whitespace.
    m = re.search(r"(^|\s)//", line)
    return line[:m.start()] if m else line


def parse_blocks(text):
    """Return (header_comments, [(header, {opcode: value}), ...]) in file order."""
    text = re.sub(r"/\*.*?\*/", " ", text, flags=re.S)
    comments = {}
    blocks = []
    current = None
    for raw in text.splitlines():
        hm = _HEADER_COMMENT_RE.match(raw.strip())
        if hm and hm.group(2):
            comments.setdefault(hm.group(1).strip().lower(), hm.group(2))
        line = _strip_comment(raw)
        tokens = list(_TOKEN_RE.finditer(line))
        for i, tok in enumerate(tokens):
            if tok.group(1):
                current = (tok.group(1).lower(), {})
                blocks.append(current)
                continue
            end = tokens[i + 1].start() if i + 1 < len(tokens) else len(line)
            value = line[tok.end():end].strip()
            if current is None:
                current = ("global", {})
                blocks.append(current)
            current[1][tok.group(2)] = value
    return comments, blocks


def parse_sfz(text):
    """Parse SFZ text into {"comments", "control", "global", "regions"}.

    Each region is the merged opcode dict (control/global/master/group/region)
    plus "_group_index" and "_region_index".
    """
    comments, blocks = parse_blocks(text)
    control, cur_global, cur_master, cur_group = {}, {}, {}, {}
    first_global = {}
    regions = []
    group_index = -1
    for header, ops in blocks:
        if header == "control":
            control.update(ops)
        elif header == "global":
            cur_global, cur_master, cur_group = dict(ops), {}, {}
            if not first_global:
                first_global = dict(ops)
        elif header == "master":
            cur_master, cur_group = dict(ops), {}
        elif header == "group":
            cur_group = dict(ops)
            group_index += 1
        elif header == "region":
            merged = {}
            for layer in (cur_global, cur_master, cur_group, ops):
                merged.update(layer)
            if "sample" in merged and control.get("default_path"):
                merged["sample"] = control["default_path"].replace("\\", "/") + merged["sample"]
            merged["_group_index"] = max(group_index, 0)
            merged["_region_index"] = len(regions)
            regions.append(merged)
    return {"comments": comments, "control": control, "global": first_global, "regions": regions}


def _num(value, cast=float):
    if value is None or value == "":
        return None
    try:
        f = float(value)
    except ValueError:
        return None
    if cast is int:
        return int(round(f))
    return int(f) if f.is_integer() else f


def _prefixed(ops, prefixes):
    out = {}
    for k, v in ops.items():
        if k.startswith("_"):
            continue
        if any(k.startswith(p) for p in prefixes):
            n = _num(v)
            out[k] = n if n is not None else v
    return out


def normalize_zone(ops):
    """One merged SFZ region -> normalized zone dict (see README 'zones')."""
    key = note_number(ops.get("key"))
    lokey = note_number(ops.get("lokey"))
    hikey = note_number(ops.get("hikey"))
    root = note_number(ops.get("pitch_keycenter"))
    if key is not None:
        lokey = key if lokey is None else lokey
        hikey = key if hikey is None else hikey
        root = key if root is None else root
    lokey = 0 if lokey is None else lokey
    hikey = 127 if hikey is None else hikey
    root = 60 if root is None else root  # SFZ default
    loop_mode = ops.get("loop_mode") or ops.get("loopmode")
    loop_start = _num(ops.get("loop_start", ops.get("loopstart")), int)
    loop_end = _num(ops.get("loop_end", ops.get("loopend")), int)
    looped = loop_mode in ("loop_continuous", "loop_sustain") or (
        loop_mode is None and loop_start is not None and loop_end is not None)
    zone = {
        "index": ops.get("_region_index"),
        "sample": (ops.get("sample") or "").replace("\\", "/"),
        "group_index": ops.get("_group_index"),
        "group_label": ops.get("group_label"),
        "region_label": ops.get("region_label"),
        "root_key": root,
        "key_range": [lokey, hikey],
        "velocity_range": [_num(ops.get("lovel"), int) or 1,
                           _num(ops.get("hivel"), int) if ops.get("hivel") else 127],
        "fine_tune_cents": _num(ops.get("tune")) or 0,
        "transpose_semitones": _num(ops.get("transpose"), int) or 0,
        "pitch_keytrack": _num(ops.get("pitch_keytrack")),
        "gain_db": _num(ops.get("volume")) or 0,
        "pan": _num(ops.get("pan")) or 0,
        "amp_veltrack": _num(ops.get("amp_veltrack")),
        "sample_start": _num(ops.get("offset"), int) or 0,
        "sample_end": _num(ops.get("end"), int),
        "loop": {
            "looped": bool(looped),
            "mode": loop_mode,
            "start": loop_start,
            "end": loop_end,
            "crossfade": _num(ops.get("loop_crossfade")),
        },
        "trigger": ops.get("trigger", "attack"),
        "release_trigger": ops.get("trigger") in ("release", "release_key"),
        "exclusive_group": _num(ops.get("group"), int),
        "off_by": _num(ops.get("off_by"), int),
        "seq_length": _num(ops.get("seq_length"), int),
        "seq_position": _num(ops.get("seq_position"), int),
        "amp_envelope": _prefixed(ops, ("ampeg_",)),
        "filter": _prefixed(ops, ("fil_", "fil2_", "cutoff", "resonance")),
        "filter_envelope": _prefixed(ops, ("fileg_",)),
        "pitch_envelope": _prefixed(ops, ("pitcheg_",)),
        "lfos": _prefixed(ops, ("amplfo_", "pitchlfo_", "fillfo_", "lfo")),
        "crossfade": _prefixed(ops, ("xfin_", "xfout_", "xf_")),
        "opcodes": {k: v for k, v in ops.items() if not k.startswith("_")},
    }
    return zone


def zones_from_sfz_text(text):
    parsed = parse_sfz(text)
    return parsed, [normalize_zone(r) for r in parsed["regions"]]
