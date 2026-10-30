# SPDX-License-Identifier: Apache-2.0
## A picture of an envelope: attack, decay to sustain, a held stretch, then
## the release, on a time axis that fits the whole shape.
@tool
class_name AKEnvView
extends Control

## {attack_s, decay_s, sustain, release_s, curve}.
var env := {}
var line_color := Color(1.0, 0.81, 0.23)


func _init() -> void:
	custom_minimum_size = Vector2(0, 48) * AKUiScale.factor()
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## The envelope's level at time `t` with the note held for `hold_s`.
static func level_at(e: Dictionary, t: float, hold_s: float) -> float:
	var a := maxf(0.0, float(e.get("attack_s", 0.0)))
	var d := maxf(1e-4, float(e.get("decay_s", 0.2)))
	var s := clampf(float(e.get("sustain", 0.0)), 0.0, 1.0)
	var r := maxf(1e-4, float(e.get("release_s", 0.15)))
	var expo := String(e.get("curve", "linear")) == "exp"
	var held := func(x: float) -> float:
		if x < a:
			return x / a
		var y := x - a
		if expo:
			return s + (1.0 - s) * exp(-y / d)
		return lerpf(1.0, s, minf(1.0, y / d))
	if t <= hold_s:
		return held.call(t)
	return float(held.call(hold_s)) * exp(-(t - hold_s) / r)


func _draw() -> void:
	var w := size.x
	var h := size.y
	draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, 0.25))
	var a := maxf(0.0, float(env.get("attack_s", 0.0)))
	var d := maxf(1e-4, float(env.get("decay_s", 0.2)))
	var r := maxf(1e-4, float(env.get("release_s", 0.15)))
	var expo := String(env.get("curve", "linear")) == "exp"
	var decay_len := d * (4.0 if expo else 1.0)
	var hold := a + decay_len + maxf(0.1, 0.25 * (a + decay_len))
	var total := hold + 4.0 * r
	var pts := PackedVector2Array()
	var n := maxi(32, int(w))
	for i in n + 1:
		var t := total * float(i) / float(n)
		pts.append(Vector2(w * float(i) / float(n), h - 2.0 - (h - 4.0) * level_at(env, t, hold)))
	var xr := w * hold / total
	draw_line(Vector2(xr, 0), Vector2(xr, h), Color(1, 1, 1, 0.15))
	draw_polyline(pts, line_color, 1.5, true)
