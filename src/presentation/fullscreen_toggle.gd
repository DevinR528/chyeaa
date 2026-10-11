extends Node
## Autoload: F11 grows the window in quarter-scale steps, then enters fullscreen.
## Shift+F11 shrinks it. The game's fixed-aspect view scales with the window.

const VIEW_SIZE := Vector2i(840, 504)
const MIN_WINDOW_SCALE := 1.0
const WINDOW_SCALE_STEP := 0.25
const MAX_WORK_AREA_FILL := 0.95


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed(&"toggle_fullscreen") or event.is_echo():
		return
	var direction := -1 if event is InputEventKey and event.shift_pressed else 1
	_step_window_size(direction)
	get_viewport().set_input_as_handled()


func _step_window_size(direction: int) -> void:
	var fullscreen := DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
	if fullscreen:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		_set_window_scale(_largest_windowed_scale() if direction < 0 else MIN_WINDOW_SCALE)
		return

	var current_scale := _current_window_scale()
	var largest_scale := _largest_windowed_scale()
	if direction > 0 and current_scale + WINDOW_SCALE_STEP > largest_scale:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
		return

	var next_scale := current_scale + WINDOW_SCALE_STEP * direction
	_set_window_scale(clampf(next_scale, MIN_WINDOW_SCALE, largest_scale))


func _current_window_scale() -> float:
	var window_size := DisplayServer.window_get_size()
	var scale := minf(
		float(window_size.x) / float(VIEW_SIZE.x),
		float(window_size.y) / float(VIEW_SIZE.y)
	)
	return snappedf(scale, WINDOW_SCALE_STEP)


func _largest_windowed_scale() -> float:
	var screen := DisplayServer.window_get_current_screen()
	var usable_size := DisplayServer.screen_get_usable_rect(screen).size
	var fit_scale := minf(
		float(usable_size.x) / float(VIEW_SIZE.x),
		float(usable_size.y) / float(VIEW_SIZE.y)
	) * MAX_WORK_AREA_FILL
	return maxf(MIN_WINDOW_SCALE, floorf(fit_scale / WINDOW_SCALE_STEP) * WINDOW_SCALE_STEP)


func _set_window_scale(scale: float) -> void:
	var size := Vector2i(
		roundi(float(VIEW_SIZE.x) * scale),
		roundi(float(VIEW_SIZE.y) * scale)
	)
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(size)

	var screen := DisplayServer.window_get_current_screen()
	var usable_rect := DisplayServer.screen_get_usable_rect(screen)
	DisplayServer.window_set_position(usable_rect.position + (usable_rect.size - size) / 2)
