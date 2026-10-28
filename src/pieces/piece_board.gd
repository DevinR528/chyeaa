class_name PieceBoard
extends RefCounted
## Editable piece. The node tree matches an imported piece scene. Kind cells stay
## on kind tiles; biome art is applied later, when a room is built.

enum Stamp {
	BLOCK,
	WINDMILL,
	MOVING_PLATFORM,
	BREAKABLE,
	GATE,
	FALL_BLOCK,
	SWITCH,
	WALKER,
	THROWABLE,
}

enum PortalEnd {
	ENTRY,
	EXIT,
}

const TILE := MovementStats.TILE
const KIND_TILES := preload("res://resources/tiles/kind_tiles.tres")
const MAX_BRUSH := 64
const BLOCK_SCENE := preload("res://scenes/props/block.tscn")
const WINDMILL_SCENE := preload("res://scenes/props/windmill.tscn")
const MOVING_SCENE := preload("res://scenes/props/moving_platform.tscn")
const BREAKABLE_SCENE := preload("res://scenes/props/breakable.tscn")
const GATE_SCENE := preload("res://scenes/props/gate.tscn")
const FALL_SCENE := preload("res://scenes/props/fall_block.tscn")
const SWITCH_SCENE := preload("res://scenes/props/switch.tscn")
const WALKER_SCENE := preload("res://scenes/actors/walker.tscn")
const THROWABLE_SCENE := preload("res://scenes/actors/throwable.tscn")

const _SCENES := {
	Stamp.BLOCK: BLOCK_SCENE,
	Stamp.WINDMILL: WINDMILL_SCENE,
	Stamp.MOVING_PLATFORM: MOVING_SCENE,
	Stamp.BREAKABLE: BREAKABLE_SCENE,
	Stamp.GATE: GATE_SCENE,
	Stamp.FALL_BLOCK: FALL_SCENE,
	Stamp.SWITCH: SWITCH_SCENE,
	Stamp.WALKER: WALKER_SCENE,
	Stamp.THROWABLE: THROWABLE_SCENE,
}

var root: Node2D
var piece_id := &"new_piece"
## Id this board was opened as. Empty until a library piece is opened or saved.
var opened_id := &""
var cols := 32
var rows := 24
var difficulty := 1
var unique := false
var tags: Array[StringName] = []
var entry_a := Vector2i.ZERO
var entry_b := Vector2i.ZERO
var entry_facing := PieceData.Facing.LEFT
var exit_a := Vector2i.ZERO
var exit_b := Vector2i.ZERO
var exit_facing := PieceData.Facing.RIGHT
var spawn_feet := Vector2.ZERO
## Square brush edge, in cells. Paint and erase share it. The cell passed to
## `paint_cell` is the brush's top-left corner.
var brush_size := 8
var paint_kind := Room.Kind.SOLID
var selected: Node


static func blank(id: StringName, next_cols := 32, next_rows := 24) -> PieceBoard:
	var board := PieceBoard.new()
	board.piece_id = id
	board.cols = maxi(next_cols, RoomGenerator.MIN_APERTURE_W)
	board.rows = maxi(next_rows, RoomGenerator.MIN_APERTURE_H)
	board.root = board._make_root(id)
	board._default_portals()
	board._sync_markers()
	board._sync_spawn()
	return board


static func from_data(data: PieceData) -> PieceBoard:
	var board := PieceBoard.new()
	board.root = data.scene.instantiate() as Node2D
	board.piece_id = data.piece_id
	board.opened_id = data.piece_id
	board.cols = data.cols
	board.rows = data.rows
	board.difficulty = data.difficulty
	board.unique = data.unique
	board.tags = data.tags.duplicate()
	board.entry_a = data.entry_a
	board.entry_b = data.entry_b
	board.entry_facing = data.entry_facing
	board.exit_a = data.exit_a
	board.exit_b = data.exit_b
	board.exit_facing = data.exit_facing
	board.spawn_feet = data.spawn_feet
	board._sync_markers()
	board._sync_spawn()
	return board


func step_brush(delta: int) -> void:
	brush_size = clampi(brush_size + delta, 1, MAX_BRUSH)


## Paints or erases a `brush_size` square whose top-left is `cell`. Cells outside
## the piece are skipped.
func paint_cell(cell: Vector2i, erase := false) -> void:
	var bounds := Rect2i(Vector2i.ZERO, Vector2i(cols, rows))
	for y in brush_size:
		for x in brush_size:
			var at := cell + Vector2i(x, y)
			if bounds.has_point(at):
				_paint_one(at, erase)


func place_prefab(stamp: Stamp, at: Vector2) -> Node2D:
	var packed: PackedScene = _SCENES[stamp]
	var node := packed.instantiate() as Node2D
	var parent := root.get_node(^"Actors" if stamp == Stamp.WALKER or stamp == Stamp.THROWABLE else ^"Props")
	node.name = _unique_name(parent, String(node.name))
	node.position = at
	parent.add_child(node)
	if stamp == Stamp.WINDMILL and node is TileProp:
		var arm := BLOCK_SCENE.instantiate() as Node2D
		arm.name = &"Arm"
		arm.position = Vector2.ZERO
		if arm is TileProp:
			(arm as TileProp).size = Vector2(16, 16)
		node.add_child(arm)
	selected = node
	return node


## Slider write. `property` is one of the tuning rows for this node.
func set_tuned_value(node: Node, property: StringName, value: float) -> bool:
	if node == null:
		return false
	if property == &"size_x" or property == &"size_y":
		if not ("size" in node):
			return false
		var size: Vector2 = node.get(&"size")
		if property == &"size_x":
			size.x = value
		else:
			size.y = value
		node.set(&"size", size)
		return true
	var spin := _spin(node)
	if spin != null and property in [&"radius", &"turns_per_second", &"start_turn"]:
		spin.set(property, value)
		return true
	if property == &"travel":
		var motion := _oscillation(node)
		if motion == null:
			return false
		motion.travel = value
		return true
	if property == &"speed":
		if node is Walker:
			(node as Walker).speed = value
			return true
		var motion := _oscillation(node)
		if motion != null:
			motion.speed = value
			return true
		var path := _path(node)
		if path == null:
			return false
		path.speed = value
		return true
	return false


func tuning_rows(node: Node) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	if node != null and "size" in node:
		var size: Vector2 = node.get(&"size")
		rows.append(_row(&"Width", &"size_x", size.x, 8.0, 256.0, 8.0))
		rows.append(_row(&"Height", &"size_y", size.y, 8.0, 256.0, 8.0))
	var spin := _spin(node)
	if spin != null:
		rows.append(_row(&"Radius", &"radius", spin.radius, 8.0, 256.0, 1.0))
		rows.append(_row(&"Turns / s", &"turns_per_second", spin.turns_per_second, -2.0, 2.0, 0.05))
		rows.append(_row(&"Start turn", &"start_turn", spin.start_turn, 0.0, 1.0, 0.05))
	var motion := _oscillation(node)
	if motion != null:
		rows.append(_row(&"Travel", &"travel", motion.travel, 8.0, 256.0, 1.0))
		rows.append(_row(&"Speed", &"speed", motion.speed, 0.0, 8.0, 0.05))
	elif node is Walker:
		rows.append(_row(&"Speed", &"speed", (node as Walker).speed, 0.0, 400.0, 1.0))
	else:
		var path := _path(node)
		if path != null:
			rows.append(_row(&"Path speed", &"speed", path.speed, 0.0, 400.0, 1.0))
	return rows


## Both ends must share an outer edge, and the opening must fit the player.
## A rejected portal leaves the previous one in place.
func set_portal(which: PortalEnd, a: Vector2i, b: Vector2i) -> bool:
	var facing := portal_facing(a, b)
	if facing < 0:
		return false
	if which == PortalEnd.ENTRY:
		entry_a = a
		entry_b = b
		entry_facing = facing as PieceData.Facing
	else:
		exit_a = a
		exit_b = b
		exit_facing = facing as PieceData.Facing
	_sync_markers()
	return true


func portal_facing(a: Vector2i, b: Vector2i) -> int:
	var bounds := Rect2i(Vector2i.ZERO, Vector2i(cols, rows))
	if not bounds.has_point(a) or not bounds.has_point(b):
		return -1
	if a.x == b.x and a.y != b.y:
		if absi(a.y - b.y) + 1 < RoomGenerator.MIN_APERTURE_H:
			return -1
		if a.x == 0:
			return PieceData.Facing.LEFT
		if a.x == cols - 1:
			return PieceData.Facing.RIGHT
		return -1
	if a.y == b.y and a.x != b.x:
		if absi(a.x - b.x) + 1 < RoomGenerator.MIN_APERTURE_W:
			return -1
		if a.y == 0:
			return PieceData.Facing.UP
		if a.y == rows - 1:
			return PieceData.Facing.DOWN
	return -1


## Snaps a drag to the nearer outer edge along its longer axis.
func snap_segment(from: Vector2i, to: Vector2i) -> Dictionary:
	var vertical := absi(to.y - from.y) >= absi(to.x - from.x)
	if vertical:
		var x := 0 if from.x + to.x < cols else cols - 1
		var y0 := clampi(mini(from.y, to.y), 0, rows - 1)
		var y1 := clampi(maxi(from.y, to.y), 0, rows - 1)
		return {"a": Vector2i(x, y0), "b": Vector2i(x, y1)}
	var y := 0 if from.y + to.y < rows else rows - 1
	var x0 := clampi(mini(from.x, to.x), 0, cols - 1)
	var x1 := clampi(maxi(from.x, to.x), 0, cols - 1)
	return {"a": Vector2i(x0, y), "b": Vector2i(x1, y)}


func set_spawn(feet: Vector2) -> void:
	var limit := Vector2(cols, rows) * TILE
	spawn_feet = Vector2(clampf(feet.x, 0.0, limit.x), clampf(feet.y, 0.0, limit.y))
	_sync_spawn()


func set_size(next_cols: int, next_rows: int) -> bool:
	if next_cols < RoomGenerator.MIN_APERTURE_W or next_rows < RoomGenerator.MIN_APERTURE_H:
		return false
	var old_cols := cols
	var old_rows := rows
	var old_entry_a := entry_a
	var old_entry_b := entry_b
	var old_exit_a := exit_a
	var old_exit_b := exit_b
	cols = next_cols
	rows = next_rows
	_clamp_portal(PortalEnd.ENTRY)
	_clamp_portal(PortalEnd.EXIT)
	if portal_facing(entry_a, entry_b) < 0 or portal_facing(exit_a, exit_b) < 0:
		cols = old_cols
		rows = old_rows
		entry_a = old_entry_a
		entry_b = old_entry_b
		exit_a = old_exit_a
		exit_b = old_exit_b
		_sync_markers()
		return false
	_erase_outside()
	_sync_markers()
	return true


func set_tag(tag: StringName, enabled: bool) -> void:
	if enabled and not tags.has(tag):
		tags.append(tag)
	elif not enabled and tags.has(tag):
		tags.erase(tag)


func pick(global_point: Vector2) -> Node:
	selected = _find_placed(global_point)
	return selected


## Drops the selected prop or actor. Returns its name, or "" when nothing can be removed.
func remove_selected() -> String:
	if selected == null or not is_instance_valid(selected):
		selected = null
		return ""
	var parent := selected.get_parent()
	if parent == null or (StringName(parent.name) != &"Props" and StringName(parent.name) != &"Actors"):
		return ""
	var label := String(selected.name)
	var node := selected
	selected = null
	node.free()
	return label


## Removes the placed object under the point, without clearing the selection on a miss.
func remove_at(global_point: Vector2) -> String:
	var hit := _find_placed(global_point)
	if hit == null:
		return ""
	selected = hit
	return remove_selected()


func _find_placed(global_point: Vector2) -> Node:
	var found: Node = null
	for parent_name in [&"Props", &"Actors"]:
		for child in root.get_node(NodePath(parent_name)).get_children():
			if child is Node2D and _hits(child as Node2D, global_point):
				found = child
	return found


func duplicate_board() -> PieceBoard:
	var copy := from_data(to_piece_data())
	var next := String(piece_id) + "_copy"
	copy.piece_id = StringName(next)
	copy.opened_id = &""
	return copy


func to_piece_data() -> PieceData:
	var data := PieceData.new()
	_fill(data)
	data.scene = pack_root(root)
	return data


static func pack_root(node: Node) -> PackedScene:
	if node == null:
		return null
	_flatten(node, node)
	var packed := PackedScene.new()
	if packed.pack(node) != OK:
		return null
	return packed


func play_layout() -> Dictionary:
	var data := to_piece_data()
	var flex: Array[Vector3i] = []
	return {
		"id": &"piece_play",
		"placed": [{"piece": data, "ox": 0, "oy": 0}],
		"flex_runs": flex,
		"cols": cols,
		"rows": rows,
		"spawn_feet": spawn_feet,
	}


func _fill(data: PieceData) -> void:
	data.piece_id = piece_id
	data.cols = cols
	data.rows = rows
	data.difficulty = clampi(difficulty, 1, 10)
	data.unique = unique
	data.tags = tags.duplicate()
	data.entry_a = entry_a
	data.entry_b = entry_b
	data.entry_facing = entry_facing
	data.exit_a = exit_a
	data.exit_b = exit_b
	data.exit_facing = exit_facing
	data.spawn_feet = spawn_feet
	data.authored_in_editor = true
	data.source_hash = "editor"


func _make_root(id: StringName) -> Node2D:
	var node := Node2D.new()
	node.name = StringName(String(id).to_pascal_case())
	for layer_name in [&"Terrain", &"BlockTerrain", &"GrappleSurfaces", &"PogoSurfaces"]:
		var layer := TileMapLayer.new()
		layer.name = layer_name
		layer.tile_set = KIND_TILES
		node.add_child(layer)
		layer.owner = node
	var spawn := Marker2D.new()
	spawn.name = &"Spawn"
	node.add_child(spawn)
	spawn.owner = node
	for portal_name in [&"EntryPortal", &"ExitPortal"]:
		var group := Node2D.new()
		group.name = portal_name
		node.add_child(group)
		group.owner = node
		for marker_name in [&"A", &"B"]:
			var marker := Marker2D.new()
			marker.name = marker_name
			group.add_child(marker)
			marker.owner = node
	for folder_name in [&"Props", &"Actors"]:
		var folder := Node2D.new()
		folder.name = folder_name
		node.add_child(folder)
		folder.owner = node
	return node


func _default_portals() -> void:
	var span := RoomGenerator.MIN_APERTURE_H
	var y := mini(8, rows - span)
	entry_a = Vector2i(0, y)
	entry_b = Vector2i(0, y + span - 1)
	entry_facing = PieceData.Facing.LEFT
	exit_a = Vector2i(cols - 1, y)
	exit_b = Vector2i(cols - 1, y + span - 1)
	exit_facing = PieceData.Facing.RIGHT
	spawn_feet = Vector2(TILE * 4, TILE * (y + 2))


func _paint_one(cell: Vector2i, erase: bool) -> void:
	for layer_name in [&"Terrain", &"GrappleSurfaces", &"PogoSurfaces"]:
		(root.get_node(NodePath(layer_name)) as TileMapLayer).erase_cell(cell)
	if erase or paint_kind == Room.Kind.EMPTY:
		return
	var layer := root.get_node(^"Terrain") as TileMapLayer
	var atlas := Vector2i.ZERO
	match paint_kind:
		Room.Kind.SOLID:
			atlas = Vector2i(0, 0)
		Room.Kind.GRAPPLE:
			layer = root.get_node(^"GrappleSurfaces") as TileMapLayer
			atlas = Vector2i(1, 0)
		Room.Kind.EXIT:
			atlas = Vector2i(3, 0)
		Room.Kind.DEATH:
			atlas = Vector2i(4, 0)
		Room.Kind.POGO:
			layer = root.get_node(^"PogoSurfaces") as TileMapLayer
			atlas = Vector2i(5, 0)
		_:
			return
	layer.set_cell(cell, 0, atlas)


func _clamp_portal(which: PortalEnd) -> void:
	var a := entry_a if which == PortalEnd.ENTRY else exit_a
	var b := entry_b if which == PortalEnd.ENTRY else exit_b
	var facing := entry_facing if which == PortalEnd.ENTRY else exit_facing
	match facing:
		PieceData.Facing.LEFT:
			a.x = 0
			b.x = 0
			a.y = clampi(a.y, 0, rows - 1)
			b.y = clampi(b.y, 0, rows - 1)
		PieceData.Facing.RIGHT:
			a.x = cols - 1
			b.x = cols - 1
			a.y = clampi(a.y, 0, rows - 1)
			b.y = clampi(b.y, 0, rows - 1)
		PieceData.Facing.UP:
			a.y = 0
			b.y = 0
			a.x = clampi(a.x, 0, cols - 1)
			b.x = clampi(b.x, 0, cols - 1)
		PieceData.Facing.DOWN:
			a.y = rows - 1
			b.y = rows - 1
			a.x = clampi(a.x, 0, cols - 1)
			b.x = clampi(b.x, 0, cols - 1)
	if which == PortalEnd.ENTRY:
		entry_a = a
		entry_b = b
	else:
		exit_a = a
		exit_b = b


func _erase_outside() -> void:
	for layer_name in [&"Terrain", &"GrappleSurfaces", &"PogoSurfaces"]:
		var layer := root.get_node(NodePath(layer_name)) as TileMapLayer
		for cell in layer.get_used_cells():
			if cell.x >= cols or cell.y >= rows:
				layer.erase_cell(cell)


func _sync_markers() -> void:
	_place_marker(&"EntryPortal", entry_a, entry_b)
	_place_marker(&"ExitPortal", exit_a, exit_b)


func _place_marker(portal_name: StringName, a: Vector2i, b: Vector2i) -> void:
	var group := root.get_node(NodePath(portal_name)) as Node2D
	(group.get_node(^"A") as Node2D).position = (Vector2(a) + Vector2(0.5, 0.5)) * TILE
	(group.get_node(^"B") as Node2D).position = (Vector2(b) + Vector2(0.5, 0.5)) * TILE


func _sync_spawn() -> void:
	(root.get_node(^"Spawn") as Node2D).position = spawn_feet


func _unique_name(parent: Node, base: String) -> String:
	if not parent.has_node(base):
		return base
	var index := 2
	while parent.has_node("%s%d" % [base, index]):
		index += 1
	return "%s%d" % [base, index]


func _hits(node: Node2D, global_point: Vector2) -> bool:
	if _contains(node, global_point):
		return true
	for child in node.get_children():
		if child is Node2D and _hits(child as Node2D, global_point):
			return true
	return false


func _contains(node: Node2D, global_point: Vector2) -> bool:
	var size := Vector2(32, 32)
	if "size" in node:
		size = node.get(&"size")
	size = size.max(Vector2(32, 32))
	if Rect2(node.global_position - size * 0.5, size).has_point(global_point):
		return true
	var spin := _spin(node)
	return spin != null and global_point.distance_to(node.global_position) <= spin.radius


func _spin(node: Node) -> SpinMotion:
	if node is TileProp and (node as TileProp).spin != null:
		return (node as TileProp).spin
	if node == null:
		return null
	return node.get_node_or_null(^"SpinMotion") as SpinMotion


func _oscillation(node: Node) -> OscillatingMotion:
	if node is TileProp and (node as TileProp).oscillation != null:
		return (node as TileProp).oscillation
	if node == null:
		return null
	return node.get_node_or_null(^"OscillatingMotion") as OscillatingMotion


func _path(node: Node) -> PathMotion:
	if node is TileProp and (node as TileProp).path != null:
		return (node as TileProp).path
	if node == null:
		return null
	return node.get_node_or_null(^"PathMotion") as PathMotion


static func _flatten(node: Node, owner_root: Node) -> void:
	node.scene_file_path = ""
	if node != owner_root:
		node.owner = owner_root
	for child in node.get_children():
		_flatten(child, owner_root)


func _row(label: String, property: StringName, value: float, minimum: float, maximum: float, step: float) -> Dictionary:
	return {
		"label": label,
		"property": property,
		"value": value,
		"min": minimum,
		"max": maximum,
		"step": step,
	}
