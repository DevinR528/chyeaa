class_name RoomGenerator
extends RefCounted
## Seeded linear piece stitching and runtime Room assembly.

const TILE := MovementStats.TILE
const MAX_ATTEMPTS := 80
const FLEX_LEN_MIN := 3
const FLEX_LEN_MAX := 12
const FLEX_SHELL := 3
const MIN_APERTURE_H := 4
const MIN_APERTURE_W := 3
const KIND_TILES := preload("res://resources/tiles/kind_tiles.tres")
const RoomScript := preload("res://src/rooms/room.gd")

const OPPOSITE := {
	PieceData.Facing.LEFT: PieceData.Facing.RIGHT,
	PieceData.Facing.RIGHT: PieceData.Facing.LEFT,
	PieceData.Facing.UP: PieceData.Facing.DOWN,
	PieceData.Facing.DOWN: PieceData.Facing.UP,
}


class SeedRng:
	extends RefCounted

	var original_seed := 1
	var state := 1

	func _init(seed: int) -> void:
		original_seed = absi(seed) if seed != 0 else 1
		state = original_seed

	func next() -> float:
		state = (1103515245 * state + 12345) & 0x7fffffff
		return float(state) / float(0x80000000)

	func integer(minimum: int, maximum: int) -> int:
		if minimum > maximum:
			var swap := minimum
			minimum = maximum
			maximum = swap
		if minimum == maximum:
			return minimum
		return minimum + floori(next() * (maximum - minimum + 1))

	func pick(items: Array) -> Variant:
		return items[integer(0, items.size() - 1)]

	func fork(salt: int) -> SeedRng:
		return SeedRng.new((original_seed ^ salt) if (original_seed ^ salt) != 0 else 1)


static func generate_layout(
	library: PieceLibrary,
	seed := 1,
	target_difficulty := 3,
	piece_count := Vector2i(1, 2),
) -> Dictionary:
	var rng := SeedRng.new(seed)
	var start := library.find_tag(&"cap_start")
	var finish := library.find_tag(&"cap_end")
	if start == null or finish == null:
		push_error("Piece library requires cap_start and cap_end")
		return {}
	var pool: Array[PieceData] = []
	for piece in library.pieces:
		if not piece.has_tag(&"cap_start") and not piece.has_tag(&"cap_end"):
			pool.append(piece)
	if pool.is_empty():
		push_error("Piece library has no gameplay pieces")
		return {}

	var count := rng.integer(piece_count.x, maxi(piece_count.x, piece_count.y))
	var recipe: Array[int] = []
	for _index in count:
		var roll := rng.next()
		var difficulty := target_difficulty
		if roll < 0.25:
			difficulty = maxi(1, target_difficulty - 1)
		elif roll > 0.85:
			difficulty = mini(10, target_difficulty + 1)
		recipe.append(difficulty)

	for attempt in MAX_ATTEMPTS:
		var attempt_rng := rng.fork(attempt * 9973)
		var sequence: Array[PieceData] = [start]
		var used: Dictionary = {}
		var previous := start
		var valid := true
		for difficulty in recipe:
			var by_difficulty: Array[PieceData] = pool.filter(
				func(piece: PieceData) -> bool: return piece.difficulty == difficulty
			)
			var base := by_difficulty if not by_difficulty.is_empty() else pool
			var compatible := _compatible_after(previous, base)
			if compatible.is_empty():
				compatible = _compatible_after(previous, pool)
			var candidates: Array[PieceData] = []
			for piece in compatible:
				if not piece.unique or not used.has(piece.piece_id):
					candidates.append(piece)
			if candidates.is_empty():
				valid = false
				break
			var fresh: Array[PieceData] = candidates.filter(
				func(piece: PieceData) -> bool: return not used.has(piece.piece_id)
			)
			var picked := attempt_rng.pick(fresh if not fresh.is_empty() else candidates) as PieceData
			sequence.append(picked)
			used[picked.piece_id] = true
			previous = picked
		if not valid or not _portals_compatible(previous.exit(), finish.entry()):
			continue
		sequence.append(finish)
		var layout := _place_sequence(sequence, attempt_rng)
		if not layout.is_empty():
			return _normalize_layout(layout, seed, target_difficulty)

	for middle in pool:
		if not _portals_compatible(start.exit(), middle.entry()):
			continue
		if not _portals_compatible(middle.exit(), finish.entry()):
			continue
		var fallback := _place_sequence([start, middle, finish], rng.fork(0xabc))
		if not fallback.is_empty():
			return _normalize_layout(fallback, seed, target_difficulty)
	push_error("Room generation failed for seed %d" % seed)
	return {}


static func build_room(layout: Dictionary) -> Room:
	if layout.is_empty():
		return null
	var room := Node2D.new()
	room.name = StringName(layout.id)
	room.set_script(RoomScript)
	room.extent_cells = Rect2i(Vector2i.ZERO, Vector2i(layout.cols, layout.rows))
	var terrain := _add_layer(room, &"Terrain", KIND_TILES)
	_add_layer(room, &"BlockTerrain", KIND_TILES)
	var grapple := _add_layer(room, &"GrappleSurfaces", KIND_TILES)
	var pogo := _add_layer(room, &"PogoSurfaces", KIND_TILES)
	var props := Node2D.new()
	props.name = &"Props"
	room.add_child(props)
	var actors := Node2D.new()
	actors.name = &"Actors"
	room.add_child(actors)

	for placement: Dictionary in layout.placed:
		var piece: PieceData = placement.piece
		var origin := Vector2i(placement.ox, placement.oy)
		var source := piece.scene.instantiate()
		_copy_cells(source.get_node(^"Terrain"), terrain, origin)
		_copy_cells(source.get_node(^"GrappleSurfaces"), grapple, origin)
		_copy_cells(source.get_node(^"PogoSurfaces"), pogo, origin)
		_move_entity_roots(source.get_node(^"Props"), props, Vector2(origin) * TILE)
		_move_entity_roots(source.get_node(^"Actors"), actors, Vector2(origin) * TILE)
		source.free()
	for run: Vector3i in layout.flex_runs:
		for x in range(run.y, run.z + 1):
			terrain.set_cell(Vector2i(x, run.x), 0, Vector2i.ZERO)

	var spawn := Marker2D.new()
	spawn.name = &"Spawn"
	spawn.position = layout.spawn_feet
	room.add_child(spawn)
	return room as Room


static func generate_room(
	library: PieceLibrary,
	seed := 1,
	target_difficulty := 3,
	piece_count := Vector2i(1, 2),
) -> Room:
	return build_room(generate_layout(library, seed, target_difficulty, piece_count))


static func _place_sequence(sequence: Array[PieceData], rng: SeedRng) -> Dictionary:
	var placed: Array[Dictionary] = [{"piece": sequence[0], "ox": 2, "oy": 2}]
	var flex_runs: Array[Vector3i] = []
	for index in range(1, sequence.size()):
		var fitted := _place_after_search(placed.back(), sequence[index], rng, placed)
		if fitted.is_empty():
			return {}
		placed.append(fitted.placed)
		flex_runs.append_array(fitted.flex_runs)
	return {"placed": placed, "flex_runs": flex_runs}


static func _place_after_search(
	previous: Dictionary,
	next_piece: PieceData,
	rng: SeedRng,
	placed: Array[Dictionary],
) -> Dictionary:
	if not _portals_compatible((previous.piece as PieceData).exit(), next_piece.entry()):
		return {}
	var exit_world := _translated_portal((previous.piece as PieceData).exit(), previous.ox, previous.oy)
	var guess := roundi(absf(
		_portal_mid_y(exit_world) - _portal_mid_y(next_piece.entry())
		if exit_world.facing in [PieceData.Facing.LEFT, PieceData.Facing.RIGHT]
		else _portal_mid_x(exit_world) - _portal_mid_x(next_piece.entry())
	))
	var need := maxi(FLEX_LEN_MIN, guess + 2)
	var base_length := maxi(
		need,
		rng.integer(FLEX_LEN_MIN, mini(FLEX_LEN_MAX, need + 2)),
	)
	base_length = mini(FLEX_LEN_MAX, base_length)
	var lengths: Array[int] = []
	for length in range(base_length, FLEX_LEN_MAX + 1):
		lengths.append(length)
	for length in range(base_length - 1, 1, -1):
		lengths.append(length)
	for length in lengths:
		for lateral in [0, -1, 1, -2, 2, -3, 3, -4, 4]:
			var candidate := _place_after(previous, next_piece, length, lateral)
			if candidate.is_empty():
				continue
			if placed.any(func(other: Dictionary) -> bool: return _overlaps(candidate, other)):
				continue
			var entry_world := _translated_portal(next_piece.entry(), candidate.ox, candidate.oy)
			return {
				"placed": candidate,
				"flex_runs": _generate_flex(exit_world, entry_world, length),
			}
	return {}


static func _place_after(previous: Dictionary, next_piece: PieceData, length: int, lateral: int) -> Dictionary:
	var exit_world := _translated_portal((previous.piece as PieceData).exit(), previous.ox, previous.oy)
	var entry := next_piece.entry()
	if not _portals_compatible(exit_world, entry):
		return {}
	var exit_bounds := _portal_bounds(exit_world)
	var entry_bounds := _portal_bounds(entry)
	var ox := 0
	var oy := 0
	match int(exit_world.facing):
		PieceData.Facing.RIGHT:
			ox = exit_bounds.x1 + 1 + length - entry_bounds.x0
			oy = roundi(_portal_mid_y(exit_world) - _portal_mid_y(entry)) + lateral
		PieceData.Facing.LEFT:
			ox = exit_bounds.x0 - 1 - length - entry_bounds.x1
			oy = roundi(_portal_mid_y(exit_world) - _portal_mid_y(entry)) + lateral
		PieceData.Facing.DOWN:
			oy = exit_bounds.y1 + 1 + length - entry_bounds.y0
			ox = roundi(_portal_mid_x(exit_world) - _portal_mid_x(entry)) + lateral
		PieceData.Facing.UP:
			oy = exit_bounds.y0 - 1 - length - entry_bounds.y1
			ox = roundi(_portal_mid_x(exit_world) - _portal_mid_x(entry)) + lateral
	return {"piece": next_piece, "ox": ox, "oy": oy}


static func _normalize_layout(layout: Dictionary, seed: int, target: int) -> Dictionary:
	var min_x := 1 << 30
	var min_y := 1 << 30
	for placement: Dictionary in layout.placed:
		min_x = mini(min_x, placement.ox)
		min_y = mini(min_y, placement.oy)
	for run: Vector3i in layout.flex_runs:
		min_x = mini(min_x, run.y)
		min_y = mini(min_y, run.x)
	var dx := 2 - min_x
	var dy := 2 - min_y
	var shifted_placed: Array[Dictionary] = []
	var max_x := 0
	var max_y := 0
	for placement: Dictionary in layout.placed:
		var shifted := {
			"piece": placement.piece,
			"ox": placement.ox + dx,
			"oy": placement.oy + dy,
		}
		shifted_placed.append(shifted)
		max_x = maxi(max_x, shifted.ox + (shifted.piece as PieceData).cols)
		max_y = maxi(max_y, shifted.oy + (shifted.piece as PieceData).rows)
	var shifted_flex: Array[Vector3i] = []
	for run: Vector3i in layout.flex_runs:
		var shifted := Vector3i(run.x + dy, run.y + dx, run.z + dx)
		shifted_flex.append(shifted)
		max_x = maxi(max_x, shifted.z + 1)
		max_y = maxi(max_y, shifted.x + 2)
	var start: Dictionary = shifted_placed[0]
	return {
		"id": &"gen_%d_%d" % [seed, target],
		"placed": shifted_placed,
		"flex_runs": shifted_flex,
		"cols": maxi(8, max_x + 2),
		"rows": maxi(8, max_y + 2),
		"spawn_feet": (start.piece as PieceData).spawn_feet + Vector2(start.ox, start.oy) * TILE,
	}


static func _generate_flex(exit_portal: Dictionary, entry_portal: Dictionary, length: int) -> Array[Vector3i]:
	var runs: Array[Vector3i] = []
	var a := _portal_bounds(exit_portal)
	var b := _portal_bounds(entry_portal)
	if exit_portal.facing in [PieceData.Facing.LEFT, PieceData.Facing.RIGHT]:
		var hull_y0: int = mini(a.y0, b.y0) - FLEX_SHELL
		var hull_y1: int = maxi(a.y1, b.y1) + FLEX_SHELL
		for index in length:
			var amount := 1.0 if length == 1 else float(index) / float(length - 1)
			var x: int = a.x1 + 1 + index if exit_portal.facing == PieceData.Facing.RIGHT else a.x0 - 1 - index
			var aperture := _ensure_aperture(
				roundi(lerpf(a.y0, b.y0, amount)),
				roundi(lerpf(a.y1, b.y1, amount)),
				MIN_APERTURE_H,
			)
			_add_solid_column(runs, x, hull_y0, aperture.x - 1)
			_add_solid_column(runs, x, aperture.y + 1, hull_y1)
		var a_columns := [a.x1, a.x1 - 1] if exit_portal.facing == PieceData.Facing.RIGHT else [a.x0, a.x0 + 1]
		var b_columns := [b.x0, b.x0 + 1] if exit_portal.facing == PieceData.Facing.RIGHT else [b.x1, b.x1 - 1]
		for x in a_columns:
			_seal_vertical(runs, x, a.y0, a.y1, hull_y0, hull_y1)
		for x in b_columns:
			_seal_vertical(runs, x, b.y0, b.y1, hull_y0, hull_y1)
	else:
		var hull_x0: int = mini(a.x0, b.x0) - FLEX_SHELL
		var hull_x1: int = maxi(a.x1, b.x1) + FLEX_SHELL
		for index in length:
			var amount := 1.0 if length == 1 else float(index) / float(length - 1)
			var y: int = a.y1 + 1 + index if exit_portal.facing == PieceData.Facing.DOWN else a.y0 - 1 - index
			var aperture := _ensure_aperture(
				roundi(lerpf(a.x0, b.x0, amount)),
				roundi(lerpf(a.x1, b.x1, amount)),
				MIN_APERTURE_W,
			)
			_add_solid_row(runs, y, hull_x0, aperture.x - 1)
			_add_solid_row(runs, y, aperture.y + 1, hull_x1)
		var a_rows := [a.y1, a.y1 - 1] if exit_portal.facing == PieceData.Facing.DOWN else [a.y0, a.y0 + 1]
		var b_rows := [b.y0, b.y0 + 1] if exit_portal.facing == PieceData.Facing.DOWN else [b.y1, b.y1 - 1]
		for y in a_rows:
			_seal_horizontal(runs, y, a.x0, a.x1, hull_x0, hull_x1)
		for y in b_rows:
			_seal_horizontal(runs, y, b.x0, b.x1, hull_x0, hull_x1)
	return runs


static func _ensure_aperture(first: int, last: int, minimum: int) -> Vector2i:
	var low := mini(first, last)
	var high := maxi(first, last)
	var need := minimum - (high - low + 1)
	if need > 0:
		low -= ceili(float(need) / 2.0)
		high += floori(float(need) / 2.0)
	return Vector2i(low, high)


static func _seal_vertical(runs: Array[Vector3i], x: int, y0: int, y1: int, hull_y0: int, hull_y1: int) -> void:
	var aperture := _ensure_aperture(y0, y1, MIN_APERTURE_H)
	_add_solid_column(runs, x, hull_y0, aperture.x - 1)
	_add_solid_column(runs, x, aperture.y + 1, hull_y1)


static func _seal_horizontal(runs: Array[Vector3i], y: int, x0: int, x1: int, hull_x0: int, hull_x1: int) -> void:
	var aperture := _ensure_aperture(x0, x1, MIN_APERTURE_W)
	_add_solid_row(runs, y, hull_x0, aperture.x - 1)
	_add_solid_row(runs, y, aperture.y + 1, hull_x1)


static func _add_solid_column(runs: Array[Vector3i], x: int, from_y: int, to_y: int) -> void:
	for y in range(from_y, to_y + 1):
		runs.append(Vector3i(y, x, x))


static func _add_solid_row(runs: Array[Vector3i], y: int, from_x: int, to_x: int) -> void:
	if to_x >= from_x:
		runs.append(Vector3i(y, from_x, to_x))


static func _compatible_after(previous: PieceData, candidates: Array[PieceData]) -> Array[PieceData]:
	return candidates.filter(
		func(piece: PieceData) -> bool: return _portals_compatible(previous.exit(), piece.entry())
	)


static func _portals_compatible(exit_portal: Dictionary, entry_portal: Dictionary) -> bool:
	return OPPOSITE[int(exit_portal.facing)] == int(entry_portal.facing)


static func _translated_portal(portal: Dictionary, ox: int, oy: int) -> Dictionary:
	return {
		"a": portal.a + Vector2i(ox, oy),
		"b": portal.b + Vector2i(ox, oy),
		"facing": portal.facing,
	}


static func _portal_bounds(portal: Dictionary) -> Dictionary:
	return {
		"x0": mini(portal.a.x, portal.b.x),
		"x1": maxi(portal.a.x, portal.b.x),
		"y0": mini(portal.a.y, portal.b.y),
		"y1": maxi(portal.a.y, portal.b.y),
	}


static func _portal_mid_x(portal: Dictionary) -> float:
	var bounds := _portal_bounds(portal)
	return (bounds.x0 + bounds.x1) / 2.0


static func _portal_mid_y(portal: Dictionary) -> float:
	var bounds := _portal_bounds(portal)
	return (bounds.y0 + bounds.y1) / 2.0


static func _overlaps(a: Dictionary, b: Dictionary) -> bool:
	var ap: PieceData = a.piece
	var bp: PieceData = b.piece
	return not (
		a.ox + ap.cols - 1 < b.ox
		or b.ox + bp.cols - 1 < a.ox
		or a.oy + ap.rows - 1 < b.oy
		or b.oy + bp.rows - 1 < a.oy
	)


static func _add_layer(room: Node2D, layer_name: StringName, tile_set: TileSet) -> TileMapLayer:
	var layer := TileMapLayer.new()
	layer.name = layer_name
	layer.tile_set = tile_set
	room.add_child(layer)
	return layer


static func _copy_cells(source: TileMapLayer, target: TileMapLayer, origin: Vector2i) -> void:
	for cell in source.get_used_cells():
		target.set_cell(
			cell + origin,
			source.get_cell_source_id(cell),
			source.get_cell_atlas_coords(cell),
			source.get_cell_alternative_tile(cell),
		)


static func _move_entity_roots(source: Node, target: Node, offset: Vector2) -> void:
	for child in source.get_children():
		_clear_owner(child)
		source.remove_child(child)
		target.add_child(child)
		if child is Node2D:
			(child as Node2D).position += offset
		if child is TileProp and (child as TileProp).path != null:
			(child as TileProp).path.position += offset


static func _clear_owner(node: Node) -> void:
	node.owner = null
	for child in node.get_children():
		_clear_owner(child)
