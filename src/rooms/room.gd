class_name Room
extends Node2D
## A playable room. `Terrain` is shared by every character; the surface layers
## are enabled only for characters that use them (the prototype's exclusions).
## Death and exit tiles collide only on the hazard and exit layers, so bodies pass
## through and touch sensors report them.

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
const KILL_PLANE_DEPTH := 16.0 * MovementStats.TILE

@onready var terrain: TileMapLayer = $Terrain
@onready var grapple_surfaces: TileMapLayer = $GrappleSurfaces
@onready var pogo_surfaces: TileMapLayer = $PogoSurfaces
@onready var spawn: Marker2D = $Spawn


func _ready() -> void:
	_add_out_of_bounds_walls()
	_add_kill_plane()


## World-space room extent, taken from the terrain so it never drifts from the tiles.
func pixel_rect() -> Rect2:
	var cells := terrain.get_used_rect()
	var tile := Vector2(terrain.tile_set.tile_size)
	return Rect2(terrain.global_position + Vector2(cells.position) * tile, Vector2(cells.size) * tile)


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
	if not terrain.get_used_rect().has_point(cell):
		return Kind.SOLID
	for layer: TileMapLayer in [pogo_surfaces, grapple_surfaces, terrain]:
		if not layer.enabled:
			continue
		var data := layer.get_cell_tile_data(cell)
		if data != null:
			return data.get_custom_data(KIND_DATA)
	return Kind.EMPTY


func kind_at(point: Vector2) -> Kind:
	return kind_at_cell(cell_at(point))


## Whether the cell blocks the body. Left, right, and above the room are solid;
## below is open so falls reach the kill plane.
func is_solid_cell(cell: Vector2i) -> bool:
	var bounds := terrain.get_used_rect()
	if cell.y < bounds.position.y or cell.x < bounds.position.x or cell.x >= bounds.end.x:
		return true
	if cell.y >= bounds.end.y:
		return false
	for layer: TileMapLayer in [grapple_surfaces, terrain]:
		if not layer.enabled:
			continue
		var data := layer.get_cell_tile_data(cell)
		if data != null and data.get_collision_polygons_count(0) > 0:
			return true
	return false


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
