#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Write AKRecipe / AKCueMap .tres files from Python dicts (handy for batches).

Strings starting with & become StringNames (&"saw"); "$token" stays a string
for palette lookup; layers / fx / transforms become Array[Dictionary].
"""
import os


def gd(v):
    if isinstance(v, bool):
        return "true" if v else "false"
    if isinstance(v, (int, float)):
        return repr(float(v)) if isinstance(v, float) else str(v)
    if isinstance(v, str):
        return '&"%s"' % v[1:] if v.startswith("&") else '"%s"' % v
    if isinstance(v, list):
        return "[" + ", ".join(gd(x) for x in v) + "]"
    if isinstance(v, dict):
        return "{" + ", ".join('"%s": %s' % (k, gd(x)) for k, x in v.items()) + "}"
    raise TypeError(v)


TYPED = {"layers", "fx", "transforms"}


def recipe(path, palette=None, **fields):
    lines = ['[gd_resource type="Resource" script_class="AKRecipe" format=3]', "",
             '[ext_resource type="Script" path="res://addons/audio_kit/core/recipe.gd" id="1"]']
    if palette:
        lines.append('[ext_resource type="Resource" path="%s" id="2"]' % palette)
    lines += ["", "[resource]", 'script = ExtResource("1")']
    for k, v in fields.items():
        if k in TYPED:
            lines.append("%s = Array[Dictionary](%s)" % (k, gd(v)))
        elif k == "voice":
            lines.append('voice = &"%s"' % v)
        else:
            lines.append("%s = %s" % (k, gd(v)))
    if palette:
        lines.append('palette = ExtResource("2")')
    os.makedirs(os.path.dirname(path), exist_ok=True)
    open(path, "w").write("\n".join(lines) + "\n")


def cue_map(path, sounds, master_fx=None, reverb=None, end_fade_s=None):
    names = list(sounds.items())
    lines = ['[gd_resource type="Resource" script_class="AKCueMap" format=3]', "",
             '[ext_resource type="Script" path="res://addons/audio_kit/core/cue_map.gd" id="1"]']
    for i, (_, res) in enumerate(names):
        lines.append('[ext_resource type="Resource" path="%s" id="%d"]' % (res, i + 2))
    lines += ["", "[resource]", 'script = ExtResource("1")',
              "sounds = {" + ", ".join('"%s": ExtResource("%d")' % (n, i + 2) for i, (n, _) in enumerate(names)) + "}"]
    if master_fx is not None:
        lines.append("master_fx = Array[Dictionary](%s)" % gd(master_fx))
    if reverb is not None:
        lines.append("reverb = %s" % gd(reverb))
    if end_fade_s is not None:
        lines.append("end_fade_s = %s" % gd(float(end_fade_s)))
    open(path, "w").write("\n".join(lines) + "\n")


def resource(path, script_class, script_path, fields, refs=None, typed=()):
    """Any kit resource (AKPattern, AKSong, AKTempoMap...). `refs` maps a field to
    a res:// path written as an ExtResource; `typed` names Array[Dictionary] fields."""
    refs = refs or {}
    lines = ['[gd_resource type="Resource" script_class="%s" format=3]' % script_class, "",
             '[ext_resource type="Script" path="%s" id="1"]' % script_path]
    for i, (k, rp) in enumerate(refs.items()):
        lines.append('[ext_resource type="Resource" path="%s" id="%d"]' % (rp, i + 2))
    lines += ["", "[resource]", 'script = ExtResource("1")']
    for k, v in fields.items():
        if k in typed:
            lines.append("%s = Array[Dictionary](%s)" % (k, gd(v)))
        else:
            lines.append("%s = %s" % (k, gd(v)))
    for i, k in enumerate(refs):
        lines.append('%s = ExtResource("%d")' % (k, i + 2))
    os.makedirs(os.path.dirname(path), exist_ok=True)
    open(path, "w").write("\n".join(lines) + "\n")
