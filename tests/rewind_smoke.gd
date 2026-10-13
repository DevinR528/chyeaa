extends SceneTree
## Rewind replays the same step live play recorded, including a platform, a walker,
## and a throwable. Commit spends a charge. Cancel does not. A death cannot be
## scrubbed past unless debug history is on.

const Rooms := preload("res://tests/test_room_builder.gd")
const STANDARD_SCENE := preload("res://scenes/player/standard.tscn")
const PLATFORM_SCENE := preload("res://scenes/props/moving_platform.tscn")
const WALKER_SCENE := preload("res://scenes/actors/walker.tscn")
const THROWABLE_SCENE := preload("res://scenes/actors/throwable.tscn")

var _failed := false


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	await _check_replay()
	await _check_scrub_time()
	paused = false
	quit(1 if _failed else 0)


func _check_replay() -> void:
	var room := Rooms.make_room(root, func(layers: Dictionary) -> void:
		layers.Terrain.set_cell(Vector2i(18, 8), 0, Rooms.DEATH_TILE)
	)
	var floor_y := Rooms.FLOOR_ROW * Rooms.TILE
	room.spawn.position = Vector2(48, floor_y)
	var platform := Rooms.add_prop(room, PLATFORM_SCENE, Vector2(160, floor_y - 48), Vector2(48, 8))
	platform.oscillation.axis = OscillatingMotion.Axis.X
	platform.oscillation.travel = 24.0
	platform.oscillation.speed = 2.0
	platform.reset()
	var walker := Rooms.add_actor(room, WALKER_SCENE, Vector2(220, floor_y - 8))
	var ball := Rooms.add_actor(room, THROWABLE_SCENE, Vector2(280, floor_y - 40))
	var camera := FollowCamera.new()
	var runner := RoomRunner.new()
	runner.room = room
	runner.camera = camera
	runner.characters = [STANDARD_SCENE]
	runner.character_index = 0
	runner.add_child(camera)
	root.add_child(runner)
	var ui := RunUI.new()
	ui.runner = runner
	root.add_child(ui)
	await physics_frame

	_expect(not runner.get_node(^"RewindTrail").visible, "rewind trail showed without the debug overlay")
	var reach := ReachOverlay.new()
	reach.name = &"ReachOverlay"
	reach.runner = runner
	reach.visible = true
	runner.add_child(reach)
	reach.visible = true
	await physics_frame
	_expect(runner.get_node(^"RewindTrail").visible, "debug overlay did not show the rewind trail")

	camera.position_smoothing_enabled = true
	camera.position_smoothing_speed = 7.0
	camera.limit_left = -100000
	camera.limit_top = -100000
	camera.limit_right = 100000
	camera.limit_bottom = 100000
	Input.action_press(&"move_right")
	for _frame in 25:
		await physics_frame
	Input.action_release(&"move_right")
	var player_at := runner.player.global_position
	var walker_at := walker.global_position
	var ball_at := ball.global_position
	var platform_at := platform.global_position
	var total := runner.log.steps.size()
	_expect(total > 10, "rewind log did not record the run, length %d" % total)
	_expect(runner.log.trail.size() == total, "trail length %d did not match the log %d" % [runner.log.trail.size(), total])
	var far := camera.get_screen_center_position()
	runner.preview_rewind(0)
	_expect(runner.log.trail.is_empty(), "rewind kept %d trail points" % runner.log.trail.size())
	_expect(
		_camera_on_player(camera, runner.player),
		"rewind left the camera at %s, player at %s" % [camera.get_screen_center_position(), runner.player.global_position],
	)
	_expect(
		far.distance_to(camera.get_screen_center_position()) > 8.0,
		"camera stayed at %s" % camera.get_screen_center_position(),
	)
	runner.preview_rewind(total)
	_expect(runner.log.trail.size() == total, "forward scrub left the trail at %d" % runner.log.trail.size())
	_expect(
		_camera_on_player(camera, runner.player),
		"forward scrub left the camera at %s, player at %s" % [camera.get_screen_center_position(), runner.player.global_position],
	)
	_expect(
		runner.player.global_position.distance_to(player_at) < 0.5,
		"replay missed the player, %s vs %s" % [runner.player.global_position, player_at],
	)
	_expect(
		walker.global_position.distance_to(walker_at) < 0.5,
		"replay missed the walker, %s vs %s" % [walker.global_position, walker_at],
	)
	_expect(
		ball.global_position.distance_to(ball_at) < 0.5,
		"replay missed the throwable, %s vs %s" % [ball.global_position, ball_at],
	)
	_expect(
		platform.global_position.distance_to(platform_at) < 0.5,
		"replay missed the platform, %s vs %s" % [platform.global_position, platform_at],
	)

	ui.open_picker()
	_expect("free (debug)" in _picker_text(ui), "debug picker hid rewind: %s" % _picker_text(ui))
	ui.close_picker()

	runner.build.add_stack(RunBuild.Id.CHECKPOINT)
	runner.build.add_stack(RunBuild.Id.REWIND)
	runner.apply_build()
	var checkpoint: CheckpointPotion = runner.belt.potion(RunBuild.Id.CHECKPOINT)
	var rewind: RewindPotion = runner.belt.potion(RunBuild.Id.REWIND)
	checkpoint.uses = 1
	rewind.uses = 2
	var at_drink := runner.log.steps.size()
	runner.drink_potion(RunBuild.Id.CHECKPOINT)
	_expect(room.checkpoint is Vector2, "checkpoint did not plant before the scrub")
	for _frame in 8:
		await physics_frame
	runner.preview_rewind(at_drink - 1)
	_expect(not room.checkpoint is Vector2, "scrubbing behind the drink left the checkpoint")
	runner.preview_rewind(at_drink)
	_expect(room.checkpoint is Vector2, "returning to the drink did not replant the checkpoint")

	var ui_rewind: RewindScreen = ui.get_node(^"Rewind")
	reach.visible = false
	ui.open_picker()
	Input.action_press(&"jump")
	# Paused mid-physics, so the rest of this frame may not run the UI. The next
	# one does, with the confirm still held, and the scrub must survive it.
	await process_frame
	await process_frame
	Input.action_release(&"jump")
	_expect(ui_rewind.open and not ui.picker_open, "drinking rewind did not leave the scrub open")
	_expect(rewind.uses == 2, "opening rewind spent a charge, uses %d" % rewind.uses)
	if ui.picker_open:
		ui.close_picker()
	if ui_rewind.open:
		ui_rewind._cancel()
	_expect(not ui_rewind.open and rewind.uses == 2, "cancel after a drink spent a charge")

	ui.open_rewind()
	_expect(ui_rewind.open, "rewind screen did not open")
	ui_rewind._seek(at_drink - 1)
	ui_rewind._cancel()
	_expect(not ui_rewind.open and rewind.uses == 2, "cancel spent a rewind charge or left the screen open")
	_expect(room.checkpoint is Vector2, "cancel did not restore the checkpoint")

	reach.visible = false
	ui.open_rewind()
	ui_rewind._seek(at_drink - 1)
	ui_rewind._commit()
	_expect(rewind.uses == 1, "commit did not spend a rewind charge, uses %d" % rewind.uses)
	_expect(not room.checkpoint is Vector2, "commit kept the checkpoint it had scrubbed away")

	reach.visible = false
	var lived := runner.log.steps.size()
	runner.player.respawn(_cell_feet(room, Vector2i(18, 8)))
	for _frame in 80:
		await physics_frame
		if runner.log.steps.size() < lived:
			break
	_expect(runner.log.steps.size() < lived, "a death kept the history that led into it")

	runner.keep_rewind_history = true
	for _frame in 10:
		await physics_frame
	var kept := runner.log.steps.size()
	runner.player.respawn(_cell_feet(room, Vector2i(18, 8)))
	for _frame in 80:
		await physics_frame
		if runner.log.respawn_floor() > kept:
			break
	_expect(runner.log.steps.size() > kept, "debug history dropped the steps before the death")
	_expect(runner.rewind_floor() == 0, "debug history locked the scrub at the death")
	ui.open_rewind()
	ui_rewind._seek(0)
	_expect(ui_rewind._k == 0, "debug scrub did not reach the start of the history")
	ui_rewind._cancel()

	runner.player.respawn(room.spawn_feet(), true)
	_expect(runner.player.is_on_floor(), "a respawn on the ground did not read as grounded")
	runner.player.respawn(room.spawn_feet() + Vector2(0, -40), true)
	_expect(not runner.player.is_on_floor(), "a respawn in the air read as grounded")
	ui.free()
	runner.free()
	room.free()


func _check_scrub_time() -> void:
	var runner := RoomRunner.new()
	var camera := FollowCamera.new()
	runner.camera = camera
	runner.characters = [STANDARD_SCENE]
	runner.character_index = 0
	runner.add_child(camera)
	root.add_child(runner)
	_expect(runner.start_generated_run(1), "timing run did not generate")
	await physics_frame
	var frame := PlayerInputFrame.new()
	frame.move = Vector2.RIGHT
	for _step in 7200:
		runner._run_step(1.0 / 60.0, frame)
	for count in [3600, 7200]:
		var started := Time.get_ticks_msec()
		runner.preview_rewind(0)
		runner.preview_rewind(count)
		var elapsed := Time.get_ticks_msec() - started
		print("rewind replay %d steps: %d ms" % [count, elapsed])
	runner.free()


func _cell_feet(room: Room, cell: Vector2i) -> Vector2:
	var center := room.terrain.to_global(room.terrain.map_to_local(cell))
	return center + Vector2(0, 4)


func _camera_on_player(camera: FollowCamera, player: PlayerBody) -> bool:
	return camera.get_screen_center_position().distance_to(player.global_position) < 8.0


func _picker_text(ui: RunUI) -> String:
	var text := ""
	for child in ui._picker_rows.get_children():
		text += (child as Label).text
	return text


func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	_failed = true
	push_error(message)
