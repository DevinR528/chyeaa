class_name Room
extends Node2D
## A playable room. `BlockTerrain` (art tiles of any size) and `Terrain` (8 px kind
## tiles, for detail smaller than a block) are shared by every character; don't
## paint both over the same spot. The surface layers are enabled only for characters
## that use them (the prototype's exclusions). Death and exit tiles collide only on
## the hazard and exit layers, so bodies pass through and touch sensors report them.
## Cell queries use Terrain's 8 px cells and see a tile wherever its collision
## reaches, so art tiles may be larger than their layer's cells.
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

## TileSet custom data layer holding a `Kind` on every tile.
const KIND_DATA := &"kind"
## TileSet physics layer that collides on WORLD.
const WORLD_PHYSICS := 0
const ANY_PHYSICS := -1
const KILL_PLANE_DEPTH := 16.0 * MovementStats.TILE

## TileSet to how many cells past its own a tile's collision reaches.
var _reach_by_tile_set := {}

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


## Props first, so carriers are back in place before anything resets onto them.
func reset_entities() -> void:
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


## Topmost kind the current character sees. Outside the room counts as solid.
func kind_at_cell(cell: Vector2i) -> Kind:
	if not cell_bounds().has_point(cell):
		return Kind.SOLID
	for layer: TileMapLayer in [pogo_surfaces, grapple_surfaces, terrain, block_terrain]:
		if not layer.enabled:
			continue
		for data in _tiles_at(layer, cell, ANY_PHYSICS):
			var kind: Kind = data.get_custom_data(KIND_DATA)
			if kind != Kind.EMPTY:
				return kind
	return Kind.EMPTY


func kind_at(point: Vector2) -> Kind:
	return kind_at_cell(cell_at(point))


## Whether the cell blocks the body. Left, right, and above the room are solid;
## below is open so falls reach the kill plane.
func is_solid_cell(cell: Vector2i) -> bool:
	var bounds := cell_bounds()
	if cell.y < bounds.position.y or cell.x < bounds.position.x or cell.x >= bounds.end.x:
		return true
	if cell.y >= bounds.end.y:
		return false
	for layer: TileMapLayer in [grapple_surfaces, terrain, block_terrain]:
		if not layer.enabled:
			continue
		if not _tiles_at(layer, cell, WORLD_PHYSICS).is_empty():
			return true
	return false


## Tiles on `layer` covering the centre of a Terrain cell. A tile covers it where a
## collision polygon on `physics` (any layer for ANY_PHYSICS) contains it, so art
## larger than its cell counts everywhere it collides. With ANY_PHYSICS, a tile
## with no collision at all covers just its own cell.
func _tiles_at(layer: TileMapLayer, cell: Vector2i, physics: int) -> Array[TileData]:
	var found: Array[TileData] = []
	if layer.tile_set == null:
		return found
	var point := layer.to_local(cell_rect(cell).get_center())
	var home := layer.local_to_map(point)
	var reach := _reach(layer)
	for y in range(home.y - reach, home.y + reach + 1):
		for x in range(home.x - reach, home.x + reach + 1):
			var at := Vector2i(x, y)
			var data := layer.get_cell_tile_data(at)
			if data != null and _covers(layer, at, data, point, physics):
				found.append(data)
	return found


func _covers(layer: TileMapLayer, at: Vector2i, data: TileData, point: Vector2, physics: int) -> bool:
	var local := _untransform(point - layer.map_to_local(at), data, layer.get_cell_alternative_tile(at))
	var has_polygons := false
	for index in layer.tile_set.get_physics_layers_count():
		if physics != ANY_PHYSICS and index != physics:
			continue
		for polygon in data.get_collision_polygons_count(index):
			has_polygons = true
			if Geometry2D.is_point_in_polygon(local, data.get_collision_polygon_points(index, polygon)):
				return true
	return physics == ANY_PHYSICS and not has_polygons and at == layer.local_to_map(point)


## Undoes a painted tile's flip and transpose, so `local` can be tested against its
## untransformed collision polygons. Godot transposes first, then flips.
func _untransform(local: Vector2, data: TileData, alternative: int) -> Vector2:
	var flip_h := data.flip_h != bool(alternative & TileSetAtlasSource.TRANSFORM_FLIP_H)
	var flip_v := data.flip_v != bool(alternative & TileSetAtlasSource.TRANSFORM_FLIP_V)
	var transpose := data.transpose != bool(alternative & TileSetAtlasSource.TRANSFORM_TRANSPOSE)
	if flip_h:
		local.x = -local.x
	if flip_v:
		local.y = -local.y
	return Vector2(local.y, local.x) if transpose else local


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
