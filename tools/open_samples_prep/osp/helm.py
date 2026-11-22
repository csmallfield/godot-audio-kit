"""Helm presets (.helm): read, and name what matters.

Helm (Matt Tytel, GPL-3.0; factory presets CC-BY 4.0) saves a patch as JSON: metadata
(patch_name, author, license, folder_name, synth_version) and "settings", the plugin's
parameters in their own units (cutoff in semitones, times in seconds, switches and menus
as numbers), with "modulations", a list of {source, destination, amount}.
"""

import hashlib
import json

WAVES = ["sine", "triangle", "square", "down saw", "up saw", "3 step", "4 step", "8 step",
         "3 pyramid", "5 pyramid", "9 pyramid", "noise"]
FILTER_STYLES = ["12 dB", "24 dB", "shelf"]


def is_helm(name):
    return name.lower().endswith(".helm")


def read(data):
    """Bytes of a .helm file -> the JSON object. Raises ValueError when it isn't a Helm patch."""
    try:
        d = json.loads(data.decode("utf-8"))
    except (UnicodeDecodeError, json.JSONDecodeError) as e:
        raise ValueError("not JSON: %s" % e)
    if not isinstance(d, dict) or not isinstance(d.get("settings"), dict):
        raise ValueError("no settings")
    return d


def sound_sha256(d):
    s = d["settings"]
    mods = s.get("modulations", [])
    vals = {k: v for k, v in s.items() if k != "modulations"}
    key = json.dumps([sorted(vals.items()),
                      sorted((m.get("source"), m.get("destination"), m.get("amount")) for m in mods)],
                     sort_keys=True)
    return hashlib.sha256(key.encode()).hexdigest()


def named_params(d):
    s = d["settings"]
    g = lambda k: float(s.get(k, 0) or 0)  # noqa: E731

    def wave(k):
        i = int(g(k))
        return WAVES[i] if 0 <= i < len(WAVES) else "?"

    st = int(g("filter_style"))
    names = {"osc_1_waveform": wave("osc_1_waveform"), "osc_2_waveform": wave("osc_2_waveform"),
             "sub_waveform": wave("sub_waveform"),
             "filter_style": FILTER_STYLES[st] if 0 <= st < 3 else "?"}
    mods = s.get("modulations", [])
    f = []
    for n in ("1", "2"):
        if g("osc_%s_volume" % n) > 0.01:
            f.append("osc%s %s" % (n, names["osc_%s_waveform" % n]))
            if g("osc_%s_unison_voices" % n) > 1:
                f.append("osc%s unison" % n)
    if g("sub_volume") > 0.01:
        f.append("sub")
    if g("noise_volume") > 0.01:
        f.append("noise")
    if g("cross_modulation") > 0.001:
        f.append("cross mod")
    if abs(g("osc_feedback_amount")) > 0.001:
        f.append("osc feedback")
    if g("filter_on") > 0.5:
        f.append("filter " + names["filter_style"])
    if g("formant_on") > 0.5:
        f.append("formant")
    if g("distortion_on") > 0.5:
        f.append("distortion")
    if g("delay_on") > 0.5:
        f.append("delay")
    if g("reverb_on") > 0.5:
        f.append("reverb")
    if g("stutter_on") > 0.5:
        f.append("stutter")
    if g("arp_on") > 0.5:
        f.append("arpeggiator")
    if mods:
        f.append("%d modulations" % len(mods))
    return {"params": {k: v for k, v in s.items() if k != "modulations"}, "modulations": mods,
            "names": names, "features": f}
