class_name Backdrop
extends Node2D
## Parallax backdrop behind whatever room is playing. It lives beside the room,
## not in it, and is drawn first; the runner frames it to each room it plays.
## Children are BackdropLayers, back to front.


func _ready() -> void:
	# Room content may use a negative z_index (props behind the player); tree order
	# alone would put those behind the backdrop.
	z_index = RenderingServer.CANVAS_ITEM_Z_MIN


func frame(room_rect: Rect2, view_size: Vector2) -> void:
	for layer in layers():
		layer.frame(room_rect, view_size)


func layers() -> Array[BackdropLayer]:
	var found: Array[BackdropLayer] = []
	for child in get_children():
		if child is BackdropLayer:
			found.append(child)
	return found
