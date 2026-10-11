extends SceneTree

const FLAT_FLOOR_SCENE := preload("res://tests/flat_floor.tscn")
const Rooms := preload("res://tests/test_room_builder.gd")
const POGO_SCENE := preload("res://scenes/player/pogo.tscn")

var _failed := false


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var main := FLAT_FLOOR_SCENE.instantiate()
	root.add_child(main)
	var player := main.get_node("Player") as PlayerBody

	_check_input_latching(player.player_input)
	await _settle_on_floor(player)
	_expect(player.is_on_floor(), "player did not land on the test floor")

	var start_x := player.position.x
	Input.action_press(&"move_right")
	await _physics_frames(15)
	Input.action_release(&"move_right")
	_expect(player.position.x > start_x, "right input did not move the player")
	_expect(player.facing > 0.0, "right input did not update facing")

	var floor_y := player.position.y
	Input.action_press(&"jump")
	await _physics_frames(2)
	Input.action_release(&"jump")
	await _physics_frames(4)
	_expect(player.position.y < floor_y, "jump input did not launch the player")
	_expect(player.velocity.y < 0.0, "jump did not produce upward velocity")

	await _settle_on_floor(player)
	Input.action_press(&"dash")
	await _physics_frames(2)
	Input.action_release(&"dash")
	_expect(player.dash_time_left > 0.0, "dash input did not start a dash")
	_expect(player.move_state == PlayerBody.MovementState.DASH and player.movement_clip() == &"dash", "dashing is not in the DASH state")
	_expect(absf(player.velocity.x) > player.stats.max_run, "dash was not faster than run speed")
	await _physics_frames(ceili(player.stats.dash_duration * Engine.physics_ticks_per_second) + 1)
	_expect(player.move_state != PlayerBody.MovementState.DASH, "DASH outlasted the dash timer")

	_check_coyote_time(player)
	_check_jump_buffer(player)
	_check_jump_cut(player)

	main.queue_free()
	await process_frame
	await _check_pogo_run_speed_is_constant()
	quit(1 if _failed else 0)


func _settle_on_floor(player: PlayerBody) -> void:
	for _frame in 180:
		await physics_frame
		if player.is_on_floor():
			return


func _physics_frames(count: int) -> void:
	for _frame in count:
		await physics_frame


func _check_input_latching(input_source: PlayerInput) -> void:
	var press := InputEventAction.new()
	press.action = &"action"
	press.pressed = true
	input_source._input(press)

	_expect(input_source.consume().action_pressed, "input event was not latched until consumption")
	_expect(not input_source.consume().action_pressed, "latched input fired more than once")
	_expect(
		PlayerInput.aim_quadrant(Vector2(1.0, 0.1)) == PlayerInputFrame.Aim.RIGHT,
		"four-way aim did not choose the horizontal quadrant",
	)


func _check_coyote_time(player: PlayerBody) -> void:
	player.move_state = PlayerBody.MovementState.FALL
	player.velocity = Vector2.ZERO
	player.coyote_time_left = player.stats.coyote_time

	var frame := PlayerInputFrame.new()
	frame.jump_pressed = true
	frame.jump_held = true
	player._tick_timers(0.08, frame, false)
	player._update_motion(0.0, frame, false)

	_expect(player.velocity.y == player.stats.jump_velocity, "jump inside coyote window did not fire")


func _check_jump_buffer(player: PlayerBody) -> void:
	player.move_state = PlayerBody.MovementState.FALL
	player.velocity = Vector2.ZERO
	player.coyote_time_left = 0.0
	player.jump_buffer_left = 0.0

	var early_frame := PlayerInputFrame.new()
	early_frame.jump_pressed = true
	early_frame.jump_held = true
	player._tick_timers(0.0, early_frame, false)
	player._update_motion(0.0, early_frame, false)
	_expect(is_zero_approx(player.velocity.y), "early buffered jump fired before landing")

	var landing_frame := PlayerInputFrame.new()
	landing_frame.jump_held = true
	player._tick_timers(0.08, landing_frame, true)
	player._update_motion(0.0, landing_frame, true)
	_expect(player.velocity.y == player.stats.jump_velocity, "buffered jump did not fire on landing")


func _check_jump_cut(player: PlayerBody) -> void:
	player.move_state = PlayerBody.MovementState.FALL
	player.velocity = Vector2(0.0, player.stats.jump_velocity)
	player.jump_cuttable = true
	player.jump_held_previous = true
	player.jump_buffer_left = 0.0

	var released_frame := PlayerInputFrame.new()
	player._update_motion(0.0, released_frame, false)
	_expect(
		is_equal_approx(player.velocity.y, player.stats.jump_velocity * player.stats.jump_cut),
		"releasing jump did not apply jump cut",
	)


func _check_pogo_run_speed_is_constant() -> void:
	var room := Rooms.make_room(root, func(_layers: Dictionary) -> void: pass)
	var player := Rooms.spawn_player(root, room, POGO_SCENE, Vector2(80, Rooms.FLOOR_ROW * Rooms.TILE))
	player.frozen = true
	player.move_state = PlayerBody.MovementState.RUN
	await _next_process()
	var sprite := player.get_node(^"CharacterSprite") as CharacterSprite

	var input_frame := PlayerInputFrame.new()
	input_frame.move.x = 1.0
	var delta := 1.0 / 60.0
	player.velocity.x = player.stats.max_run
	for _frame in 60:
		player._update_motion(delta, input_frame, true)
		sprite.animation_player.advance(delta)
		_expect(is_equal_approx(player.velocity.x, player.stats.max_run), "Pogo animation changed physical run speed")
	player.free()
	room.free()
	await process_frame


func _next_process() -> void:
	await process_frame
	await process_frame


func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	_failed = true
	push_error(message)
