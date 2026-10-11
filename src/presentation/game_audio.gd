class_name GameAudio
extends Node
## Presentation-only mapping from completed gameplay facts to sound playback.

const FOOTSTEP_VOICE := &"footstep"

signal playback_requested(
	sound: StringName,
	stream: AudioStream,
	volume: float,
	pitch: float,
	voice: StringName,
)
signal voice_stopped(voice: StringName)

@export_range(1, 16, 1) var one_shot_pool_size := 6
## Tests disable device playback while still exercising mapping and voice state.
@export var playback_enabled := true
@export_group("Streams")
@export var dash_stream: AudioStream
@export var land_stream: AudioStream
@export var death_stream: AudioStream
@export var exit_stream: AudioStream
@export var bash_stream: AudioStream
@export var footstep_right_stream: AudioStream
@export var footstep_left_stream: AudioStream

var footstep_active := false
var runner: RoomRunner
var _bound_player: PlayerBody
var _bound_sprite: CharacterSprite
var _bound_pogo: PogoStrike
var _one_shots: Array[AudioStreamPlayer] = []
var _pool_cursor := 0
var _footstep_player: AudioStreamPlayer


func _ready() -> void:
	for index in one_shot_pool_size:
		var voice := AudioStreamPlayer.new()
		voice.name = "OneShot%d" % index
		add_child(voice)
		_one_shots.append(voice)
	_footstep_player = AudioStreamPlayer.new()
	_footstep_player.name = &"Footstep"
	add_child(_footstep_player)


func _exit_tree() -> void:
	for player in _one_shots:
		player.stop()
		player.stream = null
	if _footstep_player != null:
		_footstep_player.stop()
		_footstep_player.stream = null


func bind_runner(next_runner: RoomRunner) -> void:
	if runner != null:
		if runner.restarted.is_connected(_on_restarted):
			runner.restarted.disconnect(_on_restarted)
		if runner.character_changed.is_connected(_on_character_changed):
			runner.character_changed.disconnect(_on_character_changed)
	_disconnect_player()
	runner = next_runner
	if runner == null:
		return
	runner.restarted.connect(_on_restarted)
	runner.character_changed.connect(_on_character_changed)
	if runner.player != null:
		_connect_player(runner.player)


static func land_options(airtime: float) -> Dictionary:
	var amount := clampf(airtime / 0.9, 0.0, 1.0)
	return {
		"volume": amount,
		"pitch": 1.28 - 0.5 * amount,
	}


func _connect_player(player: PlayerBody) -> void:
	_disconnect_player()
	_bound_player = player
	_bound_player.dashed.connect(_on_dashed)
	_bound_player.landed.connect(_on_landed)
	_bound_sprite = player.get_node_or_null(^"CharacterSprite") as CharacterSprite
	if _bound_sprite != null:
		_bound_sprite.frame_event.connect(_on_frame_event)
		_bound_sprite.clip_changed.connect(_on_clip_changed)
	_bound_pogo = player.ability as PogoStrike
	if _bound_pogo != null:
		_bound_pogo.side_bashed.connect(_on_side_bashed)


func _disconnect_player() -> void:
	_stop_footstep()
	if is_instance_valid(_bound_player):
		if _bound_player.dashed.is_connected(_on_dashed):
			_bound_player.dashed.disconnect(_on_dashed)
		if _bound_player.landed.is_connected(_on_landed):
			_bound_player.landed.disconnect(_on_landed)
	if is_instance_valid(_bound_sprite):
		if _bound_sprite.frame_event.is_connected(_on_frame_event):
			_bound_sprite.frame_event.disconnect(_on_frame_event)
		if _bound_sprite.clip_changed.is_connected(_on_clip_changed):
			_bound_sprite.clip_changed.disconnect(_on_clip_changed)
	if is_instance_valid(_bound_pogo) and _bound_pogo.side_bashed.is_connected(_on_side_bashed):
		_bound_pogo.side_bashed.disconnect(_on_side_bashed)
	_bound_player = null
	_bound_sprite = null
	_bound_pogo = null


func _on_character_changed(_index: int) -> void:
	_connect_player(runner.player)


func _on_dashed(_facing: float) -> void:
	_play_one_shot(&"dash", dash_stream, 0.55, 0.99)


func _on_landed(airtime: float) -> void:
	var options := land_options(airtime)
	_play_one_shot(&"land", land_stream, options.volume, options.pitch)


func _on_restarted(reason: RoomRunner.RestartReason) -> void:
	if reason == RoomRunner.RestartReason.EXIT:
		_play_one_shot(&"exit", exit_stream, 0.65)
	else:
		_play_one_shot(&"death", death_stream, 0.6)


func _on_side_bashed() -> void:
	_play_one_shot(&"bash", bash_stream, 0.7)


func _on_frame_event(event_name: StringName, _clip: StringName, _frame_index: int) -> void:
	match event_name:
		&"footstep_right":
			_play_footstep(&"footstep_right", footstep_right_stream)
		&"footstep_left":
			_play_footstep(&"footstep_left", footstep_left_stream)


func _on_clip_changed(clip: StringName) -> void:
	if clip != &"run":
		_stop_footstep()


func _play_one_shot(
	sound: StringName,
	stream: AudioStream,
	volume := 1.0,
	pitch := 1.0,
) -> void:
	if stream == null or _one_shots.is_empty():
		return
	var player: AudioStreamPlayer
	for candidate in _one_shots:
		if not candidate.playing:
			player = candidate
			break
	if player == null:
		player = _one_shots[_pool_cursor]
		player.stop()
	_pool_cursor = (_pool_cursor + 1) % _one_shots.size()
	player.stream = stream
	player.volume_db = linear_to_db(maxf(volume, 0.0))
	player.pitch_scale = pitch
	playback_requested.emit(sound, stream, volume, pitch, &"")
	if playback_enabled:
		player.play()


func _play_footstep(sound: StringName, stream: AudioStream) -> void:
	if stream == null:
		return
	_stop_footstep()
	_footstep_player.stream = stream
	_footstep_player.volume_db = 0.0
	_footstep_player.pitch_scale = 1.0
	footstep_active = true
	playback_requested.emit(sound, stream, 1.0, 1.0, FOOTSTEP_VOICE)
	if playback_enabled:
		_footstep_player.play()


func _stop_footstep() -> void:
	if not footstep_active:
		return
	_footstep_player.stop()
	footstep_active = false
	voice_stopped.emit(FOOTSTEP_VOICE)
