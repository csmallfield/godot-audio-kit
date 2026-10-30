# SPDX-License-Identifier: Apache-2.0
## The Sound Lab's scope and spectrum. Give it samples with `show_samples`:
##
##   WAVE      a few cycles, steadied on a rising zero crossing (an oscilloscope)
##   SPECTRUM  levels by frequency on a log axis, 20 Hz .. 20 kHz, 0 to -90 dB
##   NOTE      a whole rendered note: its outline over time
@tool
class_name AKScope
extends Control

enum Mode { WAVE, SPECTRUM, NOTE }

@export var mode := Mode.WAVE:
	set(v):
		mode = v
		queue_redraw()
var sample_rate := 48000
## Samples drawn across the width in WAVE mode.
var window := 1024
var line_color := Color(0.45, 0.85, 1.0)

var _samples := PackedFloat32Array()
var _db := PackedFloat32Array()
var _fft_size := 2048


func _init() -> void:
	custom_minimum_size = Vector2(200, 110) * AKUiScale.factor()
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func show_samples(samples: PackedFloat32Array, sr := 48000) -> void:
	_samples = samples
	sample_rate = sr
	if mode == Mode.SPECTRUM:
		_db = AKSpectrum.magnitudes_db(samples, _fft_size)
	queue_redraw()


## The spectrum last shown (decibels per bin).
func spectrum() -> PackedFloat32Array:
	return _db


## Where WAVE mode starts drawing: the last rising zero crossing that leaves
## a full window after it, so a steady tone stands still.
func trigger_index() -> int:
	var n := _samples.size()
	var i := n - window - 1
	while i > 0:
		if _samples[i - 1] <= 0.0 and _samples[i] > 0.0:
			return i
		i -= 1
	return maxi(0, n - window)


func _draw() -> void:
	var w := size.x
	var h := size.y
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.05, 0.06, 0.08))
	match mode:
		Mode.WAVE:
			_draw_wave(w, h)
		Mode.SPECTRUM:
			_draw_spectrum(w, h)
		Mode.NOTE:
			_draw_note(w, h)


func _draw_wave(w: float, h: float) -> void:
	draw_line(Vector2(0, h * 0.5), Vector2(w, h * 0.5), Color(1, 1, 1, 0.12))
	if _samples.size() < 2:
		return
	var start := trigger_index()
	var n := mini(window, _samples.size() - start)
	var pts := PackedVector2Array()
	for i in n:
		pts.append(Vector2(w * float(i) / float(maxi(1, n - 1)), h * 0.5 - clampf(_samples[start + i], -1.1, 1.1) * h * 0.45))
	if pts.size() >= 2:
		draw_polyline(pts, line_color, 1.0, true)


func _draw_spectrum(w: float, h: float) -> void:
	var font := get_theme_default_font()
	for f: float in [100.0, 1000.0, 10000.0]:
		var x := w * log(f / 20.0) / log(1000.0)
		draw_line(Vector2(x, 0), Vector2(x, h), Color(1, 1, 1, 0.1))
		if font:
			draw_string(font, Vector2(x + 2, h - 3), ("%dk" % int(f / 1000.0)) if f >= 1000.0 else "%d" % int(f), HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(1, 1, 1, 0.35))
	for db: float in [-30.0, -60.0]:
		var y := h * -db / 90.0
		draw_line(Vector2(0, y), Vector2(w, y), Color(1, 1, 1, 0.07))
	if _db.size() < 2:
		return
	var n := (_db.size() - 1) * 2
	var pts := PackedVector2Array()
	var cols := maxi(2, int(w / 2.0))
	for c in cols:
		# Each column shows the loudest bin it covers.
		var f0 := 20.0 * pow(1000.0, float(c) / float(cols))
		var f1 := 20.0 * pow(1000.0, float(c + 1) / float(cols))
		var k0 := clampi(int(f0 * n / sample_rate), 1, _db.size() - 1)
		var k1 := clampi(int(f1 * n / sample_rate), k0, _db.size() - 1)
		var v := -200.0
		for k in range(k0, k1 + 1):
			v = maxf(v, _db[k])
		pts.append(Vector2(w * float(c) / float(cols - 1), clampf(h * -v / 90.0, 0.0, h)))
	draw_polyline(pts, line_color, 1.0, true)


func _draw_note(w: float, h: float) -> void:
	draw_line(Vector2(0, h * 0.5), Vector2(w, h * 0.5), Color(1, 1, 1, 0.12))
	var n := _samples.size()
	if n < 2:
		return
	var cols := maxi(1, int(w))
	for c in cols:
		var a := int(float(c) / cols * n)
		var b := maxi(a + 1, int(float(c + 1) / cols * n))
		var lo := 0.0
		var hi := 0.0
		for i in range(a, mini(b, n)):
			lo = minf(lo, _samples[i])
			hi = maxf(hi, _samples[i])
		# Clipped at the frame: anything past full scale shows red.
		var over := hi > 1.0 or lo < -1.0
		hi = minf(hi, 1.1)
		lo = maxf(lo, -1.1)
		draw_line(Vector2(c, h * 0.5 - hi * h * 0.45), Vector2(c, h * 0.5 - lo * h * 0.45 + 0.5), Color(1.0, 0.35, 0.3) if over else line_color)
