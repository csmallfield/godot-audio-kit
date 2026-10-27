#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Writes tests/auxy/fixture.axbw: a small bundle shaped like Auxy's
"Export for Bitwig Studio" (a zip of manifest.json, loop_<channel>_<slot>.mid
and stem_<channel>.wav), and tests/auxy/fixture.json, the answer key worked
out here, independently of the importer.

The layout copies what real Auxy exports do (format_version 0.1, 480 ticks a
quarter, a tempo track plus a notes track, every track ending at the loop's
length) with music written for this fixture. It covers the cases that tripped
Auxy's other exporters and the importer's merging:

  - a scene with start_offset 1 (its loops start in their second bar)
  - a two-bar loop in one-bar scenes (it restarts each scene)
  - the same set of loops in consecutive scenes (one scene, no new marker)
  - two channels with the same preset name; a channel with no loops
  - loops the song never plays; an empty scene (silence)
  - a drum channel (notes from 36 up) and a velocity that isn't 127

    pip install mido
    python3 tools/auxy_fixture/make_fixture.py
"""
import io
import json
import os
import struct
import zipfile

import mido

OUT = os.path.join(os.path.dirname(__file__), "..", "..", "tests", "auxy")
PPQ = 480
BPM = 100

CHANNELS = [
    {"label": "Kit Alpha", "kind": "drums", "color": "#0270D6"},
    {"label": "Fat Basset", "kind": "instrument", "color": "#F4875C"},
    {"label": "Fat Basset", "kind": "instrument", "color": "#D45F9D"},
    {"label": "Empty One", "kind": "instrument", "color": "#42BD63"},
    {"label": "Glass Lead", "kind": "instrument", "color": "#F8A852"},
]

# key -> (beats, [(beat, length_beats, midi, velocity)])
LOOPS = {
    "0_0": (4, [(0, 0.25, 36, 127), (2, 0.25, 36, 127), (1, 0.25, 37, 127), (3, 0.25, 37, 127)]
           + [(i * 0.5, 0.25, 38, 127) for i in range(8)]),
    "0_1": (8, [(0, 0.25, 36, 127), (1, 0.25, 37, 127), (2.5, 0.25, 36, 127), (3, 0.25, 37, 127),
                (4, 0.25, 36, 127), (5, 0.25, 37, 127), (6, 0.25, 39, 100), (6.5, 0.25, 39, 100), (7, 0.25, 39, 100)]),
    "0_2": (4, [(0, 0.25, 40, 127)]),                                     # never played
    "1_0": (8, [(0, 1.5, 40, 127), (2, 0.5, 43, 127), (3, 0.5, 45, 127), (4, 1.5, 38, 127), (6, 1.0, 41, 127)]),
    "1_1": (4, [(0, 0.75, 36, 127), (1, 0.25, 36, 127), (2, 1.0, 39, 127)]),
    "2_0": (16, [(0, 8, 60, 127), (0, 8, 63, 127), (0, 8, 67, 127), (8, 8, 58, 127), (8, 8, 62, 127), (8, 8, 65, 127)]),
    "4_0": (8, [(0, 0.5, 79, 127), (1, 0.5, 82, 127), (2, 1.0, 84, 127), (4, 0.5, 86, 127), (5, 2.5, 84, 127)]),
    "4_1": (4, [(0, 1, 91, 127)]),                                        # never played
}

SCENES = [
    {"loop_locations": ["0_0"], "number_of_bars": 2, "start_offset": 0},
    {"loop_locations": ["0_0", "1_0"], "number_of_bars": 4, "start_offset": 0},
    {"loop_locations": ["1_0", "0_0"], "number_of_bars": 1, "start_offset": 0},
    {"loop_locations": ["0_0", "1_0"], "number_of_bars": 1, "start_offset": 0},
    {"loop_locations": ["0_1", "1_0", "2_0"], "number_of_bars": 3, "start_offset": 1},
    {"loop_locations": ["0_1", "1_0", "2_0", "4_0"], "number_of_bars": 4, "start_offset": 0},
    {"loop_locations": ["1_1"], "number_of_bars": 2, "start_offset": 0},
    {"loop_locations": [], "number_of_bars": 1, "start_offset": 0},
    {"loop_locations": ["0_0", "4_0"], "number_of_bars": 2, "start_offset": 0},
]


def loop_midi(beats, notes):
    """Two tracks as Auxy writes them: tempo, then the notes; both end at the loop's length."""
    mid = mido.MidiFile(type=1, ticks_per_beat=PPQ)
    t0 = mido.MidiTrack()
    t0.append(mido.MetaMessage("set_tempo", tempo=mido.bpm2tempo(BPM), time=0))
    t0.append(mido.MetaMessage("end_of_track", time=beats * PPQ))
    t1 = mido.MidiTrack()
    evs = []
    for beat, length, key, vel in notes:
        evs.append((round(beat * PPQ), 1, mido.Message("note_on", note=key, velocity=vel)))
        evs.append((round((beat + length) * PPQ), 0, mido.Message("note_off", note=key, velocity=0)))
    evs.sort(key=lambda e: (e[0], e[1]))
    now = 0
    for tick, _, msg in evs:
        t1.append(msg.copy(time=tick - now))
        now = tick
    t1.append(mido.MetaMessage("end_of_track", time=beats * PPQ - now))
    mid.tracks += [t0, t1]
    buf = io.BytesIO()
    mid.save(file=buf)
    return buf.getvalue()


def tiny_wav(channel):
    """0.01 s of 16-bit stereo at 44.1 kHz, its samples marking the channel."""
    frames = 441
    data = struct.pack("<%dh" % (frames * 2), *([channel * 100] * frames * 2))
    fmt = struct.pack("<HHIIHH", 1, 2, 44100, 44100 * 4, 4, 16)
    body = b"WAVE" + b"fmt " + struct.pack("<I", len(fmt)) + fmt + b"data" + struct.pack("<I", len(data)) + data
    return b"RIFF" + struct.pack("<I", len(body)) + body


def loop_bars(key):
    return max(1, -(-LOOPS[key][0] // 4))


def notes_played(bars):
    """Notes the timeline sounds: each bar plays its loop's notes starting in that bar of the loop."""
    n = 0
    for row in bars.values():
        for cell in row:
            if cell:
                key, lb = cell
                n += sum(1 for b, _, _, _ in LOOPS[key][1] if lb * 4 <= b < lb * 4 + 4)
    return n


def answer_key():
    tracks, track_of, seen = [], {}, {}
    used_channels = {int(k.split("_")[0]) for k in LOOPS}
    for ci, ch in enumerate(CHANNELS):
        if ci not in used_channels:
            continue
        name, n = ch["label"], 2
        while name in seen:
            name = "%s %d" % (ch["label"], n)
            n += 1
        seen[name] = True
        track_of[ci] = name
        tracks.append(name)
    total = sum(s["number_of_bars"] for s in SCENES)
    bars = {t: [None] * total for t in tracks}
    bar = 0
    markers, scenes, last = [], [], None
    for s in SCENES:
        sig = ",".join(sorted(s["loop_locations"]))
        if sig and sig not in scenes:
            scenes.append(sig)
        if sig != last:
            markers.append(bar)
            last = sig
        for key in s["loop_locations"]:
            t = track_of[int(key.split("_")[0])]
            for b in range(s["number_of_bars"]):
                bars[t][bar + b] = [key, (s["start_offset"] + b) % loop_bars(key)]
        bar += s["number_of_bars"]
    loops = {}
    for key, (beats, notes) in LOOPS.items():
        drums = CHANNELS[int(key.split("_")[0])]["kind"] == "drums"
        loops[key] = {
            "bars": loop_bars(key),
            "notes": sorted([round(b * 96), round(l * 96), k - 36 if drums else k, round(v / 127, 3)] for b, l, k, v in notes),
        }
    played = {int(k.split("_")[0]) for s in SCENES for k in s["loop_locations"]}
    return {
        "bpm": BPM, "total_bars": total, "tracks": tracks,
        "track_of": {str(c): t for c, t in track_of.items()},
        "bars": bars, "markers": markers, "scenes": scenes, "loops": loops,
        "stems": sorted(track_of[c] for c in played),
        "patches": {"Fat Basset": "wavetable_bass", "Fat Basset 2": "wavetable_bass", "Glass Lead": "fm_bell"},
        "kit_pieces": 1 + max(k - 36 for key, (_, notes) in LOOPS.items()
                              if CHANNELS[int(key.split("_")[0])]["kind"] == "drums" for _, _, k, _ in notes),
        "notes_played": notes_played(bars),
    }


def main():
    os.makedirs(OUT, exist_ok=True)
    manifest = {"scenes": SCENES, "scale": "C Minor", "bpm": BPM, "format_version": "0.1",
                "channels": CHANNELS, "title": "Fixture - Test Song", "creator": "Godot Audio Kit"}
    with zipfile.ZipFile(os.path.join(OUT, "fixture.axbw"), "w", zipfile.ZIP_DEFLATED) as z:
        for key, (beats, notes) in LOOPS.items():
            z.writestr("loop_%s.mid" % key, loop_midi(beats, notes))
        for ci in range(len(CHANNELS)):
            z.writestr("stem_%d.wav" % ci, tiny_wav(ci))
        z.writestr("manifest.json", json.dumps(manifest, indent=2))
    with open(os.path.join(OUT, "fixture.json"), "w") as f:
        json.dump(answer_key(), f, indent=1)
    print("wrote", os.path.normpath(OUT))


if __name__ == "__main__":
    main()
