extends SceneTree
## One-time import of the prototype demo room. After this, the room is authored in
## Godot; re-running overwrites scenes/rooms/demo.tscn and the kind TileSet.
## Entities and decorative stamps are not imported yet.
##
## Run from lil-guy/:
##   godot --headless --path . --script res://src/tools/import_demo_room.gd
## The first run paints the kind tile PNG; run `godot --headless --path . --import`
## so Godot imports it, then run this script again.

const RoomScript := preload("res://src/rooms/room.gd")
const Kind := RoomScript.Kind

const SOURCE_JSON := "../assets/levels/demo.json"
const KIND_TILES_PNG := "res://assets/tiles/kind_tiles.png"
const TILE_SET_PATH := "res://resources/tiles/kind_tiles.tres"
const ROOM_SCENE_PATH := "res://scenes/rooms/demo.tscn"
const TILE := 8

## Prototype run flag (6th run field): 1 forces solid, 2 forces pass-through.
const FLAG_NONE := 0
const FLAG_SOLID := 1
const FLAG_SOFT := 2

## The prototype spawn is the top-left of the Standard body (20x28); rooms store feet.
const PROTOTYPE_BODY_SIZE := Vector2(20, 28)

## Atlas column order of the kind tiles. Prototype fill colours; soft tiles are
## drawn faint with a dashed rim like the prototype's pass-through surfaces.
## `physics` is the TileSet physics layer the tile's square is on (-1 for none).
const TILE_STYLES: Array[Dictionary] = [
	{ "kind": Kind.SOLID, "solid": true, "physics": 0, "color": Color("#3d5a45") },
	{ "kind": Kind.GRAPPLE, "solid": true, "physics": 0, "color": Color("#c45a1a") },
	{ "kind": Kind.GRAPPLE, "solid": false, "physics": -1, "color": Color("#c45a1a") },
	{ "kind": Kind.EXIT, "solid": false, "physics": 2, "color": Color("#1a6b3a") },
	{ "kind": Kind.DEATH, "solid": false, "physics": 1, "color": Color("#6b1a1a") },
	{ "kind": Kind.POGO, "solid": false, "physics": -1, "color": Color("#5a2a6b") },
]
## Collision layer of each TileSet physics layer, by index.
const TILE_PHYSICS_LAYERS: Array[int] = [PhysicsLayers.WORLD, PhysicsLayers.HAZARD, PhysicsLayers.EXIT]
const SOFT_FILL_ALPHA := 0.18
const SOFT_RIM_ALPHA := 0.85


func _initialize() -> void:
	quit(_import())


func _import() -> int:
	if not ResourceLoader.exists(KIND_TILES_PNG):
		_paint_kind_tiles()
		print("Painted %s. Run `--import`, then run this script again." % KIND_TILES_PNG)
		return 2

	var doc := _read_room_json()
	if doc.is_empty():
		return 1
	var cols := int(doc.cols)
	var rows := int(doc.rows)
	var cells := _expand_runs(doc, cols, rows)
	if bool(doc.get("auto_border", true)):
		_fill_border(cells, cols, rows)

	var tile_set := _build_tile_set()
	var room := Node2D.new()
	room.name = "Demo"
	room.set_script(RoomScript)
	var terrain := _add_layer(room, "Terrain", tile_set)
	var grapple_surfaces := _add_layer(room, "GrappleSurfaces", tile_set)
	var pogo_surfaces := _add_layer(room, "PogoSurfaces", tile_set)
	var layers := {
		Kind.SOLID: terrain,
		Kind.EXIT: terrain,
		Kind.DEATH: terrain,
		Kind.GRAPPLE: grapple_surfaces,
		Kind.POGO: pogo_surfaces,
	}

	for cell: Vector2i in cells:
		var stack: Array = cells[cell]
		if not _stack_survives_layering(stack):
			push_error("Unsupported tile stack at %s: %s" % [cell, stack])
			return 1
		for entry: Dictionary in stack:
			var atlas := _atlas_for(entry.kind, entry.flag)
			if atlas == Vector2i(-1, -1):
				push_error("Unsupported tile at %s: %s" % [cell, entry])
				return 1
			(layers[entry.kind] as TileMapLayer).set_cell(cell, 0, atlas)

	var spawn := Marker2D.new()
	spawn.name = "Spawn"
	spawn.position = Vector2(doc.spawn.x, doc.spawn.y) + Vector2(PROTOTYPE_BODY_SIZE.x / 2.0, PROTOTYPE_BODY_SIZE.y)
	room.add_child(spawn)
	spawn.owner = room

	var summary := "Imported %dx%d demo room: terrain %d, grapple %d, pogo %d cells. Skipped %d entities and %d stamps." % [
		cols,
		rows,
		terrain.get_used_cells().size(),
		grapple_surfaces.get_used_cells().size(),
		pogo_surfaces.get_used_cells().size(),
		(doc.get("entities", []) as Array).size(),
		(doc.get("stamps", []) as Array).size(),
	]
	var packed := PackedScene.new()
	var pack_error := packed.pack(room)
	room.free()
	if pack_error != OK:
		push_error("Could not pack the demo room: %s" % error_string(pack_error))
		return 1
	_make_dir(ROOM_SCENE_PATH)
	var save_error := ResourceSaver.save(packed, ROOM_SCENE_PATH)
	if save_error != OK:
		push_error("Could not save %s: %s" % [ROOM_SCENE_PATH, error_string(save_error)])
		return 1

	print(summary)
	return 0


func _read_room_json() -> Dictionary:
	var path := ProjectSettings.globalize_path("res://").path_join(SOURCE_JSON)
	var text := FileAccess.get_file_as_string(path)
	if text.is_empty():
		push_error("Could not read %s" % path)
		return {}
	var parsed: Variant = JSON.parse_string(text)
	if not parsed is Dictionary:
		push_error("%s is not a room document" % path)
		return {}
	return parsed


## Prototype `apply_runs`: low z first, a later run at the same z replaces the
## entry, and an Empty run erases it. Each cell keeps a z-sorted stack.
func _expand_runs(doc: Dictionary, cols: int, rows: int) -> Dictionary:
	var runs: Array[Dictionary] = []
	for layer: Dictionary in doc.layers:
		for run: Array in layer.runs:
			runs.append({
				"order": runs.size(),
				"row": int(run[0]),
				"x0": int(run[1]),
				"x1": int(run[2]),
				"kind": int(run[3]),
				"z": _optional_int(run, 4),
				"flag": _optional_int(run, 5),
			})
	runs.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return a.z < b.z or (a.z == b.z and a.order < b.order))

	var cells := {}
	for run in runs:
		if run.row < 0 or run.row >= rows:
			continue
		for x in range(maxi(run.x0, 0), mini(run.x1, cols - 1) + 1):
			var cell := Vector2i(x, run.row)
			var stack: Array = cells.get(cell, [])
			var existing := stack.find_custom(func(entry: Dictionary) -> bool: return entry.z == run.z)
			if run.kind == Kind.EMPTY:
				if existing >= 0:
					stack.remove_at(existing)
			elif existing >= 0:
				stack[existing] = { "kind": run.kind, "z": run.z, "flag": run.flag }
			else:
				stack.append({ "kind": run.kind, "z": run.z, "flag": run.flag })
				stack.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.z < b.z)
			if stack.is_empty():
				cells.erase(cell)
			else:
				cells[cell] = stack
	return cells


func _optional_int(run: Array, index: int) -> int:
	if run.size() <= index or run[index] == null:
		return 0
	return int(run[index])


## Prototype `auto_border`: empty left, right, and bottom edge cells become solid.
func _fill_border(cells: Dictionary, cols: int, rows: int) -> void:
	for y in rows:
		for x in cols:
			var on_edge := y == rows - 1 or x == 0 or x == cols - 1
			var cell := Vector2i(x, y)
			if on_edge and not cells.has(cell):
				cells[cell] = [{ "kind": Kind.SOLID, "z": 0, "flag": FLAG_NONE }]


## In the prototype only the top of a stack interacts. Godot layers all collide at
## once, so the only stack that behaves the same is solid grapple over plain solid.
func _stack_survives_layering(stack: Array) -> bool:
	if stack.size() <= 1:
		return true
	var top: Dictionary = stack.back()
	if top.kind != Kind.GRAPPLE or top.flag == FLAG_SOFT:
		return false
	for index in stack.size() - 1:
		var lower: Dictionary = stack[index]
		if lower.kind != Kind.SOLID or lower.flag != FLAG_NONE:
			return false
	return true


## Returns (-1, -1) for kind/flag pairs the room format does not support.
func _atlas_for(kind: int, flag: int) -> Vector2i:
	for column in TILE_STYLES.size():
		var style: Dictionary = TILE_STYLES[column]
		if style.kind != kind:
			continue
		var default_solid := kind == Kind.SOLID or kind == Kind.GRAPPLE
		var solid := default_solid if flag == FLAG_NONE else flag == FLAG_SOLID
		if style.solid == solid:
			return Vector2i(column, 0)
	return Vector2i(-1, -1)


func _build_tile_set() -> TileSet:
	var tile_set := TileSet.new()
	tile_set.tile_size = Vector2i(TILE, TILE)
	for index in TILE_PHYSICS_LAYERS.size():
		tile_set.add_physics_layer()
		tile_set.set_physics_layer_collision_layer(index, TILE_PHYSICS_LAYERS[index])
		tile_set.set_physics_layer_collision_mask(index, 0)
	tile_set.add_custom_data_layer()
	tile_set.set_custom_data_layer_name(0, RoomScript.KIND_DATA)
	tile_set.set_custom_data_layer_type(0, TYPE_INT)

	var source := TileSetAtlasSource.new()
	source.texture = load(KIND_TILES_PNG)
	source.texture_region_size = Vector2i(TILE, TILE)
	tile_set.add_source(source, 0)

	var half := TILE / 2.0
	var square := PackedVector2Array([
		Vector2(-half, -half), Vector2(half, -half), Vector2(half, half), Vector2(-half, half),
	])
	for column in TILE_STYLES.size():
		var style: Dictionary = TILE_STYLES[column]
		var coords := Vector2i(column, 0)
		source.create_tile(coords)
		var data := source.get_tile_data(coords, 0)
		data.set_custom_data(RoomScript.KIND_DATA, style.kind)
		var physics_layer: int = style.physics
		if physics_layer >= 0:
			data.add_collision_polygon(physics_layer)
			data.set_collision_polygon_points(physics_layer, 0, square)

	_make_dir(TILE_SET_PATH)
	ResourceSaver.save(tile_set, TILE_SET_PATH)
	return load(TILE_SET_PATH)


func _add_layer(room: Node2D, layer_name: String, tile_set: TileSet) -> TileMapLayer:
	var layer := TileMapLayer.new()
	layer.name = layer_name
	layer.tile_set = tile_set
	room.add_child(layer)
	layer.owner = room
	return layer


func _paint_kind_tiles() -> void:
	var image := Image.create_empty(TILE * TILE_STYLES.size(), TILE, false, Image.FORMAT_RGBA8)
	for column in TILE_STYLES.size():
		var style: Dictionary = TILE_STYLES[column]
		var origin := Vector2i(column * TILE, 0)
		if style.solid:
			image.fill_rect(Rect2i(origin, Vector2i(TILE, TILE)), style.color)
		else:
			_paint_soft_tile(image, origin, style.color)
	_make_dir(KIND_TILES_PNG)
	image.save_png(ProjectSettings.globalize_path(KIND_TILES_PNG))


## Faint fill plus a 2-on 2-off dashed rim, restarting at each tile's top-left.
func _paint_soft_tile(image: Image, origin: Vector2i, color: Color) -> void:
	var fill := Color(color, SOFT_FILL_ALPHA)
	var rim := Color(color, SOFT_RIM_ALPHA)
	image.fill_rect(Rect2i(origin, Vector2i(TILE, TILE)), fill)
	for step in TILE:
		if step % 4 >= 2:
			continue
		image.set_pixelv(origin + Vector2i(step, 0), rim)
		image.set_pixelv(origin + Vector2i(step, TILE - 1), rim)
		image.set_pixelv(origin + Vector2i(0, step), rim)
		image.set_pixelv(origin + Vector2i(TILE - 1, step), rim)


func _make_dir(resource_path: String) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(resource_path.get_base_dir()))
