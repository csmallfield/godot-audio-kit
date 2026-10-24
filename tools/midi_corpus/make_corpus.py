#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Writes the MIDI test corpus in tests/midi/: small files covering the ways
real .mid files differ (format 0 and 1, running status, note-on velocity 0
as note-off, tempo and meter changes, mid-bar tempo changes, drums on
channel 10, the sustain pedal, overlapping notes on one key, markers, SMPTE
time, a truncated file).

The music is public domain (Bach/Petzold's Minuet in G, Beethoven's Ode to
Joy) in our own arrangement, or written for this corpus; the files are
Apache-2.0 like the rest of the repo.

Next to each .mid it writes <name>.json: the notes as this script meant them
(seconds, pitch, velocity, channel), worked out here independently of the
kit's parser, so the import test checks against an answer key.

    pip install mido
    python3 tools/midi_corpus/make_corpus.py
"""
import json
import os
import struct

import mido

OUT = os.path.join(os.path.dirname(__file__), "..", "..", "tests", "midi")
PPQ = 480
NAMES = {"C": 0, "D": 2, "E": 4, "F": 5, "G": 7, "A": 9, "B": 11}


def note(n):
    """'F#5' -> 78."""
    semi = NAMES[n[0]]
    i = 1
    while i < len(n) and n[i] in "#b":
        semi += 1 if n[i] == "#" else -1
        i += 1
    return (int(n[i:]) + 1) * 12 + semi


class Key:
    """Answer key: notes in seconds from a tempo list [(tick, us_per_quarter)]."""

    def __init__(self, tempos):
        self.tempos = sorted(tempos)
        self.notes = []

    def sec(self, tick):
        s = 0.0
        for i, (t0, us) in enumerate(self.tempos):
            t1 = self.tempos[i + 1][0] if i + 1 < len(self.tempos) else 1 << 60
            if tick <= t0:
                break
            s += (min(tick, t1) - t0) / PPQ * us / 1e6
        return s

    def add(self, part, start, end, midi, vel, ch):
        self.notes.append({"part": part, "time_s": round(self.sec(start), 6), "length_s": round(self.sec(end) - self.sec(start), 6),
                           "beat": start / PPQ, "midi": midi, "velocity": vel, "channel": ch})

    def save(self, name, extra=None):
        d = {"notes": sorted(self.notes, key=lambda n: (n["time_s"], n["midi"]))}
        d.update(extra or {})
        with open(os.path.join(OUT, name + ".json"), "w") as f:
            json.dump(d, f, indent=1)


def track_from(events):
    """[(abs_tick, msg)] -> a mido track with delta times."""
    tr = mido.MidiTrack()
    last = 0
    for tick, msg in sorted(events, key=lambda e: (e[0], 0 if e[1].type in ("note_off",) else 1)):
        tr.append(msg.copy(time=tick - last))
        last = tick
    tr.append(mido.MetaMessage("end_of_track", time=0))
    return tr


# ---------------------------------------------------------------- minuet (format 1)

def minuet():
    """Minuet in G (BWV Anh. 114), first 16 bars, 3/4 at 112, melody and an
    arranged bass, on two tracks; mido's writer (no running status)."""
    q, e = PPQ, PPQ // 2
    bars = [
        [("D5", q), ("G4", e), ("A4", e), ("B4", e), ("C5", e)],
        [("D5", q), ("G4", q), ("G4", q)],
        [("E5", q), ("C5", e), ("D5", e), ("E5", e), ("F#5", e)],
        [("G5", q), ("G4", q), ("G4", q)],
        [("C5", q), ("D5", e), ("C5", e), ("B4", e), ("A4", e)],
        [("B4", q), ("C5", e), ("B4", e), ("A4", e), ("G4", e)],
        [("F#4", q), ("G4", e), ("A4", e), ("B4", e), ("G4", e)],
        [("A4", 3 * q)],
    ]
    bars = bars + bars[:6] + [[("A4", q), ("B4", e), ("A4", e), ("G4", e), ("F#4", e)], [("G4", 3 * q)]]
    bass = ["G3", "B3", "C4", "B3", "A3", "G3", "D4", "D3", "G3", "B3", "C4", "B3", "A3", "G3", "D3", "G2"]
    us = mido.bpm2tempo(112)
    key = Key([(0, us)])
    conductor = [(0, mido.MetaMessage("set_tempo", tempo=us)), (0, mido.MetaMessage("time_signature", numerator=3, denominator=4)),
                 (0, mido.MetaMessage("track_name", name="Minuet in G"))]
    mel = [(0, mido.MetaMessage("track_name", name="Melody")), (0, mido.Message("program_change", channel=0, program=0))]
    t = 0
    for b in bars:
        for n, d in b:
            k = note(n)
            mel.append((t, mido.Message("note_on", channel=0, note=k, velocity=90)))
            mel.append((t + d - 20, mido.Message("note_off", channel=0, note=k, velocity=64)))
            key.add("melody", t, t + d - 20, k, 90, 0)
            t += d
    bs = [(0, mido.MetaMessage("track_name", name="Bass")), (0, mido.Message("program_change", channel=1, program=32)),
          (0, mido.Message("control_change", channel=1, control=7, value=90))]
    for i, n in enumerate(bass):
        k = note(n)
        bs.append((i * 3 * q, mido.Message("note_on", channel=1, note=k, velocity=70)))
        bs.append((i * 3 * q + 3 * q - 40, mido.Message("note_off", channel=1, note=k, velocity=0)))
        key.add("bass", i * 3 * q, i * 3 * q + 3 * q - 40, k, 70, 1)
    mf = mido.MidiFile(type=1, ticks_per_beat=PPQ)
    mf.tracks = [track_from(conductor), track_from(mel), track_from(bs)]
    mf.save(os.path.join(OUT, "minuet_g.mid"))
    key.save("minuet_g", {"bpm": 112, "beats_per_bar": 3})


# ---------------------------------------------------------------- ode (format 0, hand-encoded)

def vlq(v):
    out = [v & 0x7F]
    v >>= 7
    while v:
        out.insert(0, 0x80 | (v & 0x7F))
        v >>= 7
    return bytes(out)


def ode():
    """Ode to Joy, 4/4, written byte by byte as a format 0 file with running
    status throughout and note-on velocity 0 for note-offs, a flute program,
    and a slowing (a tempo change on beat 3 of bar 7, mid-bar)."""
    tune = "E4 E4 F4 G4 G4 F4 E4 D4 C4 C4 D4 E4 E4. D4/ D4: E4 E4 F4 G4 G4 F4 E4 D4 C4 C4 D4 E4 D4. C4/ C4:".split()
    q = PPQ
    events = []  # (tick, bytes-without-status, status) or meta
    t = 0
    key_tempos = [(0, 500000)]
    slow_at = 6 * 4 * q + 2 * q   # bar 7 (0-based 6), beat 3
    key_tempos.append((slow_at, 600000))
    key_tempos.append((slow_at + 4 * q, 750000))
    key = Key(key_tempos)
    for tok in tune:
        d = q
        name = tok
        if tok.endswith("."):
            d, name = q * 3 // 2, tok[:-1]
        elif tok.endswith("/"):
            d, name = q // 2, tok[:-1]
        elif tok.endswith(":"):
            d, name = q * 2, tok[:-1]
        k = note(name)
        vel = 80 if (t // q) % 4 else 100
        events.append((t, 0x90, bytes([k, vel])))
        events.append((t + d - 30, 0x90, bytes([k, 0])))   # velocity 0 = off
        key.add("melody", t, t + d - 30, k, vel, 0)
        t += d
    body = bytearray()
    body += vlq(0) + b"\xff\x03" + vlq(3) + b"Ode"
    body += vlq(0) + b"\xff\x51\x03" + struct.pack(">I", 500000)[1:]
    body += vlq(0) + b"\xff\x58\x04" + bytes([4, 2, 24, 8])
    body += vlq(0) + bytes([0xC0, 73])     # flute
    metas = [(slow_at, b"\xff\x51\x03" + struct.pack(">I", 600000)[1:]), (slow_at + 4 * q, b"\xff\x51\x03" + struct.pack(">I", 750000)[1:])]
    allev = [(tk, 1, st, data) for tk, st, data in events] + [(tk, 0, None, m) for tk, m in metas]
    allev.sort(key=lambda x: (x[0], x[1]))
    last = 0
    running = None
    for tk, kind, st, data in allev:
        body += vlq(tk - last)
        last = tk
        if kind == 0:
            body += data            # meta keeps running status alive (common practice)
        else:
            if st != running:
                body += bytes([st])
                running = st
            body += data
    body += vlq(0) + b"\xff\x2f\x00"
    with open(os.path.join(OUT, "ode_format0.mid"), "wb") as f:
        f.write(b"MThd" + struct.pack(">IHHH", 6, 0, 1, PPQ))
        f.write(b"MTrk" + struct.pack(">I", len(body)) + bytes(body))
    key.save("ode_format0", {"bpm": 120, "beats_per_bar": 4})


# ---------------------------------------------------------------- groove (format 1, the awkward bits)

def groove():
    """Written for the corpus: drums, bass and piano over 8 bars. Markers
    "verse" (bar 1) and "chorus" (bar 5); 4/4 changing to 7/8 at bar 7; a
    tempo change half way through bar 3; piano chords under the sustain
    pedal; one key struck again before its note-off (overlap); CC 7/10/91."""
    q = PPQ
    tempos = [(0, mido.bpm2tempo(100)), (2 * 4 * q + 2 * q, mido.bpm2tempo(110))]
    key = Key(tempos)
    con = [(0, mido.MetaMessage("set_tempo", tempo=tempos[0][1])), (0, mido.MetaMessage("time_signature", numerator=4, denominator=4)),
           (0, mido.MetaMessage("marker", text="verse")), (4 * 4 * q, mido.MetaMessage("marker", text="chorus")),
           (tempos[1][0], mido.MetaMessage("set_tempo", tempo=tempos[1][1])),
           (6 * 4 * q, mido.MetaMessage("time_signature", numerator=7, denominator=8))]
    bar_start = [i * 4 * q for i in range(7)] + [6 * 4 * q + int(3.5 * q)]   # bar 7 (index 6) is 7/8 = 3.5 quarters
    end = bar_start[-1] + int(3.5 * q)
    dr = [(0, mido.MetaMessage("track_name", name="Drums"))]
    for b in range(8):
        s = bar_start[b]
        n_beats = 4 if b < 6 else 3.5
        steps = int(n_beats * 2)
        for i in range(steps):
            t = s + i * q // 2
            hits = [42]
            if i % 4 == 0:
                hits.append(36)
            if i % 4 == 2:
                hits.append(38)
            for h in hits:
                v = 100 if h != 42 else 60
                dr.append((t, mido.Message("note_on", channel=9, note=h, velocity=v)))
                dr.append((t + 60, mido.Message("note_off", channel=9, note=h, velocity=0)))
                key.add("drums", t, t + 60, h, v, 9)
    bass = [(0, mido.MetaMessage("track_name", name="Bass")), (0, mido.Message("program_change", channel=1, program=38)),
            (0, mido.Message("control_change", channel=1, control=10, value=40))]
    roots = ["A2", "A2", "F2", "G2", "C3", "C3", "D3", "E2"]
    for b in range(8):
        k = note(roots[b])
        for beat in range(4 if b < 6 else 3):
            t = bar_start[b] + beat * q
            bass.append((t, mido.Message("note_on", channel=1, note=k, velocity=85)))
            bass.append((t + q - 60, mido.Message("note_off", channel=1, note=k, velocity=0)))
            key.add("bass", t, t + q - 60, k, 85, 1)
    pno = [(0, mido.MetaMessage("track_name", name="Keys")), (0, mido.Message("program_change", channel=2, program=4)),
           (0, mido.Message("control_change", channel=2, control=91, value=60))]
    chords = [["A3", "C4", "E4"], ["A3", "C4", "E4"], ["F3", "A3", "C4"], ["G3", "B3", "D4"],
              ["C4", "E4", "G4"], ["C4", "E4", "G4"], ["D4", "F4", "A4"], ["E3", "G#3", "B3"]]
    for b in range(8):
        s = bar_start[b]
        nxt = bar_start[b + 1] if b + 1 < 8 else end
        pno.append((s, mido.Message("control_change", channel=2, control=64, value=127)))
        for n in chords[b]:
            k = note(n)
            pno.append((s, mido.Message("note_on", channel=2, note=k, velocity=70)))
            pno.append((s + q // 4, mido.Message("note_off", channel=2, note=k, velocity=0)))
            key.add("keys", s, nxt - 10, k, 70, 2)        # sounds until the pedal lifts
        pno.append((nxt - 10, mido.Message("control_change", channel=2, control=64, value=0)))
    # A struck-again key: E5 at bar 5 beat 1, again at beat 2 before the first off.
    k = note("E5")
    s = bar_start[4]
    pno += [(s, mido.Message("note_on", channel=2, note=k, velocity=90)), (s + q, mido.Message("note_on", channel=2, note=k, velocity=90)),
            (s + q + q // 2, mido.Message("note_off", channel=2, note=k, velocity=0)), (s + 2 * q, mido.Message("note_off", channel=2, note=k, velocity=0))]
    # Pedal is down then (lifted at the next bar - 10), so both sound until then: FIFO + pedal.
    key.add("keys", s, bar_start[5] - 10, k, 90, 2)
    key.add("keys", s + q, bar_start[5] - 10, k, 90, 2)
    mf = mido.MidiFile(type=1, ticks_per_beat=PPQ)
    mf.tracks = [track_from(con), track_from(dr), track_from(bass), track_from(pno)]
    mf.save(os.path.join(OUT, "groove_meter_pedal.mid"))
    key.save("groove_meter_pedal", {"markers": ["verse", "chorus"]})


# ---------------------------------------------------------------- SMPTE and a broken file

def smpte_and_broken():
    """A file timed in SMPTE (25 fps x 40 ticks = 1000 ticks a second) and a
    copy of the minuet cut off half way through its second track."""
    body = bytearray()
    t = 0
    key_notes = []
    for i, n in enumerate(["C4", "E4", "G4", "C5"]):
        k = note(n)
        body += vlq(0 if i == 0 else 250) + bytes([0x90, k, 100])
        body += vlq(250) + bytes([0x80, k, 0])
        key_notes.append({"part": "melody", "time_s": i * 0.5, "length_s": 0.25, "midi": k, "velocity": 100, "channel": 0})
    body += vlq(0) + b"\xff\x2f\x00"
    div = ((256 - 25) << 8) | 40
    with open(os.path.join(OUT, "smpte_25fps.mid"), "wb") as f:
        f.write(b"MThd" + struct.pack(">IHHH", 6, 0, 1, div))
        f.write(b"MTrk" + struct.pack(">I", len(body)) + bytes(body))
    with open(os.path.join(OUT, "smpte_25fps.json"), "w") as f:
        json.dump({"notes": key_notes}, f, indent=1)
    data = open(os.path.join(OUT, "minuet_g.mid"), "rb").read()
    with open(os.path.join(OUT, "truncated.mid"), "wb") as f:
        f.write(data[: int(len(data) * 0.7)])


if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    minuet()
    ode()
    groove()
    smpte_and_broken()
    print("wrote", sorted(os.listdir(OUT)))
