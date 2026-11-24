# SPDX-License-Identifier: Apache-2.0
# Renders library patches for analysis (docs/plans/patch-library.md, Analysis), for analyze.py:
#
#   godot --headless --path . --script res://tools/patch_library/render_batch.gd -- <list.txt> <out dir> [part/parts]
#
# The list holds "<id>\t<patch path>" lines. Each patch plays notes 36, 60 and 84 at velocity 100,
# each alone: held 2 s, then released for 1.5 s (3.5 s a note, 10.5 s in all). The three notes go to
# <out>/<n>.raw as mono 16-bit samples at 24 kHz (left and right averaged, pairs of 48 kHz samples
# averaged), and a line per patch to <out>/meta_<part>.jsonl: {id, file, params} with the patch's
# settings that the sound alone hides (oscillators, noise, FM, width, matrix rows, effects).
# "part/parts" (e.g. 3/8) takes every parts-th patch from the part-th.
extends SceneTree

const VERSION := 1
const NOTES := [36, 60, 84]
const HOLD_S := 2.0
const NOTE_S := 3.5
const SR := 48000

var _ran := false


func _process(_d: float) -> bool:
	if not _ran:
		_ran = true
		_run()
	return false


func _run() -> void:
	AK.disk_cache = false
	var args := OS.get_cmdline_user_args()
	if args.size() < 2:
		push_error("usage: render_batch.gd -- <list.txt> <out dir> [part/parts]")
		quit(2)
		return
	var lines := FileAccess.get_file_as_string(args[0]).split("\n", false)
	var out := args[1]
	var part := 0
	var parts := 1
	if args.size() > 2 and args[2].contains("/"):
		part = int(args[2].get_slice("/", 0))
		parts = maxi(1, int(args[2].get_slice("/", 1)))
	DirAccess.make_dir_recursive_absolute(out)
	var meta := FileAccess.open(out.path_join("meta_%d.jsonl" % part), FileAccess.WRITE)
	var done := 0
	for i in range(part, lines.size(), parts):
		var bits := lines[i].split("\t")
		if bits.size() < 2:
			continue
		var p: AKPatch = ResourceLoader.load(bits[1], "", ResourceLoader.CACHE_MODE_IGNORE)
		if p == null:
			meta.store_line(JSON.stringify({id = bits[0], error = "load"}))
			continue
		var pcm := PackedByteArray()
		pcm.resize(int(NOTE_S * SR / 2) * NOTES.size() * 2)
		var at := 0
		for n in NOTES:
			var b := AKSynth.render_notes(p, [{time_s = 0.0, note = n, velocity = 100.0 / 127.0, length_s = HOLD_S}], NOTE_S, SR)
			var half := int(NOTE_S * SR / 2)
			for k in half:
				var j := 2 * k
				var v := 0.0
				if j + 1 < b.l.size():
					v = 0.25 * (b.l[j] + b.l[j + 1] + b.r[j] + b.r[j + 1])
				pcm.encode_s16(at, clampi(roundi(v * 32767.0), -32768, 32767))
				at += 2
		var file := "%d.raw" % i
		var f := FileAccess.open(out.path_join(file), FileAccess.WRITE)
		f.store_buffer(pcm)
		f.close()
		meta.store_line(JSON.stringify({id = bits[0], file = file, params = params(p)}))
		done += 1
	meta.close()
	print("rendered %d" % done)
	quit()


## The settings that a short render hides or that tell kinds of sound apart.
static func params(p: AKPatch) -> Dictionary:
	var levels := 0.0
	var noise := 0.0
	var fm := 0.0
	var stack := 1
	var n_osc := 0
	for o: Dictionary in p.oscillators:
		var lv := absf(float(o.get("level", 1.0)))
		if lv > 0.0:
			n_osc += 1
		levels += lv
		if String(o.get("shape", "")) == "noise":
			noise += lv
		fm += absf(float(o.get("fm_index", 0.0)))
		for m in o.get("fm", []):
			if m is Dictionary:
				fm += absf(float(m.get("index", 0.0)))
		fm += absf(float(o.get("feedback", 0.0)))
		stack = maxi(stack, int(o.get("stack", 1)))
	var env_cut := 0.0
	var lfo_pitch := 0.0
	var lfo_amp := 0.0
	var lfo_cut := 0.0
	for r: Dictionary in p.mods:
		var s := String(r.get("source", ""))
		var d := String(r.get("dest", ""))
		var a := absf(float(r.get("amount", 0.0)))
		if s.begins_with("env") and d in ["cutoff", "cutoff2"]:
			env_cut += a
		elif s.begins_with("lfo"):
			if d == "pitch" or d.ends_with(".pitch"):
				lfo_pitch += a
			elif d == "amp" or d.ends_with(".level"):
				lfo_amp += a
			elif d in ["cutoff", "cutoff2"]:
				lfo_cut += a
	var fx := {}
	for e: Dictionary in p.effects:
		var t := String(e.get("type", ""))
		fx[t] = maxf(float(fx.get(t, 0.0)), float(e.get("mix", e.get("wet", 0.5))))
	return {
		n_osc = n_osc,
		noise_share = noise / levels if levels > 0.0 else 0.0,
		fm = fm,
		unison = p.unison,
		detune = p.detune_cents if p.unison > 1 else 0.0,
		stack = stack,
		mono = p.mode != "poly",
		glide = p.glide_s,
		arp = not p.arp.is_empty() and bool(p.arp.get("on", true)),
		env_cut = env_cut,
		lfo_pitch = lfo_pitch,
		lfo_amp = lfo_amp,
		lfo_cut = lfo_cut,
		reverb = float(fx.get("reverb", 0.0)),
		delay = float(fx.get("delay", 0.0)),
		chorus = 1.0 if fx.has("chorus") or fx.has("flanger") else 0.0,
		filter = String(p.filter.get("type", "lowpass")),
		cutoff = float(p.filter.get("cutoff_hz", 18000.0)),
		version = VERSION,
	}
