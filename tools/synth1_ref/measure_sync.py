# SPDX-License-Identifier: Apache-2.0
"""Synth1's tempo-synced values and its arpeggiator, at 120 bpm (a beat is 0.5 s):
the synced LFO period per speed value, the arpeggiator's step per beat value, its
note order per type value and its octave range. One note at a time (two voices at
once crash Synth1 under DawDreamer). Writes data/sync.json."""
import json
import pathlib
import sys

import numpy as np

sys.path.insert(0, str(pathlib.Path(__file__).parent))
from synth1 import SR, Synth1, mono, neutral  # noqa: E402
from measure_env import envelope  # noqa: E402
from measure_lfo import inst_freq, period  # noqa: E402

OUT = pathlib.Path(__file__).parent / "data"
BPM = 120.0


def fresh():
	s = Synth1()
	s.engine.set_bpm(BPM)
	return s


def lfo_sync_period(v):
	"""The synced LFO's period (s) on the amp, triangle, key sync on."""
	s = fresh()
	s.load(neutral(osc1_shape=0, lfo1_on=1, lfo1_type=1, lfo1_depth=127, lfo1_dest=4, lfo1_sync=1,
		lfo1_keysync=1, lfo1_speed=v))
	dur = 20.0
	e = envelope(mono(s.render([(69, 127, 0.0, dur)], dur)), 240)[::48]
	p = period(e, 0.004 / 48, dur / 2.1 / 48)
	return None if not p else round(p * 48, 4)


def arp_notes(over, dur=4.0, note=57):
	"""The arpeggiator's notes (MIDI, from pitch) and their onsets (s), one key held. Mono, so
	steps never overlap."""
	s = fresh()
	s.load(neutral(**dict(dict(osc1_shape=0, arp_on=1, arp_type=1, arp_oct=0, arp_beat=11, arp_gate=64,
		play_mode=1, a_attack=0, a_decay=64, a_sustain=127, a_release=0), **over)))
	x = mono(s.render([(note, 127, 0.0, dur)], dur))
	e = envelope(x, 48)
	on = e > 0.1 * float(np.max(e))
	starts = [i for i in range(1, len(on)) if on[i] and not on[i - 1]]
	if on[0]:
		starts = [0] + starts
	f = inst_freq(x)
	notes = []
	for st in starts:
		seg = f[st + 480:st + 1440]
		if len(seg) < 100:
			continue
		hz = float(np.median(seg))
		notes.append(round(69 + 12 * np.log2(max(hz, 1.0) / 440.0)))
	return [round(i / SR, 4) for i in starts], notes


def run():
	out = {"bpm": BPM, "lfo_sync_period_s": {}, "arp_step_s": {}, "arp_type_notes": {}, "arp_oct_notes": {}}
	for v in range(0, 128):
		out["lfo_sync_period_s"][v] = lfo_sync_period(v)
		print("lfo sync", v, out["lfo_sync_period_s"][v], flush=True)
	for b in range(0, 20):
		t, _ = arp_notes(dict(arp_beat=b, arp_oct=1), dur=8.0)
		d = np.diff(t)
		out["arp_step_s"][b] = round(float(np.median(d)), 4) if len(d) else None
		print("arp beat", b, out["arp_step_s"][b], flush=True)
	for ty in range(5):
		_, n = arp_notes(dict(arp_type=ty, arp_oct=2, arp_beat=11), dur=6.0)
		out["arp_type_notes"][ty] = n[:16]
		print("arp type", ty, n[:16], flush=True)
	for o in range(4):
		_, n = arp_notes(dict(arp_type=1, arp_oct=o, arp_beat=11), dur=6.0)
		out["arp_oct_notes"][o] = n[:16]
		print("arp oct", o, n[:16], flush=True)
	OUT.mkdir(exist_ok=True)
	(OUT / "sync.json").write_text(json.dumps(out, indent=1))


if __name__ == "__main__":
	run()
