extends RefCounted
## Builds small rooms in code for headless tests: a floor, side walls, and
## whatever the test paints. Preload it; it has no class_name on purpose.

const KIND_TILES := preload("res://resources/tiles/kind_tiles.tres")
const ROOM_SCRIPT := preload("res://src/rooms/room.gd")

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
	for layer_name in [&"Terrain", &"GrappleSurfaces", &"PogoSurfaces"]:
		var layer := TileMapLayer.new()
		layer.name = layer_name
		layer.tile_set = KIND_TILES
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
