extends SceneTree
## Audio event mapping without depending on a real output device.

const MAIN_SCENE := preload("res://scenes/main.tscn")

var _failed := false
var _requests: Array[Dictionary] = []
var _stopped_voices: Array[StringName] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var main := MAIN_SCENE.instantiate() as RoomRunner
	main.process_mode = Node.PROCESS_MODE_DISABLED
	root.add_child(main)
	var audio := main.get_node(^"GameAudio") as GameAudio
	audio.playback_enabled = false
	audio.playback_requested.connect(_on_playback_requested)
	audio.voice_stopped.connect(func(voice: StringName) -> void: _stopped_voices.append(voice))

	_expect(audio._one_shots.size() == audio.one_shot_pool_size, "one-shot pool was not created")
	main.player.dashed.emit(1.0)
	_expect_request(&"dash", "dash2.wav", 0.55, 0.99)

	main.player.landed.emit(0.45)
	_expect_request(&"land", "jump_land.wav", 0.5, 1.03)
	var quiet := GameAudio.land_options(-1.0)
	var loud := GameAudio.land_options(2.0)
	_expect(quiet.volume == 0.0 and quiet.pitch == 1.28, "short landing options were not clamped")
	_expect(loud.volume == 1.0 and loud.pitch == 0.78, "long landing options were not clamped")

	main.restarted.emit(RoomRunner.RestartReason.DEATH)
	_expect_request(&"death", "bird_poo.wav", 0.6, 1.0)
	main.restarted.emit(RoomRunner.RestartReason.FALL)
	_expect_request(&"death", "bird_poo.wav", 0.6, 1.0)
	main.restarted.emit(RoomRunner.RestartReason.EXIT)
	_expect_request(&"exit", "fanfare.ogg", 0.65, 1.0)

	main.switch_character(2)
	var pogo := main.player
	(pogo.ability as PogoStrike).side_bashed.emit(1.0)
	_expect_request(&"bash", "bash.ogg", 0.7, 1.0)

	var sprite := pogo.get_node(^"CharacterSprite") as CharacterSprite
	sprite.frame_event.emit(&"footstep_right", &"run", 0)
	_expect_request(&"footstep_right", "footstep.wav", 1.0, 1.0, GameAudio.FOOTSTEP_VOICE)
	_expect(audio.footstep_active, "first footstep did not claim its named voice")
	sprite.frame_event.emit(&"footstep_left", &"run", 4)
	_expect_request(&"footstep_left", "footstep_cane.wav", 1.0, 1.0, GameAudio.FOOTSTEP_VOICE)
	_expect(_stopped_voices == [GameAudio.FOOTSTEP_VOICE], "second footstep did not replace the first voice")
	sprite.clip_changed.emit(&"idle")
	_expect(not audio.footstep_active and _stopped_voices.size() == 2, "leaving run did not stop the footstep voice")

	var stale_player := main.player
	var before_switch := _requests.size()
	main.switch_character(0)
	stale_player.dashed.emit(1.0)
	_expect(_requests.size() == before_switch, "replaced character still drove audio")
	main.player.dashed.emit(1.0)
	_expect(_requests.size() == before_switch + 1 and _requests.back().sound == &"dash", "new character was not connected to audio")

	await process_frame
	main.free()
	await process_frame
	quit(1 if _failed else 0)


func _on_playback_requested(
	sound: StringName,
	stream: AudioStream,
	volume: float,
	pitch: float,
	voice: StringName,
) -> void:
	_requests.append({
		"sound": sound,
		"path": stream.resource_path,
		"volume": volume,
		"pitch": pitch,
		"voice": voice,
	})


func _expect_request(
	sound: StringName,
	file_name: String,
	volume: float,
	pitch: float,
	voice := &"",
) -> void:
	if _requests.is_empty():
		_expect(false, "%s did not request playback" % sound)
		return
	var request: Dictionary = _requests.back()
	_expect(request.sound == sound, "expected %s, got %s" % [sound, request.sound])
	_expect(String(request.path).ends_with(file_name), "%s mapped to %s" % [sound, request.path])
	_expect(is_equal_approx(request.volume, volume), "%s volume was %f, expected %f" % [sound, request.volume, volume])
	_expect(is_equal_approx(request.pitch, pitch), "%s pitch was %f, expected %f" % [sound, request.pitch, pitch])
	_expect(request.voice == voice, "%s voice was %s, expected %s" % [sound, request.voice, voice])


func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	_failed = true
	push_error(message)
