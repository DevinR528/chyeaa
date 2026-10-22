extends Node
## Autoload. user://player.cfg keeps the window position, size, and fullscreen flag.
## Saving the window leaves other sections in place, so later settings can share the file.

const PATH := "user://player.cfg"
const SECTION := "window"
const SAVE_DELAY := 0.4

var _live := false
var _applying := false
var _dirty := false
var _have_rect := false
var _position := Vector2i.ZERO
var _size := Vector2i.ZERO
var _fullscreen := false
var _timer: Timer


func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		return
	_timer = Timer.new()
	_timer.one_shot = true
	_timer.wait_time = SAVE_DELAY
	_timer.timeout.connect(_flush)
	add_child(_timer)
	get_tree().root.size_changed.connect(func() -> void: remember_window(false))
	var loaded := read_window(PATH)
	if loaded.is_empty():
		# The first layout pass is not a placement the player chose.
		await get_tree().process_frame
		_live = true
		return
	_live = true
	await _apply(loaded)


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_WM_POSITION_CHANGED, NOTIFICATION_WM_SIZE_CHANGED:
			remember_window(false)
		NOTIFICATION_WM_CLOSE_REQUEST, NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_WM_WINDOW_FOCUS_OUT:
			remember_window(true)


## Reads the live window. Fullscreen reports the monitor size, so that mode keeps the stored rect.
func remember_window(flush_now := false) -> void:
	if not _live or _applying:
		return
	var mode := DisplayServer.window_get_mode()
	var fullscreen := (
		mode == DisplayServer.WINDOW_MODE_FULLSCREEN
		or mode == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN
	)
	var position := _position
	var size := _size
	if not fullscreen:
		position = DisplayServer.window_get_position()
		size = DisplayServer.window_get_size()
	var next := next_window(_stored(), fullscreen, position, size)
	if next.is_empty():
		return
	_position = next.position
	_size = next.size
	_fullscreen = next.fullscreen
	_have_rect = true
	_dirty = true
	if flush_now:
		_timer.stop()
		_flush()
	elif _timer.is_stopped():
		_timer.start()


func _apply(loaded: Dictionary) -> void:
	_applying = true
	var screens := _usable_screens()
	var fitted: Dictionary = fit_to_screens(loaded.position, loaded.size, screens)
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(fitted.size)
	DisplayServer.window_set_position(fitted.position)
	if loaded.fullscreen:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	_position = fitted.position
	_size = fitted.size
	_fullscreen = loaded.fullscreen
	_have_rect = true
	if fitted.position != loaded.position or fitted.size != loaded.size:
		write_window(PATH, fitted.position, fitted.size, loaded.fullscreen)
	await get_tree().process_frame
	_applying = false


func _flush() -> void:
	if not _dirty or not _have_rect:
		return
	_dirty = false
	write_window(PATH, _position, _size, _fullscreen)


func _stored() -> Dictionary:
	if not _have_rect:
		return {}
	return {position = _position, size = _size, fullscreen = _fullscreen}


func _usable_screens() -> Array[Rect2i]:
	var screens: Array[Rect2i] = []
	var count := DisplayServer.get_screen_count()
	if count <= 0:
		return screens
	var current := clampi(DisplayServer.window_get_current_screen(), 0, count - 1)
	screens.append(DisplayServer.screen_get_usable_rect(current))
	for index in count:
		if index != current:
			screens.append(DisplayServer.screen_get_usable_rect(index))
	return screens


## The current screen is first. A rect that misses every screen is pulled onto that one.
static func fit_to_screens(position: Vector2i, size: Vector2i, screens: Array[Rect2i]) -> Dictionary:
	var fitted_size := Vector2i(maxi(size.x, 1), maxi(size.y, 1))
	if screens.is_empty():
		return {position = position, size = fitted_size}
	var screen := _screen_for(Rect2i(position, fitted_size), screens)
	fitted_size = Vector2i(mini(fitted_size.x, screen.size.x), mini(fitted_size.y, screen.size.y))
	var max_position := screen.position + screen.size - fitted_size
	return {
		position = Vector2i(
			clampi(position.x, screen.position.x, max_position.x),
			clampi(position.y, screen.position.y, max_position.y)
		),
		size = fitted_size,
	}


static func read_window(path: String) -> Dictionary:
	var config := ConfigFile.new()
	if config.load(path) != OK:
		return {}
	if not config.has_section_key(SECTION, "position") or not config.has_section_key(SECTION, "size"):
		return {}
	var position = _vector2i_or_null(config.get_value(SECTION, "position"))
	var size = _vector2i_or_null(config.get_value(SECTION, "size"))
	if position == null or size == null or size.x <= 0 or size.y <= 0:
		return {}
	return {
		position = position,
		size = size,
		fullscreen = bool(config.get_value(SECTION, "fullscreen", false)),
	}


## Loads the file first so a window write does not drop sections added later.
static func write_window(path: String, position: Vector2i, size: Vector2i, fullscreen: bool) -> void:
	var config := ConfigFile.new()
	var err := config.load(path)
	if err != OK and err != ERR_FILE_NOT_FOUND:
		push_error("player data could not be read: %s" % error_string(err))
		return
	config.set_value(SECTION, "position", position)
	config.set_value(SECTION, "size", size)
	config.set_value(SECTION, "fullscreen", fullscreen)
	err = config.save(path)
	if err != OK:
		push_error("player data could not be saved: %s" % error_string(err))


## Fullscreen keeps the previous windowed rect. An empty result means there is nothing to store yet.
static func next_window(current: Dictionary, fullscreen: bool, position: Vector2i, size: Vector2i) -> Dictionary:
	var stored_position: Vector2i = current.get("position", Vector2i.ZERO)
	var stored_size: Vector2i = current.get("size", Vector2i.ZERO)
	var have := current.has("size") and stored_size.x > 0 and stored_size.y > 0
	if not fullscreen and size.x > 0 and size.y > 0:
		stored_position = position
		stored_size = size
		have = true
	if not have:
		return {}
	return {position = stored_position, size = stored_size, fullscreen = fullscreen}


static func _screen_for(window: Rect2i, screens: Array[Rect2i]) -> Rect2i:
	var best := screens[0]
	var best_area := -1
	for screen in screens:
		var overlap := window.intersection(screen)
		var area := overlap.size.x * overlap.size.y if overlap.size.x > 0 and overlap.size.y > 0 else 0
		if area > best_area:
			best_area = area
			best = screen
	return best


static func _vector2i_or_null(value: Variant) -> Variant:
	if value is Vector2i:
		return value
	if value is Vector2:
		return Vector2i(roundi(value.x), roundi(value.y))
	return null
