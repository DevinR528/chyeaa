extends SceneTree
## Window rect persistence: file round-trip, fullscreen keeping the windowed rect,
## and a saved position pulled back onto a screen that exists.

const PlayerDataScript := preload("res://src/player_data.gd")
const TEST_FILE := "player_data_smoke.cfg"
const TEST_PATH := "user://" + TEST_FILE

var _failed := false


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_cleanup()
	_check_round_trip()
	_check_rejected_values()
	_check_preserved_section()
	_check_fullscreen_keeps_windowed_rect()
	_check_fit_to_screens()
	_cleanup()
	quit(1 if _failed else 0)


func _check_round_trip() -> void:
	_expect(PlayerDataScript.read_window(TEST_PATH).is_empty(), "missing player data loaded a window")
	PlayerDataScript.write_window(TEST_PATH, Vector2i(120, 80), Vector2i(1260, 756), true)
	var loaded: Dictionary = PlayerDataScript.read_window(TEST_PATH)
	_expect(
		loaded.position == Vector2i(120, 80)
		and loaded.size == Vector2i(1260, 756)
		and loaded.fullscreen,
		"saved window was %s" % loaded
	)

	var config := ConfigFile.new()
	config.set_value("window", "position", Vector2(12, 34))
	config.set_value("window", "size", Vector2(100.2, 200.6))
	config.save(TEST_PATH)
	loaded = PlayerDataScript.read_window(TEST_PATH)
	_expect(
		loaded.position == Vector2i(12, 34) and loaded.size == Vector2i(100, 201) and not loaded.fullscreen,
		"vector2 window was %s" % loaded
	)


func _check_rejected_values() -> void:
	var config := ConfigFile.new()
	config.set_value("window", "position", Vector2i(1, 1))
	config.set_value("window", "size", Vector2i(0, 10))
	config.save(TEST_PATH)
	_expect(PlayerDataScript.read_window(TEST_PATH).is_empty(), "zero size was restored")

	config.set_value("window", "size", Vector2i(-5, 40))
	config.save(TEST_PATH)
	_expect(PlayerDataScript.read_window(TEST_PATH).is_empty(), "negative size was restored")

	config.set_value("window", "position", "nope")
	config.set_value("window", "size", Vector2i(100, 80))
	config.save(TEST_PATH)
	_expect(PlayerDataScript.read_window(TEST_PATH).is_empty(), "non-vector position was restored")


func _check_preserved_section() -> void:
	var config := ConfigFile.new()
	config.set_value("input", "placeholder", "later")
	config.save(TEST_PATH)
	PlayerDataScript.write_window(TEST_PATH, Vector2i(10, 20), Vector2i(840, 504), false)
	config = ConfigFile.new()
	_expect(config.load(TEST_PATH) == OK, "player data file was not written")
	_expect(config.get_value("input", "placeholder") == "later", "window save dropped another section")
	var loaded: Dictionary = PlayerDataScript.read_window(TEST_PATH)
	_expect(
		loaded.position == Vector2i(10, 20) and loaded.size == Vector2i(840, 504) and not loaded.fullscreen,
		"preserved file lost the window: %s" % loaded
	)


func _check_fullscreen_keeps_windowed_rect() -> void:
	var windowed := {position = Vector2i(40, 50), size = Vector2i(840, 504), fullscreen = false}
	var fullscreen: Dictionary = PlayerDataScript.next_window(windowed, true, Vector2i(0, 0), Vector2i(1920, 1080))
	_expect(
		fullscreen.position == Vector2i(40, 50)
		and fullscreen.size == Vector2i(840, 504)
		and fullscreen.fullscreen,
		"fullscreen replaced the windowed rect with %s" % fullscreen
	)
	var moved: Dictionary = PlayerDataScript.next_window(fullscreen, false, Vector2i(90, 70), Vector2i(1050, 630))
	_expect(
		moved.position == Vector2i(90, 70) and moved.size == Vector2i(1050, 630) and not moved.fullscreen,
		"leaving fullscreen kept %s" % moved
	)
	_expect(
		PlayerDataScript.next_window({}, true, Vector2i(0, 0), Vector2i(1920, 1080)).is_empty(),
		"fullscreen with no windowed rect was stored"
	)
	var kept: Dictionary = PlayerDataScript.next_window(windowed, false, Vector2i(1, 1), Vector2i(0, 10))
	_expect(kept.position == windowed.position and kept.size == windowed.size, "zero size wiped the stored rect")


func _check_fit_to_screens() -> void:
	var screens: Array[Rect2i] = [Rect2i(0, 0, 1920, 1080), Rect2i(-1920, 0, 1920, 1080)]
	var inside := PlayerDataScript.fit_to_screens(Vector2i(100, 80), Vector2i(840, 504), screens)
	_expect(inside.position == Vector2i(100, 80) and inside.size == Vector2i(840, 504), "on-screen window moved to %s" % inside)

	var second := PlayerDataScript.fit_to_screens(Vector2i(-1500, 100), Vector2i(840, 504), screens)
	_expect(
		second.position == Vector2i(-1500, 100) and second.size == Vector2i(840, 504),
		"window on the other screen moved to %s" % second
	)

	var gone := PlayerDataScript.fit_to_screens(Vector2i(5000, 4000), Vector2i(840, 504), screens)
	_expect(gone.position == Vector2i(1080, 576) and gone.size == Vector2i(840, 504), "off-screen window landed at %s" % gone)

	var huge := PlayerDataScript.fit_to_screens(Vector2i(100, 80), Vector2i(4000, 3000), screens)
	_expect(huge.position == Vector2i(0, 0) and huge.size == Vector2i(1920, 1080), "oversized window became %s" % huge)

	var overhang := PlayerDataScript.fit_to_screens(Vector2i(1800, 100), Vector2i(840, 504), screens)
	_expect(overhang.position == Vector2i(1080, 100) and overhang.size == Vector2i(840, 504), "overhanging window became %s" % overhang)


func _cleanup() -> void:
	var dir := DirAccess.open("user://")
	if dir != null and dir.file_exists(TEST_FILE):
		dir.remove(TEST_FILE)


func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	_failed = true
	push_error(message)
