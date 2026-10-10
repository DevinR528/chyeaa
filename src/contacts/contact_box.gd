class_name ContactBox
extends Area2D
## Body-to-body contact between the player, walkers, and throwables. Each body
## owns one and reacts to `touched` for itself; there is no central resolver.
##
## Every box's `touched` arrives in the physics flush, before any body's tick, so
## all handlers read the same end-of-tick state. Decide in the handler and change
## your own body at the start of its tick; changing it in the handler would let
## a handler that runs later read the change.

signal touched(other: Node2D)

## Top fraction of a body that counts as a stomp.
const STOMP_BAND_FRACTION := 1.0 / 3.0
## Smaller than the body by this on each side, so flush contact (the player
## standing on an idle throwable) is not a touch.
const INSET := 0.01

var _rect := RectangleShape2D.new()


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
	area_entered.connect(func(area: Area2D) -> void:
		if area is ContactBox:
			touched.emit(area.get_parent()))


func resize(body_size: Vector2) -> void:
	_rect.size = body_size - Vector2.ONE * INSET * 2.0


## Deferred: monitoring cannot change while the physics flush delivers signals.
func set_active(active: bool) -> void:
	set_deferred(&"monitoring", active)
	set_deferred(&"monitorable", active)
