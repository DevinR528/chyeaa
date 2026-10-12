extends SceneTree
## BlockTerrain: art tiles larger than their 8 px cells (like the hand-made TileSet)
## answer the room's cell queries everywhere physics says they collide, flipped and
## transposed too; blocks hold the player up; death blocks are a hazard; and the
## demo room's TileSet follows the room's conventions.

const Rooms := preload("res://tests/test_room_builder.gd")
const STANDARD_SCENE := preload("res://scenes/player/standard.tscn")
const DEMO_SCENE := preload("res://scenes/rooms/demo.tscn")
const FLOOR_ROW := Rooms.FLOOR_ROW
const TILE := Rooms.TILE
const BLOCK := Rooms.BLOCK_CELLS
## The collision each kind may have, as collision layer bits (0 = none).
const KIND_COLLISION := {
	Room.Kind.EMPTY: [0],
	Room.Kind.SOLID: [PhysicsLayers.WORLD],
	Room.Kind.GRAPPLE: [PhysicsLayers.WORLD, 0],
	Room.Kind.EXIT: [PhysicsLayers.EXIT],
	Room.Kind.DEATH: [PhysicsLayers.HAZARD],
	Room.Kind.POGO: [0],
}

var _failed := false


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	await _check_queries_match_physics()
	await _check_player_lands_on_blocks()
	await _check_death_blocks_are_a_hazard()
	await _check_demo_block_terrain()
	quit(1 if _failed else 0)


func _check_queries_match_physics() -> void:
	var placed := [
		[Vector2i(10, 10), Rooms.BLOCK_SOLID_TILE, 0, BLOCK * BLOCK, "solid block"],
		[Vector2i(20, 10), Rooms.BLOCK_LEDGE_TILE, 0, BLOCK * BLOCK / 2, "ledge"],
		[Vector2i(30, 10), Rooms.BLOCK_LEDGE_TILE, TileSetAtlasSource.TRANSFORM_FLIP_H, BLOCK * BLOCK / 2, "ledge flipped"],
		[Vector2i(40, 10), Rooms.BLOCK_LEDGE_TILE, TileSetAtlasSource.TRANSFORM_TRANSPOSE, BLOCK * BLOCK / 2, "ledge transposed"],
		[Vector2i(10, 20), Rooms.BLOCK_LEDGE_TILE, TileSetAtlasSource.TRANSFORM_TRANSPOSE | TileSetAtlasSource.TRANSFORM_FLIP_V, BLOCK * BLOCK / 2, "ledge rotated"],
	]
	var room := Rooms.make_room(root, func(layers: Dictionary) -> void:
		for tile: Array in placed:
			(layers.BlockTerrain as TileMapLayer).set_cell(tile[0], 0, tile[1], tile[2])
		(layers.BlockTerrain as TileMapLayer).set_cell(Vector2i(20, 20), 0, Rooms.BLOCK_DEATH_TILE))
	await physics_frame
	await physics_frame
	for tile: Array in placed:
		var solid := 0
		for cell in _window(tile[0]):
			var physics_solid := _physics_hit(room, cell, PhysicsLayers.WORLD)
			if room.is_solid_cell(cell) != physics_solid:
				_expect(false, "%s: is_solid_cell(%s) is %s but physics says %s" % [tile[4], cell, not physics_solid, physics_solid])
			_expect((room.kind_at_cell(cell) == Room.Kind.SOLID) == physics_solid, "%s: kind at %s disagrees with physics" % [tile[4], cell])
			solid += int(physics_solid)
		_expect(solid == tile[3], "%s covers %d cells, expected %d" % [tile[4], solid, tile[3]])
	var deadly := 0
	for cell in _window(Vector2i(20, 20)):
		var physics_deadly := _physics_hit(room, cell, PhysicsLayers.HAZARD)
		_expect((room.kind_at_cell(cell) == Room.Kind.DEATH) == physics_deadly, "death block: kind at %s disagrees with physics" % cell)
		_expect(not room.is_solid_cell(cell), "death block: %s should not block the body" % cell)
		deadly += int(physics_deadly)
	_expect(deadly == BLOCK * BLOCK, "death block covers %d cells, expected %d" % [deadly, BLOCK * BLOCK])
	room.free()
	await process_frame


func _check_player_lands_on_blocks() -> void:
	var platform_row := 18
	var room := Rooms.make_room(root, func(layers: Dictionary) -> void:
		for x in [16, 20, 24]:
			(layers.BlockTerrain as TileMapLayer).set_cell(Vector2i(x, platform_row), 0, Rooms.BLOCK_SOLID_TILE)
		(layers.BlockTerrain as TileMapLayer).set_cell(Vector2i(Rooms.ROOM_SIZE.x, 0), 0, Rooms.BLOCK_SOLID_TILE))
	var platform_top := platform_row * TILE
	_expect(room.pixel_rect().end.x >= (Rooms.ROOM_SIZE.x + BLOCK) * TILE, "room extent ends at %s, inside a block past the 8 px terrain" % room.pixel_rect().end.x)

	var player := Rooms.spawn_player(root, room, STANDARD_SCENE, Vector2(22 * TILE, platform_top - 24.0))
	for _frame in 60:
		await physics_frame
	_expect(player.is_on_floor() and absf(player.body_rect().end.y - platform_top) < 0.1, "player did not land on the blocks (feet %f, top %f)" % [player.body_rect().end.y, platform_top])
	player.free()
	room.free()
	await process_frame


func _check_death_blocks_are_a_hazard() -> void:
	var room := Rooms.make_room(root, func(layers: Dictionary) -> void:
		(layers.BlockTerrain as TileMapLayer).set_cell(Vector2i(20, FLOOR_ROW - BLOCK), 0, Rooms.BLOCK_DEATH_TILE))
	var touched: Array[int] = []
	var player := Rooms.spawn_player(root, room, STANDARD_SCENE, Vector2(22 * TILE, (FLOOR_ROW - BLOCK) * TILE - 16.0))
	player.trigger_touched.connect(func(layer: int) -> void: touched.append(layer))
	for _frame in 30:
		await physics_frame
	_expect(touched.any(func(layer: int) -> bool: return layer & PhysicsLayers.HAZARD), "falling into a death block did not report a hazard")
	player.free()
	room.free()
	await process_frame


## The demo's BlockTerrain TileSet is made by hand in scenes/tiles/block_terrain.tscn.
func _check_demo_block_terrain() -> void:
	var room := DEMO_SCENE.instantiate() as Room
	root.add_child(room)
	var blocks := room.block_terrain
	if blocks.tile_set != null:
		_check_tile_set_conventions(blocks.tile_set)
	room.free()


## Every tile in the TileSet, painted or not: its collision matches its kind (no
## kind and no collision is decoration).
func _check_tile_set_conventions(tile_set: TileSet) -> void:
	_expect(
		tile_set.get_custom_data_layer_by_name(Room.KIND_DATA) != -1,
		"BlockTerrain's TileSet has no `kind` custom data layer"
	)
	_expect(
		tile_set.get_physics_layers_count() > 0 and tile_set.get_physics_layer_collision_layer(Room.WORLD_PHYSICS) == PhysicsLayers.WORLD,
		"BlockTerrain's physics layer 0 must collide on WORLD"
	)
	if _failed:
		return
	for source_index in tile_set.get_source_count():
		var source_id := tile_set.get_source_id(source_index)
		var source := tile_set.get_source(source_id) as TileSetAtlasSource
		if source == null:
			continue
		for tile_index in source.get_tiles_count():
			var coords := source.get_tile_id(tile_index)
			for alternative_index in source.get_alternative_tiles_count(coords):
				var alternative := source.get_alternative_tile_id(coords, alternative_index)
				var data := source.get_tile_data(coords, alternative)
				var label := "BlockTerrain tile %s %s alt %d" % [source.resource_name if source.resource_name else str(source_id), coords, alternative]
				var kind: int = data.get_custom_data(Room.KIND_DATA)
				var collides := 0
				for physics in tile_set.get_physics_layers_count():
					if data.get_collision_polygons_count(physics) > 0:
						collides |= tile_set.get_physics_layer_collision_layer(physics)
				_expect(KIND_COLLISION.get(kind, []).has(collides), "%s has kind %s but its collision layers are %d" % [label, Room.Kind.keys()[kind], collides])


func _window(origin: Vector2i) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for y in range(origin.y - BLOCK - 1, origin.y + 2 * BLOCK + 1):
		for x in range(origin.x - BLOCK - 1, origin.x + 2 * BLOCK + 1):
			cells.append(Vector2i(x, y))
	return cells


func _physics_hit(room: Room, cell: Vector2i, layer: int) -> bool:
	var query := PhysicsPointQueryParameters2D.new()
	query.position = room.cell_rect(cell).get_center()
	query.collision_mask = layer
	return not room.get_world_2d().direct_space_state.intersect_point(query).is_empty()


func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	_failed = true
	push_error(message)
