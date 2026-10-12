extends SceneTree
## Debug readout and contact log stay off the simulation: the same inputs land
## on the same state with the readout hidden or shown, and a stomp is captured
## as data rather than console text.

const Rooms := preload("res://tests/test_room_builder.gd")
const STANDARD_SCENE := preload("res://scenes/player/standard.tscn")
const WALKER_SCENE := preload("res://scenes/actors/walker.tscn")
const FLOOR_Y := Rooms.FLOOR_ROW * Rooms.TILE

var _failed := false


func _initialize() -> void:
	var off := await _trace(false)
	var on := await _trace(true)
	_expect(_same(off, on), "debug readout changed the run: off %s on %s" % [off, on])
	await _check_stomp_record()
	await _check_toggle()
	_release_input()
	ContactLog.enabled = false
	ContactLog.clear()
	if _failed:
		quit(1)
	else:
		quit(0)


func _trace(debug_on: bool) -> Dictionary:
	ContactLog.enabled = debug_on
	ContactLog.clear()
	var room := Rooms.make_room(root, func(_layers: Dictionary) -> void: pass)
	var player := STANDARD_SCENE.instantiate() as PlayerBody
	room.add_child(player)
	var feet := Vector2(48, FLOOR_Y)
	# Enter the tree before respawn so the body shape exists, and so the floor does too.
	await physics_frame
	player.respawn(feet)
	var readout := PlayReadout.new()
	readout.player = player
	readout.shown = debug_on
	root.add_child(readout)
	Input.action_press(&"move_right")
	player.apply_jump()
	for frame in 24:
		await physics_frame
	var snap := {
		"position": player.global_position,
		"velocity": player.velocity,
		"move_state": player.move_state,
		"grounded": player.is_on_floor(),
		"coyote": player.coyote_time_left,
	}
	if debug_on:
		_expect(readout._label.text.contains("grounded"), "readout did not list grounded")
		_expect(readout._label.text.contains("kind"), "readout did not list the kind under the feet")
	_release_input()
	readout.free()
	room.free()
	return snap


func _check_stomp_record() -> void:
	var off := await _stomp(false)
	var on := await _stomp(true)
	_expect(_same(off.state, on.state), "contact logging changed the stomp: off %s on %s" % [off.state, on.state])
	_expect(off.records.is_empty(), "contact log recorded while disabled")
	var stomp: Dictionary = {}
	for entry in on.records:
		if entry.get("decision") == "stomp":
			stomp = entry
			break
	_expect(not stomp.is_empty(), "no stomp decision was captured: %s" % [on.records])
	if stomp.is_empty():
		return
	_expect(stomp["participants"] is Array and stomp["participants"].size() == 2, "stomp participants were not both bodies")
	_expect(stomp["player_rect"] is Rect2 and stomp["target_rect"] is Rect2, "stomp did not keep both boxes")
	_expect(stomp["player_velocity"] is Vector2 and stomp["target_velocity"] is Vector2, "stomp did not keep both velocities")
	_expect(stomp["feet_y"] is float and stomp["previous_feet_y"] is float, "stomp did not keep swept feet")


func _stomp(debug_on: bool) -> Dictionary:
	ContactLog.enabled = debug_on
	ContactLog.clear()
	var room := Rooms.make_room(root, func(_layers: Dictionary) -> void: pass)
	var walker := Rooms.add_actor(room, WALKER_SCENE, Vector2(240, FLOOR_Y - 8), func(actor: RoomActor) -> void:
		(actor as Walker).speed = 0.0) as Walker
	var player := STANDARD_SCENE.instantiate() as PlayerBody
	room.add_child(player)
	player.global_position = Vector2(240, FLOOR_Y - 60)
	var died := false
	walker.died.connect(func(_cause: Walker.DeathCause) -> void: died = true)
	for _frame in 60:
		await physics_frame
		if died:
			break
	var result := {
		"state": {
			"position": player.global_position,
			"velocity": player.velocity,
			"alive": walker.alive,
		},
		"records": ContactLog.records.duplicate(true),
	}
	room.free()
	return result


func _same(off: Dictionary, on: Dictionary) -> bool:
	for key in off:
		if not on.has(key):
			return false
		var left: Variant = off[key]
		var right: Variant = on[key]
		if left is float or left is int:
			if not is_equal_approx(float(left), float(right)):
				return false
		elif left is Vector2:
			# A visible readout snaps the canvas by a fraction of a pixel.
			if (left as Vector2).distance_to(right) > 0.25:
				return false
		elif left != right:
			return false
	return true


func _check_toggle() -> void:
	var readout := PlayReadout.new()
	root.add_child(readout)
	await physics_frame
	var event := InputEventAction.new()
	event.action = &"toggle_debug"
	event.pressed = true
	readout._input(event)
	_expect(readout.shown and readout._label.visible, "toggle_debug did not show the readout")
	readout.free()


func _release_input() -> void:
	for action in [&"move_right", &"move_left", &"jump", &"dash"]:
		Input.action_release(action)


func _expect(ok: bool, message: String) -> void:
	if not ok:
		_failed = true
		push_error(message)
