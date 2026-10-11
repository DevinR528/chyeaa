extends SceneTree
## Grapple and pogo strike checks in small rooms built in code.

const Rooms := preload("res://tests/test_room_builder.gd")
const GRAPPLER_SCENE := preload("res://scenes/player/grappler.tscn")
const POGO_SCENE := preload("res://scenes/player/pogo.tscn")
const FLOOR_ROW := Rooms.FLOOR_ROW
const TILE := Rooms.TILE

var _failed := false
var _hitstops: Array[float] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	await _check_grapple_latches_and_pulls()
	await _check_grapple_jump_off()
	await _check_grapple_blocked_by_solid()
	await _check_pogo_down_bounce()
	await _check_pogo_side_pop()
	quit(1 if _failed else 0)


func _check_grapple_latches_and_pulls() -> void:
	var room := Rooms.make_room(root, _grapple_wall)
	var player := _spawn(room, GRAPPLER_SCENE, Vector2(80, FLOOR_ROW * TILE))
	var grapple := player.ability as Grapple
	await _physics_frames(2)

	Input.action_press(&"action")
	var attached_frame := -1
	var fastest := 0.0
	for frame in 40:
		await physics_frame
		if attached_frame < 0 and grapple.state == Grapple.State.ATTACHED:
			attached_frame = frame
		fastest = maxf(fastest, player.velocity.x)
	_expect(attached_frame >= 0 and attached_frame < 20, "grapple did not latch a grapple wall 20 tiles away (frame %d)" % attached_frame)
	_expect(_hitstops.has(grapple.hitstop), "grapple latch did not request hitstop")
	_expect(fastest > player.stats.max_run, "grapple pull was not faster than running")

	Input.action_release(&"action")
	await _physics_frames(2)
	_expect(grapple.state == Grapple.State.RETRACT or grapple.state == Grapple.State.INACTIVE, "releasing action did not let go")
	await _free(room, player)


func _check_grapple_jump_off() -> void:
	var room := Rooms.make_room(root, _grapple_wall)
	var player := _spawn(room, GRAPPLER_SCENE, Vector2(80, FLOOR_ROW * TILE))
	var grapple := player.ability as Grapple
	await _physics_frames(2)

	Input.action_press(&"action")
	for _frame in 20:
		await physics_frame
		if grapple.state == Grapple.State.ATTACHED:
			break
	Input.action_press(&"jump")
	var highest_launch := 0.0
	for _frame in 3:
		await physics_frame
		highest_launch = minf(highest_launch, player.velocity.y)
	Input.action_release(&"jump")
	Input.action_release(&"action")
	_expect(is_equal_approx(highest_launch, grapple.jump_velocity), "jumping off the grapple did not use the grapple jump (%f)" % highest_launch)
	_expect(grapple.state != Grapple.State.ATTACHED, "jumping off left the grapple attached")
	await _free(room, player)


func _check_grapple_blocked_by_solid() -> void:
	var room := Rooms.make_room(root, func(layers: Dictionary) -> void:
		Rooms.paint_column(layers.Terrain, 30, 18, FLOOR_ROW - 1, Rooms.SOLID_TILE))
	var player := _spawn(room, GRAPPLER_SCENE, Vector2(80, FLOOR_ROW * TILE))
	var grapple := player.ability as Grapple
	await _physics_frames(2)

	Input.action_press(&"action")
	var ever_attached := false
	var retracted := false
	for _frame in 30:
		await physics_frame
		ever_attached = ever_attached or grapple.state == Grapple.State.ATTACHED
		retracted = retracted or grapple.state == Grapple.State.RETRACT
	Input.action_release(&"action")
	_expect(not ever_attached, "grapple latched onto a plain solid wall")
	_expect(retracted, "grapple did not retract after hitting a solid wall")
	await _free(room, player)


func _check_pogo_down_bounce() -> void:
	var room := Rooms.make_room(root, func(layers: Dictionary) -> void:
		Rooms.paint_row(layers.PogoSurfaces, 25, 1, Rooms.ROOM_SIZE.x - 2, Rooms.POGO_TILE))
	var player := _spawn(room, POGO_SCENE, Vector2(240, 120))
	var strike := player.ability as PogoStrike
	player.dash_cooldown_left = 1.0
	await _physics_frames(2)

	Input.action_press(&"move_down")
	await physics_frame
	Input.action_press(&"action")
	var launch := 0.0
	var struck := false
	for _frame in 30:
		await physics_frame
		struck = struck or strike.state == PogoStrike.State.STRIKE
		launch = minf(launch, player.velocity.y)
	Input.action_release(&"action")
	Input.action_release(&"move_down")
	var expected := -sqrt(2.0 * player.stats.gravity * strike.bounce_tiles * TILE)
	_expect(struck, "down + action in the air did not strike")
	_expect(is_equal_approx(launch, expected), "down strike on a pogo tile launched %f, expected %f" % [launch, expected])
	_expect(is_zero_approx(player.dash_cooldown_left), "pogo bounce did not refresh the dash")
	await _free(room, player)


func _check_pogo_side_pop() -> void:
	var room := Rooms.make_room(root, func(layers: Dictionary) -> void:
		Rooms.paint_column(layers.PogoSurfaces, 20, 1, FLOOR_ROW - 1, Rooms.POGO_TILE))
	var player := _spawn(room, POGO_SCENE, Vector2(140, 150))
	var strike := player.ability as PogoStrike
	await _physics_frames(2)

	Input.action_press(&"move_right")
	await physics_frame
	Input.action_press(&"action")
	var launch := 0.0
	var recoil := 0.0
	var locked := false
	for _frame in 4:
		await physics_frame
		launch = minf(launch, player.velocity.y)
		recoil = minf(recoil, player.velocity.x)
		locked = locked or strike.side_lock_left > 0.0
	Input.action_release(&"action")
	Input.action_release(&"move_right")
	var expected := -sqrt(2.0 * player.stats.gravity * strike.side_pop_tiles * TILE)
	_expect(is_equal_approx(launch, expected), "side strike popped %f, expected %f" % [launch, expected])
	_expect(is_equal_approx(recoil, -strike.side_recoil), "side strike did not recoil off the face (%f)" % recoil)
	_expect(locked, "side pop did not lock horizontal input")
	_expect(_hitstops.has(strike.side_hitstop), "side pop did not request hitstop")
	await _free(room, player)


func _grapple_wall(layers: Dictionary) -> void:
	Rooms.paint_column(layers.GrappleSurfaces, 30, 18, FLOOR_ROW - 1, Rooms.GRAPPLE_TILE)


func _spawn(room: Room, scene: PackedScene, feet: Vector2) -> PlayerBody:
	var player := Rooms.spawn_player(root, room, scene, feet)
	_hitstops.clear()
	player.hitstop_requested.connect(func(seconds: float) -> void: _hitstops.append(seconds))
	return player


func _free(room: Room, player: PlayerBody) -> void:
	player.free()
	room.free()
	await process_frame


func _physics_frames(count: int) -> void:
	for _frame in count:
		await physics_frame


func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	_failed = true
	push_error(message)
