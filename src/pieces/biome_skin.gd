class_name BiomeSkin
extends Resource
## Art tiles applied when a room is built. Pieces keep kind cells; this pass
## replaces only the cells a rule can draw. Anything else stays on kind tiles.

@export var biome_id := &""
## Art tileset. Null, or an empty rule list, leaves the room on kind tiles.
@export var tileset: TileSet
@export var rules: Array[BiomeSkinRule] = []


func apply(room: Node) -> void:
	if room == null or tileset == null or rules.is_empty():
		return
	for rule in rules:
		if rule == null:
			continue
		var target := room.get_node_or_null(NodePath(str(rule.layer))) as TileMapLayer
		if target == null:
			continue
		if not _claim_tileset(target):
			continue
		for source_name in [&"Terrain", &"GrappleSurfaces", &"PogoSurfaces", &"BlockTerrain"]:
			var source := room.get_node_or_null(NodePath(source_name)) as TileMapLayer
			if source == null:
				continue
			for cell in source.get_used_cells():
				if _kind_at(source, cell) != rule.kind:
					continue
				target.set_cell(cell, 0, rule.atlas)
				if source != target:
					source.erase_cell(cell)


func _claim_tileset(target: TileMapLayer) -> bool:
	if target.tile_set == tileset:
		return true
	if not target.get_used_cells().is_empty():
		return false
	target.tile_set = tileset
	return true


func _kind_at(layer: TileMapLayer, cell: Vector2i) -> int:
	var data := layer.get_cell_tile_data(cell)
	if data == null:
		return Room.Kind.EMPTY
	var value: Variant = data.get_custom_data(Room.KIND_DATA)
	if value == null or not (typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT):
		return Room.Kind.EMPTY
	return int(value)
