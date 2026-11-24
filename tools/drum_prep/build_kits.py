#!/usr/bin/env python3
"""Build drum kits from a converted, tagged collection: writes <collection>/kits/<Machine>/<Kit>.json
and kits/index.json. GAK loads one with AKKit.load_json(path). See README.md (Kits)."""

import argparse
import json
import math
import os
import re
import shutil
import sys
from collections import Counter, defaultdict

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from dp import TOOL_VERSION  # noqa: E402
from dp.machine import safe_component  # noqa: E402

# Rows in GAK's order (as the shipped kits): name, level offset (dB, after peaks are set to -3 dBFS), pan.
ROWS = [("kick", -1.0, 0.0), ("snare", -3.0, 0.0), ("clap", -4.0, 0.0), ("closed_hat", -9.0, 0.15),
        ("open_hat", -10.0, 0.15), ("pedal_hat", -11.0, 0.15), ("tom_low", -5.0, -0.3), ("tom_mid", -5.0, 0.0),
        ("tom_high", -5.0, 0.3), ("crash", -10.0, -0.25), ("ride", -12.0, 0.25), ("rim", -9.0, -0.2),
        ("perc", -10.0, 0.2)]
ROW = {r[0]: r for r in ROWS}
ORDER = {r[0]: i for i, r in enumerate(ROWS)}
EXTRA_ROWS = {"fx": (-10.0, 0.0), "vox": (-8.0, 0.0), "loop": (-6.0, 0.0), "tonal": (-8.0, 0.0), "other": (-8.0, 0.0)}
CORE = {"kick", "snare", "clap", "hat", "tom", "cymbal", "rim"}
MAX_ASSEMBLED = 8
MAX_PERC = 16
_NAT = re.compile(r"(\d+)")


def natural(s):
    return [int(t) if t.isdigit() else t.lower() for t in _NAT.split(s)]


def role_of(final, feat):
    """A sound's row family from its final tag: kick, snare, clap, closed_hat ..., tom, crash, ride, rim, perc."""
    c, k = final.get("category", ""), (final.get("kind") or "").split(":")[0]
    if c in ("kick", "snare", "clap", "rim"):
        return c
    if c == "hat":
        if k == "pedal":
            return "pedal_hat"
        if k in ("open", "closed_to_open", "open_to_closed"):
            return "open_hat"
        if k == "closed":
            return "closed_hat"
        return "open_hat" if feat.get("decay40_s", 0) > 0.35 else "closed_hat"
    if c == "tom":
        return "perc" if k == "timpani" else "tom"
    if c == "cymbal":
        return "ride" if k in ("ride", "ride_bell") else "crash"
    if c == "perc":
        return "perc"
    return c or "other"


def rank(final, role=""):
    """Lower is better: both agree, then a sure name, a sure sound, an unsure name, an unsure sound.
    An open hat that is one (not a closed-to-open transition) comes before those that aren't."""
    f = final.get("from", "")
    if role == "open_hat" and (final.get("kind") or "") not in ("open", ""):
        return 5 + rank(final)
    if f == "both":
        return 0
    if f == "name":
        return 1 if final.get("sure") else 3
    return 2 if final.get("sure") else 4


def gain_for(row, peak_db):
    off = ROW[row][1] if row in ROW else EXTRA_ROWS.get(row, (-8.0, 0.0))[0]
    if peak_db is None:
        return off
    return round(max(-30.0, min(24.0, off + (-3.0 - peak_db))), 1)


class Collection:
    def __init__(self, out):
        self.out = out
        with open(os.path.join(out, "catalog.json"), encoding="utf-8") as fh:
            self.cat = {e["path"]: e for e in json.load(fh)["entries"]}
        with open(os.path.join(out, "tags.json"), encoding="utf-8") as fh:
            self.tags = json.load(fh)["files"]
        with open(os.path.join(out, "analysis", "features.json"), encoding="utf-8") as fh:
            self.feats = json.load(fh)["files"]

    def sound(self, path):
        """What a kit needs to know about one file."""
        e, t, f = self.cat[path], self.tags.get(path, {}), self.feats.get(path, {})
        fin = t.get("final", {"category": "", "kind": ""})
        pitch = t.get("analysis", {}).get("pitch_hz") or f.get("f0_late") or f.get("f0_early") or 0.0
        role = role_of(fin, f)
        return {"path": path, "final": fin, "role": role, "rank": rank(fin, role), "peak_db": e.get("peak_dbfs"),
                "pitch": pitch, "silent": f.get("silent", False), "layer": (e.get("layer_group"), e.get("layer_index")),
                "channels": e.get("channels", 1), "seconds": e.get("seconds", 0.0), "kind": e.get("kind", "oneshot")}


ROLE_WORDS = {"kick", "kik", "bd", "bassdrum", "bass", "snare", "snr", "sd", "clap", "hat", "hihat", "hh", "closed", "open",
              "pedal", "tom", "toms", "crash", "ride", "cymbal", "cym", "rim", "rimshot", "perc"}


def style_of(s):
    """A sound's style word, the first word of its name when that isn't the drum's own word
    ('Pop Kick 1' -> 'pop', 'TR-808 Snare' -> 'tr-808'); '' when there's none."""
    base = s["path"].rsplit("/", 1)[-1].rsplit(".", 1)[0]
    words = [w for w in re.split(r"[\s_]+", base.lower()) if w]
    if len(words) < 2 or words[0] in ROLE_WORDS or words[0].isdigit():
        return ""
    return words[0]


def unit_pieces(units, layer_members):
    """Sounds as kit units: a velocity-layer group (BK-5 [Vn]) is one unit holding all its layers."""
    out, seen = [], set()
    for s in units:
        g = s["layer"][0]
        if g:
            key = (s["path"].split("/", 1)[0], g)
            if key in seen:
                continue
            seen.add(key)
            members = sorted(layer_members[key], key=lambda m: int(m["layer"][1] or 0))
            out.append(dict(s, layers=members))
        else:
            out.append(s)
    return out


def piece(name, row, s):
    """A kit piece for unit `s` on row `row`, named `name`."""
    p = {"name": name}
    if s.get("layers") and len(s["layers"]) > 1:
        n = len(s["layers"])
        p["layers"] = [{"sound": m["path"], "up_to": round((i + 1) / n, 3)} for i, m in enumerate(s["layers"])]
        peak = max((m["peak_db"] for m in s["layers"] if m["peak_db"] is not None), default=None)
    else:
        p["sound"] = s["path"]
        peak = s["peak_db"]
    p["gain_db"] = gain_for(row, peak)
    pan = ROW[row][2] if row in ROW else 0.0
    if pan and s.get("channels", 1) == 1:
        p["pan"] = pan
    if row in ("closed_hat", "open_hat", "pedal_hat"):
        p["choke"] = "hats"
    fin = s["final"]
    p["category"], p["kind"], p["sure"] = fin.get("category", ""), fin.get("kind", ""), bool(fin.get("sure"))
    return p


def order_toms(toms):
    """Toms lowest first by measured pitch (unpitched ones last, in their own order)."""
    return sorted(toms, key=lambda s: (s["pitch"] <= 0, s["pitch"] if s["pitch"] > 0 else 0))


def folder_kit(name, machine, folder, sounds, layer_members):
    """Every file of a kit folder, rows in GAK's order, toms low to high."""
    units = unit_pieces([s for s in sounds if not s["silent"]], layer_members)
    by_role = defaultdict(list)
    for s in units:
        by_role[s["role"]].append(s)
    pieces, used = [], Counter()

    def add(base, row, s):
        used[base] += 1
        pieces.append(piece(base if used[base] == 1 else "%s_%d" % (base, used[base]), row, s))

    for r in ("kick", "snare", "clap", "closed_hat", "open_hat", "pedal_hat"):
        for s in by_role.get(r, []):
            add(r, r, s)
    toms = order_toms(by_role.get("tom", []))
    n = len(toms)
    for i, s in enumerate(toms):
        r = "tom_low" if n == 1 or i < n / 3 else "tom_mid" if i < 2 * n / 3 else "tom_high"
        add(r, r, s)
    for r in ("crash", "ride", "rim"):
        for s in by_role.get(r, []):
            add(r, r, s)
    for s in by_role.get("perc", []):
        base = (s["final"].get("kind") or "perc").split(":")[0] or "perc"
        add(base, "perc", s)
    for r in ("fx", "vox", "loop", "tonal", "other"):
        for s in by_role.get(r, []):
            add(r, r, s)
    return {"name": name, "machine": machine, "from": "folder", "folder": folder, "pieces": pieces}


def assembled_kits(machine, sounds, layer_members):
    """Kits put together from a machine's sounds: kit i takes the i-th best of each row."""
    units = unit_pieces([s for s in sounds if not s["silent"] and s["kind"] == "oneshot"], layer_members)
    pools = defaultdict(list)
    for s in sorted(units, key=lambda s: (s["rank"], natural(s["path"]))):
        pools[s["role"]].append(s)
    kicks, snares = pools.get("kick", []), pools.get("snare", []) or pools.get("clap", [])
    if not kicks or not snares:
        return []
    # Kicks whose style can fill most rows come first ('Pop Kick' when there are Pop snares,
    # hats, toms and cymbals), so the kits a machine sorted by instrument still hang together.
    styled = defaultdict(set)
    for r, pool in pools.items():
        for s in pool:
            st = style_of(s)
            if st:
                styled[st].add(r)
    kicks = sorted(kicks, key=lambda s: (-len(styled.get(style_of(s), ())) if style_of(s) else 0, s["rank"], natural(s["path"])))
    n = max(1, min(MAX_ASSEMBLED, len(kicks), len(snares)))
    tom_pool = pools.get("tom", [])
    best = [s for s in tom_pool if s["rank"] <= 1]      # toms the name says are toms, when there are enough
    toms = order_toms(best if len(best) >= 3 else tom_pool)
    kits = []
    for i in range(n):
        pieces = []
        kick = kicks[i % len(kicks)]
        home = kick["path"].rsplit("/", 1)[0]
        style = style_of(kick)

        def pick(pool, i=i):
            """The i-th of a pool, from the kick's own folder when that folder has any (a kit's set),
            else of the kick's style when any share it ('Pop Kick' with 'Pop Snare')."""
            same = [s for s in pool if s["path"].rsplit("/", 1)[0] == home]
            if not same and style:
                same = [s for s in pool if style_of(s) == style]
            use = same or pool
            return use[i % len(use)]

        for r in ("kick", "snare", "clap", "closed_hat", "open_hat", "pedal_hat"):
            pool = pools.get(r, [])
            if r == "pedal_hat" and not pool:
                pool = pools.get("closed_hat", [])
            if pool:
                pieces.append(piece(r, r, kick if r == "kick" else pick(pool)))
        if toms:
            # three toms spread over the machine's range, a different set per kit where there are enough
            same = [s for s in toms if s["path"].rsplit("/", 1)[0] == home]
            ts = same if len(same) >= 3 else toms
            k = len(ts)
            for j, r in enumerate(("tom_low", "tom_mid", "tom_high")):
                band = ts[int(j * k / 3): max(int(j * k / 3) + 1, int((j + 1) * k / 3))]
                pieces.append(piece(r, r, band[i % len(band)]))
        for r in ("crash", "ride", "rim"):
            pool = pools.get(r, [])
            if pool:
                pieces.append(piece(r, r, pick(pool)))
        perc = pools.get("perc", [])
        kinds = []
        for s in perc:
            kd = (s["final"].get("kind") or "perc").split(":")[0] or "perc"
            if kd not in kinds:
                kinds.append(kd)
        for j in range(min(2, len(kinds))):
            kd = kinds[(i * 2 + j) % len(kinds)]
            pick = [s for s in perc if ((s["final"].get("kind") or "perc").split(":")[0] or "perc") == kd]
            pieces.append(piece(kd, "perc", pick[i % len(pick)]))
        name = machine if n == 1 else "%s %d" % (machine, i + 1)
        kits.append({"name": name, "machine": machine, "from": "assembled", "pieces": pieces})
    return kits


def percussion_kit(machine, sounds, layer_members):
    units = unit_pieces([s for s in sounds if not s["silent"] and s["kind"] == "oneshot" and s["role"] == "perc"],
                        layer_members)
    by_kind = defaultdict(list)
    for s in sorted(units, key=lambda s: (s["rank"], natural(s["path"]))):
        by_kind[(s["final"].get("kind") or "perc").split(":")[0] or "perc"].append(s)
    if sum(len(v) for v in by_kind.values()) < 8 or len(by_kind) < 3:
        return None
    pieces, used = [], Counter()
    # one of each kind first, then seconds, up to MAX_PERC
    rnd = 0
    while len(pieces) < MAX_PERC and any(len(v) > rnd for v in by_kind.values()):
        for kd in sorted(by_kind):
            v = by_kind[kd]
            if rnd < len(v) and len(pieces) < MAX_PERC:
                used[kd] += 1
                pieces.append(piece(kd if used[kd] == 1 else "%s_%d" % (kd, used[kd]), "perc", v[rnd]))
        rnd += 1
    return {"name": "%s Percussion" % machine, "machine": machine, "from": "percussion", "pieces": pieces}


def sound_set(machine, sounds, layer_members):
    """For a machine nothing else makes a kit of: all its sounds (up to 64), rows in GAK's order."""
    fs = sorted([s for s in sounds if not s["silent"]], key=lambda s: natural(s["path"]))[:64]
    if not fs:
        return None
    k = folder_kit(machine, machine, "", fs, layer_members)
    k["from"] = "all"
    k.pop("folder", None)
    return k


def is_kit_folder(sounds):
    """A folder that is a kit: a kick, a snare or clap and a hat, and not mostly effects, voices,
    loops or tonal sounds (an FX or vocal folder with a stray kick isn't one; a GM kit full of
    percussion is)."""
    cats = [s["final"].get("category") for s in sounds]
    roles = set(cats)
    tagged = [c for c in cats if c]
    other = sum(1 for c in tagged if c in ("fx", "vox", "loop", "tonal"))
    return (len(sounds) >= 5 and "kick" in roles and ("snare" in roles or "clap" in roles) and "hat" in roles
            and other <= 0.4 * max(1, len(tagged)))


def kit_name_of(folder):
    leaf = folder.rsplit("/", 1)[-1]
    leaf = re.sub(r"^(DRM|PRC|BEL)_", "", leaf)
    return leaf.replace("_", " ").strip() or folder


def build(out):
    col = Collection(out)
    by_machine = defaultdict(list)
    for p in col.cat:
        by_machine[p.split("/", 1)[0]].append(col.sound(p))
    kits_dir = os.path.join(out, "kits")
    if os.path.isdir(kits_dir):
        shutil.rmtree(kits_dir)   # this tool's own output
    index = []
    for machine_dir, sounds in sorted(by_machine.items()):
        machine = col.cat[sounds[0]["path"]]["machine"]
        layer_members = defaultdict(list)
        for s in sounds:
            if s["layer"][0]:
                layer_members[(s["path"].split("/", 1)[0], s["layer"][0])].append(s)
        kits = []
        by_folder = defaultdict(list)
        for s in sounds:
            inner = s["path"].split("/", 1)[1]
            if "/" in inner:
                by_folder[inner.rsplit("/", 1)[0]].append(s)
        for folder, fs in sorted(by_folder.items()):
            if is_kit_folder(fs):
                fs.sort(key=lambda s: natural(s["path"]))
                kits.append(folder_kit(kit_name_of(folder), machine, folder, fs, layer_members))
        kits += assembled_kits(machine, sounds, layer_members)
        pk = percussion_kit(machine, sounds, layer_members)
        if pk:
            kits.append(pk)
        if not kits:
            ss = sound_set(machine, sounds, layer_members)
            if ss:
                kits.append(ss)
        names = Counter()
        for k in kits:
            names[k["name"]] += 1
            if names[k["name"]] > 1:
                k["name"] = "%s (%d)" % (k["name"], names[k["name"]])
            k["collection"] = os.path.basename(os.path.normpath(out))
            k["root"] = "../.."           # the collection, relative to this file
            k["tool_version"] = TOOL_VERSION
            k["sure_share"] = round(sum(1 for p in k["pieces"] if p["sure"]) / max(1, len(k["pieces"])), 2)
            rel = "%s/%s.json" % (safe_component(machine_dir), safe_component(k["name"]))
            path = os.path.join(kits_dir, *rel.split("/"))
            os.makedirs(os.path.dirname(path), exist_ok=True)
            with open(path, "w", encoding="utf-8", newline="\n") as fh:
                json.dump(k, fh, indent=1, ensure_ascii=False)
            index.append({"path": rel, "name": k["name"], "machine": machine, "from": k["from"],
                          "folder": k.get("folder", ""), "pieces": len(k["pieces"]), "sure_share": k["sure_share"],
                          "layered": sum(1 for p in k["pieces"] if "layers" in p)})
    with open(os.path.join(kits_dir, "index.json"), "w", encoding="utf-8", newline="\n") as fh:
        json.dump({"tool_version": TOOL_VERSION, "kits": index}, fh, indent=1, ensure_ascii=False)
    return index


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--out", required=True, help="the converted collection")
    a = ap.parse_args(argv)
    index = build(a.out)
    c = Counter(k["from"] for k in index)
    print("%d kits from %d machines: %s" % (len(index), len({k["machine"] for k in index}), dict(c)))
    print("layered pieces: %d; machines without a kit: see below" % sum(k["layered"] for k in index))
    return 0


if __name__ == "__main__":
    sys.exit(main())
