class_name ContactBox
extends Area2D
## Body-to-body contact between the player, walkers, and throwables. Each body
## owns one and reacts to `touched` for itself; there is no central resolver.
##
## Every box's `touched` arrives before any body's tick, so all handlers read the
## same end-of-tick state. Live play gets that from the physics flush. Rewind
## polls, because `flush_queries` is not on the scripting API. Decide in the
## handler and change your own body at the start of its tick.

signal touched(other: Node2D)

## Top fraction of a body that counts as a stomp.
const STOMP_BAND_FRACTION := 1.0 / 3.0
## Smaller than the body by this on each side, so flush contact (the player
## standing on an idle throwable) is not a touch.
const INSET := 0.01

var _rect := RectangleShape2D.new()
var _overlapping: Array[int] = []


static func attach(body: CollisionObject2D, body_size: Vector2, offset := Vector2.ZERO) -> ContactBox:
	var box := ContactBox.new()
	box.name = &"ContactBox"
	box.collision_layer = PhysicsLayers.CONTACT
	box.collision_mask = PhysicsLayers.CONTACT
	var shape := CollisionShape2D.new()
	shape.shape = box._rect
	shape.position = offset
	box.add_child(shape)
	box.resize(body_size)
	body.add_child(box)
	return box


## Top-only stomp: the feet are in the target's top band or swept through it from
## above. Side runs keep the feet low and are rejected.
static func is_stomp(feet_y: float, previous_feet_y: float, velocity_y: float, target: Rect2) -> bool:
	var top := target.position.y
	var band := target.size.y * STOMP_BAND_FRACTION
	if previous_feet_y > top + band and feet_y > top + band:
		return false
	if feet_y < top - 2.0:
		return false
	if velocity_y > 0.0:
		return true
	return previous_feet_y < top - 1.0


func _ready() -> void:
	area_entered.connect(_on_area_entered)
	area_exited.connect(_on_area_exited)


func _on_area_entered(area: Area2D) -> void:
	if not area is ContactBox or _overlapping.has(area.get_instance_id()):
		return
	_overlapping.append(area.get_instance_id())
	touched.emit(area.get_parent())


func _on_area_exited(area: Area2D) -> void:
	_overlapping.erase(area.get_instance_id())


## Edge-triggered, matching `area_entered`. Call before the bodies tick.
func sync_overlaps() -> void:
	if not monitoring or not is_inside_tree():
		_overlapping.clear()
		return
	var shape_node := get_child(0) as CollisionShape2D
	var params := PhysicsShapeQueryParameters2D.new()
	params.shape = _rect
	params.transform = shape_node.global_transform
	params.collision_mask = collision_mask
	params.collide_with_areas = true
	params.collide_with_bodies = false
	params.exclude = [get_rid()]
	var found: Array[int] = []
	for hit in get_world_2d().direct_space_state.intersect_shape(params, 16):
		var area := hit.collider as Area2D
		if not area is ContactBox or not (area as ContactBox).monitorable:
			continue
		var id := area.get_instance_id()
		found.append(id)
		if not _overlapping.has(id):
			touched.emit(area.get_parent())
	_overlapping = found


func clear_overlaps() -> void:
	_overlapping.clear()


func resize(body_size: Vector2) -> void:
	_rect.size = body_size - Vector2.ONE * INSET * 2.0


## Immediate: callers are ticks, not the flush, and a rewind runs many ticks
## before the engine is idle again.
func set_active(active: bool) -> void:
	monitoring = active
	monitorable = active
