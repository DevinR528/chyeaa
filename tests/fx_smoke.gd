extends SceneTree
## Death and exit effects delay the next screen, a dash does not survive that
## respawn, and the dash leaves a fading trail.

const Rooms := preload("res://tests/test_room_builder.gd")
const STANDARD_SCENE := preload("res://scenes/player/standard.tscn")
const REWARD_SCENE := preload("res://scenes/ui/reward_menu.tscn")
const DEATH_COLUMN := 40
const EXIT_COLUMN := 50

var _failed := false
var _restarts: Array[RoomRunner.RestartReason] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var floor_y := Rooms.FLOOR_ROW * Rooms.TILE
	var runner := RoomRunner.new()
	runner.process_physics_priority = -10
	var room := Rooms.make_room(runner, func(layers: Dictionary) -> void:
		Rooms.paint_column(layers.Terrain, DEATH_COLUMN, 20, Rooms.FLOOR_ROW - 1, Rooms.DEATH_TILE)
		Rooms.paint_column(layers.Terrain, EXIT_COLUMN, 20, Rooms.FLOOR_ROW - 1, Rooms.EXIT_TILE))
	var camera := FollowCamera.new()
	camera.process_physics_priority = 30
	var menu := REWARD_SCENE.instantiate() as RewardMenu
	runner.room = room
	runner.camera = camera
	runner.reward_menu = menu
	runner.characters = [STANDARD_SCENE]
	runner.character_index = 0
	runner.add_child(camera)
	runner.add_child(menu)
	runner.restarted.connect(func(reason: RoomRunner.RestartReason) -> void: _restarts.append(reason))
	root.add_child(runner)
	room.spawn.position = Vector2(48.0, floor_y)
	var player := runner.player
	player.respawn(room.spawn_feet())
	for _frame in 30:
		await physics_frame
		if player.is_on_floor():
			break

	await _check_dash_trail(player)
	await _check_death_stops_the_dash(runner, player, floor_y)
	await _check_exit_waits_to_offer(runner, player, floor_y)

	runner.queue_free()
	await process_frame
	quit(1 if _failed else 0)


func _check_dash_trail(player: PlayerBody) -> void:
	Input.action_press(&"move_right")
	Input.action_press(&"dash")
	await _physics_frames(4)
	Input.action_release(&"dash")
	Input.action_release(&"move_right")
	_expect(player.dash_trail.ghost_count() >= 2, "dash left %d ghosts" % player.dash_trail.ghost_count())
	_expect(
		player.dash_trail.trailing_behind(player.body_rect().position.x),
		"dash trail did not stay behind the body",
	)
	var guard := 0
	while player.move_state == PlayerBody.MovementState.DASH and guard < 30:
		await physics_frame
		guard += 1
	_expect(player.dash_trail.ghost_count() > 0, "trail cleared when the dash ended")
	await _physics_frames(ceili(DashTrail.FADE * Engine.physics_ticks_per_second) + 2)
	_expect(player.dash_trail.ghost_count() == 0, "trail outlived its fade")


func _check_death_stops_the_dash(runner: RoomRunner, player: PlayerBody, floor_y: float) -> void:
	_restarts.clear()
	player.respawn(Vector2(48.0, floor_y))
	await _physics_frames(2)
	Input.action_press(&"move_right")
	Input.action_press(&"dash")
	var saw_dash := false
	var death_x := 0.0
	for _frame in 40:
		await physics_frame
		if player.move_state == PlayerBody.MovementState.DASH and absf(player.velocity.x) > player.stats.max_run:
			saw_dash = true
		if runner.fx.is_playing():
			death_x = player.global_position.x
			break
	Input.action_release(&"dash")
	Input.action_release(&"move_right")
	_expect(saw_dash and runner.fx.kind == RoomFx.Kind.DEATH, "dash into a death tile did not start the shatter")
	_expect(_restarts.is_empty(), "death restarted before the shatter finished")
	_expect(absf(player.velocity.x) < 1.0, "death kept dash speed %.1f" % player.velocity.x)
	for _frame in 5:
		await physics_frame
		_expect(absf(player.global_position.x - death_x) < 1.0, "player slid during the death effect")
		_expect(absf(player.velocity.x) < 1.0, "dash speed returned during the death effect")
		_expect(is_zero_approx(player.modulate.a), "the body stayed visible during the shatter")

	await _wait_for_restart(RoomRunner.RestartReason.DEATH)
	_expect(_restarts.has(RoomRunner.RestartReason.DEATH), "death effect did not respawn")
	var spawn_x := runner.room.spawn_feet().x
	_expect(absf(player.global_position.x - spawn_x) < 8.0, "death respawned at x %.1f, spawn is %.1f" % [player.global_position.x, spawn_x])
	for _frame in 5:
		await physics_frame
		_expect(absf(player.velocity.x) < 1.0, "respawn kept horizontal speed %.1f" % player.velocity.x)


func _check_exit_waits_to_offer(runner: RoomRunner, player: PlayerBody, floor_y: float) -> void:
	_restarts.clear()
	var menu := runner.reward_menu
	player.respawn(Vector2(EXIT_COLUMN * Rooms.TILE + 4.0, floor_y))
	await _physics_frames(4)
	_expect(runner.fx.is_playing() and runner.fx.kind == RoomFx.Kind.EXIT, "exit did not start the clear effect")
	_expect(not menu.open and _restarts.is_empty(), "exit opened the next screen before the effect")
	for _frame in _effect_frames():
		await physics_frame
		if menu.open:
			break
	_expect(menu.open, "exit effect did not open the reward menu")
	_expect(_restarts.is_empty(), "exit restarted before a card was picked")
	_expect(is_zero_approx(player.modulate.a), "the body was showing when the reward menu opened")
	menu.choose_selected()
	_expect(_restarts.has(RoomRunner.RestartReason.EXIT), "picking a card did not finish the exit")
	_expect(absf(player.global_position.x - runner.room.spawn_feet().x) < 8.0, "the pick did not respawn at the room marker")


func _effect_frames() -> int:
	return ceili(RoomFx.EXIT_DURATION * Engine.physics_ticks_per_second) + 8


func _wait_for_restart(reason: RoomRunner.RestartReason) -> void:
	for _frame in _effect_frames():
		await physics_frame
		if _restarts.has(reason):
			return


func _physics_frames(count: int) -> void:
	for _frame in count:
		await physics_frame


func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	_failed = true
	push_error(message)
