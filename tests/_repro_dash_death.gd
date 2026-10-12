extends SceneTree

const Rooms := preload("res://tests/test_room_builder.gd")
const STANDARD_SCENE := preload("res://scenes/player/standard.tscn")


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var runner := RoomRunner.new()
	runner.process_physics_priority = -10
	var room := Rooms.make_room(runner, func(layers: Dictionary) -> void:
		Rooms.paint_column(layers.Terrain, 18, 20, Rooms.FLOOR_ROW - 1, Rooms.DEATH_TILE))
	var camera := FollowCamera.new()
	camera.process_physics_priority = 30
	runner.add_child(camera)
	runner.room = room
	runner.camera = camera
	runner.characters = [STANDARD_SCENE]
	runner.character_index = 0
	var floor_y := Rooms.FLOOR_ROW * Rooms.TILE
	root.add_child(runner)
	room.spawn.position = Vector2(48.0, floor_y)
	await physics_frame

	var player := runner.player
	player.respawn(Vector2(40.0, floor_y))
	var watcher := Node.new()
	watcher.set_script(load("res://tests/_repro_watch.gd"))
	watcher.process_physics_priority = 50
	watcher.set("body", player)
	runner.add_child(watcher)
	for _frame in 20:
		await physics_frame
		if player.is_on_floor():
			break
	print("settled vel ", player.velocity, " pos ", player.global_position, " floor ", player.is_on_floor())

	Input.action_press(&"dash")
	Input.action_press(&"move_right")
	for _frame in 8:
		await physics_frame
		print("dash frame vel ", player.velocity.x, " state ", player.move_state, " pos ", player.global_position.x, " pending ", runner._pending_restart)
		if runner._pending_restart != RoomRunner.NO_RESTART:
			break
	Input.action_release(&"dash")
	Input.action_release(&"move_right")
	print("after contact vel ", player.velocity, " pos ", player.global_position)

	for _frame in 6:
		await physics_frame
		print("post vel ", player.velocity, " pos ", player.global_position.x, " state ", player.move_state, " dash_vx ", player.dash_velocity_x)

	runner.queue_free()
	await process_frame
	quit(0)
