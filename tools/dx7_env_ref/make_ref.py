# SPDX-License-Identifier: Apache-2.0
"""Writes tests/data/dx7_env_ref.json: msfa's own DX7 envelope levels, for the
`dx7` envelope mode's tests.

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


main()
