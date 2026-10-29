# SPDX-License-Identifier: Apache-2.0
## Game sound effects straight from the SFX generator, as AudioStreams: a
## button per category plays that category's recipe stream, which picks a
## new variation each play (AKRecipeStream.vary_per_play). "New sounds"
## rolls new seeds. No native core needed (it only makes the first play of
## each sound faster).
extends Control

var players := {}    # category -> AudioStreamPlayer
var seed_ := 1


func _ready() -> void:
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_FULL_RECT)
	box.offset_left = 16
	box.offset_top = 12
	add_child(box)
	var title := Label.new()
	title.text = "Audio Kit: generated sound effects (each play varies)"
	box.add_child(title)
	var grid := GridContainer.new()
	grid.columns = 5
	box.add_child(grid)
	for cat in AKSfxGen.CATEGORIES:
		if cat == &"random":
			continue
		var p := AudioStreamPlayer.new()
		add_child(p)
		players[cat] = p
		var b := Button.new()
		b.text = String(cat).replace("_", " ")
		b.custom_minimum_size = Vector2(120, 40)
		var c: StringName = cat
		b.pressed.connect(func() -> void: play(c))
		grid.add_child(b)
	var again := Button.new()
	again.text = "New sounds"
	again.pressed.connect(reroll)
	box.add_child(again)
	reroll()


## Give every category a new recipe (seeded, so a seed always gives the same set).
func reroll() -> void:
	seed_ += 1
	for cat in players:
		var r := AKSfxGen.generate(cat, seed_ * 101)
		(players[cat] as AudioStreamPlayer).stream = AKRecipeStream.of(r, true, 4)


func play(cat: StringName) -> void:
	(players[cat] as AudioStreamPlayer).play()
