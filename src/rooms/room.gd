class_name Room
extends Node2D
## A playable room. `BlockTerrain` (art tiles of any size) and `Terrain` (8 px kind
## tiles, for detail smaller than a block) are shared by every character; don't
## paint both over the same spot. The surface layers are enabled only for characters
## that use them (the prototype's exclusions). Death and exit tiles collide only on
## the hazard and exit layers, so bodies pass through and touch sensors report them.
## Kind and solidity come from the physics space, so a tile counts wherever its
## shape reaches, including art tiles larger than an 8 px cell. Grapple and pogo
## tiles carry sensor shapes (mask 0). Props are not tiles; abilities test them
## separately.
##
## Every layer's TileSet follows kind_tiles.tres: a `kind` custom data layer holding a
## `Kind` on every tile, and physics layer 0 colliding on WORLD for solid tiles.
## Tiles with no kind and no collision are decoration.

enum Kind {
	EMPTY,
	SOLID,
	GRAPPLE,
	EXIT,
	DEATH,
	POGO,
}

signal switch_registered(room_switch: SwitchProp)
signal switch_unregistered(room_switch: SwitchProp)

## TileSet custom data layer holding a `Kind` on every tile.
const KIND_DATA := &"kind"
## TileSet physics layer that collides on WORLD.
const WORLD_PHYSICS := 0
const KILL_PLANE_DEPTH := 16.0 * MovementStats.TILE
const _TILE_MASK := PhysicsLayers.WORLD | PhysicsLayers.HAZARD | PhysicsLayers.EXIT | PhysicsLayers.GRAPPLE | PhysicsLayers.POGO

## TileSet to how many cells past its own a tile's collision reaches.
var _reach_by_tile_set := {}
var _switches_by_id: Dictionary = {}

## Optional generated-room bounds. Authored rooms derive their extent from tiles.
@export var extent_cells := Rect2i()

@onready var terrain: TileMapLayer = $Terrain
@onready var block_terrain: TileMapLayer = $BlockTerrain
@onready var grapple_surfaces: TileMapLayer = $GrappleSurfaces
@onready var pogo_surfaces: TileMapLayer = $PogoSurfaces
@onready var spawn: Marker2D = $Spawn


func _ready() -> void:
	_add_out_of_bounds_walls()
	_add_kill_plane()


## World-space room extent, taken from both terrain layers so it never drifts from the tiles.
func pixel_rect() -> Rect2:
	if extent_cells.has_area():
		var tile := Vector2(terrain.tile_set.tile_size)
		return Rect2(
			terrain.global_position + Vector2(extent_cells.position) * tile,
			Vector2(extent_cells.size) * tile,
		)
	var rect := Rect2()
	for layer: TileMapLayer in [terrain, block_terrain]:
		if layer.tile_set == null:
			continue
		var cells := layer.get_used_rect()
		if cells.has_area():
			cells = cells.grow(_reach(layer))
			var tile := Vector2(layer.tile_set.tile_size)
			var layer_rect := Rect2(layer.global_position + Vector2(cells.position) * tile, Vector2(cells.size) * tile)
			rect = layer_rect if not rect.has_area() else rect.merge(layer_rect)
	return rect


## The room's extent in Terrain's 8 px cells.
func cell_bounds() -> Rect2i:
	var rect := pixel_rect()
	var tile := Vector2(terrain.tile_set.tile_size)
	return Rect2i(cell_at(rect.position + tile / 2.0), Vector2i((rect.size / tile).round()))


func kill_plane_y() -> float:
	return pixel_rect().end.y + KILL_PLANE_DEPTH


## Where the spawned player's feet rest.
func spawn_feet() -> Vector2:
	return spawn.global_position


## Grapple and pogo tiles and props exist only for characters that use them.
func use_surfaces(grapple: bool, pogo: bool) -> void:
	grapple_surfaces.enabled = grapple
	pogo_surfaces.enabled = pogo
	for prop in props():
		var excluded := (prop.surface == Kind.GRAPPLE and not grapple) or (prop.surface == Kind.POGO and not pogo)
		prop.set_excluded(excluded)


## Every prop in this room, carriers before what they carry.
func props() -> Array[TileProp]:
	var found: Array[TileProp] = []
	for node in get_tree().get_nodes_in_group(TileProp.GROUP):
		if is_ancestor_of(node):
			found.append(node)
	return found


## Every walker and throwable in this room.
func actors() -> Array[RoomActor]:
	var found: Array[RoomActor] = []
	for node in get_tree().get_nodes_in_group(RoomActor.GROUP):
		if is_ancestor_of(node):
			found.append(node)
	return found


func register_switch(room_switch: SwitchProp) -> void:
	var matches: Array = _switches_by_id.get(room_switch.switch_id, [])
	if matches.has(room_switch):
		return
	matches.append(room_switch)
	_switches_by_id[room_switch.switch_id] = matches
	switch_registered.emit(room_switch)


func unregister_switch(room_switch: SwitchProp) -> void:
	var matches: Array = _switches_by_id.get(room_switch.switch_id, [])
	if not matches.has(room_switch):
		return
	matches.erase(room_switch)
	if matches.is_empty():
		_switches_by_id.erase(room_switch.switch_id)
	else:
		_switches_by_id[room_switch.switch_id] = matches
	switch_unregistered.emit(room_switch)


func switches_with_id(switch_id: StringName) -> Array[SwitchProp]:
	var found: Array[SwitchProp] = []
	for room_switch in _switches_by_id.get(switch_id, []):
		if is_instance_valid(room_switch):
			found.append(room_switch)
	return found


## Switch state first, then carriers before what they carry, then actors.
func reset_entities() -> void:
	for matches: Array in _switches_by_id.values():
		for room_switch: SwitchProp in matches:
			room_switch.reset()
	for prop in props():
		prop.reset()
	for actor in actors():
		actor.reset()


func freeze_entities(frozen: bool) -> void:
	for prop in props():
		prop.frozen = frozen
	for actor in actors():
		actor.frozen = frozen


## First present prop with `surface` whose box contains `point`, or null.
func prop_at(point: Vector2, surface: Kind) -> TileProp:
	for prop in props():
		if prop.surface == surface and prop.is_present() and prop.rect().has_point(point):
			return prop
	return null


func cell_at(point: Vector2) -> Vector2i:
	return terrain.local_to_map(terrain.to_local(point))


func cell_rect(cell: Vector2i) -> Rect2:
	var tile := Vector2(terrain.tile_set.tile_size)
	return Rect2(terrain.to_global(Vector2(cell) * tile), tile)


## Topmost kind the current character sees, from the tile shapes covering the cell
## centre. Outside the room counts as solid.
func kind_at_cell(cell: Vector2i) -> Kind:
	if not cell_bounds().has_point(cell):
		return Kind.SOLID
	return _kind_at_point(cell_rect(cell).get_center())


func kind_at(point: Vector2) -> Kind:
	return kind_at_cell(cell_at(point))


## Whether the cell blocks the body. Left, right, and above the room are solid;
## below is open so falls reach the kill plane.
func is_solid_cell(cell: Vector2i) -> bool:
	return _is_solid(cell, cell_rect(cell).get_center())


## Same solidity rule at `point` itself, for a hook sample that is not a cell centre.
func is_solid_at(point: Vector2) -> bool:
	return _is_solid(cell_at(point), point)


## A room tile shape on `mask` covers `point`. Props and the boundary walls do not.
func has_tile(point: Vector2, mask: int) -> bool:
	for hit in _point_hits(point, mask):
		if _is_room_tile(hit["collider"]):
			return true
	return false


## A room tile shape on `mask` overlaps the convex polygon. `points` are around `origin`.
func tiles_overlap(origin: Vector2, points: PackedVector2Array, mask: int) -> bool:
	var shape := ConvexPolygonShape2D.new()
	shape.points = points
	var params := PhysicsShapeQueryParameters2D.new()
	params.shape = shape
	params.transform = Transform2D(0.0, origin)
	params.collision_mask = mask
	params.collide_with_areas = false
	params.collide_with_bodies = true
	params.margin = 0.0
	for hit in get_world_2d().direct_space_state.intersect_shape(params, 16):
		if _is_room_tile(hit["collider"]):
			return true
	return false


## Left, right, and above the room. Below is open.
func is_out_of_bounds_solid(cell: Vector2i) -> bool:
	var bounds := cell_bounds()
	return cell.y < bounds.position.y or cell.x < bounds.position.x or cell.x >= bounds.end.x


func _is_solid(cell: Vector2i, point: Vector2) -> bool:
	if is_out_of_bounds_solid(cell):
		return true
	if cell.y >= cell_bounds().end.y:
		return false
	return has_tile(point, PhysicsLayers.WORLD)


func _kind_at_point(point: Vector2) -> Kind:
	var bits_by_layer := {}
	for hit in _point_hits(point, _TILE_MASK):
		var layer := hit["collider"] as TileMapLayer
		if not _is_room_tile(layer):
			continue
		bits_by_layer[layer] = int(bits_by_layer.get(layer, 0)) | PhysicsServer2D.body_get_collision_layer(hit["rid"])
	for layer: TileMapLayer in [pogo_surfaces, grapple_surfaces, terrain, block_terrain]:
		var kind := _kind_from_bits(int(bits_by_layer.get(layer, 0)))
		if kind != Kind.EMPTY:
			return kind
	return Kind.EMPTY


func _kind_from_bits(bits: int) -> Kind:
	if bits & PhysicsLayers.POGO:
		return Kind.POGO
	if bits & PhysicsLayers.GRAPPLE:
		return Kind.GRAPPLE
	if bits & PhysicsLayers.HAZARD:
		return Kind.DEATH
	if bits & PhysicsLayers.EXIT:
		return Kind.EXIT
	if bits & PhysicsLayers.WORLD:
		return Kind.SOLID
	return Kind.EMPTY


func _point_hits(point: Vector2, mask: int) -> Array:
	var query := PhysicsPointQueryParameters2D.new()
	query.position = point
	query.collision_mask = mask
	query.collide_with_areas = false
	query.collide_with_bodies = true
	return get_world_2d().direct_space_state.intersect_point(query, 16)


func _is_room_tile(collider: Object) -> bool:
	var layer := collider as TileMapLayer
	return layer != null and layer.enabled and is_ancestor_of(layer)


## How many cells past its own any tile's collision reaches on `layer`.
func _reach(layer: TileMapLayer) -> int:
	var tile_set := layer.tile_set
	if _reach_by_tile_set.has(tile_set):
		return _reach_by_tile_set[tile_set]
	var extent := 0.0
	for source_index in tile_set.get_source_count():
		var source := tile_set.get_source(tile_set.get_source_id(source_index)) as TileSetAtlasSource
		if source == null:
			continue
		for tile_index in source.get_tiles_count():
			var coords := source.get_tile_id(tile_index)
			for alternative_index in source.get_alternative_tiles_count(coords):
				var data := source.get_tile_data(coords, source.get_alternative_tile_id(coords, alternative_index))
				for physics in tile_set.get_physics_layers_count():
					for polygon in data.get_collision_polygons_count(physics):
						for vertex in data.get_collision_polygon_points(physics, polygon):
							extent = maxf(extent, maxf(absf(vertex.x), absf(vertex.y)))
	var tile := float(mini(tile_set.tile_size.x, tile_set.tile_size.y))
	var reach := maxi(0, ceili((extent - tile / 2.0) / tile))
	_reach_by_tile_set[tile_set] = reach
	return reach


## Left, right, and above the room are solid; below is open so falls reach the kill plane.
func _add_out_of_bounds_walls() -> void:
	var rect := pixel_rect()
	var walls := StaticBody2D.new()
	walls.name = "OutOfBounds"
	walls.collision_layer = PhysicsLayers.WORLD
	_add_wall(walls, Vector2(rect.position.x, rect.get_center().y), Vector2.RIGHT)
	_add_wall(walls, Vector2(rect.end.x, rect.get_center().y), Vector2.LEFT)
	_add_wall(walls, Vector2(rect.get_center().x, rect.position.y), Vector2.DOWN)
	add_child(walls)


## Everything below `kill_plane_y` is on the fall layer; touch sensors report it.
func _add_kill_plane() -> void:
	var kill_plane := StaticBody2D.new()
	kill_plane.name = "KillPlane"
	kill_plane.collision_layer = PhysicsLayers.FALL
	kill_plane.collision_mask = 0
	_add_wall(kill_plane, Vector2(pixel_rect().get_center().x, kill_plane_y()), Vector2.UP)
	add_child(kill_plane)


func _add_wall(walls: StaticBody2D, point: Vector2, open_side: Vector2) -> void:
	var boundary := WorldBoundaryShape2D.new()
	boundary.normal = open_side
	var shape := CollisionShape2D.new()
	shape.shape = boundary
	shape.position = to_local(point)
	walls.add_child(shape)
