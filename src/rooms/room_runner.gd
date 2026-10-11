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

var player: PlayerBody
var hitstop_left := 0.0
## The request tick itself does not count down, so a hitstop freezes its full length.
var _hitstop_requested_this_tick := false
var _pending_restart := NO_RESTART


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
	player.trigger_touched.connect(_on_trigger_touched)
	player.crushed.connect(_queue_restart.bind(RestartReason.DEATH))
	player.hurt.connect(_queue_restart.bind(RestartReason.DEATH).unbind(1))
	add_child(player)
	room.use_surfaces(player.uses_grapple_surfaces, player.uses_pogo_surfaces)
	camera.target = player
	camera.frame_room(room.pixel_rect())
	_respawn()
	character_changed.emit(index)


func restart(reason: RestartReason) -> void:
	_respawn()
	restarted.emit(reason)


func _respawn() -> void:
	hitstop_left = 0.0
	_hitstop_requested_this_tick = false
	_pending_restart = NO_RESTART
	room.freeze_entities(false)
	room.reset_entities()
	player.respawn(room.spawn_feet())
	camera.snap_to_target()


func _tick_hitstop(delta: float) -> void:
	if _hitstop_requested_this_tick:
		_hitstop_requested_this_tick = false
	elif hitstop_left > 0.0:
		hitstop_left = maxf(0.0, hitstop_left - delta)
	var frozen := hitstop_left > 0.0
	if frozen != player.frozen:
		player.frozen = frozen
		room.freeze_entities(frozen)


func _on_hitstop_requested(seconds: float) -> void:
	if seconds > hitstop_left:
		hitstop_left = seconds
		_hitstop_requested_this_tick = true


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
