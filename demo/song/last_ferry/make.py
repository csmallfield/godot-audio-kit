#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Last Ferry: an original late-night ballad, F minor, 80 bpm, about 2:50.
Reed lead (saxophone-like) over electric piano, pad, fretless-ish bass and a
drum machine with a gated snare. Intro, verse, chorus, verse, chorus, a solo
over new changes, a last chorus a semitone up, outro.

Everything here is data for the Audio Kit: recipes, patterns and the song.
Regenerate: python3 demo/song/last_ferry/make.py"""
import os, sys
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "../../../tools"))
from write_recipes import recipe, resource, cue_map

D = os.path.dirname(os.path.abspath(__file__))
R = "res://demo/song/last_ferry/"
S = "res://addons/audio_kit/sequencer/"
BAR = 16          # steps per bar (sixteenths)

# ------------------------------------------------------------------ sounds
vel = {"intensity": {"gain_db": [-9.0, 0.0]}}
recipe(os.path.join(D, "lead.tres"), voice="reed", seed=101, send=0.35,
       params={"brightness": 0.62, "breath": 0.14, "growl": 0.18, "vibrato_cents": 24.0, "vibrato_delay_s": 0.3,
               "release_s": 0.12, "sustain": 0.8},
       fx=[{"type": "echo", "time_s": 0.5625, "feedback": 0.22, "mix": 0.16, "tail_s": 1.2}],
       bind={"intensity": {"gain_db": [-8.0, 0.0], "brightness": [0.45, 0.75]}})
recipe(os.path.join(D, "ep.tres"), voice="fm", seed=102, send=0.25,
       params={"ratio": 1.0, "index": 2.2, "index_end": 0.35, "index_decay_s": 0.5, "ratio2": 14.0, "index2": 0.18,
               "attack_s": 0.002, "decay_s": 1.6, "sustain": 0.22, "release_s": 0.35},
       fx=[{"type": "lowpass", "cutoff_hz": 4200.0}], bind=vel)
recipe(os.path.join(D, "pad.tres"), voice="wavetable", seed=103, send=0.55,
       params={"position": 0.32, "unison": 5, "detune_cents": 11.0, "cutoff_hz": 1100.0, "env_octaves": 0.4,
               "filter_decay_s": 2.0, "q": 0.6, "attack_s": 0.7, "decay_s": 1.0, "sustain": 0.8, "release_s": 0.9})
recipe(os.path.join(D, "bass.tres"), voice="fm", seed=104, send=0.05,
       params={"ratio": 1.0, "index": 1.4, "index_end": 0.35, "index_decay_s": 0.22, "attack_s": 0.006, "decay_s": 0.5,
               "sustain": 0.55, "release_s": 0.07},
       fx=[{"type": "lowpass", "cutoff_hz": 900.0}], bind=vel)
recipe(os.path.join(D, "kick.tres"), voice="kick", seed=105,
       params={"tune_hz": 52.0, "punch": 2.2, "decay_s": 0.38, "click": 0.25, "drive": 0.15}, bind=vel)
# The big 80s snare: a short bright room, cut off hard (gated reverb).
recipe(os.path.join(D, "snare.tres"), voice="snare", seed=106, send=0.15,
       params={"tone_hz": 185.0, "tone": 0.55, "noise": 0.85, "noise_hz": 6000.0, "noise_decay_s": 0.2},
       fx=[{"type": "room", "room": 0.9, "damp": 0.3, "mix": 0.75, "quality": "small", "tail_s": 0.5}],
       transforms=[{"type": "trim", "length_s": 0.42}, {"type": "fade", "out_s": 0.06}], bind=vel)
recipe(os.path.join(D, "rim.tres"), voice="snare", seed=107, send=0.2,
       params={"tone_hz": 420.0, "tone": 0.8, "noise": 0.25, "noise_hz": 7000.0, "noise_decay_s": 0.04, "tone_decay_s": 0.03},
       bind=vel)
recipe(os.path.join(D, "hat.tres"), voice="hat", seed=108, vary={"decay_s": 0.2}, vary_variants=4,
       params={"decay_s": 0.05, "tone_hz": 8500.0, "metal": 0.5}, bind=vel)
recipe(os.path.join(D, "crash.tres"), voice="hat", seed=109, send=0.4,
       params={"decay_s": 1.4, "tone_hz": 6500.0, "metal": 0.75, "tune": 0.8})
recipe(os.path.join(D, "riser.tres"), voice="whoosh", seed=110, send=0.5, offset_s=-1.4,
       params={"length_s": 1.5, "low_hz": 400.0, "high_hz": 9000.0, "peak": 0.95, "shape": 2.0})

# ------------------------------------------------------------------ harmony
# Voicings (MIDI, four upper voices, voice-led) and bass roots.
CH = {
    "Fm7": ([53, 56, 60, 63], 41), "Dbmaj7": ([53, 56, 60, 61], 37), "Bbm7": ([53, 56, 58, 61], 34),
    "C7": ([52, 55, 58, 60], 36), "Eb": ([53, 55, 58, 63], 39), "Cm7": ([51, 55, 58, 60], 36),
    "Eb7": ([53, 55, 58, 61], 39), "Abmaj7": ([51, 55, 56, 60], 32), "Gm7b5": ([53, 55, 58, 61], 31),
}
INTRO = ["Fm7", "Dbmaj7", "Bbm7", "C7"]
VERSE = ["Fm7", "Dbmaj7", "Bbm7", "C7"] * 2
CHORUS = ["Dbmaj7", "Eb", "Cm7", "Fm7", "Dbmaj7", "Eb", "Bbm7", "C7"]
SOLO = ["Bbm7", "Eb7", "Abmaj7", "Dbmaj7", "Gm7b5", "C7", "Fm7", "C7"]
OUTRO = ["Fm7", "Dbmaj7", "Fm7", "Fm7"]

# ------------------------------------------------------------------ melody
# (bar, step in bar, length in steps, midi)
def m(*bars):
    out = []
    for b, notes in enumerate(bars):
        for st, ln, n in notes:
            out.append((b, st, ln, n))
    return out

INTRO_LEAD = m([], [], [(8, 8, 72)], [(0, 8, 70), (8, 8, 67)])
VERSE1 = m([(8, 4, 60), (12, 4, 63)],
           [(0, 6, 65), (6, 2, 63), (8, 4, 61), (12, 4, 60)],
           [(0, 6, 61), (6, 2, 60), (8, 8, 58)],
           [(0, 4, 60), (4, 4, 64), (8, 8, 67)],
           [(0, 6, 68), (6, 2, 67), (8, 4, 65), (12, 4, 63)],
           [(0, 8, 65), (8, 4, 68), (12, 4, 72)],
           [(0, 6, 73), (6, 2, 72), (8, 4, 70), (12, 4, 68)],
           [(0, 8, 67), (8, 4, 64), (12, 4, 60)])
VERSE2 = VERSE1[:12] + m([], [], [], [],
           [(0, 4, 68), (4, 4, 70), (8, 8, 72)],
           [(0, 6, 73), (6, 2, 72), (8, 8, 68)],
           [(0, 4, 70), (4, 4, 68), (8, 4, 65), (12, 4, 61)],
           [(0, 8, 64), (8, 8, 67)])
CHORUS_LEAD = m([(0, 4, 77), (4, 4, 75), (8, 8, 72)],
                [(0, 4, 70), (4, 2, 72), (6, 2, 70), (8, 8, 67)],
                [(0, 6, 72), (6, 2, 70), (8, 4, 67), (12, 4, 63)],
                [(0, 12, 65), (12, 4, 72)],
                [(0, 4, 77), (4, 4, 75), (8, 4, 72), (12, 4, 73)],
                [(0, 6, 75), (6, 2, 77), (8, 8, 79)],
                [(0, 4, 77), (4, 4, 73), (8, 4, 72), (12, 4, 70)],
                [(0, 8, 72), (8, 8, 67)])
SOLO_LEAD = m([(0, 2, 73), (2, 2, 72), (4, 2, 70), (6, 2, 68), (8, 8, 65)],
              [(0, 4, 67), (4, 2, 70), (6, 2, 73), (8, 6, 75), (14, 2, 73)],
              [(0, 8, 72), (8, 2, 75), (10, 2, 79), (12, 4, 80)],
              [(0, 8, 77), (8, 4, 72), (12, 4, 73)],
              [(0, 4, 73), (4, 4, 70), (8, 4, 67), (12, 4, 65)],
              [(0, 2, 64), (2, 2, 67), (4, 2, 70), (6, 2, 72), (8, 8, 76)],
              [(0, 12, 77), (12, 4, 75)],
              [(0, 4, 72), (4, 4, 70), (8, 8, 67)])
OUTRO_LEAD = m([(0, 8, 72), (8, 8, 68)], [(0, 16, 65)], [], [])


def note_name(n):
    names = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
    return "%s%d" % (names[n % 12], n // 12 - 1)


def melody_steps(mel, bars):
    """A notes-only lane: one entry per step, "." rest, "~" tie."""
    steps = ["."] * (bars * BAR)
    for b, st, ln, n in mel:
        i = b * BAR + st
        steps[i] = note_name(n)
        for k in range(1, ln):
            steps[i + k] = "~"
    return steps


# ------------------------------------------------------------------ lanes
def ep_lanes(chords, comp="X------.x-----.."):
    """Four EP voices, each playing its chord tone on every hit."""
    lanes = []
    hits = comp.count("X") + comp.count("x") + comp.count("o")
    for v in range(4):
        notes = []
        for c in chords:
            notes += [CH[c][0][v]] * hits
        lanes.append({"name": "ep%d" % v, "recipe": R + "ep.tres", "steps": comp * len(chords), "notes": notes,
                      "gate": 0.9, "gain_db": -12.0, "pan": [-0.35, -0.12, 0.12, 0.35][v]})
    return lanes


def pad_lanes(chords, gain=-13.0):
    lanes = []
    for v in range(3):
        notes = [CH[c][0][v + 1] for c in chords]
        lanes.append({"name": "pad%d" % v, "recipe": R + "pad.tres", "steps": ("x" + "-" * 15) * len(chords),
                      "notes": notes, "gate": 0.95, "gain_db": gain, "pan": [-0.4, 0.0, 0.4][v]})
    return lanes


def bass_lane(chords, rhythm="X-----.x-.x-----"):
    notes = []
    for c in chords:
        r = CH[c][1]
        notes += [r, r + 7, r]
    return {"name": "bass", "recipe": R + "bass.tres", "steps": rhythm * len(chords), "notes": notes, "gate": 0.9,
            "gain_db": -4.0}


def lead_lane(mel, bars, gain=-4.0):
    return {"name": "lead", "recipe": R + "lead.tres", "notes": melody_steps(mel, bars), "gate": 0.92, "gain_db": gain}


VERSE_DRUMS = [
    {"name": "kick", "recipe": R + "kick.tres", "steps": "X.........x.....", "length": 16, "gain_db": -9.0},
    {"name": "rim", "recipe": R + "rim.tres", "steps": "....o.......o...", "length": 16, "gain_db": 2.0},
    {"name": "hat", "recipe": R + "hat.tres", "steps": "x.o.x.o.x.o.x.o.", "length": 16, "gain_db": 2.0, "pan": 0.25},
]
CHORUS_DRUMS = [
    {"name": "kick", "recipe": R + "kick.tres", "steps": "X......x.x......", "length": 16, "gain_db": -7.0},
    {"name": "snare", "recipe": R + "snare.tres", "steps": "....X.......X...", "length": 16, "gain_db": 7.0},
    {"name": "hat", "recipe": R + "hat.tres", "steps": "x.x.X.x.x.x.X.x.", "length": 16, "gain_db": 4.0, "pan": 0.25},
]

P = "AKPattern"
def pattern(name, bars, lanes, seed):
    resource(os.path.join(D, name + ".tres"), P, S + "pattern.gd",
             {"steps": bars * BAR, "seed": seed, "swing": 0.53, "humanize_ms": 6.0, "humanize_velocity": 0.07,
              "lanes": lanes}, typed={"lanes"})
    return R + name + ".tres"

intro = pattern("p_intro", 4, ep_lanes(INTRO, "X---------------") + pad_lanes(INTRO, -13.0) + [lead_lane(INTRO_LEAD, 4, -2.0)], 1)
verse1 = pattern("p_verse1", 8, ep_lanes(VERSE) + pad_lanes(VERSE, -18.0) + [bass_lane(VERSE)] + VERSE_DRUMS + [lead_lane(VERSE1, 8, -1.0)], 2)
chorus = pattern("p_chorus", 8, ep_lanes(CHORUS, "X---x---X---x---") + pad_lanes(CHORUS) + [bass_lane(CHORUS, "X-----.xX-----.x")] + CHORUS_DRUMS + [lead_lane(CHORUS_LEAD, 8, 2.0)], 3)
verse2 = pattern("p_verse2", 8, ep_lanes(VERSE) + pad_lanes(VERSE, -18.0) + [bass_lane(VERSE)] + VERSE_DRUMS + [lead_lane(VERSE2, 8, -1.0)], 4)
solo = pattern("p_solo", 8, ep_lanes(SOLO, "X---x---X---x---") + pad_lanes(SOLO, -14.0) + [bass_lane(SOLO)] + CHORUS_DRUMS + [lead_lane(SOLO_LEAD, 8, 3.0)], 5)
outro = pattern("p_outro", 4, ep_lanes(OUTRO, "X---------------") + pad_lanes(OUTRO, -12.0) + [lead_lane(OUTRO_LEAD, 4, -1.0)], 6)

resource(os.path.join(D, "tempo.tres"), "AKTempoMap", S + "tempo_map.gd", {"bpm": 80.0, "beats_per_bar": 4, "offset_s": 0.2})

sections = [
    {"name": "intro", "bars": 4, "patterns": [intro], "automation": {"pad0.gain_db": [[0.0, -10.0], [1.0, 0.0]]}},
    {"name": "verse1", "bars": 8, "patterns": [verse1]},
    {"name": "chorus1", "bars": 8, "patterns": [chorus]},
    {"name": "verse2", "bars": 8, "patterns": [verse2]},
    {"name": "chorus2", "bars": 8, "patterns": [chorus]},
    {"name": "solo", "bars": 8, "patterns": [solo], "automation": {"lead.brightness": [[0.0, 0.6], [1.0, 0.85]]}},
    {"name": "chorus3", "bars": 8, "patterns": [chorus], "transpose": 1, "gain_db": 1.0},
    {"name": "outro", "bars": 4, "patterns": [outro],
     "automation": {"lead.gain_db": [[0.0, 0.0], [1.0, -6.0]], "ep0.gain_db": [[0.5, 0.0], [1.0, -12.0]]}},
]
stingers = [{"to": c, "recipe": R + "crash.tres", "gain_db": -8.0} for c in ["chorus1", "chorus2", "chorus3"]]
stingers += [{"to": "solo", "recipe": R + "riser.tres", "gain_db": -6.0}, {"to": "chorus3", "from": "solo", "recipe": R + "crash.tres", "gain_db": -6.0}]

resource(os.path.join(D, "last_ferry.tres"), "AKSong", S + "song.gd", {
    "sections": sections,
    "stingers": stingers,
    "reverb": {"room": 0.72, "damp": 0.35, "width": 1.0, "quality": "full", "return_db": -2.0},
    "master_fx": [{"type": "dcblock"}, {"type": "lowpass", "cutoff_hz": 15000.0}, {"type": "loudness", "target_lufs": -16.0},
                  {"type": "limit", "ceiling_db": -1.5}],
}, refs={"tempo": R + "tempo.tres"}, typed={"sections", "stingers", "master_fx"})
# The video's cue map: no effects of its own, the song's space and a master
# chain at the kit's level (the AKCueBridge mixes the song through it).
cue_map(os.path.join(D, "video_map.tres"), {}, reverb={"room": 0.72, "damp": 0.35, "width": 1.0, "quality": "full", "return_db": -2.0})
bars = sum(s["bars"] for s in sections)
print("wrote Last Ferry: %d bars, %.1f s" % (bars, bars * 3.0 + 0.2))
