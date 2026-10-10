class_name FollowCamera
extends Camera2D
## Tracks the target's origin. The drag margins are the prototype's dead zone, and
## position smoothing is its catch-up ease. Limits keep the view inside the room.

@export var target: Node2D


func _physics_process(_delta: float) -> void:
	if target != null:
		global_position = target.global_position


func frame_room(rect: Rect2) -> void:
	limit_left = floori(rect.position.x)
	limit_top = floori(rect.position.y)
	limit_right = ceili(rect.end.x)
	limit_bottom = ceili(rect.end.y)


## Centers on the target with no easing (room entry and respawn).
func snap_to_target() -> void:
	global_position = target.global_position
	align()
	reset_smoothing()
	reset_physics_interpolation()
