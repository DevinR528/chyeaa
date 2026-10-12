class_name CheckpointPotion
extends Potion
## Plants a respawn flag at the player's feet. A spent potion stays in the belt
## so the flag remains until the run leaves the room or the potion is unequipped
## while it still has charges.

var has_flag := false
var flag := Vector2.ZERO
var flag_node: Node2D


func clear(room: Room) -> void:
	has_flag = false
	room.clear_checkpoint()
	_drop_flag()


func use(feet: Vector2, room: Room) -> PotionUse:
	if uses <= 0:
		return null
	var previous: Variant = room.checkpoint
	uses -= 1
	room.set_checkpoint(feet.round())
	var planted: Vector2 = room.spawn_feet()
	has_flag = true
	flag = planted
	_place_flag(room, planted)
	var record := CheckpointUse.new()
	record.bind(
		func() -> void:
			if previous is Vector2:
				room.set_checkpoint(previous as Vector2)
				has_flag = true
				flag = room.spawn_feet()
				_place_flag(room, flag)
			else:
				has_flag = false
				room.clear_checkpoint()
				_drop_flag(),
		func() -> void:
			room.set_checkpoint(planted)
			has_flag = true
			flag = planted
			_place_flag(room, planted),
	)
	return record


func _place_flag(room: Room, at: Vector2) -> void:
	if flag_node == null or not is_instance_valid(flag_node):
		flag_node = Flag.new()
		flag_node.name = &"CheckpointFlag"
		room.add_child(flag_node)
	flag_node.global_position = at
	flag_node.queue_redraw()


func _drop_flag() -> void:
	if flag_node != null and is_instance_valid(flag_node):
		flag_node.queue_free()
	flag_node = null


class Flag extends Node2D:
	func _ready() -> void:
		z_index = 10

	func _draw() -> void:
		draw_line(Vector2.ZERO, Vector2(0, -20), Color("e8e0d0"), 1.5)
		draw_colored_polygon(
			PackedVector2Array([Vector2(0, -20), Vector2(12, -15), Vector2(0, -11)]),
			Color("38bdf8"),
		)
