class_name FollowCamera
extends Camera2D
## Tracks the target's origin. The drag margins are the prototype's dead zone, and
## position smoothing is its catch-up ease. Limits keep the view inside the room.

@export var target: Node2D

var shake := ScreenShake.new()


var _rewind_hold := false
var _smoothing_before := false


func _physics_process(_delta: float) -> void:
	if target == null:
		return
	global_position = target.global_position
	if _rewind_hold:
		_commit_scroll()


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


## Rewind runs while the tree is paused, so smoothing would keep the old frame.
func hold_for_rewind(held: bool) -> void:
	if held == _rewind_hold:
		return
	_rewind_hold = held
	if held:
		_smoothing_before = position_smoothing_enabled
		position_smoothing_enabled = false
		process_mode = Node.PROCESS_MODE_ALWAYS
		snap_to_target()
	else:
		position_smoothing_enabled = _smoothing_before
		process_mode = Node.PROCESS_MODE_INHERIT


## Centers on the target with no easing (room entry, respawn, and rewind).
func snap_to_target() -> void:
	if target == null:
		return
	global_position = target.global_position
	_commit_scroll()


func _commit_scroll() -> void:
	var was := position_smoothing_enabled
	position_smoothing_enabled = false
	reset_smoothing()
	force_update_scroll()
	reset_physics_interpolation()
	if not _rewind_hold:
		position_smoothing_enabled = was
