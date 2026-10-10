extends SceneTree
## Touch sensor checks: death and exit tiles report through physics, and flush
## edge contact does not count.

const Rooms := preload("res://tests/test_room_builder.gd")
const STANDARD_SCENE := preload("res://scenes/player/standard.tscn")
const EXIT_COLUMN := 30
const DEATH_COLUMN := 40

var _failed := false
var _touched: Array[int] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var room := Rooms.make_room(root, func(layers: Dictionary) -> void:
		Rooms.paint_column(layers.Terrain, EXIT_COLUMN, 20, Rooms.FLOOR_ROW - 1, Rooms.EXIT_TILE)
		Rooms.paint_column(layers.Terrain, DEATH_COLUMN, 20, Rooms.FLOOR_ROW - 1, Rooms.DEATH_TILE))
	var player := Rooms.spawn_player(root, room, STANDARD_SCENE, Vector2(80, Rooms.FLOOR_ROW * Rooms.TILE))
	player.trigger_touched.connect(func(layer: int) -> void: _touched.append(layer))
	var floor_y := Rooms.FLOOR_ROW * Rooms.TILE
	var half_width := player.body_rect().size.x / 2.0

	await _place_and_wait(player, Vector2(EXIT_COLUMN * Rooms.TILE - half_width, floor_y))
	_expect(_touched.is_empty(), "standing flush against an exit tile counted as touching it: %s" % [_touched])

	await _place_and_wait(player, Vector2(EXIT_COLUMN * Rooms.TILE - half_width + 1.0, floor_y))
	_expect(_touched.has(PhysicsLayers.EXIT), "overlapping an exit tile by 1px was not reported: %s" % [_touched])

	await _place_and_wait(player, Vector2(DEATH_COLUMN * Rooms.TILE + 4.0, floor_y))
	_expect(_touched.has(PhysicsLayers.HAZARD), "overlapping a death tile was not reported: %s" % [_touched])

	await _place_and_wait(player, Vector2(80, room.kill_plane_y() + 64.0))
	_expect(_touched.has(PhysicsLayers.FALL), "falling below the kill plane was not reported: %s" % [_touched])

	player.free()
	room.free()
	await process_frame
	quit(1 if _failed else 0)


func _place_and_wait(player: PlayerBody, feet: Vector2) -> void:
	_touched.clear()
	player.respawn(feet)
	for _frame in 3:
		await physics_frame
		player.velocity = Vector2.ZERO


func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	_failed = true
	push_error(message)
