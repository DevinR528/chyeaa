class_name FollowCamera
extends Camera2D
## Tracks the target's origin. The drag margins are the prototype's dead zone, and
## position smoothing is its catch-up ease. Limits keep the view inside the room.

@export var target: Node2D

var shake := ScreenShake.new()


func _physics_process(_delta: float) -> void:
	if target != null:
		global_position = target.global_position


func _process(delta: float) -> void:
	shake.tick(delta)
	# Moving the camera right shifts the frame left, hence the sign inversion.
	# Requests are screen pixels while Camera2D offset is in world units.
	offset = -shake.offset / zoom


func request_shake(seconds: float, amplitude: float, frequency := ScreenShake.DEFAULT_FREQUENCY, direction := Vector2.ZERO) -> void:
	shake.request(seconds, amplitude, frequency, direction)


func clear_shake() -> void:
	shake.clear()
	offset = Vector2.ZERO


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
