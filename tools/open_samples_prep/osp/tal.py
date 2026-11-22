"""TAL-NoiseMaker presets (.vstpreset, .noisemakerpreset): read, and name the parameters.

TAL-NoiseMaker (TAL Software, free; an older version is open source in DISTRHO-Ports)
saves its state as XML: <tal curprogram="n" version="..."><programs><program .../>...</programs>.
A .vstpreset wraps that XML (the whole bank) in a VST3 preset; a .noisemakerpreset is the
XML itself. The preset is the program at curprogram. Each program's attributes are the
plugin's parameters, normalized 0..1; a program can also hold the drawn envelope's curve
(<splinePoints>, Bezier points in 0..1).
"""

import hashlib
import re

# Menus, in the order the plugin lists them; a stored value v picks entry round(v * (n - 1)).
ENUMS = {
    "filtertype": ["LP 24", "LP 18", "LP 12", "LP 6", "HP 24", "BP 24", "Notch 24", "LP SV 24",
                   "HP SV 24", "BP SV 24", "Moog LP 24", "type 12"],
    "osc1waveform": ["saw", "pulse", "noise"],
    "osc2waveform": ["saw", "pulse", "sine", "noise", "triangle"],
    "lfo1waveform": ["sine", "triangle", "saw", "square", "sample and hold", "smooth random"],
    "lfo1destination": ["off", "filter", "osc1", "osc2", "pw", "fm", "lfo2 rate", "osc1+2"],
    "lfo2destination": ["off", "filter", "osc1", "osc2", "pan", "volume", "lfo1 rate", "osc1+2"],
    "freeaddestination": ["off", "filter", "osc1", "osc2", "pw", "fm"],
    "envelopeeditordest1": ["off", "filter", "osc1", "osc2", "osc1+2", "fm", "ringmod", "volume"],
    "portamentomode": ["off", "auto", "on"],
}
ENUMS["lfo2waveform"] = ENUMS["lfo1waveform"]
# Switches (on above 0.5).
SWITCHES = {"oscsync", "lfo1sync", "lfo1keytrigger", "lfo2sync", "lfo2keytrigger", "chorus1enable",
            "chorus2enable", "delaysync", "envelopeoneshot", "envelopefixtempo"}
# Editor state, not sound.
UI_KEYS = {"tab1open", "tab2open", "tab3open", "tab4open"}


def is_tal(name, data):
    n = name.lower()
    return n.endswith((".vstpreset", ".noisemakerpreset")) and b"<tal" in data


def _attrs(text):
    return dict(re.findall(r'([\w:.-]+)="([^"]*)"', text))


def read(data):
    """Bytes of a preset -> {name, version, program_xml, params {attr: float}, curve [points]}.

    The program is the one at curprogram. Raises ValueError when there is no TAL XML."""
    i = data.find(b"<tal")
    if i < 0:
        raise ValueError("no <tal> XML")
    x = data[i:].split(b"\0", 1)[0].decode("utf-8", "replace")
    head = re.match(r"<tal\b([^>]*)>", x)
    if not head:
        raise ValueError("no <tal> element")
    ha = _attrs(head.group(1))
    progs = re.findall(r"<program\b[^>]*?(?:/>|>.*?</program>)", x, re.S)
    if not progs:
        raise ValueError("no programs")
    cur = int(ha.get("curprogram", "0") or 0)
    prog = progs[cur] if 0 <= cur < len(progs) else progs[0]
    a = _attrs(prog[:prog.find(">")])
    params = {}
    for k, v in a.items():
        if k == "programname":
            continue
        try:
            params[k] = float(v)
        except ValueError:
            pass
    curve = [_attrs(m) for m in re.findall(r"<splinePoint\b([^>]*)/?>", prog)]
    curve = [{k: float(v) for k, v in p.items()} for p in curve]
    return {"name": a.get("programname", ""), "version": ha.get("version"), "program_xml": prog,
            "params": params, "curve": curve, "programs_in_file": len(progs), "curprogram": cur}


def pick(key, v):
    """The menu item TAL-NoiseMaker plays for a stored value (checked against 5.0.6). Menus round,
    floor(v (n - 1) + 1.5); the LFO waves truncate, int(v * 5.000001). osc2's items are saw, pulse,
    triangle, sine, noise (0.5 plays a triangle)."""
    table = ENUMS[key]
    if key == "osc2waveform":
        table = ["saw", "pulse", "triangle", "sine", "noise"]
    if key in ("lfo1waveform", "lfo2waveform"):
        return table[min(len(table) - 1, max(0, int(v * 5.000001)))]
    return table[min(len(table) - 1, max(0, int(v * (len(table) - 1) + 0.5)))]


def sound_sha256(parsed):
    p = parsed["params"]
    s = ",".join("%s=%.6f" % (k, p[k]) for k in sorted(p) if k not in UI_KEYS)
    s += "|" + ",".join("%.5f" % x for pt in parsed["curve"]
                        for x in (pt.get("centerPointX", 0), pt.get("centerPointY", 0)))
    return hashlib.sha256(s.encode()).hexdigest()


def named_params(parsed):
    p = parsed["params"]
    names = {k: pick(k, p[k]) for k in ENUMS if k in p}
    g = lambda k: p.get(k, 0.0)  # noqa: E731
    f = []
    if g("osc2volume") > 0.01:
        f.append("osc2 " + names.get("osc2waveform", "?"))
    if g("osc3volume") > 0.01:
        f.append("sub osc")
    if g("oscsync") > 0.5:
        f.append("sync")
    if g("ringmodulation") > 0.01:
        f.append("ring")
    if g("osc2fm") > 0.01:
        f.append("fm")
    for n in ("1", "2"):
        if abs(g("lfo%samount" % n) - 0.5) > 0.01 and names.get("lfo%sdestination" % n, "off") != "off":
            f.append("lfo%s -> %s" % (n, names["lfo%sdestination" % n])
                     + (" (tempo sync)" if g("lfo%ssync" % n) > 0.5 else ""))
    if g("freeadamount") > 0.01 and names.get("freeaddestination", "off") != "off":
        f.append("free AD -> " + names["freeaddestination"])
    if g("envelopeeditoramount") > 0.01 and names.get("envelopeeditordest1", "off") != "off":
        f.append("drawn envelope -> " + names["envelopeeditordest1"])
    if g("chorus1enable") > 0.5 or g("chorus2enable") > 0.5:
        f.append("chorus")
    if g("reverbwet") > 0.01:
        f.append("reverb")
    if g("delaywet") > 0.01:
        f.append("delay")
    if g("highpass") > 0.01:
        f.append("high-pass")
    if g("detune") > 0.01:
        f.append("detune")
    if g("vintagenoise") > 0.01:
        f.append("vintage noise")
    if g("oscbitcrusher") > 0.01:
        f.append("bitcrusher")
    if g("filterdrive") > 0.01:
        f.append("filter drive")
    if g("portamento") > 0.01 and names.get("portamentomode") != "off":
        f.append("glide")
    return {"params": p, "names": names, "features": f}
