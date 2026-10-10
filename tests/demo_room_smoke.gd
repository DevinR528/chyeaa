extends SceneTree
## Demo room checks that do not pin authored content, so editing the room in
## Godot only breaks this if spawn, triggers, or character surfaces break.

const MAIN_SCENE := preload("res://scenes/main.tscn")

var _failed := false
var _restarts: Array[RoomRunner.RestartReason] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var main := MAIN_SCENE.instantiate() as RoomRunner
	root.add_child(main)
	main.restarted.connect(func(reason: RoomRunner.RestartReason) -> void: _restarts.append(reason))
	var room := main.room
	_check_character_surfaces(main)
	main.switch_character(0)
	var player := main.player
	_expect(
		player.body_rect().end.is_equal_approx(Vector2(room.spawn_feet().x + player.body_rect().size.x / 2.0, room.spawn_feet().y)),
		"player did not spawn standing on the spawn marker",
	)

	for _frame in 300:
		await physics_frame
		if player.is_on_floor():
			break
	_expect(player.is_on_floor(), "player never landed after spawning in the demo room")
	_expect(_restarts.is_empty(), "spawn fall triggered a restart: %s" % [_restarts])

	await _expect_restart_at(main, _first_cell_of(room, Room.Kind.DEATH), RoomRunner.RestartReason.DEATH)
	await _expect_restart_at(main, _first_cell_of(room, Room.Kind.EXIT), RoomRunner.RestartReason.EXIT)
	await _expect_restart_at(main, Vector2(room.spawn_feet().x, room.kill_plane_y() + 64.0), RoomRunner.RestartReason.FALL)

	_check_out_of_bounds_ceiling(main)
	await _check_moving_props_move(main)
	await _check_restart_resets_actors(main)

	main.queue_free()
	await process_frame
	quit(1 if _failed else 0)


func _check_character_surfaces(main: RoomRunner) -> void:
	var expected := {
		0: [false, false],
		1: [true, false],
		2: [false, true],
	}
	for index: int in expected:
		main.switch_character(index)
		var surfaces := [main.room.grapple_surfaces.enabled, main.room.pogo_surfaces.enabled]
		_expect(surfaces == expected[index], "character %d sees grapple/pogo surfaces %s" % [index, surfaces])
		for prop in main.room.props():
			var hidden_kinds := []
			if not surfaces[0]:
				hidden_kinds.append(Room.Kind.GRAPPLE)
			if not surfaces[1]:
				hidden_kinds.append(Room.Kind.POGO)
			_expect(prop.excluded == hidden_kinds.has(prop.surface), "character %d: %s excluded is %s" % [index, prop.name, prop.excluded])
	_expect(main.get_children().filter(func(node: Node) -> bool: return node is PlayerBody).size() == 1, "switching left more than one player in the room")


func _expect_restart_at(main: RoomRunner, feet: Vector2, reason: RoomRunner.RestartReason) -> void:
	_restarts.clear()
	main.player.respawn(feet)
	for _frame in 4:
		await physics_frame
	_expect(_restarts.has(reason), "expected restart %s at %s, got %s" % [
		RoomRunner.RestartReason.keys()[reason], feet, _restarts,
	])
	var spawn_feet := main.room.spawn_feet()
	_expect(
		main.player.body_rect().end.y <= spawn_feet.y + 8.0 and absf(main.player.global_position.x - spawn_feet.x) < 8.0,
		"restart did not return the player to spawn",
	)


## Feet position that puts the player's body over the cell's center.
func _first_cell_of(room: Room, kind: Room.Kind) -> Vector2:
	for cell in room.terrain.get_used_cells():
		var data := room.terrain.get_cell_tile_data(cell)
		if data.get_custom_data(Room.KIND_DATA) == kind:
			var center := room.terrain.to_global(room.terrain.map_to_local(cell))
			return center + Vector2(0, 4)
	_expect(false, "demo room has no %s tile" % Room.Kind.keys()[kind])
	return room.spawn_feet()


func _check_out_of_bounds_ceiling(main: RoomRunner) -> void:
	var space := main.get_world_2d().direct_space_state
	var query := PhysicsPointQueryParameters2D.new()
	query.position = main.room.pixel_rect().position + Vector2(main.room.pixel_rect().size.x / 2.0, -4.0)
	_expect(not space.intersect_point(query).is_empty(), "space above the room is not solid")


func _check_moving_props_move(main: RoomRunner) -> void:
	var moving := main.room.props().filter(func(prop: TileProp) -> bool: return prop.oscillation != null or prop.path != null)
	var start := moving.map(func(prop: TileProp) -> Vector2: return prop.global_position)
	for _frame in 30:
		await physics_frame
	for index in moving.size():
		var prop: TileProp = moving[index]
		_expect(not prop.global_position.is_equal_approx(start[index]), "%s has motion but did not move" % prop.name)


func _check_restart_resets_actors(main: RoomRunner) -> void:
	var actors := main.room.actors()
	for actor in actors:
		actor.position += Vector2(24, -24)
		if actor is Walker:
			(actor as Walker).alive = false
		elif actor is Throwable:
			(actor as Throwable).launch(Vector2(200, -200))
	await physics_frame
	main.restart(RoomRunner.RestartReason.DEATH)
	for actor in actors:
		_expect(actor.position.is_equal_approx(actor.home), "%s did not return to where it was placed" % actor.name)
		if actor is Walker:
			_expect((actor as Walker).alive, "%s stayed dead after a restart" % actor.name)
		elif actor is Throwable:
			_expect((actor as Throwable).state == Throwable.State.IDLE, "%s was not idle after a restart" % actor.name)


func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	_failed = true
	push_error(message)
