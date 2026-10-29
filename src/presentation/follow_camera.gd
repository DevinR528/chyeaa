class_name FollowCamera
extends Camera2D
## Tracks the target's origin. The drag margins are the prototype's dead zone, and
## position smoothing is its catch-up ease. Limits keep the view inside the room.

@export var _debug: bool = false

@export_range(-200.0, 700.0) var CAMERA_OFFSET: float = -100.0
@export var target: Node2D

var shake := ScreenShake.new()

## Horizontal look limit, in world units. Shorter than the vertical look.
@export var PAN_MAX_X: float = 70.0
## Vertical look limit, in world units.
@export var PAN_MAX_Y: float = 100.0
## Speed at the start of a full look on the longer axis. Closing speed is the
## remaining gap over that same time, so the offset slows as it nears the limit.
@export var PAN_SPEED: float = 200.0
var _pan_input: Vector2 = Vector2.ZERO
var _pan_offset: Vector2 = Vector2.ZERO

var _rewind_hold := false
var _smoothing_before := false


func _physics_process(_delta: float) -> void:
	if target == null:
		return
	_set_global_pos(target.global_position)
	if _rewind_hold:
		_commit_scroll()


func _process(delta: float) -> void:
	shake.tick(delta)
	# Moving the camera right shifts the frame left, hence the sign inversion.
	# Requests are screen pixels while Camera2D offset is in world units.
	# Pan eases toward the stick and slows into the limit ellipse. Releasing
	# the stick eases back to center. Shake stays in screen pixels.
	_pan_offset = _ease_pan(delta)
	offset = -shake.offset / zoom + _pan_offset
	# TODO: remove, this is only for debug code
	queue_redraw()


func bind_player(player: PlayerBody):
	target = player
	player.player_input.connect("camera_pan", on_camera_pan)

func request_shake(seconds: float, amplitude: float, frequency := ScreenShake.DEFAULT_FREQUENCY, direction := Vector2.ZERO) -> void:
	shake.request(seconds, amplitude, frequency, direction)


func clear_shake() -> void:
	shake.clear()
	offset = _pan_offset


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
	_set_global_pos(target.global_position)
	_commit_scroll()


func _commit_scroll() -> void:
	var was := position_smoothing_enabled
	position_smoothing_enabled = false
	reset_smoothing()
	force_update_scroll()
	reset_physics_interpolation()
	if not _rewind_hold:
		position_smoothing_enabled = was


func _set_global_pos(pos: Vector2) -> void:
	global_position = pos + Vector2(0, CAMERA_OFFSET)


func get_camera_drag_rect() -> Rect2:
	var viewport_size = get_viewport().get_visible_rect().size
	var world_viewport_size = viewport_size / zoom
	
	var camera_center: Vector2 = get_target_position()
	
	var left = drag_left_margin
	var right = drag_right_margin
	var top = drag_top_margin
	var bottom = drag_bottom_margin
	
	var left_bound   = camera_center.x - (world_viewport_size.x / 2.0) * left
	var right_bound  = camera_center.x + (world_viewport_size.x / 2.0) * right
	var top_bound    = camera_center.y - (world_viewport_size.y / 2.0) * top
	var bottom_bound = camera_center.y + (world_viewport_size.y / 2.0) * bottom
	
	var rect_position = Vector2(left_bound, top_bound)
	var rect_size = Vector2(right_bound - left_bound, bottom_bound - top_bound)
	
	return Rect2(to_local(rect_position), rect_size)


func _draw() -> void:
	if !_debug: return
	var drag = get_camera_drag_rect()
	draw_rect(drag, Color.SEA_GREEN, false, 2.0)


func _ease_pan(delta: float) -> Vector2:
	var p_target := _pan_target()
	var span := maxf(PAN_MAX_X, PAN_MAX_Y)
	if span <= 0.0:
		return Vector2.ZERO
	if PAN_SPEED <= 0.0:
		return _pan_offset
	var blend := 1.0 - exp(-delta * PAN_SPEED / span)
	return _pan_offset.lerp(p_target, blend)


func _pan_target() -> Vector2:
	var stick := _pan_input.limit_length(1.0)
	return Vector2(stick.x * PAN_MAX_X, stick.y * PAN_MAX_Y)


# SIGNAL handlers
# =============================================================

func on_camera_pan(pan_move: Vector2) -> void:
	_pan_input = pan_move
