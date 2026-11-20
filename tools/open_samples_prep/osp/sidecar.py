"""Building instrument.json and README.txt contents."""

import re

from .slug import is_noise, slugify

FAMILY_TAGS = {
    "synthesizers": ["synth"], "pianos": ["piano", "keys"], "keyboards": ["keys"],
    "percussioninstruments": ["percussion"], "stringedinstruments": ["strings"],
    "windinstruments": ["winds"], "choral": ["choir", "vocal"], "musicboxes": ["music-box"],
    "oneshotsamples": ["one-shot"], ".misc": ["misc"],
}
MANUFACTURERS = ["Ensoniq", "Roland", "Korg", "Kawai", "Yamaha", "Wurlitzer", "Gretsch", "Atari", "Casio",
                 "Ensoniq", "Emu", "E-mu", "Akai", "Moog", "Sequential", "Oberheim", "Rhodes",
                 "Hammond", "Steinway", "Fender", "Gibson", "Asahi"]
# Words worth a tag when they show up in patch, group or zone names.
ARTICULATIONS = {
    "sustain", "sus", "staccato", "stacc", "legato", "pluck", "plucked", "pizz", "pizzicato",
    "tremolo", "trem", "vibrato", "mute", "muted", "open", "slap", "buzz", "rim", "rimshot",
    "roll", "flam", "drag", "ghost", "accent", "release", "rel", "harmonic", "harmonics",
    "strike", "struck", "bowed", "bow", "scrape", "swell", "chop", "pad", "lead", "bass", "bell",
    "bells", "brass", "strings", "organ", "choir", "vox", "voice", "piano", "epiano", "keys",
    "guitar", "gtr", "flute", "sweep", "noise", "fx", "hit", "loop", "riser", "drone", "arp",
    "soft", "hard", "piezo", "mallet", "mallets", "stick", "sticks", "brush", "click", "shot",
    "center", "edge", "click", "dead", "choke", "crash", "ride", "hihat", "hat", "kick", "snare",
    "tom", "cymbal", "clap", "perc", "sine", "square", "saw", "pulse", "detuned", "unison",
    "harpsichord", "harpsich", "clav", "vibe", "marimba", "koto", "orchestra", "chime", "timpani",
    "synth", "whistle", "train", "harp", "sax", "trumpet", "horn", "violin", "cello", "organ",
}
NOTE_IN_NAME_RE = re.compile(r"(?<![A-Za-z0-9])([A-Ga-g])(#|b|s)?(-?[0-8])(?![0-9])")
NOTE_BASE = {"c": 0, "d": 2, "e": 4, "f": 5, "g": 7, "a": 9, "b": 11}


def humanize(name):
    return re.sub(r"(?<=[a-z])(?=[A-Z])", " ", name).strip()


# Name words -> GAK patch categories (AKPatch.CATEGORIES). First match wins.
CATEGORY_WORDS = [
    ("bass", ["bass"]), ("brass", ["brass", "horn", "trumpet", "trombone", "tuba", "sax"]),
    ("strings", ["string", "strings", "violin", "cello", "viola", "orchestra", "orch"]),
    ("organ", ["organ", "pipes", "pipe"]),
    ("keys", ["piano", "e.piano", "epiano", "clav", "harpsich", "harpsichord", "keys", "rhodes"]),
    ("bell", ["bell", "bells", "chime", "vibe", "marimba", "glock", "celesta", "steel drum",
              "xylo", "tub bells"]),
    ("pluck", ["guitar", "koto", "harp", "pluck", "sitar", "banjo", "mandolin", "pizz"]),
    ("voice", ["voice", "vocal", "choir", "vox"]),
    ("lead", ["lead", "solo", "flute", "whistle", "oboe", "clarinet"]),
    ("pad", ["pad", "sweep", "atmos", "warm"]),
    ("fx", ["fx", "train", "take off", "noise", "effect", "wind", "timpani", "drum", "perc"]),
]


def guess_category(*texts):
    t = " " + " ".join(x.lower() for x in texts if x) + " "
    for cat, words in CATEGORY_WORDS:
        for w in words:
            if re.search(r"(?<![a-z])" + re.escape(w), t):
                return cat
    return None


def identity_for(cand):
    if cand.kind == "dx7-voice":
        bank = cand.source_file
        dirs = bank.split("/")[:-1]
        return {
            "family": humanize(dirs[0]) if dirs else None,
            "family_folder": dirs[0] if dirs else None,
            "folders": [d for d in dirs[1:] if not is_noise(d)],
            "manufacturer": "Yamaha",
            "model": "DX7",
            "instrument": bank.rsplit("/", 1)[-1].rsplit(".", 1)[0],
            "patch": cand.voice["name"].strip(),
            "voice_number": cand.voice["index"],
        }
    parts = cand.rel.split("/")
    dirs = parts[:-1]
    leaf = parts[-1]
    if cand.is_file and "." in leaf:
        leaf = leaf.rsplit(".", 1)[0]
    family_raw = dirs[0] if dirs else (parts[0] if not cand.is_file else "")
    groups = [d for d in dirs[1:] if not is_noise(d)]
    manufacturer = model = None
    if family_raw.lower() == "synthesizers" and len(dirs) >= 3:
        manufacturer = re.sub(r"Synthesizers?$", "", dirs[1]).strip() or dirs[1]
        model = dirs[2]
        instrument = model
    else:
        instrument = groups[0] if groups else leaf
        words = " ".join(parts)
        for m in MANUFACTURERS:
            if re.search(rf"(?<![A-Za-z]){re.escape(m)}(?![a-z])", words, re.I):
                manufacturer = m
                break
        if manufacturer:
            for p in dirs + [leaf]:
                if manufacturer.lower() in p.lower():
                    model = p
                    break
    return {
        "family": humanize(family_raw.lstrip(".")) or None,
        "family_folder": family_raw or None,
        "folders": groups,
        "manufacturer": manufacturer,
        "model": model,
        "instrument": instrument,
        "patch": leaf,
    }


def notes_in_name(name):
    """Note names found in a file name, as MIDI numbers assuming C4 = 60.

    Sample makers disagree on octave numbering, so treat these as hints.
    """
    out = []
    for m in NOTE_IN_NAME_RE.finditer(name):
        acc = {"#": 1, "s": 1, "b": -1, None: 0}[m.group(2)]
        out.append(NOTE_BASE[m.group(1).lower()] + acc + (int(m.group(3)) + 1) * 12)
    return out


def words(text):
    text = humanize(text or "")
    return [w for w in re.split(r"[^a-z0-9]+", text.lower()) if w]


def build_tags(identity, extra_words=(), flags=(), category=None, keywords=()):
    tags = []

    def add(t):
        t = slugify(str(t)) if t else None
        if t and t not in tags:
            tags.append(t)

    fam = (identity.get("family_folder") or "").lower()
    for t in FAMILY_TAGS.get(fam, [identity.get("family")]):
        add(t)
    add(identity.get("manufacturer"))
    add(identity.get("model"))
    add(identity.get("instrument"))
    if category:
        add(category)
    for k in keywords:
        add(k)
    for w in extra_words:
        for x in words(w):
            if x in ARTICULATIONS:
                add(x)
    for f in flags:
        add(f)
    return sorted(tags)


def summarize_samples(samples):
    rates = sorted({s["sample_rate"] for s in samples if s.get("sample_rate")})
    bits = sorted({s["bit_depth"] for s in samples if s.get("bit_depth")})
    chans = sorted({s["channels"] for s in samples if s.get("channels")})
    fmts = sorted({s["format"] for s in samples if s.get("format")})
    durs = [s["duration_s"] for s in samples if s.get("duration_s") is not None]
    return {
        "sample_count": len(samples),
        "sample_rates": rates,
        "bit_depths": bits,
        "channels": chans,
        "stereo": 2 in chans or any(c > 2 for c in chans),
        "mono": 1 in chans,
        "sample_formats": fmts,
        "total_duration_s": round(sum(durs), 6),
        "min_duration_s": min(durs) if durs else None,
        "max_duration_s": max(durs) if durs else None,
    }


def summarize_zones(zones, group_names=()):
    roots = sorted({z["root_key"] for z in zones})
    vel_layers = sorted({tuple(z["velocity_range"]) for z in zones})
    per_note = [set() for _ in range(128)]
    for z in zones:
        if z["release_trigger"]:
            continue
        lo, hi = max(0, z["key_range"][0]), min(127, z["key_range"][1])
        for n in range(lo, hi + 1):
            per_note[n].add(tuple(z["velocity_range"]))
    layers = max((len(v) for v in per_note), default=0)
    stacks = {}
    for z in zones:
        k = (tuple(z["key_range"]), tuple(z["velocity_range"]), z["trigger"])
        stacks[k] = stacks.get(k, 0) + 1
    seq = max([z["seq_length"] or 0 for z in zones] or [0])
    rr_named = sorted({g for g in group_names if re.search(r"(^|[^a-z])rr\d*", g.lower())})
    return {
        "zone_count": len(zones),
        "root_notes": roots,
        "key_span": [min(z["key_range"][0] for z in zones),
                     max(z["key_range"][1] for z in zones)] if zones else None,
        "velocity_ranges": [list(v) for v in vel_layers],
        # most distinct velocity ranges playing on any one key (attack zones)
        "velocity_layer_count": layers,
        "max_zones_per_key_velocity": max(stacks.values()) if stacks else 0,
        "round_robin": {
            "seq_length": seq or None,
            "groups_named_rr": rr_named,
            "max_stacked_zones": max(stacks.values()) if stacks else 0,
            "likely": bool(seq > 1 or rr_named),
        },
        "looped": any(z["loop"]["looped"] for z in zones),
        "looped_zone_count": sum(1 for z in zones if z["loop"]["looped"]),
        "release_trigger_zones": sum(1 for z in zones if z["release_trigger"]),
        "exclusive_groups": sorted({z["exclusive_group"] for z in zones
                                    if z["exclusive_group"] is not None}),
        "groups": sorted({z["group_label"] for z in zones if z["group_label"]}),
    }


def readme_text(sc):
    o, i, c, p = sc["origin"], sc["identity"], sc.get("content", {}), sc["processing"]
    lines = [
        f"{i.get('patch')}  ({sc['status']})",
        "=" * 60,
        f"Source:        {o['source_path']}",
        f"Format:        {o['format']}",
        f"SHA-256:       {o.get('source_sha256')}",
        f"Collection:    {o['collection'].get('name')} {o['collection'].get('version') or ''}".rstrip(),
        f"License:       {o['license'].get('name')}",
        "",
        f"Family:        {i.get('family')}",
        f"Manufacturer:  {i.get('manufacturer') or '-'}",
        f"Model:         {i.get('model') or '-'}",
        f"Instrument:    {i.get('instrument')}",
        f"Category:      {i.get('category') or '-'}",
        "",
    ]
    s = c.get("samples_summary") or {}
    z = c.get("zones_summary") or {}
    if s:
        lines += [
            f"Samples:       {s.get('sample_count')}  rate {s.get('sample_rates')}  "
            f"bits {s.get('bit_depths')}  channels {s.get('channels')}",
            f"Duration:      total {s.get('total_duration_s')} s  "
            f"(per sample {s.get('min_duration_s')} - {s.get('max_duration_s')} s)",
        ]
    if z:
        lines += [
            f"Zones:         {z.get('zone_count')}  roots {z.get('root_notes')}",
            f"Velocity:      {z.get('velocity_layer_count')} layer(s)",
            f"Round robin:   {'yes' if z.get('round_robin', {}).get('likely') else 'no'}",
            f"Loops:         {'yes' if z.get('looped') else 'no'}",
        ]
    r = c.get("render")
    if r:
        lines.append(f"Render:        keys {r.get('notes')} (first {r.get('first_note')}, step "
                     f"{r.get('step')}), velocity {r.get('velocities')}, hold {r.get('hold_s')} s, "
                     f"release {r.get('release_s')} s, gap {r.get('gap_s')} s")
    d = (c.get("dx7") or {}).get("params")
    if d:
        lines.append(f"DX7 voice:     algorithm {d['algorithm']}, feedback {d['feedback']}, "
                     f"carriers {c['dx7'].get('carriers')}, transpose {d['transpose_semitones']:+d}")
    if i.get("description"):
        lines.append(f"Description:   {i['description']}")
    if c.get("notes_from_names"):
        lines.append(f"Notes in file names (C4=60, hint only): {c['notes_from_names']}")
    out = sc.get("outputs") or {}
    if out:
        lines += ["", "Files here:"]
        for k, v in out.items():
            if v:
                lines.append(f"  {k}: {v}")
    if p.get("lost"):
        lines += ["", "Not carried over:"] + [f"  - {x}" for x in p["lost"]]
    if p.get("warnings"):
        lines += ["", "Warnings:"] + [f"  - {x}" for x in p["warnings"]]
    lines += ["", f"Tags: {', '.join(sc.get('tags', []))}", "",
              f"Made by {p['tool']} {p['tool_version']}"
              + (f" with ConvertWithMoss {p['convertwithmoss_version']}"
                 if p.get("convertwithmoss_version") else "")
              + f" on {p.get('date')}. Full details: instrument.json", ""]
    return "\n".join(lines)
