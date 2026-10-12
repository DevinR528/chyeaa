extends SceneTree
## Imported-piece metadata, stitching rules, determinism, and runtime assembly.

const LIBRARY := preload("res://resources/pieces/library.tres")
const STANDARD_SCENE := preload("res://scenes/player/standard.tscn")

var _failed := false


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_check_imported_library()
	_check_portal_placement_and_overlap()
	_check_seeded_generation()
	await _check_runtime_room()
	quit(1 if _failed else 0)


func _check_imported_library() -> void:
	_expect(LIBRARY.pieces.size() == 12, "piece index did not import all 12 entries")
	for piece: PieceData in LIBRARY.pieces:
		_expect(piece.scene != null, "%s has no imported scene" % piece.piece_id)
		var scene := piece.scene.instantiate()
		for child_name in [&"Terrain", &"BlockTerrain", &"GrappleSurfaces", &"PogoSurfaces", &"Spawn", &"EntryPortal", &"ExitPortal", &"Props", &"Actors"]:
			_expect(scene.has_node(NodePath(child_name)), "%s lacks %s" % [piece.piece_id, child_name])
		scene.free()


func _check_portal_placement_and_overlap() -> void:
	var left := _piece(&"left", 10, 10, PieceData.Facing.LEFT, PieceData.Facing.RIGHT, 2)
	var right := _piece(&"right", 8, 8, PieceData.Facing.LEFT, PieceData.Facing.RIGHT, 0)
	var placed_a := {"piece": left, "ox": 2, "oy": 2}
	var placed_b := RoomGenerator._place_after(placed_a, right, 3, 0)
	_expect(not placed_b.is_empty(), "opposite-facing portals did not join")
	var exit_world := RoomGenerator._translated_portal(left.exit(), 2, 2)
	var entry_world := RoomGenerator._translated_portal(right.entry(), placed_b.ox, placed_b.oy)
	var flex := RoomGenerator._generate_flex(exit_world, entry_world, 3)
	_expect(not flex.is_empty(), "mismatched apertures did not produce a flex corridor")
	_expect(
		RoomGenerator._place_after(
			placed_a,
			_piece(&"wrong", 8, 8, PieceData.Facing.RIGHT, PieceData.Facing.RIGHT, 0),
			3,
			0,
		).is_empty(),
		"same-facing portals joined",
	)
	_expect(
		RoomGenerator._overlaps(placed_a, {"piece": right, "ox": 5, "oy": 5}),
		"overlapping piece rectangles were accepted",
	)


func _check_seeded_generation() -> void:
	var first := RoomGenerator.generate_layout(LIBRARY, 42, 3, Vector2i(1, 3))
	var second := RoomGenerator.generate_layout(LIBRARY, 42, 3, Vector2i(1, 3))
	_expect(not first.is_empty(), "fixed-seed generation failed")
	_expect(_signature(first) == _signature(second), "fixed seed was not deterministic")
	var placed: Array = first.placed
	_expect((placed.front().piece as PieceData).has_tag(&"cap_start"), "generated room lacks start cap")
	_expect((placed.back().piece as PieceData).has_tag(&"cap_end"), "generated room lacks end cap")
	_expect(placed.size() - 2 >= 1 and placed.size() - 2 <= 3, "piece-count budget was ignored")
	var occupied: Array[Dictionary] = []
	for placement: Dictionary in placed:
		for previous in occupied:
			_expect(not RoomGenerator._overlaps(placement, previous), "generated pieces overlap")
		occupied.append(placement)


func _check_runtime_room() -> void:
	var layout := RoomGenerator.generate_layout(LIBRARY, 7, 3, Vector2i(1, 2))
	var room := RoomGenerator.build_room(layout)
	var runner := RoomRunner.new()
	runner.process_physics_priority = -10
	runner.add_child(room)
	var camera := FollowCamera.new()
	camera.process_physics_priority = 30
	camera.process_callback = Camera2D.CAMERA2D_PROCESS_PHYSICS
	runner.add_child(camera)
	runner.room = room
	runner.camera = camera
	runner.characters = [STANDARD_SCENE]
	runner.character_index = 0
	root.add_child(runner)
	await physics_frame
	await physics_frame

	_expect(runner.player.room == room, "RoomRunner did not own the generated room/player pair")
	_expect(room.extent_cells.size == Vector2i(layout.cols, layout.rows), "generated room extent was lost")
	_expect(room.spawn_feet().is_equal_approx(layout.spawn_feet), "generated spawn marker moved")
	var found_collision := false
	for cell in room.terrain.get_used_cells():
		if room.has_tile(room.cell_rect(cell).get_center(), PhysicsLayers.WORLD):
			found_collision = true
			break
	_expect(found_collision, "generated terrain has no collision")
	for prop in room.props():
		_expect(room.is_ancestor_of(prop), "generated prop escaped room ownership")
	for actor in room.actors():
		_expect(room.is_ancestor_of(actor), "generated actor escaped room ownership")
	runner.queue_free()
	await process_frame


func _piece(
	id: StringName,
	cols: int,
	rows: int,
	entry_facing: PieceData.Facing,
	exit_facing: PieceData.Facing,
	entry_y: int,
) -> PieceData:
	var piece := PieceData.new()
	piece.piece_id = id
	piece.cols = cols
	piece.rows = rows
	piece.entry_facing = entry_facing
	piece.entry_a = Vector2i(0 if entry_facing == PieceData.Facing.LEFT else cols - 1, entry_y)
	piece.entry_b = piece.entry_a + Vector2i(0, 3)
	piece.exit_facing = exit_facing
	piece.exit_a = Vector2i(cols - 1 if exit_facing == PieceData.Facing.RIGHT else 0, 2)
	piece.exit_b = piece.exit_a + Vector2i(0, 3)
	return piece


func _signature(layout: Dictionary) -> String:
	var parts: Array[String] = []
	for placement: Dictionary in layout.placed:
		parts.append("%s@%d,%d" % [placement.piece.piece_id, placement.ox, placement.oy])
	for run: Vector3i in layout.flex_runs:
		parts.append("%d:%d-%d" % [run.x, run.y, run.z])
	return "|".join(parts)


func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	_failed = true
	push_error(message)
