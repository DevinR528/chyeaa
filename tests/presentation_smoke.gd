extends SceneTree
## Pure shake/vignette math plus Pogo hitstop-to-shake integration.

const Rooms := preload("res://tests/test_room_builder.gd")
const POGO_SCENE := preload("res://scenes/player/pogo.tscn")

var _failed := false


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_check_screen_shake()
	_check_vignette_values()
	await _check_pogo_shake_order()
	quit(1 if _failed else 0)


func _check_screen_shake() -> void:
	var shake := ScreenShake.new()
	shake.request(1.0, 10.0, 1.0, Vector2(2.0, 0.0))
	_expect(is_equal_approx(shake.strength(), 10.0), "shake did not begin at peak strength")
	shake.request(2.0, 9.0, 3.0)
	_expect(is_equal_approx(shake.duration, 1.0), "weaker request replaced an active shake")
	shake.tick(0.25)
	_expect(shake.offset.is_equal_approx(Vector2(5.625, 0.0)), "directional quadratic shake was %s" % shake.offset)
	var camera := FollowCamera.new()
	camera.zoom = Vector2.ONE * 2.0
	camera.request_shake(1.0, 10.0, 1.0, Vector2.RIGHT)
	camera._process(0.25)
	_expect(camera.offset.is_equal_approx(Vector2(-2.8125, 0.0)), "camera did not preserve screen-pixel shake at zoom")
	camera.free()
	shake.clear()
	_expect(not shake.is_active() and shake.offset == Vector2.ZERO, "shake clear left active state")


func _check_vignette_values() -> void:
	var transform := Transform2D(
		Vector2(2.0, 0.0),
		Vector2(0.0, 2.0),
		Vector2(-18.0, -7.0),
	)
	var values := Vignette.screen_values(
		Vector2(100.0, 40.0),
		transform,
		Vector2.ONE * 2.0,
		80.0,
		176.0,
		0.22,
	)
	_expect(values.center == Vector2(182.0, 73.0), "vignette center ignored final canvas transform")
	_expect(is_equal_approx(values.inner, 160.0) and is_equal_approx(values.outer, 352.0), "vignette radii did not follow zoom")
	_expect(is_equal_approx(values.darkness, 0.22), "vignette darkness changed")


func _check_pogo_shake_order() -> void:
	var runner := RoomRunner.new()
	runner.process_physics_priority = -10
	var room := Rooms.make_room(runner, func(_layers: Dictionary) -> void: pass)
	var camera := FollowCamera.new()
	camera.process_physics_priority = 30
	camera.process_callback = Camera2D.CAMERA2D_PROCESS_PHYSICS
	runner.add_child(camera)
	runner.room = room
	runner.camera = camera
	runner.characters = [POGO_SCENE]
	runner.character_index = 0
	root.add_child(runner)
	await physics_frame

	var pogo := runner.player.ability as PogoStrike
	pogo._side_pop(1.0)
	_expect(runner.hitstop_left > 0.0, "Pogo side pop did not request hitstop")
	_expect(not camera.shake.is_active(), "shake began before hitstop released")
	for _frame in 10:
		await physics_frame
		if runner.hitstop_left <= 0.0:
			break
		_expect(not camera.shake.is_active(), "shake ran during hitstop")
	_expect(runner.hitstop_left <= 0.0, "hitstop did not finish")
	_expect(camera.shake.is_active(), "shake did not start when hitstop released")
	_expect(camera.shake.direction == Vector2.RIGHT, "shake did not retain struck-side direction")
	_expect(
		is_equal_approx(camera.shake.duration, pogo.side_shake_seconds)
		and is_equal_approx(camera.shake.amplitude, pogo.side_shake_amplitude)
		and is_equal_approx(camera.shake.frequency, pogo.side_shake_frequency),
		"RoomRunner replaced Pogo's shake tuning",
	)

	runner.restart(RoomRunner.RestartReason.DEATH)
	_expect(not camera.shake.is_active(), "restart did not clear shake")
	pogo._side_pop(-1.0)
	runner.switch_character(0)
	_expect(not camera.shake.is_active(), "character switch did not clear shake")
	runner.queue_free()
	await process_frame


func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	_failed = true
	push_error(message)
