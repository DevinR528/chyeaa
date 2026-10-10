@tool
class_name RoomActor
extends CharacterBody2D
## A room body that moves on its own: walkers and throwables. The origin is the
## box centre. Its ContactBox reports touches with the player and other actors;
## see ContactBox for when a reaction may change the body.

const GROUP := &"room_actors"
const TILE := MovementStats.TILE
const MAX_FALL := 200.0 * TILE

@export var size := Vector2(16.0, 16.0):
	set(value):
		size = value
		_shape.size = value
		if contact_box != null:
			contact_box.resize(value)
		queue_redraw()
@export var gravity := 350.0 * TILE
## Vertical velocity given to a player who stomps this body (negative is up).
@export var stomp_bounce := -40.0 * TILE

## True during hitstop: the whole room holds still, not just the player.
var frozen := false
## Rest position in the parent's space, taken from where the actor was placed.
var home := Vector2.ZERO
var contact_box: ContactBox

var _shape := RectangleShape2D.new()


func _ready() -> void:
	var shape_node := CollisionShape2D.new()
	shape_node.shape = _shape
	add_child(shape_node, false, Node.INTERNAL_MODE_FRONT)
	_shape.size = size
	if Engine.is_editor_hint():
		set_physics_process(false)
		return
	contact_box = ContactBox.attach(self, size)
	contact_box.touched.connect(_on_contact_touched)
	add_to_group(GROUP)
	home = position
	reset()


## Back to the authored start.
func reset() -> void:
	position = home
	velocity = Vector2.ZERO
	_sync_physics_transform()
	reset_physics_interpolation()


## World-space box.
func body_rect() -> Rect2:
	return Rect2(global_position - size / 2.0, size)


func accepts_stomp() -> bool:
	return false


## Whether touching this body (without stomping it) kills `player`.
func hurts(_player: PlayerBody) -> bool:
	return false


func _on_contact_touched(_other: Node2D) -> void:
	pass


func _fall(delta: float) -> void:
	velocity.y = minf(velocity.y + gravity * delta, MAX_FALL)


## Godot hands moved transforms to physics after every script has run; bodies
## that collide with this one this tick (a player standing on an idle ball)
## need the new box now.
func _sync_physics_transform() -> void:
	PhysicsServer2D.body_set_state(get_rid(), PhysicsServer2D.BODY_STATE_TRANSFORM, global_transform)


## Whether `rect` (world space) overlaps anything on the world layer except this body.
func _solid_in(rect: Rect2) -> bool:
	var shape := RectangleShape2D.new()
	shape.size = rect.size
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = shape
	query.transform = Transform2D(0.0, rect.get_center())
	query.collision_mask = PhysicsLayers.WORLD
	query.exclude = [get_rid()]
	return not get_world_2d().direct_space_state.intersect_shape(query, 1).is_empty()
