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
  - a drum stem (8 kHz mono) with a decaying sine per pad at every hit the
    song plays, so the importer's cuts can be checked: which hit each pad is
    cut from, its pitch, level and length (fixture.json "cuts")

It also writes tests/auxy/pads.axbw and pads.json: a pad test (one hit per
pad on the same kit, one pad left out, one ringing into the next hit) for
AKAuxy.kit_from_pads.

    pip install mido
    python3 tools/auxy_fixture/make_fixture.py
"""
import io
import math
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


# The drum stem: pad -> (Hz, decay time constant s, amplitude at velocity 127).
DRUM_SR = 8000
PADS = {36: (80.0, 0.08, 0.25), 37: (200.0, 0.05, 0.2), 38: (500.0, 0.12, 0.3), 39: (1200.0, 0.03, 0.15), 40: (2500.0, 0.06, 0.18)}


def drum_hits(scenes, loops):
    """Every drum hit the scenes play: [(seconds, note, velocity)], in time order."""
    out, bar = [], 0
    spb = 60.0 / BPM
    for s in scenes:
        for key in s["loop_locations"]:
            if CHANNELS[int(key.split("_")[0])]["kind"] != "drums":
                continue
            beats, notes = loops[key]
            L = max(1, -(-beats // 4))
            for b in range(s["number_of_bars"]):
                lb = (s["start_offset"] + b) % L
                for beat, _, k, v in notes:
                    if lb * 4 <= beat < lb * 4 + 4:
                        out.append((((bar + b) * 4 + beat - lb * 4) * spb, k, v))
        bar += s["number_of_bars"]
    return sorted(out)


def drum_stem(hits, seconds):
    """16-bit samples: each hit a sine at its pad's pitch, decaying from its start."""
    n = int(seconds * DRUM_SR)
    acc = [0.0] * n
    for t, k, v in hits:
        hz, tau, amp = PADS[k]
        a0 = int(round(t * DRUM_SR))
        for i in range(a0, min(n, a0 + int(tau * 9 * DRUM_SR))):
            x = (i - a0) / DRUM_SR
            acc[i] += amp * v / 127.0 * math.exp(-x / tau) * math.sin(2 * math.pi * hz * x)
    return [max(-32768, min(32767, int(round(a * 32767)))) for a in acc]


def mono_wav(samples, rate):
    data = struct.pack("<%dh" % len(samples), *samples)
    fmt = struct.pack("<HHIIHH", 1, 1, rate, rate * 2, 2, 16)
    body = b"WAVE" + b"fmt " + struct.pack("<I", len(fmt)) + fmt + b"data" + struct.pack("<I", len(data)) + data
    return b"RIFF" + struct.pack("<I", len(body)) + body


def expected_cuts(hits, samples):
    """The cut the importer should make per pad, as AKAuxy documents it: the cleanest hit
    (least ringing in the 10 ms before it, in dB under its own peak over 50 ms, clamped to
    -60..0), then the most room after it (to 2 s; a dB cleaner is worth 20 ms); hits sharing
    their instant lose. Cut to the next hit or the stem's end, trailing samples under -60 dB
    of the peak trimmed."""
    end_s = len(samples) / DRUM_SR
    times = [h[0] for h in hits]
    pre_n, peak_n = round(0.01 * DRUM_SR), round(0.05 * DRUM_SR)
    best = {}
    for i, (t, k, v) in enumerate(hits):
        later = [x for x in times if x > t + 1e-6]
        after = (later[0] if later else end_s) - t
        together = sum(1 for x in times if abs(x - t) < 1e-6) > 1
        a = min(len(samples), max(0, round(t * DRUM_SR)))
        pk = max([abs(x) / 32768.0 for x in samples[a:a + peak_n]] or [0.0])
        e = sum((x / 32768.0) ** 2 for x in samples[max(0, a - pre_n):a])
        pre_db = min(0.0, max(-60.0, 10 * math.log10(e / pre_n + 1e-20) - 20 * math.log10(pk + 1e-20)))
        score = min(after, 2.0) - 0.02 * pre_db - (100 if together else 0)
        if k not in best or score > best[k][0]:
            best[k] = (score, t, t + after, v)
    out = {}
    for k, (_, t, t1, v) in sorted(best.items()):
        a, z = int(round(t * DRUM_SR)), int(round(t1 * DRUM_SR))
        seg = [x / 32768.0 for x in samples[a:z]]
        peak = max(abs(x) for x in seg)
        e = len(seg)
        while e > 1 and abs(seg[e - 1]) < peak * 0.001:
            e -= 1
        cut_short = e == len(seg) and t1 < end_s - 1e-6
        out[str(k - 36)] = {"start_s": t, "length_s": e / DRUM_SR, "peak_db": 20 * math.log10(peak),
                            "hz": PADS[k][0], "tail_cut": cut_short}
    return out


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
        "cuts": expected_cuts(*song_drums()),
    }


def song_drums():
    hits = drum_hits(SCENES, LOOPS)
    seconds = sum(s["number_of_bars"] for s in SCENES) * 4 * 60.0 / BPM + 2.0
    return hits, drum_stem(hits, seconds)


PAD_TEST_LOOP = (8, [(0, 0.25, 36, 127), (1, 0.25, 37, 127), (3.5, 0.25, 38, 127), (4, 0.25, 39, 127)])   # 38 rings into 39
PAD_TEST_UNUSED = (4, [(0, 0.25, 40, 127)])   # pad 5 is in a loop the song never plays


def write_pad_test():
    loops = {"0_0": PAD_TEST_LOOP}
    scenes = [{"loop_locations": ["0_0"], "number_of_bars": 2, "start_offset": 0}]
    hits = drum_hits(scenes, loops)
    samples = drum_stem(hits, 2 * 4 * 60.0 / BPM + 1.5)
    manifest = {"scenes": scenes, "scale": "C Minor", "bpm": BPM, "format_version": "0.1",
                "channels": [CHANNELS[0]], "title": "Pad Test", "creator": "Godot Audio Kit"}
    with zipfile.ZipFile(os.path.join(OUT, "pads.axbw"), "w", zipfile.ZIP_DEFLATED) as z:
        z.writestr("loop_0_0.mid", loop_midi(*PAD_TEST_LOOP))
        z.writestr("loop_0_1.mid", loop_midi(*PAD_TEST_UNUSED))
        z.writestr("stem_0.wav", mono_wav(samples, DRUM_SR))
        z.writestr("manifest.json", json.dumps(manifest, indent=2))
    with open(os.path.join(OUT, "pads.json"), "w") as f:
        json.dump({"cuts": expected_cuts(hits, samples), "pads": 5, "missing": [4]}, f, indent=1)


def main():
    os.makedirs(OUT, exist_ok=True)
    manifest = {"scenes": SCENES, "scale": "C Minor", "bpm": BPM, "format_version": "0.1",
                "channels": CHANNELS, "title": "Fixture - Test Song", "creator": "Godot Audio Kit"}
    with zipfile.ZipFile(os.path.join(OUT, "fixture.axbw"), "w", zipfile.ZIP_DEFLATED) as z:
        for key, (beats, notes) in LOOPS.items():
            z.writestr("loop_%s.mid" % key, loop_midi(beats, notes))
        for ci in range(len(CHANNELS)):
            if CHANNELS[ci]["kind"] == "drums":
                z.writestr("stem_%d.wav" % ci, mono_wav(song_drums()[1], DRUM_SR))
            else:
                z.writestr("stem_%d.wav" % ci, tiny_wav(ci))
        z.writestr("manifest.json", json.dumps(manifest, indent=2))
    with open(os.path.join(OUT, "fixture.json"), "w") as f:
        json.dump(answer_key(), f, indent=1)
    write_pad_test()
    print("wrote", os.path.normpath(OUT))


if __name__ == "__main__":
    main()
