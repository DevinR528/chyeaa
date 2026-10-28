class_name RoomRunner
extends Node2D
## Plays one room with one character: spawn, character switching, hitstop, and
## restarts when the player's sensors report a fall, exit, hazard, or crush, or
## the player is hurt by a walker or throwable. Death and exit play out where the
## body stopped, and the respawn or reward menu waits until that effect ends.
## A restart also resets the room's props and actors.
## Runs its physics before the player: sensor signals from the last physics step
## arrive first, so a restart lands before the player moves again.

signal restarted(reason: RestartReason)
## Fired when a death, fall, or exit effect begins, before the delay.
signal transition_started(reason: RestartReason)
signal character_changed(index: int)

## Lower values win when several triggers are touched in one step.
enum RestartReason {
	FALL,
	EXIT,
	DEATH,
}

const NO_RESTART := -1
const GEN_RETRY_SEEDS := 5
const GEN_DIFFICULTY := 3
const GEN_PIECE_COUNT := Vector2i(1, 2)
const PIECE_LIBRARY := preload("res://resources/pieces/library.tres")
const DEMO_ROOM := preload("res://scenes/rooms/demo.tscn")

@export var room: Room
@export var camera: FollowCamera
## Optional; framed to the room so its layers line up with the room's edges.
@export var backdrop: Backdrop
## Optional presentation listener; gameplay only provides completed facts.
@export var audio: GameAudio
## When set, leaving through the exit opens this offer instead of restarting
## immediately. Picking a card adds it to the build, then the exit restart runs.
## A generated run loads the next room instead of respawning this one.
@export var reward_menu: RewardMenu
## Cycled with `next_character`. Order matches the prototype: Standard, Grappler, Pogo.
@export var characters: Array[PackedScene] = []
@export var character_index := 1
## Stacks for this run, kept off whichever character is currently spawned.
var build := RunBuild.new()
## Potions for `build`. A planted checkpoint lives here, not on the player.
var belt := PotionBelt.new()
## Input log since the last respawn. Replay calls the same step as live play.
var _log := RewindLog.new()
## True while a scrub is re-running recorded steps.
var replaying := false
## Death keeps this history, matching the debug overlays. Tests set it directly.
var keep_rewind_history := false
## Set while pause started a generated run. Exit then loads the next seed.
var gen_active := false
var gen_seed := 1
var gen_level := 1

var player: PlayerBody
var hitstop_left := 0.0
## The request tick itself does not count down, so a hitstop freezes its full length.
var _hitstop_requested_this_tick := false
var _pending_restart := NO_RESTART
var _pending_shakes: Array[Dictionary] = []
## The restart that follows a reward pick must not open the menu again.
var _exit_reward_chosen := false
var _transition_reason := NO_RESTART
var _advance_queued := false
var _cursor := 0
var fx: RoomFx


func _ready() -> void:
	# Before props and actors, so their own _physics_process sees `driven` and does not tick twice.
	process_physics_priority = -10
	fx = RoomFx.new()
	fx.name = &"RoomFx"
	fx.z_index = 10
	add_child(fx)
	var trail := RewindTrail.new()
	trail.name = &"RewindTrail"
	trail.runner = self
	add_child(trail)
	if reward_menu != null:
		reward_menu.picked.connect(_on_reward_picked)
	if backdrop != null:
		backdrop.frame(room.pixel_rect(), get_viewport_rect().size / camera.zoom)
	switch_character(character_index)
	if audio != null:
		audio.bind_runner(self)


func _physics_process(delta: float) -> void:
	if replaying or _advance_queued:
		return
	if Input.is_action_just_pressed(&"next_character"):
		switch_character((character_index + 1) % characters.size())
		return
	_run_step(delta, null)


## Live play and rewind both come through here. `recorded` is null while playing,
## and the step then samples input. A blank recorded frame is ignored on effect
## frames; those branch on the room state instead of the saved buttons.
func _run_step(real_delta: float, recorded: PlayerInputFrame) -> void:
	if player == null or room == null:
		return
	if replaying:
		_sync_replay_contacts()
	if fx.is_playing():
		_note_input(PlayerInputFrame.new(), real_delta)
		_tick_fx(real_delta)
		_note_trail()
		return
	if _pending_restart != NO_RESTART:
		_begin_transition(_pending_restart)
		_note_input(PlayerInputFrame.new(), real_delta)
		_tick_room(real_delta, PlayerInputFrame.new())
		_note_trail()
		return
	_tick_hitstop(real_delta)
	if hitstop_left > 0.0:
		return
	var frame := recorded if recorded != null else player.player_input.consume()
	_note_input(frame, real_delta)
	_tick_room(real_delta, frame)
	_note_trail()


## The engine flushes area contacts once per physics frame. A scrub runs many
## steps inside one call, so it queries the pairs itself before each step.
func _sync_replay_contacts() -> void:
	if player.contact_box != null:
		player.contact_box.sync_overlaps()
	for actor in room.actors():
		if actor.contact_box != null:
			actor.contact_box.sync_overlaps()
	player.sync_trigger_contacts()


func _clear_contact_memory() -> void:
	if player != null and player.contact_box != null:
		player.contact_box.clear_overlaps()
	if room == null:
		return
	for actor in room.actors():
		if actor.contact_box != null:
			actor.contact_box.clear_overlaps()


func _tick_room(real_delta: float, frame: PlayerInputFrame) -> void:
	for prop in room.props():
		prop.driven = true
		prop.tick(real_delta)
	for actor in room.actors():
		actor.driven = true
		actor.tick(real_delta)
	player.driven = true
	player.tick(real_delta, frame)


func _note_input(frame: PlayerInputFrame, real_delta: float) -> void:
	if replaying or player == null:
		return
	_sync_recording()
	if not _log.recording:
		return
	_log.push(frame, real_delta, player.stats)


func _note_trail() -> void:
	if player == null:
		return
	if replaying:
		if _log.recording and _debug_overlay_on():
			_log.put_trail(_cursor, player.global_position)
		return
	if _log.recording and _debug_overlay_on():
		_log.push_trail(player.global_position)
	if _log.recording:
		_cursor = _log.steps.size()


func rewind_floor() -> int:
	return 0 if _keep_history() else _log.respawn_floor()


func rewind_is_free() -> bool:
	return _keep_history()


func can_rewind() -> bool:
	return (
		_log.recording
		and player != null
		and not fx.is_playing()
		and not _advance_queued
		and _log.steps.size() > rewind_floor()
	)


func rewind_timeline() -> Dictionary:
	return {
		"floor": rewind_floor(),
		"total": _log.steps.size(),
		"deaths": _log.deaths,
		"step_seconds": 1.0 / float(Engine.physics_ticks_per_second),
		"bytes": _log.payload_bytes(),
	}


func preview_rewind(k: int) -> void:
	if not _log.recording or player == null:
		return
	var target := clampi(k, 0, _log.steps.size())
	var live_stats := player.stats
	replaying = true
	if target < _cursor:
		_log.undo_uses_through(_cursor)
		_reset_to_history_start()
		_cursor = 0
		_log.redo_uses_at(0)
	while _cursor < target:
		var step: RewindLog.Step = _log.steps[_cursor]
		player.stats = step.stats
		_run_step(step.real_delta, step.frame)
		_cursor += 1
		_log.redo_uses_at(_cursor)
	player.stats = live_stats
	replaying = false
	_log.cut_trail(_cursor)
	if camera != null:
		camera.snap_to_target()
	player.reset_physics_interpolation()
	var trail := get_node_or_null(^"RewindTrail") as RewindTrail
	if trail != null:
		trail.queue_redraw()


## Puts the room at `k` and forgets everything after it. `free_in_debug` skips the charge.
func commit_rewind(k: int, free_in_debug := false) -> void:
	preview_rewind(k)
	_log.truncate(_cursor)
	if not free_in_debug:
		var potion := belt.potion(RunBuild.Id.REWIND)
		if potion is RewindPotion:
			(potion as RewindPotion).spend()
		_drop_spent_potions()
	_sync_recording()
	hitstop_left = 0.0
	_hitstop_requested_this_tick = false
	_pending_shakes.clear()
	if camera != null:
		camera.clear_shake()
	if player != null:
		player.frozen = false
	if room != null:
		room.freeze_entities(false)


func _reset_to_history_start() -> void:
	fx.clear()
	_transition_reason = NO_RESTART
	hitstop_left = 0.0
	_hitstop_requested_this_tick = false
	_pending_restart = NO_RESTART
	_pending_shakes.clear()
	if camera != null:
		camera.clear_shake()
	room.freeze_entities(false)
	room.reset_entities()
	_set_player_alpha(1.0)
	player.respawn(_log.spawn, true)
	_clear_contact_memory()


func _debug_overlay_on() -> bool:
	var reach := get_node_or_null(^"ReachOverlay")
	if reach is CanvasItem and (reach as CanvasItem).visible:
		return true
	var readout := get_node_or_null(^"PlayReadout")
	return readout != null and bool(readout.get(&"shown"))


## Debug history, including the test flag. A death may keep the _log; a win,
## pause restart, or room change does not.
func _keep_history() -> bool:
	return keep_rewind_history or _debug_overlay_on()


## Steps are stored only while a rewind can be used. The trail is the debug line.
func _should_record() -> bool:
	if _keep_history():
		return true
	var potion := belt.potion(RunBuild.Id.REWIND)
	return potion != null and potion.uses > 0


func _sync_recording() -> void:
	if replaying or player == null:
		return
	if _should_record():
		if not _log.recording:
			_log.begin(player_feet())
			_cursor = 0
	elif _log.recording:
		_log.stop()
		_cursor = 0


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
	if room == null or camera == null:
		return
	room.use_surfaces(player.uses_grapple_surfaces, player.uses_pogo_surfaces)
	camera.bind_player(player)
	camera.frame_room(room.pixel_rect())
	_respawn(false)
	character_changed.emit(index)


## Writes this run's stats onto the current character's baseline, stores the sim
## scale, and syncs potions. A second call does not stack the modifiers again.
func apply_build() -> void:
	var had: Array[RunBuild.Id] = []
	for id: RunBuild.Id in belt.potions:
		had.append(id)
	if player != null:
		player.apply_build(build)
	if room == null:
		return
	room.sim_scale = build.time_scale
	belt.sync(build, room)
	_drop_spent_potions()
	var dropped := false
	if _log.recording:
		for id: RunBuild.Id in had:
			if not belt.potions.has(id):
				dropped = true
				break
	if dropped:
		_log.stop()
		_cursor = 0
	_sync_recording()


## Feet used when planting a checkpoint: body origin x, collision bottom y.
func player_feet() -> Vector2:
	return Vector2(player.global_position.x, player.body_rect().end.y)


func potion_choices() -> Array[Dictionary]:
	var rows := belt.choices(player)
	var rewind_row := -1
	for index in rows.size():
		if int(rows[index].action) == Potion.Action.REWIND:
			rewind_row = index
	# Debug lists Rewind even when it is not equipped, and the commit is free.
	if rewind_is_free():
		var blocked := "" if can_rewind() else "Nothing to rewind yet"
		if rewind_row >= 0:
			rows[rewind_row].blocked = blocked
			rows[rewind_row].free = true
		else:
			rows.append({
				"id": RunBuild.Id.REWIND,
				"name": RunBuild.name_of(RunBuild.Id.REWIND),
				"uses": 0,
				"action": Potion.Action.REWIND,
				"blocked": blocked,
				"free": true,
			})
	elif rewind_row >= 0 and str(rows[rewind_row].blocked) == "" and not can_rewind():
		rows[rewind_row].blocked = "Nothing to rewind yet"
	return rows


func drink_potion(id: RunBuild.Id) -> PotionUse:
	if player == null or room == null:
		return null
	var record := belt.use(id, player_feet(), room)
	if record != null and _log.recording and not replaying:
		_log.log_use(record)
	_drop_spent_potions()
	_sync_recording()
	return record


## Respawn here and keep the build. A planted checkpoint stays. The rewind log
## starts over, even while debug history is on.
func restart_room() -> void:
	_respawn(false)


## Stitch a generated room and play it. `seed` below 0 draws a random one.
## The next exit offers a reward, then loads `seed + 1` at the same difficulty.
## The build stays. `return_to_demo` leaves this run.
func start_generated_run(rng_seed := -1) -> bool:
	var chosen := absi(randi()) if rng_seed < 0 else rng_seed
	if chosen == 0:
		chosen = 1
	if _enter_generated(chosen, 1):
		return true
	for offset in range(1, 2 + GEN_RETRY_SEEDS):
		if _enter_generated(chosen + offset, 1):
			return true
	gen_active = false
	return false


## Leave a generated run and play the authored demo. The build stays.
func return_to_demo() -> void:
	gen_active = false
	load_room(DEMO_ROOM.instantiate() as Room)


## Pull the live room out of the tree without freeing it. Clears the player's
## room pointer so a detached room is not ticked. The piece editor holds it.
func detach_room() -> Room:
	var previous := room
	room = null
	if previous != null and previous.get_parent() == self:
		remove_child(previous)
	if player != null:
		player.room = null
	return previous


func load_room(next: Room) -> void:
	var previous := room
	room = next
	if next.get_parent() != self:
		add_child(next)
	if previous != null and previous != next:
		belt.on_room_exit(previous)
		previous.free()
	if player == null:
		return
	player.room = room
	room.use_surfaces(player.uses_grapple_surfaces, player.uses_pogo_surfaces)
	if camera != null:
		camera.target = player
		camera.frame_room(room.pixel_rect())
	if backdrop != null and camera != null:
		backdrop.frame(room.pixel_rect(), get_viewport_rect().size / camera.zoom)
	apply_build()
	_respawn(false)


func restart(reason: RestartReason) -> void:
	if replaying:
		_respawn(false)
		return
	if reason == RestartReason.EXIT and not _exit_reward_chosen:
		if reward_menu != null:
			var offer := build.roll_offer()
			if not offer.is_empty():
				_pending_restart = NO_RESTART
				reward_menu.open_offer(offer, gen_level if gen_active else 0)
				get_tree().paused = true
				return
		if gen_active:
			_exit_reward_chosen = false
			_queue_advance()
			return
	_exit_reward_chosen = false
	# Leaving through the exit drops a planted flag. Death and falls keep it.
	if reason == RestartReason.EXIT and room != null:
		belt.on_room_exit(room)
	# A debug death stays on this log. A win does not.
	_respawn(reason != RestartReason.EXIT and _keep_history())
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


func _on_reward_picked(id: RunBuild.Id) -> void:
	_exit_reward_chosen = true
	build.add_stack(id)
	apply_build()
	get_tree().paused = false
	if gen_active:
		_exit_reward_chosen = false
		_queue_advance()
		return
	restart(RestartReason.EXIT)


func _enter_generated(rng_seed: int, level: int) -> bool:
	var next := RoomGenerator.generate_room(PIECE_LIBRARY, rng_seed, GEN_DIFFICULTY, GEN_PIECE_COUNT)
	if next == null:
		return false
	gen_active = true
	gen_seed = rng_seed
	gen_level = level
	load_room(next)
	return true


func _queue_advance() -> void:
	if not gen_active or _advance_queued:
		return
	_advance_queued = true
	if player != null:
		player.halt()
	if room != null:
		room.freeze_entities(true)
	call_deferred(&"_advance_generated")


func _advance_generated() -> void:
	_advance_queued = false
	if not gen_active:
		return
	var base := gen_seed
	var next_level := gen_level + 1
	for offset in range(1, 2 + GEN_RETRY_SEEDS):
		if _enter_generated(base + offset, next_level):
			return
	push_warning("giving up on next generated level; restarting current room")
	_respawn(false)


## `keep_history` is a debug death or fall. Every other respawn starts a new log.
func _respawn(keep_history := false) -> void:
	fx.clear()
	_transition_reason = NO_RESTART
	hitstop_left = 0.0
	_hitstop_requested_this_tick = false
	_pending_restart = NO_RESTART
	_pending_shakes.clear()
	camera.clear_shake()
	room.freeze_entities(false)
	room.reset_entities()
	_set_player_alpha(1.0)
	# Hold the next tick. Integrating the teleport keeps a dash's speed.
	var feet := room.spawn_feet()
	room.build_collision()
	player.respawn(feet, true)
	camera.snap_to_target()
	if replaying:
		return
	if keep_history and _log.recording:
		_log.mark_respawn()
	elif _should_record():
		_log.begin(feet)
	else:
		_log.stop()
	_cursor = _log.steps.size()


func _begin_transition(reason: RestartReason) -> void:
	_pending_restart = NO_RESTART
	_transition_reason = reason
	hitstop_left = 0.0
	_hitstop_requested_this_tick = false
	_pending_shakes.clear()
	camera.clear_shake()
	room.freeze_entities(false)
	player.halt()
	if not replaying and _log.recording and reason != RestartReason.EXIT:
		_log.mark_death()
	if reason == RestartReason.EXIT:
		fx.start_exit(player)
	else:
		fx.start_death(player)
	_set_player_alpha(fx.player_alpha())
	if not replaying:
		transition_started.emit(reason)


func _tick_fx(delta: float) -> void:
	_tick_room(delta, PlayerInputFrame.new())
	player.velocity = Vector2.ZERO
	var done := fx.update(SimStep.delta(self, delta))
	_set_player_alpha(fx.player_alpha())
	if not done:
		return
	var reason := _transition_reason
	_transition_reason = NO_RESTART
	fx.clear()
	restart(reason)


func _set_player_alpha(alpha: float) -> void:
	var tint := player.modulate
	tint.a = alpha
	player.modulate = tint


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
	if replaying:
		return
	if seconds > hitstop_left:
		hitstop_left = seconds
		_hitstop_requested_this_tick = true


func _on_screen_shake_requested(
	seconds: float,
	amplitude: float,
	frequency: float,
	direction: Vector2,
) -> void:
	if replaying:
		return
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
	if fx.is_playing() or _transition_reason != NO_RESTART:
		return
	if _pending_restart == NO_RESTART or reason < _pending_restart:
		_pending_restart = reason
