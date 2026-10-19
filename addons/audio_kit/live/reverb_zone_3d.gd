# SPDX-License-Identifier: Apache-2.0
## A space with its own reverb: while the listener is inside this area, the
## AKLivePlayer's shared reverb glides to these settings (and back to the cue
## map's when it leaves). Give it a CollisionShape3D. Where zones overlap, the
## highest `priority` (the area's own) wins.
@icon("res://addons/audio_kit/icons/palette.svg")
class_name AKReverbZone3D
extends Area3D

@export_range(0.0, 1.0) var room := 0.85
@export_range(0.0, 1.0) var damp := 0.3
@export_range(0.0, 1.0) var width := 1.0
## Wet level, dB.
@export var return_db := 0.0
## Glide time into this space; below 0 uses the player's.
@export var glide_s := -1.0


func settings() -> Dictionary:
	return {room = room, damp = damp, width = width, return_db = return_db}
