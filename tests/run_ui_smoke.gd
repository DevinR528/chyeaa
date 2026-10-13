extends SceneTree
## Checkpoint planting, respawn, and the pause/HUD layer that keeps running.

const Rooms := preload("res://tests/test_room_builder.gd")
const STANDARD_SCENE := preload("res://scenes/player/standard.tscn")
const POGO_SCENE := preload("res://scenes/player/pogo.tscn")
const BLOCK_SCENE := preload("res://scenes/props/block.tscn")
const REWARD_SCENE := preload("res://scenes/ui/reward_menu.tscn")

var _failed := false
var _restarts: Array[RoomRunner.RestartReason] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_check_roll_and_belt()
	await _check_room()
	await _check_generated_run()
	paused = false
	quit(1 if _failed else 0)


func _check_roll_and_belt() -> void:
	_expect(Potion.roll_uses(func() -> float: return 0.99) == 1, "a failed continue roll was not 1 charge")
	_expect(Potion.roll_uses(func() -> float: return 0.0) == 5, "continue rolls did not stop at 5")
	_expect(
		RunUI.line_for({"name": "Checkpoint", "uses": 1, "blocked": "Can't use it here"}) == "Checkpoint — Can't use it here",
		"blocked potion line dropped the reason",
	)
	_expect(
		RunUI.line_for({"name": "Rewind", "uses": 0, "free": true}) == "Rewind — free (debug)",
		"debug rewind line showed a charge count",
	)

	var room := Rooms.make_room(root, func(_layers: Dictionary) -> void: pass)
	var belt := PotionBelt.new()
	var build := RunBuild.new()
	build.add_stack(RunBuild.Id.CHECKPOINT)
	build.add_stack(RunBuild.Id.TOP_SPEED)
	_expect(belt.sync(build, room), "equipping a checkpoint did not create a potion")
	_expect(belt.potion(RunBuild.Id.CHECKPOINT) != null, "belt missed the checkpoint")
	_expect(not belt.sync(build, room), "syncing an unchanged build reported a change")

	var checkpoint := belt.potion(RunBuild.Id.CHECKPOINT)
	checkpoint.uses = 1
	var planted := belt.use(RunBuild.Id.CHECKPOINT, Vector2(40.6, 80.2), room)
	_expect(planted != null, "planting with a charge did nothing")
	_expect(room.spawn_feet().is_equal_approx(Vector2(41, 80)), "plant did not round the feet, got %s" % room.spawn_feet())
	var first: Vector2 = room.spawn_feet()
	_expect(checkpoint.has_flag and checkpoint.flag == first, "flag did not follow the planted spawn")
	_expect(belt.use(RunBuild.Id.CHECKPOINT, Vector2.ZERO, room) == null, "a spent checkpoint planted again")
	_expect(room.spawn_feet() == first, "a refused plant moved the spawn")

	checkpoint.uses = 2
	belt.use(RunBuild.Id.CHECKPOINT, first, room)
	var replaced := belt.use(RunBuild.Id.CHECKPOINT, Vector2(120.2, 80.2), room)
	_expect(checkpoint.uses == 0, "replacing a flag did not spend the charge")
	var second: Vector2 = room.spawn_feet()
	replaced.undo()
	_expect(room.spawn_feet() == first and checkpoint.flag == first, "undo did not restore the previous flag")
	_expect(checkpoint.uses == 0, "undo refunded a charge")
	replaced.redo()
	_expect(room.spawn_feet() == second and checkpoint.uses == 0, "redo did not replant, or it refunded a charge")

	build.remove_stack(RunBuild.Id.CHECKPOINT)
	_expect(not belt.sync(build, room), "removing a spent checkpoint cleared its flag")
	_expect(checkpoint.has_flag and room.spawn_feet() == second, "a spent flag left with the build")
	build.add_stack(RunBuild.Id.CHECKPOINT)
	_expect(belt.sync(build, room) and checkpoint.uses > 0, "re-equipping a spent checkpoint did not refill it")

	checkpoint.uses = 2
	belt.use(RunBuild.Id.CHECKPOINT, Vector2(160, 80), room)
	build.remove_stack(RunBuild.Id.CHECKPOINT)
	_expect(belt.sync(build, room), "unequipping an unspent checkpoint did not clear it")
	_expect(not checkpoint.has_flag and not room.checkpoint is Vector2, "unequip left the planted spawn")
	room.free()


func _check_room() -> void:
	var room := Rooms.make_room(root, func(layers: Dictionary) -> void:
		layers.Terrain.set_cell(Vector2i(8, 8), 0, Rooms.DEATH_TILE)
		layers.Terrain.set_cell(Vector2i(12, 8), 0, Rooms.EXIT_TILE)
	)
	var floor_feet := Vector2(80, Rooms.FLOOR_ROW * Rooms.TILE)
	room.spawn.position = floor_feet
	room.set_checkpoint(Vector2(-500, -500))
	var clamped: Vector2 = room.spawn_feet()
	_expect(clamped.x > -500 and clamped.y > -500, "checkpoint feet were not clamped into the room")
	room.clear_checkpoint()

	var camera := FollowCamera.new()
	var runner := RoomRunner.new()
	runner.room = room
	runner.camera = camera
	runner.characters = [STANDARD_SCENE, POGO_SCENE]
	runner.character_index = 0
	runner.add_child(camera)
	runner.restarted.connect(func(reason: RoomRunner.RestartReason) -> void: _restarts.append(reason))
	root.add_child(runner)
	var prop := Rooms.add_prop(room, BLOCK_SCENE, Vector2(140, 200), Vector2(16, 16))

	runner.build.add_stack(RunBuild.Id.CHECKPOINT)
	runner.build.add_stack(RunBuild.Id.TOP_SPEED)
	runner.apply_build()
	runner.belt.potion(RunBuild.Id.CHECKPOINT).uses = 2
	runner.player.respawn(Vector2(200, floor_feet.y))
	var record := runner.drink_potion(RunBuild.Id.CHECKPOINT)
	var planted: Vector2 = room.spawn_feet()
	_expect(record != null and planted.x == 200, "drink did not plant at the player's feet, got %s" % planted)
	_expect(room.get_node_or_null(^"CheckpointFlag") != null, "planting did not add a flag")

	prop.position += Vector2(40, 0)
	room.reset_entities()
	_expect(prop.position == prop.home, "reset did not restore a prop")
	_expect(room.spawn_feet() == planted and room.get_node_or_null(^"CheckpointFlag") != null, "reset erased the checkpoint")

	var ui := RunUI.new()
	ui.runner = runner
	root.add_child(ui)
	await process_frame
	_expect("Checkpoint (1 left)" in ui.summary_text(), "HUD summary was '%s'" % ui.summary_text())
	_expect("Top Speed×1" in ui.summary_text(), "HUD missed top speed: '%s'" % ui.summary_text())

	_restarts.clear()
	runner.player.respawn(_cell_feet(room, Vector2i(8, 8)))
	await _await_restart()
	_expect(_restarts.has(RoomRunner.RestartReason.DEATH), "death tile did not restart, got %s" % [_restarts])
	_expect(
		runner.player.global_position.distance_to(Vector2(planted.x, planted.y - runner.player.body_rect().size.y / 2.0)) < 8.0,
		"death respawned at %s instead of the checkpoint %s" % [runner.player.global_position, planted],
	)

	_restarts.clear()
	runner.player.respawn(Vector2(planted.x, room.kill_plane_y() + 64.0))
	await _await_restart()
	_expect(_restarts.has(RoomRunner.RestartReason.FALL), "falling off did not restart, got %s" % [_restarts])
	_expect(room.spawn_feet() == planted, "a fall cleared the checkpoint")

	_restarts.clear()
	runner.player.respawn(_cell_feet(room, Vector2i(12, 8)))
	await _await_restart()
	_expect(_restarts.has(RoomRunner.RestartReason.EXIT), "exit tile did not restart, got %s" % [_restarts])
	_expect(not room.checkpoint is Vector2, "exit kept the planted checkpoint")
	_expect(
		absf(runner.player.global_position.x - floor_feet.x) < 8.0,
		"exit did not respawn at the room marker",
	)

	runner.build.add_stack(RunBuild.Id.CHECKPOINT)
	runner.apply_build()
	runner.belt.potion(RunBuild.Id.CHECKPOINT).uses = 1
	runner.player.respawn(Vector2(200, floor_feet.y))
	runner.drink_potion(RunBuild.Id.CHECKPOINT)
	var kept: Vector2 = room.spawn_feet()
	runner.switch_character(1)
	_expect(runner.player.uses_pogo_surfaces, "character switch did not reach Pogo")
	_expect(
		is_equal_approx(runner.player.stats.max_run, runner.player.base_stats.max_run * 1.12),
		"switch compounded or dropped top speed",
	)
	_expect(room.spawn_feet() == kept, "switch cleared the checkpoint")

	var before := runner.player.global_position
	Input.action_press(&"move_right")
	ui.open_pause()
	var seen := ui.ticks
	await process_frame
	await process_frame
	_expect(ui.ticks > seen, "pause UI did not process while the tree was paused")
	_expect(ui.can_process() and not runner.player.can_process(), "pause did not freeze gameplay while leaving UI running")
	_expect(runner.player.global_position == before, "paused player still moved")
	_expect("Top Speed×1" in ui._pause_summary.text, "pause menu hid the build summary")
	ui.close_pause()
	Input.action_release(&"move_right")

	var blocked: Array[Dictionary] = [{
		"id": RunBuild.Id.CHECKPOINT,
		"name": "Checkpoint",
		"uses": 1,
		"blocked": "Can't use it here",
	}]
	ui.show_choices(blocked)
	await process_frame
	_expect("Can't use it here" in (_picker_text(ui)), "picker did not list the blocked reason")
	Input.action_press(&"jump")
	await process_frame
	Input.action_release(&"jump")
	_expect(ui.picker_open, "confirm drank a blocked potion")
	ui.close_picker()

	runner.switch_character(0)
	runner.belt.potion(RunBuild.Id.CHECKPOINT).uses = 1
	ui.open_picker()
	Input.action_press(&"jump")
	await process_frame
	Input.action_release(&"jump")
	_expect(not ui.picker_open and room.checkpoint is Vector2, "confirm did not drink the checkpoint")
	ui.free()
	runner.free()
	room.free()


func _check_generated_run() -> void:
	var room := Rooms.make_room(root, func(_layers: Dictionary) -> void: pass)
	var camera := FollowCamera.new()
	var runner := RoomRunner.new()
	runner.room = room
	runner.camera = camera
	runner.characters = [STANDARD_SCENE]
	runner.character_index = 0
	var menu := REWARD_SCENE.instantiate() as RewardMenu
	runner.reward_menu = menu
	runner.add_child(camera)
	root.add_child(menu)
	root.add_child(runner)
	var ui := RunUI.new()
	ui.runner = runner
	root.add_child(ui)
	await process_frame

	var home := runner.player.global_position
	runner.player.global_position = home + Vector2(64, -32)
	ui.open_pause()
	_expect(ui.get_node(^"Pause/Center") is CenterContainer, "pause panel was not centered")
	Input.action_press(&"move_down")
	await process_frame
	Input.action_release(&"move_down")
	_expect(ui.pause_index == 1, "pause did not move to restart, index %d" % ui.pause_index)
	Input.action_press(&"jump")
	await process_frame
	Input.action_release(&"jump")
	_expect(not ui.pause_open, "restart left the pause menu open")
	_expect(
		runner.player.global_position.distance_to(home) < 8.0,
		"restart moved to %s instead of %s" % [runner.player.global_position, home],
	)
	_expect(runner.build.stack_count(RunBuild.Id.TOP_SPEED) == 0, "restart cleared the build before a stack existed")

	runner.build.add_stack(RunBuild.Id.TOP_SPEED)
	_expect(runner.start_generated_run(1), "seed 1 did not generate a room")
	_expect(runner.gen_active and runner.gen_level == 1 and runner.gen_seed == 1, "generated run did not start at level 1")
	_expect(runner.build.stack_count(RunBuild.Id.TOP_SPEED) == 1, "entering a generated room dropped the build")
	var cleared: Room = runner.room
	var cleared_spawn := cleared.spawn_feet()

	runner.restart(RoomRunner.RestartReason.EXIT)
	_expect(menu.open, "generated exit did not open the reward")
	_expect((menu.get_node(^"Root/Panel/Title") as Label).text == "Level 1", "reward omitted the level")
	var picked: RunBuild.Id = menu._ids[menu._selected]
	var picked_before := runner.build.stack_count(picked)
	var speed_before := runner.build.stack_count(RunBuild.Id.TOP_SPEED)
	menu.choose_selected()
	for _frame in 3:
		await process_frame
	_expect(not menu.open, "picking a card left the reward open")
	_expect(runner.gen_level == 2 and runner.gen_seed == 2, "next room was level %d seed %d" % [runner.gen_level, runner.gen_seed])
	_expect(runner.room != cleared, "the exit reloaded the same room")
	var speed_after := speed_before + (1 if picked == RunBuild.Id.TOP_SPEED else 0)
	_expect(
		runner.build.stack_count(RunBuild.Id.TOP_SPEED) == speed_after,
		"the next room changed top speed to %d" % runner.build.stack_count(RunBuild.Id.TOP_SPEED),
	)
	_expect(
		runner.build.stack_count(picked) == picked_before + 1,
		"the picked card was not added (%s count %d)" % [
			RunBuild.name_of(picked), runner.build.stack_count(picked),
		],
	)
	_expect(not runner.room.spawn_feet().is_equal_approx(cleared_spawn), "the next room kept the previous spawn %s" % cleared_spawn)

	for id: RunBuild.Id in RunBuild.MAX_STACKS:
		while runner.build.stack_count(id) < int(RunBuild.MAX_STACKS[id]):
			runner.build.add_stack(id)
	runner.restart(RoomRunner.RestartReason.EXIT)
	_expect(not menu.open, "a full build still opened a reward")
	for _frame in 3:
		await process_frame
	_expect(runner.gen_level == 3 and runner.gen_seed == 3, "an empty offer did not advance, level %d seed %d" % [runner.gen_level, runner.gen_seed])

	var kept_speed := runner.build.stack_count(RunBuild.Id.TOP_SPEED)
	ui.open_pause()
	_expect("Demo room" in _pause_text(ui), "generated pause still offered a generated run")
	for _move in 2:
		Input.action_press(&"move_down")
		await process_frame
		Input.action_release(&"move_down")
	_expect(ui.pause_index == 2, "pause did not land on demo, index %d" % ui.pause_index)
	Input.action_press(&"jump")
	await process_frame
	Input.action_release(&"jump")
	_expect(not ui.pause_open and not runner.gen_active, "demo entry left the generated run active")
	_expect(
		runner.room.scene_file_path == "res://scenes/rooms/demo.tscn",
		"demo entry loaded %s" % runner.room.scene_file_path,
	)
	_expect(runner.build.stack_count(RunBuild.Id.TOP_SPEED) == kept_speed, "returning to the demo dropped the build")

	ui.free()
	runner.free()
	menu.free()


func _cell_feet(room: Room, cell: Vector2i) -> Vector2:
	var center := room.terrain.to_global(room.terrain.map_to_local(cell))
	return center + Vector2(0, 4)


func _pause_text(ui: RunUI) -> String:
	var text := ""
	for child in ui._pause_rows.get_children():
		text += (child as Label).text + "\n"
	return text


func _picker_text(ui: RunUI) -> String:
	var text := ""
	for child in ui._picker_rows.get_children():
		if child is Label:
			text += (child as Label).text
	return text


func _await_restart() -> void:
	var frames := ceili(RoomFx.EXIT_DURATION * Engine.physics_ticks_per_second) + 8
	for _frame in frames:
		await physics_frame
		if not _restarts.is_empty():
			return


func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	_failed = true
	push_error(message)
