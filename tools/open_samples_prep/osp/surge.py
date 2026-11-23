"""Surge XT patches (.fxp): read, and name the parameters.

Surge XT (Surge Synth Team, free, GPL-3) saves a patch as a VST2 program chunk (CcnK/FPCh, plugin
id 'cjs3') holding Surge's own chunk: "sub3", a small header, then the patch as XML: <patch
revision="n"><meta name category comment author/><parameters> one element per parameter,
<name type="0|2" value="..."/> (0 an int, 2 a float in the parameter's own units), modulation
routings as <modrouting source depth .../> children of the parameter they move; then step
sequences, MSEGs, formulas, the macros (<customcontroller>) and more.

Old revisions are migrated by Surge as it loads them (filter types, envelope and LFO behaviour),
so the parameters here are as the file holds them; render_vsynth.py stores what Surge itself
saves back (the current revision) beside its reference render.

Menus are Surge XT 1.3.4's (src/common/SurgeStorage.h, ModulationSource.h; sst-filters'
FilterConfiguration.h).
"""

import hashlib
import re
import struct
import xml.etree.ElementTree as ET

OSC_TYPES = ["classic", "sine", "wavetable", "s&h noise", "audio input", "fm3", "fm2", "window",
             "modern", "string", "twist", "alias"]
SCENE_MODES = ["single", "key split", "dual", "channel split"]
PLAY_MODES = ["poly", "mono", "mono single trigger", "mono fingered portamento",
              "mono single trigger fingered portamento", "latch"]
FILTER_CONFIGS = ["serial 1", "serial 2", "serial 3", "dual 1", "dual 2", "stereo", "ring", "wide"]
FM_ROUTINGS = ["off", "2 > 1", "3 > 2 > 1", "2 > 1 < 3"]
LFO_TYPES = ["sine", "triangle", "square", "sawtooth", "noise", "sample & hold", "envelope",
             "step sequencer", "mseg", "formula"]
FILTER_TYPES = ["off", "lp 12", "lp 24", "lp legacy ladder", "hp 12", "hp 24", "bp 12", "notch 12",
                "comb +", "sample & hold", "lp vintage ladder", "lp ob-xd 12", "lp ob-xd 24", "lp k35",
                "hp k35", "lp diode ladder", "lp cutoff warp", "hp cutoff warp", "notch cutoff warp",
                "bp cutoff warp", "hp ob-xd 12", "notch ob-xd 12", "bp ob-xd 12", "bp 24", "notch 24",
                "comb -", "allpass", "allpass cutoff warp", "lp resonance warp", "hp resonance warp",
                "notch resonance warp", "bp resonance warp", "allpass resonance warp", "tri-pole"]
FX_TYPES = ["off", "delay", "reverb 1", "phaser", "rotary speaker", "distortion", "eq",
            "frequency shifter", "conditioner", "chorus", "vocoder", "reverb 2", "flanger",
            "ring modulator", "airwindows", "neuron", "graphic eq", "resonator", "chow", "exciter",
            "ensemble", "combulator", "nimbus", "tape", "treemonster", "waveshaper", "mid-side tool",
            "spring reverb", "bonsai", "audio input"]
MOD_SOURCES = ["original", "velocity", "keytrack", "poly aftertouch", "aftertouch", "pitchbend",
               "modwheel", "macro1", "macro2", "macro3", "macro4", "macro5", "macro6", "macro7",
               "macro8", "amp eg", "filter eg", "lfo1", "lfo2", "lfo3", "lfo4", "lfo5", "lfo6",
               "slfo1", "slfo2", "slfo3", "slfo4", "slfo5", "slfo6", "timbre", "release velocity",
               "random bipolar", "random unipolar", "alternate bipolar", "alternate unipolar",
               "breath", "expression", "sustain", "lowest key", "highest key", "latest key"]


def is_surge(name, data):
    return name.lower().endswith(".fxp") and len(data) > 64 and data[:4] == b"CcnK" and data[16:20] == b"cjs3"


def chunk(data):
    """An .fxp's program chunk: Surge's own state ("sub3" ...), as the plugin loads it."""
    if not (data[:4] == b"CcnK" and data[8:12] == b"FPCh" and data[16:20] == b"cjs3"):
        raise ValueError("not a Surge program (.fxp, plugin id cjs3)")
    n = struct.unpack(">I", data[56:60])[0]
    c = data[60:60 + n]
    if len(c) < n or not c.startswith(b"sub3"):
        raise ValueError("no Surge chunk")
    return c


def patch_xml(c):
    """The patch XML in a Surge chunk (or a state saved by the plugin)."""
    i = c.find(b"<?xml")
    if i < 0:
        i = c.find(b"<patch")
    if i < 0:
        raise ValueError("no patch XML")
    return c[i:].split(b"\0", 1)[0].decode("utf-8", "replace")


def _num(v):
    try:
        f = float(v)
    except (TypeError, ValueError):
        return v
    return int(f) if re.fullmatch(r"-?\d+", v.strip()) else f


def parse_xml(x):
    """Patch XML -> {name, category, comment, author, revision, params {name: value}, mods
    [{dest, source, source_name, depth, ...}], macros [{v, bipolar, label}]}."""
    # Some patches hold character references XML forbids (control characters in a comment).
    x = re.sub(r"&#(x[0-9a-fA-F]+|[0-9]+);", lambda m: "" if int(m.group(1)[1:], 16) < 32 and m.group(1)[0] == "x"
               or (m.group(1)[0] != "x" and int(m.group(1)) < 32) else m.group(0), x)
    root = ET.fromstring(x.encode("utf-8"))
    meta = root.find("meta")
    m = meta.attrib if meta is not None else {}
    params, mods = {}, []
    ps = root.find("parameters")
    for el in (list(ps) if ps is not None else []):
        if "value" in el.attrib:
            params[el.tag] = _num(el.attrib["value"])
        for r in el.findall("modrouting"):
            a = {k: _num(v) for k, v in r.attrib.items()}
            s = a.get("source")
            a["dest"] = el.tag
            a["source_name"] = MOD_SOURCES[s] if isinstance(s, int) and 0 <= s < len(MOD_SOURCES) else str(s)
            mods.append(a)
    macros = []
    cc = root.find("customcontroller")
    for e in (list(cc) if cc is not None else []):
        macros.append({"v": _num(e.attrib.get("v", "0")), "bipolar": _num(e.attrib.get("bipolar", "0")),
                       "label": e.attrib.get("label", "")})
    return {"name": m.get("name", ""), "category": m.get("category", ""), "comment": m.get("comment", ""),
            "author": m.get("author", ""), "revision": int(root.attrib.get("revision", "0") or 0),
            "params": params, "mods": mods, "macros": macros}


def read(data):
    """Bytes of an .fxp -> parse_xml's fields plus the chunk and its XML."""
    c = chunk(data)
    x = patch_xml(c)
    d = parse_xml(x)
    d["chunk"] = c
    d["xml"] = x
    return d


def sound_sha256(parsed):
    """The parameters and routings (not the meta): the same sound under another name hashes the same."""
    x = parsed["xml"]
    i, j = x.find("<parameters"), x.rfind("</patch>")
    return hashlib.sha256(x[i:j].encode("utf-8")).hexdigest()


def _pick(table, v):
    return table[v] if isinstance(v, int) and 0 <= v < len(table) else str(v)


def named_params(parsed):
    p = parsed["params"]
    g = lambda k, d=0: p.get(k, d)  # noqa: E731
    names = {"scene_mode": _pick(SCENE_MODES, g("scenemode")), "fx": []}
    for i in range(1, 17):
        t = g("fx%d_type" % i)
        if t:
            names["fx"].append(_pick(FX_TYPES, t))
    f = []
    scenes = ["a", "b"] if g("scenemode") in (1, 2, 3) else ["a" if g("scene_active") == 0 else "b"]
    if len(scenes) > 1:
        f.append("two scenes (" + names["scene_mode"] + ")")
    for s in scenes:
        S = s.upper()
        names[s] = {"play_mode": _pick(PLAY_MODES, g(s + "_polymode")),
                    "filter_config": _pick(FILTER_CONFIGS, g(s + "_fb_config")),
                    "fm": _pick(FM_ROUTINGS, g(s + "_fm_switch"))}
        oscs = []
        for o in "123":
            if g("%s_mute_o%s" % (s, o)) or g("%s_level_o%s" % (s, o)) <= 0.0:
                continue
            oscs.append(_pick(OSC_TYPES, g("%s_osc%s_type" % (s, o))))
        names[s]["oscillators"] = oscs
        for o in oscs:
            f.append("%s osc %s" % (S, o))
        if not g(s + "_mute_noise") and g(s + "_level_noise") > 0.0:
            f.append(S + " noise")
        if not g(s + "_mute_ring12") or not g(s + "_mute_ring23"):
            f.append(S + " ring")
        if g(s + "_fm_switch"):
            f.append(S + " fm " + names[s]["fm"])
        fts = []
        for k in "12":
            ft = g("%s_filter%s_type" % (s, k))
            if ft:
                fts.append(_pick(FILTER_TYPES, ft))
        names[s]["filters"] = fts
        for ft in fts:
            f.append(S + " filter " + ft)
        if len(fts) == 2:
            f.append(S + " filters " + names[s]["filter_config"])
        if g(s + "_ws_type"):
            f.append(S + " waveshaper")
        if names[s]["play_mode"] != "poly":
            f.append(S + " " + names[s]["play_mode"])
        lfos = []
        for k in range(12):
            t = g("%s_lfo%d_shape" % (s, k), None)
            if t is None:
                continue
            src = 17 + k
            if any(m["source"] == src for m in parsed["mods"]):
                lfos.append(("lfo%d" % (k + 1) if k < 6 else "slfo%d" % (k - 5)) + " " + _pick(LFO_TYPES, t))
        names[s]["lfos"] = lfos
        for x in lfos:
            f.append(S + " " + x)
    for x in names["fx"]:
        f.append("fx " + x)
    return {"params": p, "names": names, "features": f}
