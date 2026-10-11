extends SceneTree
## Reach overlay checks: its jump and dash numbers match what the player actually
## does, and the wall probe measures the gap to a wall.

const Rooms := preload("res://tests/test_room_builder.gd")
const STANDARD_SCENE := preload("res://scenes/player/standard.tscn")
const POGO_SCENE := preload("res://scenes/player/pogo.tscn")
const FLOOR_ROW := Rooms.FLOOR_ROW
const TILE := Rooms.TILE
const WALL_COLUMN := 30
## cast_motion bisects the probe's travel, so its precision is about 320px / 256.
const WALL_TOLERANCE := 1.5

var _failed := false


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	await _check_jump_rise(false)
	await _check_jump_rise(true)
	await _check_dash_distance()
	await _check_wall_probe()
	await _check_draws_every_layer()
	quit(1 if _failed else 0)


func _check_jump_rise(release_early: bool) -> void:
	var room := Rooms.make_room(root, func(_layers: Dictionary) -> void: pass)
	var player := Rooms.spawn_player(root, room, STANDARD_SCENE, Vector2(80, FLOOR_ROW * TILE))
	await _physics_frames(2)
	var start_feet := player.body_rect().end.y

	_send_action(&"jump", true)
	await physics_frame
	if release_early:
		_send_action(&"jump", false)
	var highest_feet := start_feet
	for _frame in 40:
		await physics_frame
		highest_feet = minf(highest_feet, player.body_rect().end.y)
	_send_action(&"jump", false)

	var stats := player.stats
	var cut := stats.jump_cut if release_early else 1.0
	var predicted := ReachOverlay.jump_rise(stats.jump_velocity, stats.gravity, cut)
	var actual := start_feet - highest_feet
	var label := "low" if release_early else "high"
	_expect(absf(predicted - actual) < 0.5, "%s jump rose %.2fpx, overlay says %.2fpx" % [label, actual, predicted])
	await _free(room, player)


func _check_dash_distance() -> void:
	var room := Rooms.make_room(root, func(_layers: Dictionary) -> void: pass)
	var player := Rooms.spawn_player(root, room, STANDARD_SCENE, Vector2(80, FLOOR_ROW * TILE))
	await _physics_frames(2)
	var start_x := player.global_position.x
	var dash_end_x := start_x

	Input.action_press(&"dash")
	for _frame in 20:
		await physics_frame
		if player.move_state == PlayerBody.MovementState.DASH:
			dash_end_x = player.global_position.x
	Input.action_release(&"dash")

	var predicted := ReachOverlay.dash_distance(player.stats)
	var actual := dash_end_x - start_x
	_expect(absf(predicted - actual) < 0.5, "dash travelled %.2fpx, overlay says %.2fpx" % [actual, predicted])
	await _free(room, player)


func _check_wall_probe() -> void:
	var room := Rooms.make_room(root, func(layers: Dictionary) -> void:
		Rooms.paint_column(layers.Terrain, WALL_COLUMN, 0, FLOOR_ROW - 1, Rooms.SOLID_TILE))
	var player := Rooms.spawn_player(root, room, STANDARD_SCENE, Vector2(80, FLOOR_ROW * TILE))
	await _physics_frames(2)
	var rect := player.body_rect()
	var wall_x := WALL_COLUMN * TILE

	var right := ReachOverlay.wall_distance(player, 1.0)
	_expect(absf(right - (wall_x - rect.end.x)) < WALL_TOLERANCE, "right wall probe read %.2fpx, gap is %.2fpx" % [right, wall_x - rect.end.x])
	var left := ReachOverlay.wall_distance(player, -1.0)
	_expect(absf(left - (rect.position.x - TILE)) < WALL_TOLERANCE, "left wall probe read %.2fpx, gap is %.2fpx" % [left, rect.position.x - TILE])

	player.respawn(Vector2(wall_x - rect.size.x / 2.0, FLOOR_ROW * TILE))
	await _physics_frames(2)
	var flush := ReachOverlay.wall_distance(player, 1.0)
	_expect(flush < WALL_TOLERANCE, "wall probe flush against a wall read %.2fpx" % flush)
	await _free(room, player)


## Catches script errors in the drawing paths; check the log for SCRIPT ERROR.
func _check_draws_every_layer() -> void:
	var room := Rooms.make_room(root, func(_layers: Dictionary) -> void: pass)
	var player := Rooms.spawn_player(root, room, POGO_SCENE, Vector2(80, FLOOR_ROW * TILE))
	var overlay := ReachOverlay.new()
	root.add_child(overlay)
	overlay.show_wall_probe = true
	overlay.follow(player)
	overlay.visible = true
	await _physics_frames(3)
	await process_frame
	_expect(overlay.global_position == player.global_position, "overlay did not follow the player")
	overlay.free()
	await _free(room, player)


## Goes through `_input` like a real key, so `PlayerInput` latches the press on
## the same tick it reads the button as held. `Input.action_press` skips that.
func _send_action(action: StringName, pressed: bool) -> void:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()


func _free(room: Room, player: PlayerBody) -> void:
	player.free()
	room.free()
	await process_frame


func _physics_frames(count: int) -> void:
	for _frame in count:
		await physics_frame


func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	_failed = true
	push_error(message)
