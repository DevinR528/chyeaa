class_name BackdropLayer
extends Parallax2D
## One parallax plate: a Sprite2D child (top-left at this node's origin) moved by
## Parallax2D's camera scroll. `frame` turns the room rect into the scroll offset,
## so the plate sits where the prototype placed it.
## `scroll_scale` is the parallax factor: 0 sticks to the screen, 1 moves with the world.

enum Anchor {
	## The plate's top-left meets the view's top-left while the camera rests on the room's top-left.
	TOP,
	## The plate's bottom meets the view's bottom while the camera rests on the room's bottom.
	BOTTOM,
}

@export var anchor := Anchor.TOP
@export var repeat_x := false

@onready var plate: Sprite2D = _find_plate()


func _find_plate() -> Sprite2D:
	for child in get_children():
		if child is Sprite2D:
			return child
	return null


func frame(room_rect: Rect2, view_size: Vector2) -> void:
	if plate == null or plate.texture == null:
		return
	var size := plate.texture.get_size()
	plate.centered = false
	plate.position = Vector2.ZERO

	var anchored := room_rect.position * scroll_scale
	if anchor == Anchor.BOTTOM:
		anchored.y = view_size.y - size.y + (room_rect.end.y - view_size.y) * scroll_scale.y
	scroll_offset = anchored

	# Godot draws repeat copies on both sides of the plate; this many always spans the view.
	repeat_size = Vector2(size.x if repeat_x else 0.0, 0.0)
	repeat_times = 2 * ceili(view_size.x / size.x) if repeat_x else 1
