@tool
class_name TileProp
extends StaticBody2D
## A tile-like room prop: a box with a surface kind. Optional component children
## move it (OscillatingMotion, PathMotion), place the props it carries (SpinMotion),
## or break it (Breakable). The origin is the box centre. Carried props are child
## TileProps; their position is an offset from the carrier's centre.
##
## A static body, so its physics transform can be set at once; its constant
## velocity is this tick's motion. A rider moving after it lands exactly on top.
## An AnimatableBody2D only moves in the next physics step: riders trail by a tick.

const GROUP := &"tile_props"

enum Solidity {
	KIND_DEFAULT,
	SOLID,
	PASS_THROUGH,
}

@export var size := Vector2(32.0, 32.0):
	set(value):
		size = value
		_shape.size = value
		queue_redraw()
@export var surface := Room.Kind.SOLID:
	set(value):
		surface = value
		_update_collision()
		queue_redraw()
## Solid and grapple surfaces block by default; the others do not.
@export var solidity := Solidity.KIND_DEFAULT:
	set(value):
		solidity = value
		_update_collision()
		queue_redraw()

@export_group("Components")
@export var oscillation: OscillatingMotion
@export var path: PathMotion
@export var spin: SpinMotion
@export var breakable: Breakable
@export var power: Power
@export var falling: FallingBehavior

## Set by the room when the current character cannot use this surface.
var excluded := false
## True during hitstop: the whole room holds still, not just the player.
var frozen := false
## Rest position in the parent's space, taken from where the prop was placed.
var home := Vector2.ZERO
## Set every tick by a spinning carrier.
var carry_offset := Vector2.ZERO

var _shape := RectangleShape2D.new()
var _previous_global := Vector2.ZERO


func _ready() -> void:
	var shape_node := CollisionShape2D.new()
	shape_node.shape = _shape
	add_child(shape_node, false, Node.INTERNAL_MODE_FRONT)
	_shape.size = size
	_update_collision()
	if Engine.is_editor_hint():
		set_physics_process(false)
		return
	add_to_group(GROUP)
	home = position
	if power != null:
		power.powered_changed.connect(_on_powered_changed)
	reset()


## Carriers process before what they carry (tree order), so a carried prop's
## velocity includes its carrier's motion this tick.
func _physics_process(delta: float) -> void:
	if frozen:
		constant_linear_velocity = Vector2.ZERO
		return
	var motion_delta := delta if power == null or power.motion_runs() else 0.0
	if falling != null:
		falling.tick(delta)
		if falling.state == FallingBehavior.State.FALLING:
			_fall(delta)
		elif falling.state != FallingBehavior.State.LANDED:
			_place(motion_delta)
	else:
		_place(motion_delta)
	if spin != null:
		spin.advance(motion_delta)
		_place_carried()
	_sync_physics_transform()
	constant_linear_velocity = (global_position - _previous_global) / delta
	_previous_global = global_position
	if breakable != null:
		var was_present := breakable.is_present()
		breakable.tick(delta)
		if breakable.is_present() != was_present:
			_update_collision()


## Back to the authored start. Carriers reset before what they carry (tree order).
func reset() -> void:
	for component in [oscillation, path, spin, breakable, falling, power]:
		if component != null:
			component.reset()
	_place(0.0)
	if spin != null:
		_place_carried()
	_sync_physics_transform()
	_previous_global = global_position
	constant_linear_velocity = Vector2.ZERO
	_update_collision()
	reset_physics_interpolation()


func is_present() -> bool:
	return (
		not excluded
		and (breakable == null or breakable.is_present())
		and (power == null or power.is_present())
	)


func is_solid() -> bool:
	match solidity:
		Solidity.SOLID:
			return true
		Solidity.PASS_THROUGH:
			return false
	return surface == Room.Kind.SOLID or surface == Room.Kind.GRAPPLE


## World-space box.
func rect() -> Rect2:
	return Rect2(global_position - size / 2.0, size)


func set_excluded(value: bool) -> void:
	excluded = value
	_update_collision()
	queue_redraw()


## The player landed on it this tick.
func stood_on() -> void:
	if breakable != null:
		breakable.on_stood_on(surface)
	if falling != null:
		falling.arm(surface)


## An ability used this surface; `use` is GRAPPLE or POGO.
func use_surface(use: Room.Kind) -> void:
	if breakable != null:
		breakable.on_surface_used(use, surface)


## Direct child props, minus the ones this character cannot use.
func carried_props() -> Array[TileProp]:
	var carried: Array[TileProp] = []
	for child in get_children():
		if child is TileProp and not child.excluded:
			carried.append(child)
	return carried


func collision_layers() -> int:
	var layers := 0
	if surface != Room.Kind.EMPTY and is_solid():
		layers |= PhysicsLayers.WORLD
	if surface == Room.Kind.DEATH:
		layers |= PhysicsLayers.HAZARD
	elif surface == Room.Kind.EXIT:
		layers |= PhysicsLayers.EXIT
	return layers


## Home, then path, then oscillation; a carried prop also adds its carrier's spin offset.
## A path is in world space, so a carried prop with a path ignores its carrier.
func _place(delta: float) -> void:
	var target := home + carry_offset
	if path != null:
		target = (get_parent() as Node2D).to_local(path.advance(delta))
	if oscillation != null:
		target += oscillation.advance(delta)
	position = target


func _fall(delta: float) -> void:
	var next_top := falling.fall(delta, rect(), _fall_blocked)
	global_position.y = next_top + size.y / 2.0


func _fall_blocked(box: Rect2) -> bool:
	var params := PhysicsShapeQueryParameters2D.new()
	var probe := RectangleShape2D.new()
	# Physics overlap queries count a flush edge as intersecting. A tiny inset
	# lets the block settle exactly on a floor while still detecting penetration.
	probe.size = box.size - Vector2.ONE * 0.02
	params.shape = probe
	params.transform = Transform2D(0.0, box.get_center())
	params.collision_mask = PhysicsLayers.WORLD
	params.collide_with_areas = false
	params.collide_with_bodies = true
	params.exclude = [get_rid()]
	return not get_world_2d().direct_space_state.intersect_shape(params, 1).is_empty()


## Godot batches node transform changes and hands them to physics after every
## script has run, which would leave riders colliding with last tick's box.
func _sync_physics_transform() -> void:
	PhysicsServer2D.body_set_state(get_rid(), PhysicsServer2D.BODY_STATE_TRANSFORM, global_transform)


func _place_carried() -> void:
	var arms := carried_props()
	for index in arms.size():
		arms[index].carry_offset = spin.offset_for(index, arms.size())


func _on_powered_changed(_is_powered: bool) -> void:
	_update_collision()
	queue_redraw()


## Runtime only, so the editor and importer never save derived layers into scenes.
func _update_collision() -> void:
	if Engine.is_editor_hint() or not is_inside_tree():
		return
	collision_layer = collision_layers() if is_present() else 0


#region Placeholder visuals
# Prototype surface boxes drawn in code until props have real art. Sprites or
# tiles should replace this region; breakables still need an arming tell.

const SURFACE_COLORS := {
	Room.Kind.SOLID: Color("#3d5a45"),
	Room.Kind.GRAPPLE: Color("#c45a1a"),
	Room.Kind.EXIT: Color("#1a6b3a"),
	Room.Kind.DEATH: Color("#6b1a1a"),
	Room.Kind.POGO: Color("#5a2a6b"),
}
const SOFT_FILL_ALPHA := 0.18
const SOFT_RIM_ALPHA := 0.85
const HATCH_COLOR := Color(1.0, 1.0, 1.0, 0.35)
const HATCH_RIM_COLOR := Color(0.0, 0.0, 0.0, 0.25)
const HATCH_SPACING := 4.0
const ARMING_ALPHA := 0.7
const ARMING_SHAKE_RATE := 40.0
const ARMING_SHAKE_PX := 1.5


func _process(_delta: float) -> void:
	if (breakable != null or falling != null) and not Engine.is_editor_hint():
		queue_redraw()


func _draw() -> void:
	if not SURFACE_COLORS.has(surface):
		return
	var in_editor := Engine.is_editor_hint()
	if not in_editor and not is_present():
		return
	var color: Color = SURFACE_COLORS[surface]
	var box := Rect2(-size / 2.0, size)
	if not in_editor:
		if breakable != null and breakable.state == Breakable.State.ARMING:
			var armed_for := breakable.delay - breakable.time_left
			box.position.x += sin(armed_for * ARMING_SHAKE_RATE) * ARMING_SHAKE_PX
			color.a *= ARMING_ALPHA
		elif falling != null:
			box.position.x += falling.draw_offset_x()
		
	if is_solid():
		draw_rect(box, color)
	else:
		draw_rect(box, Color(color, color.a * SOFT_FILL_ALPHA))
		_draw_dashed_rim(box, Color(color, color.a * SOFT_RIM_ALPHA))
	if breakable != null or falling != null:
		_draw_hatch(box)


func _draw_dashed_rim(box: Rect2, color: Color) -> void:
	var corners := [box.position, Vector2(box.end.x, box.position.y), box.end, Vector2(box.position.x, box.end.y)]
	for index in corners.size():
		draw_dashed_line(corners[index], corners[(index + 1) % corners.size()], color, 1.0, 2.0)


## Diagonal hatch marking breakable surfaces.
func _draw_hatch(box: Rect2) -> void:
	var offset := -box.size.y
	while offset < box.size.x:
		var start := maxf(0.0, -offset)
		var end := minf(box.size.y, box.size.x - offset)
		if end > start:
			draw_line(
				box.position + Vector2(offset + start, start),
				box.position + Vector2(offset + end, end),
				HATCH_COLOR,
				1.0,
			)
		offset += HATCH_SPACING
	draw_rect(box.grow(-0.5), HATCH_RIM_COLOR, false, 1.0)

#endregion
