# SPDX-License-Identifier: Apache-2.0
"""Writes tests/data/dx7_env_ref.json (msfa's own DX7 envelope levels, for the
`dx7` envelope mode) and tests/data/dx7_ref.json (frequencies, the pitch
envelope, the LFO and its pitch and amp modulation), for the tests.

    cd tools/dx7_env_ref && scons && python make_ref.py [dx7 library folder]

Cases are operators from the DX7 factory voices (the prep tool's sidecars,
`content.dx7.params`) at several keys and velocities, plus corner cases.
Each case keeps the raw DX7 values under the names the `dx7` mode uses.
"""
import json
import pathlib
import subprocess
import sys

HERE = pathlib.Path(__file__).resolve().parent
LIB = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else
		"D:/12_library/gak/processed_soundarchive/yamaha-dx7/yamaha-factory-rom")
OUT = HERE.parent.parent / "tests" / "data" / "dx7_env_ref.json"


def op_case(op, note, vel, keyoff, blocks, label):
	return {"label": label, "note": note, "velocity": vel, "keyoff_block": keyoff, "blocks": blocks, "env": {
		"mode": "dx7",
		"rates": [op["eg_rate_%d" % i] for i in (1, 2, 3, 4)],
		"levels": [op["eg_level_%d" % i] for i in (1, 2, 3, 4)],
		"output_level": op["output_level"], "rate_scaling": op["kbd_rate_scaling"],
		"velocity_sens": op["key_velocity_sensitivity"],
		"key_scaling": {"break_point": op["kbd_break_point"], "left_depth": op["kbd_left_depth"],
			"right_depth": op["kbd_right_depth"], "left_curve": op["kbd_left_curve"], "right_curve": op["kbd_right_curve"]}}}


def raw_case(rates, levels, ol, note, vel, keyoff, blocks, label, rs=0, vs=0, ks=(39, 0, 0, 0, 0)):
	return {"label": label, "note": note, "velocity": vel, "keyoff_block": keyoff, "blocks": blocks, "env": {
		"mode": "dx7", "rates": list(rates), "levels": list(levels), "output_level": ol, "rate_scaling": rs,
		"velocity_sens": vs, "key_scaling": {"break_point": ks[0], "left_depth": ks[1], "right_depth": ks[2],
			"left_curve": ks[3], "right_curve": ks[4]}}}


def main():
	files = sorted(LIB.rglob("instrument.json"))
	picks = [0, 3, 10, 17, 25, 31, 40, 52, 66, 80, 101, 127, 150, 200]
	cases = []
	for n, i in enumerate(picks):
		if i >= len(files):
			continue
		d = json.loads(files[i].read_text(encoding="utf-8"))
		p = d["content"]["dx7"]["params"]
		ops = p["operators"]
		op = ops[n % len(ops)]
		note = [36, 48, 60, 72, 84, 96, 24][n % 7]
		vel = [100, 127, 64, 20, 90, 1, 110][n % 7]
		keyoff = [300, 40, 700, 5, 150, 1200, 0][n % 7]
		cases.append(op_case(op, note, vel, keyoff, keyoff + 700, "%s op%d" % (p["name"].strip(), op["operator"])))
	# Corners: every rate at 99, rates at 0 (static counts), held levels, the attack from level 0.
	cases.append(raw_case([99, 99, 99, 99], [99, 99, 99, 0], 99, 60, 127, 20, 60, "all 99"))
	cases.append(raw_case([0, 0, 0, 0], [99, 50, 50, 0], 99, 60, 127, 300, 400, "rates 0"))
	cases.append(raw_case([50, 60, 70, 40], [0, 99, 99, 0], 99, 60, 100, 400, 900, "attack to 0 (static)"))
	cases.append(raw_case([30, 40, 80, 20], [80, 80, 40, 60], 70, 72, 100, 300, 900, "held level, release up"))
	cases.append(raw_case([76, 77, 78, 99], [99, 99, 90, 0], 99, 100, 80, 200, 300, "statics past 76", rs=7, vs=7,
			ks=(20, 99, 99, 1, 2)))
	cases.append(raw_case([80, 30, 20, 50], [99, 70, 0, 0], 0, 30, 127, 500, 700, "output level 0", ks=(60, 99, 50, 0, 3)))
	lines = []
	for c in cases:
		e = c["env"]
		k = e["key_scaling"]
		lines.append(" ".join(str(x) for x in e["rates"] + e["levels"] + [e["output_level"], k["break_point"],
				k["left_depth"], k["right_depth"], k["left_curve"], k["right_curve"], e["rate_scaling"], e["velocity_sens"],
				c["note"], c["velocity"], c["keyoff_block"], c["blocks"]]))
	res = subprocess.run([str(HERE / "dx7_env_ref.exe")], input="\n".join(lines) + "\n", capture_output=True, text=True, check=True)
	for c, line in zip(cases, res.stdout.splitlines()):
		parts = line.split()
		c["outlevel"] = int(parts[0])
		c["rate_scaling_q"] = int(parts[1])
		c["levels_q24"] = [int(x) for x in parts[2:-1]]
		c["active"] = parts[-1]
	OUT.parent.mkdir(parents=True, exist_ok=True)
	OUT.write_text(json.dumps({"source": "msfa env.cc (Dexed, commit fea2f0f), 48 kHz, one level per 64-sample block",
			"sample_rate": 48000, "cases": cases}, separators=(",", ":")), encoding="utf-8")
	print("%d cases -> %s (%d bytes)" % (len(cases), OUT, OUT.stat().st_size))
	more(files)


def more(files):
	"""Frequencies, pitch envelopes and LFOs (dx7_ref.exe)."""
	cmds = []
	freq = []
	for mode in (0, 1):
		for coarse in (0, 1, 2, 3, 5, 9, 14, 21, 31):
			for fine in (0, 1, 7, 33, 50, 99):
				for detune in (0, 3, 7, 11, 14):
					note = 21 + (coarse * 7 + fine * 3 + detune) % 87
					pm = [0, 1398101, -2796202, 123457][(coarse + fine + detune) % 4]
					freq.append({"mode": mode, "coarse": coarse, "fine": fine, "detune": detune, "note": note, "pitch_mod": pm})
	for f in freq:
		cmds.append("freq %d %d %d %d %d %d" % (f["mode"], f["coarse"], f["fine"], f["detune"], f["note"], f["pitch_mod"]))
	penv = []
	for i in range(0, min(len(files), 256), 16):
		p = json.loads(files[i].read_text(encoding="utf-8"))["content"]["dx7"]["params"]["pitch_eg"]
		penv.append({"rates": p["rates"], "levels": p["levels"], "keyoff_block": 200 + i, "blocks": 600 + i})
	penv.append({"rates": [99, 99, 99, 99], "levels": [99, 0, 50, 50], "keyoff_block": 30, "blocks": 120})
	penv.append({"rates": [0, 20, 40, 60], "levels": [0, 99, 20, 70], "keyoff_block": 900, "blocks": 1500})
	for e in penv:
		cmds.append("penv " + " ".join(str(x) for x in e["rates"] + e["levels"] + [e["keyoff_block"], e["blocks"]]))
	lfo = []
	for i, (speed, delay, wave, sync, pmd, pms, amd) in enumerate([
			(35, 0, 4, 1, 50, 3, 20), (35, 0, 4, 0, 99, 7, 99), (60, 40, 0, 1, 30, 5, 0), (10, 99, 1, 1, 70, 2, 50),
			(80, 20, 2, 1, 99, 7, 99), (99, 10, 3, 0, 40, 4, 60), (50, 70, 5, 1, 99, 6, 99), (0, 0, 0, 1, 99, 1, 99),
			(25, 55, 4, 1, 0, 0, 80), (70, 0, 5, 0, 20, 3, 0)]):
		lfo.append({"speed": speed, "delay": delay, "wave": wave, "sync": sync, "pitch_mod_depth": pmd, "pitch_mod_sens": pms,
			"amp_mod_depth": amd, "blocks": 900})
	for l in lfo:
		cmds.append("lfo %d %d %d %d %d %d %d %d" % (l["speed"], l["delay"], l["wave"], l["sync"], l["pitch_mod_depth"],
				l["pitch_mod_sens"], l["amp_mod_depth"], l["blocks"]))
	res = subprocess.run([str(HERE / "dx7_ref.exe")], input="\n".join(cmds) + "\n", capture_output=True, text=True, check=True)
	lines = res.stdout.splitlines()
	k = 0
	for f in freq:
		f["logfreq"], f["inc"] = (int(x) for x in lines[k].split())
		k += 1
	for e in penv:
		e["levels_q24"] = [int(x) for x in lines[k].split()]
		k += 1
	for l in lfo:
		v = [int(x) for x in lines[k].split()]
		l["value"], l["delay_q24"], l["pitch_mod"], l["amp_mod"] = v[0::7], v[1::7], v[2::7], v[3::7]
		l["ldiff"] = [v[4::7], v[5::7], v[6::7]]
		k += 1
	out = OUT.parent / "dx7_ref.json"
	out.write_text(json.dumps({"source": "msfa (Dexed, commit fea2f0f) via tools/dx7_env_ref/dx7_ref.exe, 48 kHz, "
			"one value per 64-sample block; LFO started from zeroed state; ldiff at level 3840<<16 for amp mod sensitivity 1..3",
			"sample_rate": 48000, "freq": freq, "pitch_env": penv, "lfo": lfo}, separators=(",", ":")), encoding="utf-8")
	print("%d freq, %d pitch env, %d lfo cases -> %s (%d bytes)" % (len(freq), len(penv), len(lfo), out, out.stat().st_size))


main()
