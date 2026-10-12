class_name SimStep
extends RefCounted
## Turns a real physics delta into gameplay time. `move_and_slide` always
## integrates with the engine delta, so `slide` scales velocity for that call
## and puts the gameplay velocity back. Engine.time_scale is not involved.

static func scale_of(node: Node) -> float:
	var current := node
	while current != null:
		if current is Room:
			return (current as Room).sim_scale
		# The player lives beside the room and keeps it on `room`, not as a parent.
		var body_room: Variant = current.get(&"room")
		if body_room is Room:
			return (body_room as Room).sim_scale
		current = current.get_parent()
	return 1.0


static func delta(node: Node, real_delta: float) -> float:
	return real_delta * scale_of(node)


static func slide(body: CharacterBody2D) -> void:
	var scale := scale_of(body)
	if is_equal_approx(scale, 1.0):
		body.move_and_slide()
		return
	body.velocity *= scale
	body.move_and_slide()
	if scale > 0.0:
		body.velocity /= scale
