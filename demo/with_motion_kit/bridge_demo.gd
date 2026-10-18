# SPDX-License-Identifier: Apache-2.0
# A tiny composition scored by AKCueBridge: a bar slams in, three blocks count
# down, a disc lands. Needs the motion kit linked (tools/link_motion_kit.sh).
@tool
extends MotionComposition

const IN := 0.0
const COUNT := [20.0, 38.0, 56.0]
const GO := 74.0
const OUT := 130.0

var _bar: ColorRect
var _blocks: Array[ColorRect] = []
var _disc: ColorRect


func _init() -> void:
	fps = 30
	duration = 160
	cue(IN, &"whoosh.in", 0.8)
	for i in COUNT.size():
		cue(COUNT[i], &"count", 0.7 + 0.15 * i, {pitch = [0.9, 1.0, 1.12][i]})
	cue(GO, &"go", 1.0)
	cue(OUT, &"whoosh.out", 0.9)


func _ready() -> void:
	if not _bar:
		_bar = _rect(Color("#ffcf3a"))
		for i in 3:
			_blocks.append(_rect(Color("#f2f2f2")))
		_disc = _rect(Color("#ff4b3a"))
	super._ready()


func _rect(c: Color) -> ColorRect:
	var r := ColorRect.new()
	r.color = c
	add_child(r)
	return r


func _frame(f: float) -> void:
	if not _bar:
		return
	var out := MK.map(f, [OUT, OUT + 12], [0, 1], MK.ease_in_back)
	_bar.position = Vector2(lerpf(-1920.0, 0.0, MK.spring(f, IN, 14, 160)), 480 + out * 700)
	_bar.size = Vector2(1920, 120)
	for i in 3:
		var s := MK.spring(f, COUNT[i], 10, 200)
		_blocks[i].size = Vector2(160, 160) * s
		_blocks[i].position = Vector2(660 + i * 230, 260) + Vector2(80, 80) * (1.0 - s)
	var d := MK.spring(f, GO, 8, 160)
	_disc.size = Vector2(300, 300)
	_disc.position = Vector2(810, lerpf(-400.0, 700.0, d) + out * 900)
