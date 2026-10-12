class_name RoomRunner
extends Node2D
## Plays one room with one character: spawn, character switching, hitstop, and
## restarts when the player's sensors report a fall, exit, hazard, or crush, or
## the player is hurt by a walker or throwable. A restart also resets the room's
## props and actors.
## Runs its physics before the player: sensor signals from the last physics step
## arrive first, so a restart lands before the player moves again.

signal restarted(reason: RestartReason)
signal character_changed(index: int)

## Lower values win when several triggers are touched in one step.
enum RestartReason {
	FALL,
	EXIT,
	DEATH,
}

const NO_RESTART := -1

@export var room: Room
@export var camera: FollowCamera
## Optional; framed to the room so its layers line up with the room's edges.
@export var backdrop: Backdrop
## Optional presentation listener; gameplay only provides completed facts.
@export var audio: GameAudio
## Cycled with `next_character`. Order matches the prototype: Standard, Grappler, Pogo.
@export var characters: Array[PackedScene] = []
@export var character_index := 1
## Stacks for this run, kept off whichever character is currently spawned.
var build := RunBuild.new()
## Potions for `build`. A planted checkpoint lives here, not on the player.
var belt := PotionBelt.new()

var player: PlayerBody
var hitstop_left := 0.0
## The request tick itself does not count down, so a hitstop freezes its full length.
var _hitstop_requested_this_tick := false
var _pending_restart := NO_RESTART
var _pending_shakes: Array[Dictionary] = []


func _ready() -> void:
	if backdrop != null:
		backdrop.frame(room.pixel_rect(), get_viewport_rect().size / camera.zoom)
	switch_character(character_index)
	if audio != null:
		audio.bind_runner(self)


func _physics_process(delta: float) -> void:
	if Input.is_action_just_pressed(&"next_character"):
		switch_character((character_index + 1) % characters.size())
		return
	if _pending_restart != NO_RESTART:
		restart(_pending_restart)
		return
	_tick_hitstop(delta)


func switch_character(index: int) -> void:
	if player != null:
		remove_child(player)
		player.queue_free()
	character_index = index
	player = characters[index].instantiate() as PlayerBody
	player.name = &"Player"
	player.room = room
	player.hitstop_requested.connect(_on_hitstop_requested)
	player.screen_shake_requested.connect(_on_screen_shake_requested)
	player.trigger_touched.connect(_on_trigger_touched)
	player.crushed.connect(_queue_restart.bind(RestartReason.DEATH))
	player.hurt.connect(_queue_restart.bind(RestartReason.DEATH).unbind(1))
	add_child(player)
	apply_build()
	room.use_surfaces(player.uses_grapple_surfaces, player.uses_pogo_surfaces)
	camera.target = player
	camera.frame_room(room.pixel_rect())
	_respawn()
	character_changed.emit(index)


## Writes this run's stats onto the current character's baseline, stores the sim
## scale, and syncs potions. A second call does not stack the modifiers again.
func apply_build() -> void:
	if player != null:
		player.apply_build(build)
	if room == null:
		return
	room.sim_scale = build.time_scale
	belt.sync(build, room)
	_drop_spent_potions()


## Feet used when planting a checkpoint: body origin x, collision bottom y.
func player_feet() -> Vector2:
	return Vector2(player.global_position.x, player.body_rect().end.y)


func drink_potion(id: RunBuild.Id) -> CheckpointUse:
	if player == null or room == null:
		return null
	var record := belt.use(id, player_feet(), room)
	_drop_spent_potions()
	return record


func restart(reason: RestartReason) -> void:
	# Leaving through the exit drops a planted flag. Death and falls keep it.
	if reason == RestartReason.EXIT and room != null:
		belt.on_room_exit(room)
	_respawn()
	restarted.emit(reason)


func _drop_spent_potions() -> void:
	var spent := belt.spent()
	if spent.is_empty() or room == null:
		return
	for id: RunBuild.Id in spent:
		build.remove_stack(id)
	if player != null:
		player.apply_build(build)
	belt.sync(build, room)


func _respawn() -> void:
	hitstop_left = 0.0
	_hitstop_requested_this_tick = false
	_pending_restart = NO_RESTART
	_pending_shakes.clear()
	camera.clear_shake()
	room.freeze_entities(false)
	room.reset_entities()
	player.respawn(room.spawn_feet())
	camera.snap_to_target()


func _tick_hitstop(delta: float) -> void:
	var was_active := hitstop_left > 0.0
	if _hitstop_requested_this_tick:
		_hitstop_requested_this_tick = false
	elif hitstop_left > 0.0:
		hitstop_left = maxf(0.0, hitstop_left - delta)
	if was_active and hitstop_left <= 0.0:
		_release_pending_shakes()
	var frozen := hitstop_left > 0.0
	if frozen != player.frozen:
		player.frozen = frozen
		room.freeze_entities(frozen)


func _on_hitstop_requested(seconds: float) -> void:
	if seconds > hitstop_left:
		hitstop_left = seconds
		_hitstop_requested_this_tick = true


func _on_screen_shake_requested(
	seconds: float,
	amplitude: float,
	frequency: float,
	direction: Vector2,
) -> void:
	if hitstop_left <= 0.0:
		camera.request_shake(seconds, amplitude, frequency, direction)
		return
	_pending_shakes.append({
		"seconds": seconds,
		"amplitude": amplitude,
		"frequency": frequency,
		"direction": direction,
	})


func _release_pending_shakes() -> void:
	for request in _pending_shakes:
		camera.request_shake(
			request.seconds,
			request.amplitude,
			request.frequency,
			request.direction,
		)
	_pending_shakes.clear()


func _on_trigger_touched(layer: int) -> void:
	var reason := RestartReason.DEATH
	if layer & PhysicsLayers.FALL:
		reason = RestartReason.FALL
	elif layer & PhysicsLayers.EXIT:
		reason = RestartReason.EXIT
	_queue_restart(reason)


func _queue_restart(reason: RestartReason) -> void:
	if _pending_restart == NO_RESTART or reason < _pending_restart:
		_pending_restart = reason
