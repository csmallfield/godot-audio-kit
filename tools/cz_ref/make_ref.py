# SPDX-License-Identifier: BSD-3-Clause
"""Writes tests/data/cz_ref.json: MAME's uPD933 (the Casio CZ's sound chip) rendering one note
of each of the chip's waves and windows, a wave pair, a high note, a pitch envelope and ring
modulation, beside the AKPatch that should sound the same (a `pd` oscillator with `cz`
envelopes). tests/test_cz.gd renders the patches at the chip's 40 kHz and holds them to these.

    cd tools/cz_ref && scons && python make_ref.py

Excerpts are kept (the attack, the sustain, the release) rather than whole renders.
"""
import json
import pathlib
import struct
import subprocess
import tempfile

HERE = pathlib.Path(__file__).resolve().parent
OUT = HERE.parent.parent / "tests" / "data" / "cz_ref.json"
WAVES = ["saw", "square", "pulse", "silent", "double_sine", "saw_pulse", "resonance", "double_pulse"]
WINS = ["none", "saw", "triangle", "trapezoid", "pulse", "double_saw"]
FRAMES = 40000
OFF = 20000
EXCERPTS = [(0, 1000), (12000, 1000), (OFF, 1000)]
# The chip's note n is 442 Hz x 2^((n - 62) / 12): MIDI note m is chip note m - 7 plus this.
CZ_CENTS = 7.851


def steps_line(kind, v, steps):
	return "env %d %d 0 %d 1 %d %d %s" % (kind, v, OFF, len(steps) - 1, len(steps),
		" ".join(str(r << 8 | lv) for r, lv in steps))


def case(label, w1, w2=None, win=0, note=62, dca=((96, 127), (80, 100), (70, 0)), dcw=((90, 80), (60, 20), (60, 0)),
		ring=False, dco=None):
	osc = {"shape": "pd", "pd_wave": WAVES[w1], "pd_window": WINS[win], "level": 1.0, "level_env": 4, "shape_env": 5,
		"filtered": False, "cents": CZ_CENTS}
	if w2 is not None:
		osc["pd_wave2"] = WAVES[w2]
	envs = [{"mode": "cz", "kind": "dca", "steps": [list(s) for s in dca], "sustain": 1, "end": len(dca) - 1},
		{"mode": "cz", "kind": "dcw", "steps": [list(s) for s in dcw], "sustain": 1, "end": len(dcw) - 1}]
	wreg = (w1 << 13) | (win << 6) | (((w2 << 10) | (1 << 9)) if w2 is not None else 0)
	lines = ["samples %d" % FRAMES, "write 0 %d %d" % (0x69, wreg), "write 0 %d %d" % (0x61, (note - 7) << 9),
		steps_line(0, 1, dca), steps_line(4, 1, dcw)]
	oscs = [osc]
	if dco:
		envs.append({"mode": "cz", "kind": "dco", "steps": [list(s) for s in dco], "sustain": 1, "end": len(dco) - 1})
		osc["pitch_env"] = 6
		lines.append(steps_line(2, 1, dco))
	if ring:
		# Line 2 (chip voice 4, run right after voice 1) a fifth up, multiplied by line 1; both heard.
		oscs.insert(0, dict(osc, pd_wave="square", semitones=7.0, ring_from=2))
		lines += ["write 0 %d %d" % (0x6c, 1 << 13), "write 0 %d %d" % (0x6e, 1 << 5), "write 0 %d %d" % (0x64, note << 9),
			steps_line(0, 4, dca), steps_line(4, 4, dcw)]
	with tempfile.TemporaryDirectory() as td:
		script, wav = pathlib.Path(td) / "s.txt", pathlib.Path(td) / "o.wav"
		script.write_text("\n".join(lines) + "\n")
		subprocess.run([str(HERE / "cz_ref.exe"), str(script), str(wav)], check=True)
		data = wav.read_bytes()[44:]
	ref = struct.unpack("<%df" % FRAMES, data)
	return {"label": label, "note": note, "frames": FRAMES, "off": OFF,
		"patch": {"oscillators": oscs, "envelopes": envs},
		"excerpts": [{"start": a, "samples": [round(x, 7) for x in ref[a:a + n]]} for a, n in EXCERPTS]}


def main():
	cases = [case("wave %s" % WAVES[w], w) for w in (0, 1, 2, 4, 5, 7)]
	cases += [case("resonance, window %s" % WINS[k], 6, win=k, dcw=((90, 100), (60, 60), (60, 0))) for k in (1, 2, 3, 4, 5)]
	cases += [case("saw and pulse pair", 0, 2), case("high note", 0, note=96),
		case("pitch envelope", 0, dco=((90, 0x40 | 6), (70, 0x40 | 1), (70, 0))), case("ring", 0, ring=True)]
	OUT.write_text(json.dumps({"source": "MAME upd933.cpp (BSD-3-Clause, Devin Acker) via tools/cz_ref", "rate": 40000,
		"cases": cases}, separators=(",", ":")) + "\n")
	print("wrote", OUT, len(cases), "cases")


if __name__ == "__main__":
	main()
