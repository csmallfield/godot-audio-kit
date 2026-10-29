# SPDX-License-Identifier: Apache-2.0
## A .mid file played as an AKSong through the General MIDI starter bank:
## minuet.mid is imported by the kit's import plugin like any resource. With
## the native core it plays live (each lane through the patches it names);
## without, it renders once and plays the bake.
extends Control

const SONG := "res://demo/sound_lab/minuet.mid"

var song: AKSong
var live: AKLive
var player: AudioStreamPlayer


func _ready() -> void:
	song = load(SONG) as AKSong
	if song == null:
		song = AKMidi.import_file(SONG)   # not imported yet (a fresh checkout outside the editor)
	player = AudioStreamPlayer.new()
	add_child(player)
	var l := Label.new()
	l.position = Vector2(16, 12)
	l.text = "Audio Kit: %s\n\n%s" % [SONG.get_file(), AKMidi.summary(song)]
	add_child(l)
	if AKLive.available():
		live = AKLive.new()
		player.stream = live.stream
		var m := AKCueMap.new()
		m.reverb = song.reverb
		m.master_fx = song.master_fx
		live.prepare([], m)
		live.song_play(song, &"song")
	else:
		player.stream = song.render().mix.to_stream()
	player.play()


func _process(_delta: float) -> void:
	if live:
		live.update()
