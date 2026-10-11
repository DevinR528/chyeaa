extends RefCounted
## Builds small rooms in code for headless tests: a floor, side walls, and
## whatever the test paints. Preload it; it has no class_name on purpose.

const KIND_TILES := preload("res://resources/tiles/kind_tiles.tres")
const ROOM_SCRIPT := preload("res://src/rooms/room.gd")
## BlockTerrain tiles from `make_block_tiles`: 32 px art on 8 px cells, each
## colliding over the BLOCK_CELLS x BLOCK_CELLS cells right of and below where it is painted.
const BLOCK_CELLS := 4
const BLOCK_SOLID_TILE := Vector2i(0, 0)
const BLOCK_DEATH_TILE := Vector2i(1, 0)
## Solid in its left two columns only, so flips and transposes change what it covers.
const BLOCK_LEDGE_TILE := Vector2i(2, 0)
## Physics layer indices in `make_block_tiles`, as in kind_tiles.tres.
const WORLD_PHYSICS := 0
const HAZARD_PHYSICS := 1

const SOLID_TILE := Vector2i(0, 0)
const GRAPPLE_TILE := Vector2i(1, 0)
const EXIT_TILE := Vector2i(3, 0)
const DEATH_TILE := Vector2i(4, 0)
const POGO_TILE := Vector2i(5, 0)
const ROOM_SIZE := Vector2i(60, 30)
const FLOOR_ROW := ROOM_SIZE.y - 1
const TILE := 8.0


## `paint` receives a Dictionary of layer name to TileMapLayer.
static func make_room(parent: Node, paint: Callable) -> Room:
	var room := Node2D.new()
	room.set_script(ROOM_SCRIPT)
	var layers := {}
	var block_tiles := make_block_tiles()
	for layer_name in [&"Terrain", &"BlockTerrain", &"GrappleSurfaces", &"PogoSurfaces"]:
		var layer := TileMapLayer.new()
		layer.name = layer_name
		layer.tile_set = block_tiles if layer_name == &"BlockTerrain" else KIND_TILES
		room.add_child(layer)
		layers[layer_name] = layer
	var spawn := Marker2D.new()
	spawn.name = &"Spawn"
	room.add_child(spawn)

	paint_row(layers.Terrain, FLOOR_ROW, 0, ROOM_SIZE.x - 1, SOLID_TILE)
	paint_column(layers.Terrain, 0, 0, FLOOR_ROW, SOLID_TILE)
	paint_column(layers.Terrain, ROOM_SIZE.x - 1, 0, FLOOR_ROW, SOLID_TILE)
	paint.call(layers)
	parent.add_child(room)
	return room as Room


## A stand-in for the hand-made BlockTerrain TileSet (scenes/tiles/block_terrain.tscn):
## art tiles larger than their 8 px cells, following the room's TileSet conventions.
static func make_block_tiles() -> TileSet:
	var tile_set := TileSet.new()
	tile_set.tile_size = Vector2i.ONE * int(TILE)
	tile_set.add_physics_layer()
	tile_set.set_physics_layer_collision_layer(WORLD_PHYSICS, PhysicsLayers.WORLD)
	tile_set.set_physics_layer_collision_mask(WORLD_PHYSICS, 0)
	tile_set.add_physics_layer()
	tile_set.set_physics_layer_collision_layer(HAZARD_PHYSICS, PhysicsLayers.HAZARD)
	tile_set.set_physics_layer_collision_mask(HAZARD_PHYSICS, 0)
	tile_set.add_custom_data_layer()
	tile_set.set_custom_data_layer_name(0, Room.KIND_DATA)
	tile_set.set_custom_data_layer_type(0, TYPE_INT)

	var art := int(TILE) * BLOCK_CELLS
	var source := TileSetAtlasSource.new()
	source.texture = ImageTexture.create_from_image(Image.create(art * 3, art, false, Image.FORMAT_RGBA8))
	source.texture_region_size = Vector2i.ONE * art
	tile_set.add_source(source)
	# Polygons are relative to the painted cell's centre; its top-left corner is at -TILE / 2.
	var corner := -TILE / 2.0
	var full := _box(corner, corner, art, art)
	var ledge := _box(corner, corner, art / 2.0, art)
	for tile: Array in [
		[BLOCK_SOLID_TILE, Room.Kind.SOLID, WORLD_PHYSICS, full],
		[BLOCK_DEATH_TILE, Room.Kind.DEATH, HAZARD_PHYSICS, full],
		[BLOCK_LEDGE_TILE, Room.Kind.SOLID, WORLD_PHYSICS, ledge],
	]:
		source.create_tile(tile[0])
		var data := source.get_tile_data(tile[0], 0)
		data.texture_origin = -Vector2i.ONE * (art - int(TILE)) / 2
		data.set_custom_data(Room.KIND_DATA, tile[1])
		data.add_collision_polygon(tile[2])
		data.set_collision_polygon_points(tile[2], 0, tile[3])
	return tile_set


static func _box(left: float, top: float, width: float, height: float) -> PackedVector2Array:
	return PackedVector2Array([Vector2(left, top), Vector2(left + width, top), Vector2(left + width, top + height), Vector2(left, top + height)])


static func spawn_player(parent: Node, room: Room, scene: PackedScene, feet: Vector2) -> PlayerBody:
	var player := scene.instantiate() as PlayerBody
	player.room = room
	parent.add_child(player)
	room.use_surfaces(player.uses_grapple_surfaces, player.uses_pogo_surfaces)
	player.respawn(feet)
	return player


## Add props before spawning the player, so `use_surfaces` sees them.
static func add_prop(parent: Node, scene: PackedScene, center: Vector2, size: Vector2, surface := Room.Kind.SOLID) -> TileProp:
	var prop := scene.instantiate() as TileProp
	prop.position = center
	prop.size = size
	prop.surface = surface
	parent.add_child(prop)
	return prop


## `setup` runs before the actor enters the tree, so its reset sees the values.
static func add_actor(parent: Node, scene: PackedScene, center: Vector2, setup := Callable()) -> RoomActor:
	var actor := scene.instantiate() as RoomActor
	actor.position = center
	if setup.is_valid():
		setup.call(actor)
	parent.add_child(actor)
	return actor


static func paint_row(layer: TileMapLayer, row: int, from_x: int, to_x: int, atlas: Vector2i) -> void:
	for x in range(from_x, to_x + 1):
		layer.set_cell(Vector2i(x, row), 0, atlas)


static func paint_column(layer: TileMapLayer, column: int, from_y: int, to_y: int, atlas: Vector2i) -> void:
	for y in range(from_y, to_y + 1):
		layer.set_cell(Vector2i(column, y), 0, atlas)
