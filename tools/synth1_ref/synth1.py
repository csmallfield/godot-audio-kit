# SPDX-License-Identifier: Apache-2.0
"""Drive Synth1 (Daichi Laboratory's freeware VST2) through DawDreamer.

A measuring aid for the Synth1 -> AKPatch converter: nothing of Synth1 is
copied here or shipped. Run with the DawDreamer venv's Python (see README).

Synth1 keeps its state as a VST chunk in which every parameter is the same
integer a .sy1 file stores, at byte CHUNK_BASE + 8 * index (then a 1). Writing
a preset's integers there and loading the chunk lets Synth1 interpret them
itself, so no value has to be guessed from the 0..1 automation scale.
"""
import os
import pathlib
import struct
import tempfile

import numpy as np

DLL = os.environ.get("SYNTH1_DLL", r"D:\tools\synth1\Synth1 VST64.dll")
SR = 48000
BLOCK = 512
CHUNK_BASE = 732
N_PARAMS = 99

# Parameter indices (the VST order; a .sy1 line is "index,value").
P = dict(
	osc1_shape=0, osc2_shape=1, osc2_pitch=2, osc2_fine=3, osc2_track=4, osc_mix=5, osc2_sync=6, osc2_ring=7,
	pulse_width=8, key_shift=9, modenv_on=10, modenv_amount=11, modenv_attack=12, modenv_decay=13,
	filter_type=14, f_attack=15, f_decay=16, f_sustain=17, f_release=18, f_freq=19, f_res=20, f_amount=21,
	f_track=22, f_sat=23, f_vel=24, a_attack=25, a_decay=26, a_sustain=27, a_release=28, a_gain=29, a_vel=30,
	arp_type=31, arp_oct=32, arp_beat=33, arp_gate=34, delay_time=35, delay_fb=36, delay_mix=37,
	play_mode=38, porta_time=39, bend_range=40, lfo1_dest=41, lfo1_type=42, lfo1_speed=43, lfo1_depth=44,
	osc1_fm=45, lfo2_dest=46, lfo2_type=47, lfo2_speed=48, lfo2_depth=49, ctrl_sens1=50, ctrl_sens2=51,
	ch_delay=52, ch_depth=53, ch_rate=54, ch_fb=55, ch_level=56, lfo1_on=57, lfo2_on=58, arp_on=59,
	eq_tone=60, eq_freq=61, eq_level=62, eq_q=63, ch_type=64, delay_on=65, chorus_on=66, lfo1_sync=67,
	lfo1_keysync=68, lfo2_sync=69, lfo2_keysync=70, modenv_dest=71, osc_tune=72, unison_on=73, porta_auto=74,
	unison_detune=75, osc1_detune=76, fx_on=77, fx_type=78, fx_ctl1=79, fx_ctl2=80, fx_mix=81, delay_type=82,
	delay_spread=83, unison_spread=84, unison_pitch=85, ctrl_src1=86, ctrl_assign1=87, ctrl_src2=88,
	ctrl_assign2=89, pan=90, osc_phase=91, unison_phase=92, unison_voices=93, sub_gain=95, sub_shape=96,
	sub_octave=97, delay_tone=98,
)


def read_sy1(path):
	"""A .sy1 file as (name, version, {index: value})."""
	lines = pathlib.Path(path).read_text(encoding="latin-1", errors="replace").splitlines()
	name = lines[0].strip() if lines else ""
	ver = 0
	vals = {}
	for line in lines[1:]:
		if line.startswith("ver="):
			try:
				ver = int(line[4:])
			except ValueError:
				pass
		elif "," in line:
			a, b = line.split(",", 1)
			try:
				vals[int(a)] = int(b)
			except ValueError:
				pass
	return name, ver, vals


class Synth1:
	"""One Synth1 instance: load integer values, render notes."""

	def __init__(self, dll=DLL, sr=SR):
		import dawdreamer as daw
		self.sr = sr
		self.engine = daw.RenderEngine(sr, BLOCK)
		self.plugin = self.engine.make_plugin_processor("synth1", dll)
		self.engine.load_graph([(self.plugin, [])])
		self._tmp = tempfile.mkdtemp(prefix="synth1_ref_")
		path = os.path.join(self._tmp, "init.bin")
		self.plugin.save_state(path)
		self._init = bytearray(pathlib.Path(path).read_bytes())
		self.init_values = {i: struct.unpack_from("<i", self._init, CHUNK_BASE + 8 * i)[0] for i in range(N_PARAMS)}

	def load(self, values):
		"""Every parameter from `values` ({index or name: int}); the rest from Synth1's initial state."""
		chunk = bytearray(self._init)
		for k, v in values.items():
			i = P[k] if isinstance(k, str) else int(k)
			if 0 <= i < N_PARAMS:
				struct.pack_into("<i", chunk, CHUNK_BASE + 8 * i, int(v))
		path = os.path.join(self._tmp, "load.bin")
		pathlib.Path(path).write_bytes(chunk)
		self.plugin.load_state(path)

	def values(self):
		"""The integers Synth1 holds now."""
		path = os.path.join(self._tmp, "now.bin")
		self.plugin.save_state(path)
		b = pathlib.Path(path).read_bytes()
		return {i: struct.unpack_from("<i", b, CHUNK_BASE + 8 * i)[0] for i in range(N_PARAMS)}

	def render(self, notes, seconds):
		"""notes: [(midi_note, velocity 1..127, start_s, length_s)]. Returns (2, n) float32."""
		self.plugin.clear_midi()
		for n, v, t, d in notes:
			self.plugin.add_midi_note(int(n), int(v), float(t), float(d))
		self.engine.render(float(seconds))
		return np.asarray(self.engine.get_audio(), dtype=np.float32)

	def text(self, name):
		return self.plugin.get_parameter_text(P[name])


def neutral(**over):
	"""A plain test patch: osc1 alone (saw; osc1 shapes are 0 sine, 1 saw, 2 pulse, 3 triangle), filter wide open, a gate-shaped amp
	envelope, and every modulator, effect, arpeggiator and unison off."""
	v = dict(
		osc1_shape=1, osc2_shape=1, osc2_pitch=64, osc2_fine=64, osc2_track=1, osc_mix=0, osc2_sync=0, osc2_ring=0,
		pulse_width=64, key_shift=0, modenv_on=0, modenv_amount=64, osc1_fm=0, osc1_detune=0, osc_tune=64,
		filter_type=1, f_freq=127, f_res=0, f_amount=64, f_track=0, f_sat=0, f_vel=0,
		f_attack=0, f_decay=64, f_sustain=127, f_release=0,
		a_attack=0, a_decay=64, a_sustain=127, a_release=0, a_gain=100, a_vel=0,
		arp_on=0, delay_on=0, chorus_on=0, fx_on=0, lfo1_on=0, lfo2_on=0, unison_on=0, play_mode=0, porta_time=0,
		eq_tone=64, eq_level=64, eq_freq=64, eq_q=64, pan=64, osc_phase=0, sub_gain=0,
	)
	v.update(over)
	return v


def rms_frames(x, frame):
	"""RMS of a mono signal in frames of `frame` samples."""
	n = len(x) // frame
	return np.sqrt(np.mean(x[: n * frame].reshape(n, frame) ** 2, axis=1) + 1e-30)


def mono(a):
	return (a[0] + a[1]) * 0.5
