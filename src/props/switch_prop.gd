@tool
class_name SwitchProp
extends Area2D
## A room-local player sensor. State changes are facts; powered props subscribe
## through their owning Room instead of polling this node.

signal state_changed(switch_id: StringName, is_on: bool)

enum Mode {
	TOGGLE,
	MOMENTARY,
	ONCE,
}

@export var switch_id := &"sw"
@export var mode := Mode.TOGGLE
@export var starts_on := false
@export var size := Vector2(16.0, 16.0):
	set(value):
		size = value
		_shape.size = value
		queue_redraw()

var is_on := false
var _latched := false
var _room: Room
var _shape := RectangleShape2D.new()
var _overlapping_players: Dictionary = {}


func _ready() -> void:
	var shape_node := CollisionShape2D.new()
	shape_node.shape = _shape
	add_child(shape_node, false, Node.INTERNAL_MODE_FRONT)
	_shape.size = size
	collision_layer = 0
	collision_mask = PhysicsLayers.PLAYER
	monitorable = false
	if Engine.is_editor_hint():
		set_process(false)
		return
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	_room = _find_room()
	if _room != null:
		_room.register_switch(self)
	tree_exiting.connect(_unregister)
	reset()


func reset() -> void:
	_overlapping_players.clear()
	_latched = mode == Mode.ONCE and starts_on
	_set_on(starts_on)


func _on_body_entered(body: Node2D) -> void:
	if not body is PlayerBody:
		return
	var was_empty := _overlapping_players.is_empty()
	_overlapping_players[body] = true
	if not was_empty:
		return
	match mode:
		Mode.TOGGLE:
			_set_on(not is_on)
		Mode.MOMENTARY:
			_set_on(true)
		Mode.ONCE:
			if not _latched:
				_latched = true
				_set_on(true)


func _on_body_exited(body: Node2D) -> void:
	if not _overlapping_players.erase(body):
		return
	if mode == Mode.MOMENTARY and _overlapping_players.is_empty():
		_set_on(false)


func _set_on(value: bool) -> void:
	if is_on == value:
		return
	is_on = value
	queue_redraw()
	state_changed.emit(switch_id, is_on)


func _unregister() -> void:
	if _room != null and is_instance_valid(_room):
		_room.unregister_switch(self)
	_room = null


func _find_room() -> Room:
	var node := get_parent()
	while node != null:
		if node is Room:
			return node
		node = node.get_parent()
	return null


#region Placeholder visuals

func _draw() -> void:
	var color := Color("#e8c84a") if is_on else Color("#5c4a1a")
	var box := Rect2(-size / 2.0, size)
	draw_rect(box, color)
	draw_rect(box.grow(-0.5), Color("#f5e6a8"), false, 1.0)

#endregion
