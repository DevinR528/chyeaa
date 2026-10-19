extends SceneTree
## Repeatable standalone import from the JavaScript piece editor's JSON.
##
## Run from the repo root:
##   godot --headless --path . --script res://src/tools/import_pieces.gd

const SOURCE_DIR := "../idea/assets/pieces"
const INDEX_FILE := "index.json"
const SCENE_DIR := "res://scenes/pieces"
const RESOURCE_DIR := "res://resources/pieces"
const LIBRARY_PATH := RESOURCE_DIR + "/library.tres"
const KIND_TILES := preload("res://resources/tiles/kind_tiles.tres")
const TILE := MovementStats.TILE
const BODY_TOP_LEFT_TO_FEET := Vector2(10.0, 28.0)
const IMPORT_VERSION := 1


func _initialize() -> void:
	quit(_import())


func _import() -> int:
	var index := _read_json(_source_path(INDEX_FILE))
	if index.is_empty() or not index.get("pieces", null) is Array:
		push_error("%s must contain a pieces array" % _source_path(INDEX_FILE))
		return 1
	var documents: Array[Dictionary] = []
	for entry: Dictionary in index.pieces:
		var id := String(entry.get("id", ""))
		var source := _source_path(id + ".json")
		var document := _read_json(source)
		if not _validate(document, source):
			return 1
		document["_import_hash"] = "%d:%s" % [IMPORT_VERSION, FileAccess.get_sha256(source)]
		documents.append(document)

	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SCENE_DIR))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(RESOURCE_DIR))
	var imported: Array[PieceData] = []
	for document in documents:
		var data := _write_piece(document)
		if data == null:
			return 1
		imported.append(data)
	var library := PieceLibrary.new()
	library.pieces = imported
	if ResourceSaver.save(library, LIBRARY_PATH) != OK:
		push_error("Could not save %s" % LIBRARY_PATH)
		return 1
	print("Imported %d JavaScript pieces into %s." % [imported.size(), SCENE_DIR])
	return 0


func _write_piece(document: Dictionary) -> PieceData:
	var id := String(document.id)
	var scene_path := SCENE_DIR.path_join(id + ".tscn")
	var resource_path := RESOURCE_DIR.path_join(id + ".tres")
	if ResourceLoader.exists(resource_path):
		var existing := load(resource_path) as PieceData
		if (
			existing != null
			and existing.source_hash == String(document._import_hash)
			and ResourceLoader.exists(scene_path)
		):
			return existing
	var root := Node2D.new()
	root.name = StringName(id.to_pascal_case())
	var terrain := _add_layer(root, &"Terrain")
	_add_layer(root, &"BlockTerrain")
	var grapple := _add_layer(root, &"GrappleSurfaces")
	var pogo := _add_layer(root, &"PogoSurfaces")
	var cells := _expand_runs(document)
	for cell: Vector2i in cells:
		var stack: Array = cells[cell]
		if not _stack_supported(stack):
			push_error("%s: unsupported tile stack at %s: %s" % [id, cell, stack])
			root.free()
			return null
		for entry: Dictionary in stack:
			var atlas := _atlas_for(entry.kind, entry.flag)
			if atlas.x < 0:
				push_error("%s: unsupported tile kind/flag at %s: %s" % [id, cell, entry])
				root.free()
				return null
			var target := terrain
			if entry.kind == Room.Kind.GRAPPLE:
				target = grapple
			elif entry.kind == Room.Kind.POGO:
				target = pogo
			target.set_cell(cell, 0, atlas)

	var spawn_feet := Vector2(document.spawn.x, document.spawn.y) + BODY_TOP_LEFT_TO_FEET
	var spawn := Marker2D.new()
	spawn.name = &"Spawn"
	spawn.position = spawn_feet
	root.add_child(spawn)
	spawn.owner = root
	_add_portal_markers(root, &"EntryPortal", document.entry)
	_add_portal_markers(root, &"ExitPortal", document.exit)
	var props := Node2D.new()
	props.name = &"Props"
	root.add_child(props)
	props.owner = root
	var actors := Node2D.new()
	actors.name = &"Actors"
	root.add_child(actors)
	actors.owner = root
	for entity: Dictionary in document.get("entities", []):
		if not PieceEntityImport.add_root(entity, props, actors, root):
			root.free()
			return null

	var packed := PackedScene.new()
	if packed.pack(root) != OK:
		push_error("Could not pack %s" % scene_path)
		root.free()
		return null
	root.free()
	var old_uid := ResourceLoader.get_resource_uid(scene_path)
	if ResourceSaver.save(packed, scene_path) != OK:
		push_error("Could not save %s" % scene_path)
		return null
	if old_uid != ResourceUID.INVALID_ID:
		ResourceSaver.set_uid(scene_path, old_uid)

	var data := PieceData.new()
	data.piece_id = StringName(id)
	data.source_hash = String(document._import_hash)
	data.cols = int(document.cols)
	data.rows = int(document.rows)
	data.difficulty = int(document.get("difficulty", 1))
	for tag in document.get("tags", []):
		data.tags.append(StringName(tag))
	data.unique = bool(document.get("unique", false))
	data.entry_a = _point(document.entry.a)
	data.entry_b = _point(document.entry.b)
	data.entry_facing = _facing(document.entry.facing)
	data.exit_a = _point(document.exit.a)
	data.exit_b = _point(document.exit.b)
	data.exit_facing = _facing(document.exit.facing)
	data.spawn_feet = spawn_feet
	data.scene = load(scene_path)
	if ResourceSaver.save(data, resource_path) != OK:
		push_error("Could not save %s" % resource_path)
		return null
	return load(resource_path) as PieceData


func _validate(document: Dictionary, source: String) -> bool:
	for key in ["id", "cols", "rows", "entry", "exit", "spawn", "layers", "entities"]:
		if not document.has(key):
			push_error("%s: missing %s" % [source, key])
			return false
	if int(document.cols) <= 0 or int(document.rows) <= 0:
		push_error("%s: cols and rows must be positive" % source)
		return false
	for portal_name in ["entry", "exit"]:
		var portal: Dictionary = document[portal_name]
		if not portal.has("a") or not portal.has("b") or not portal.has("facing"):
			push_error("%s: invalid %s portal" % [source, portal_name])
			return false
		if not _portal_valid(portal, int(document.cols), int(document.rows)):
			push_error("%s: %s portal is outside the piece or its axis does not match its facing" % [source, portal_name])
			return false
	return true


func _portal_valid(portal: Dictionary, cols: int, rows: int) -> bool:
	var a := _point(portal.a)
	var b := _point(portal.b)
	var bounds := Rect2i(Vector2i.ZERO, Vector2i(cols, rows))
	if not bounds.has_point(a) or not bounds.has_point(b):
		return false
	match String(portal.facing):
		"left", "right":
			return a.x == b.x
		"up", "down":
			return a.y == b.y
	return false


func _expand_runs(document: Dictionary) -> Dictionary:
	var ordered: Array[Dictionary] = []
	for layer: Dictionary in document.layers:
		for run: Array in layer.get("runs", []):
			if run.size() < 4:
				continue
			ordered.append({
				"order": ordered.size(),
				"row": int(run[0]),
				"x0": int(run[1]),
				"x1": int(run[2]),
				"kind": int(run[3]),
				"z": _optional_int(run, 4),
				"flag": _optional_int(run, 5),
			})
	ordered.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return a.z < b.z or (a.z == b.z and a.order < b.order)
	)
	var cells := {}
	for run in ordered:
		if run.row < 0 or run.row >= int(document.rows):
			continue
		for x in range(maxi(0, run.x0), mini(int(document.cols) - 1, run.x1) + 1):
			var cell := Vector2i(x, run.row)
			var stack: Array = cells.get(cell, [])
			var existing := stack.find_custom(func(entry: Dictionary) -> bool: return entry.z == run.z)
			if run.kind == Room.Kind.EMPTY:
				if existing >= 0:
					stack.remove_at(existing)
			elif existing >= 0:
				stack[existing] = {"kind": run.kind, "z": run.z, "flag": run.flag}
			else:
				stack.append({"kind": run.kind, "z": run.z, "flag": run.flag})
				stack.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.z < b.z)
			if stack.is_empty():
				cells.erase(cell)
			else:
				cells[cell] = stack
	return cells


func _stack_supported(stack: Array) -> bool:
	if stack.size() <= 1:
		return true
	var top: Dictionary = stack.back()
	if top.kind != Room.Kind.GRAPPLE or top.flag == 2:
		return false
	for index in stack.size() - 1:
		var lower: Dictionary = stack[index]
		if lower.kind != Room.Kind.SOLID or lower.flag != 0:
			return false
	return true


func _atlas_for(kind: int, flag: int) -> Vector2i:
	var default_solid := kind == Room.Kind.SOLID or kind == Room.Kind.GRAPPLE
	var solid := default_solid if flag == 0 else flag == 1
	match kind:
		Room.Kind.SOLID:
			return Vector2i(0, 0) if solid else Vector2i(-1, -1)
		Room.Kind.GRAPPLE:
			return Vector2i(1 if solid else 2, 0)
		Room.Kind.EXIT:
			return Vector2i(3, 0)
		Room.Kind.DEATH:
			return Vector2i(4, 0)
		Room.Kind.POGO:
			return Vector2i(5, 0)
	return Vector2i(-1, -1)


func _add_layer(root: Node2D, layer_name: StringName) -> TileMapLayer:
	var layer := TileMapLayer.new()
	layer.name = layer_name
	layer.tile_set = KIND_TILES
	root.add_child(layer)
	layer.owner = root
	return layer


func _add_portal_markers(root: Node2D, portal_name: StringName, portal: Dictionary) -> void:
	var group := Node2D.new()
	group.name = portal_name
	root.add_child(group)
	group.owner = root
	for marker_data in [[&"A", portal.a], [&"B", portal.b]]:
		var marker := Marker2D.new()
		marker.name = marker_data[0]
		marker.position = Vector2(_point(marker_data[1])) * TILE + Vector2.ONE * TILE / 2.0
		group.add_child(marker)
		marker.owner = root


func _optional_int(run: Array, index: int) -> int:
	return 0 if run.size() <= index or run[index] == null else int(run[index])


func _point(value: Dictionary) -> Vector2i:
	return Vector2i(roundi(float(value.x)), roundi(float(value.y)))


func _facing(value: String) -> PieceData.Facing:
	match value:
		"right":
			return PieceData.Facing.RIGHT
		"up":
			return PieceData.Facing.UP
		"down":
			return PieceData.Facing.DOWN
	return PieceData.Facing.LEFT


func _read_json(path: String) -> Dictionary:
	var text := FileAccess.get_file_as_string(path)
	var parsed: Variant = JSON.parse_string(text)
	if not parsed is Dictionary:
		push_error("%s is not valid JSON object" % path)
		return {}
	return parsed


func _source_path(file_name: String) -> String:
	return ProjectSettings.globalize_path("res://").path_join(SOURCE_DIR).path_join(file_name)
