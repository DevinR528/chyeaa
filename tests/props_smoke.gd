extends SceneTree
## Tile prop checks: riding, ceilings, breaking, grapple and pogo surfaces, hazards,
## per-character exclusion, crushing, and spin layout.

const Rooms := preload("res://tests/test_room_builder.gd")
const STANDARD_SCENE := preload("res://scenes/player/standard.tscn")
const GRAPPLER_SCENE := preload("res://scenes/player/grappler.tscn")
const POGO_SCENE := preload("res://scenes/player/pogo.tscn")
const BLOCK_SCENE := preload("res://scenes/props/block.tscn")
const MOVING_PLATFORM_SCENE := preload("res://scenes/props/moving_platform.tscn")
const BREAKABLE_SCENE := preload("res://scenes/props/breakable.tscn")
const WINDMILL_SCENE := preload("res://scenes/props/windmill.tscn")
const SWITCH_SCENE := preload("res://scenes/props/switch.tscn")
const GATE_SCENE := preload("res://scenes/props/gate.tscn")
const FALL_BLOCK_SCENE := preload("res://scenes/props/fall_block.tscn")
const FLOOR_ROW := Rooms.FLOOR_ROW
const TILE := Rooms.TILE
const FLOOR_Y := FLOOR_ROW * TILE

var _failed := false
var _touched: Array[int] = []
var _crushed := false


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	await _check_rider_keeps_feet()
	await _check_jump_into_descending_platform()
	await _check_breakable_stood_on()
	await _check_grapple_rides_prop()
	await _check_pogo_bounces_off_prop()
	await _check_death_prop_reports_hazard()
	await _check_surface_exclusion()
	await _check_crush_against_wall()
	await _check_one_solid_does_not_crush()
	await _check_spin_spreads_present_arms()
	await _check_switch_detects_player()
	await _check_switch_modes_and_reset()
	await _check_power_needs_and_effects()
	await _check_switch_room_isolation()
	await _check_fall_block()
	await _check_moving_platform_carries_prop()
	quit(1 if _failed else 0)


## The todo.md bug: feet must stay on a platform through its up and down moves.
func _check_rider_keeps_feet() -> void:
	var room := _empty_room()
	var platform := _moving_platform(room, Vector2(240, 160), Vector2(64, 16), OscillatingMotion.Axis.Y, 32.0, 2.0)
	var player := _spawn(room, STANDARD_SCENE, Vector2(240, platform.rect().position.y))
	await _physics_frames(10)

	var worst_gap := 0.0
	var airborne_frames := 0
	for _frame in 180:
		await physics_frame
		worst_gap = maxf(worst_gap, absf(player.body_rect().end.y - platform.rect().position.y))
		if not player.is_on_floor():
			airborne_frames += 1
	_expect(airborne_frames == 0, "rider left the platform for %d frames" % airborne_frames)
	# A one-tick lag here reads about 1px at this speed.
	_expect(worst_gap < 0.1, "rider's feet drifted %.2fpx from the platform top" % worst_gap)
	await _free(room, player)


## The todo.md bug: jumping up into a platform that is moving down must not end inside it.
func _check_jump_into_descending_platform() -> void:
	var room := _empty_room()
	var platform := _moving_platform(room, Vector2(240, FLOOR_Y - 60), Vector2(64, 16), OscillatingMotion.Axis.Y, 24.0, 3.0)
	var player := _spawn(room, STANDARD_SCENE, Vector2(240, FLOOR_Y))
	await _physics_frames(2)

	_send_action(&"jump", true)
	var worst_overlap := 0.0
	for _frame in 90:
		await physics_frame
		var overlap := player.body_rect().intersection(platform.rect())
		worst_overlap = maxf(worst_overlap, minf(overlap.size.x, overlap.size.y))
	_send_action(&"jump", false)
	_expect(worst_overlap < 0.1, "player sank %.2fpx into a platform moving down" % worst_overlap)
	await _free(room, player)


func _check_breakable_stood_on() -> void:
	var room := _empty_room()
	var prop := Rooms.add_prop(room, BREAKABLE_SCENE, Vector2(240, 200), Vector2(32, 16))
	prop.breakable.delay = 0.2
	prop.breakable.respawn = 0.5
	var player := _spawn(room, STANDARD_SCENE, Vector2(240, prop.rect().position.y))

	var vanished_frame := -1
	var returned := false
	for frame in 90:
		await physics_frame
		if vanished_frame < 0 and not prop.is_present():
			vanished_frame = frame
		elif vanished_frame >= 0 and prop.is_present():
			returned = true
			break
	_expect(vanished_frame >= 10 and vanished_frame <= 16, "breakable stood on vanished at frame %d, expected after its 0.2s delay" % vanished_frame)
	_expect(player.body_rect().end.y > prop.rect().end.y, "player did not fall through the vanished breakable")
	_expect(returned, "breakable did not respawn")
	await _free(room, player)


func _check_grapple_rides_prop() -> void:
	var room := _empty_room()
	var platform := _moving_platform(room, Vector2(240, FLOOR_Y - 24), Vector2(16, 48), OscillatingMotion.Axis.Y, 8.0, 3.0)
	platform.surface = Room.Kind.GRAPPLE
	var player := _spawn(room, GRAPPLER_SCENE, Vector2(80, FLOOR_Y))
	var grapple := player.ability as Grapple
	await _physics_frames(2)

	Input.action_press(&"action")
	for _frame in 20:
		await physics_frame
		if grapple.state == Grapple.State.ATTACHED:
			break
	_expect(grapple.attached_prop == platform, "grapple did not latch onto the grapple platform")
	var offset := grapple.hook - platform.global_position
	await _physics_frames(5)
	_expect(grapple.state == Grapple.State.ATTACHED, "grapple let go of a moving platform early")
	_expect((grapple.hook - platform.global_position).is_equal_approx(offset), "the hook did not move with the platform")
	Input.action_release(&"action")
	await _free(room, player)


func _check_pogo_bounces_off_prop() -> void:
	var room := _empty_room()
	Rooms.add_prop(room, BLOCK_SCENE, Vector2(240, 200), Vector2(96, 16), Room.Kind.POGO)
	var player := _spawn(room, POGO_SCENE, Vector2(240, 120))
	var strike := player.ability as PogoStrike
	player.dash_cooldown_left = 1.0
	await _physics_frames(2)

	Input.action_press(&"move_down")
	await physics_frame
	Input.action_press(&"action")
	var launch := 0.0
	for _frame in 30:
		await physics_frame
		launch = minf(launch, player.velocity.y)
	Input.action_release(&"action")
	Input.action_release(&"move_down")
	var expected := -sqrt(2.0 * player.stats.gravity * strike.bounce_tiles * TILE)
	_expect(is_equal_approx(launch, expected), "down strike on a pogo prop launched %f, expected %f" % [launch, expected])
	await _free(room, player)


func _check_death_prop_reports_hazard() -> void:
	var room := _empty_room()
	Rooms.add_prop(room, BLOCK_SCENE, Vector2(200, FLOOR_Y - 8), Vector2(16, 16), Room.Kind.DEATH)
	var player := _spawn(room, STANDARD_SCENE, Vector2(80, FLOOR_Y))
	await _physics_frames(2)
	_touched.clear()

	Input.action_press(&"move_right")
	for _frame in 60:
		await physics_frame
		if _touched.has(PhysicsLayers.HAZARD):
			break
	Input.action_release(&"move_right")
	_expect(_touched.has(PhysicsLayers.HAZARD), "running into a death prop was not reported")
	_expect(player.body_rect().end.x > 192.0, "a death prop blocked the player instead of letting them touch it")
	await _free(room, player)


## Standard cannot use grapple surfaces, so a grapple prop is not there for him.
func _check_surface_exclusion() -> void:
	var room := _empty_room()
	var prop := Rooms.add_prop(room, BLOCK_SCENE, Vector2(240, 160), Vector2(64, 16), Room.Kind.GRAPPLE)
	var player := _spawn(room, STANDARD_SCENE, Vector2(240, prop.rect().position.y))
	await _physics_frames(30)
	_expect(prop.excluded, "a grapple prop was not excluded for Standard")
	_expect(is_equal_approx(player.body_rect().end.y, FLOOR_Y), "Standard stood on a grapple prop (feet at %.1f)" % player.body_rect().end.y)
	player.free()

	player = _spawn(room, GRAPPLER_SCENE, Vector2(240, prop.rect().position.y))
	await _physics_frames(30)
	_expect(not prop.excluded, "a grapple prop was excluded for the Grappler")
	_expect(absf(player.body_rect().end.y - prop.rect().position.y) < 1.0, "the Grappler fell through a grapple prop")
	await _free(room, player)


func _check_crush_against_wall() -> void:
	var room := Rooms.make_room(root, func(layers: Dictionary) -> void:
		Rooms.paint_column(layers.Terrain, 20, 0, FLOOR_ROW - 1, Rooms.SOLID_TILE))
	var wall_x := 21 * TILE
	var platform := _moving_platform(room, Vector2(wall_x + 60, FLOOR_Y - 16), Vector2(16, 32), OscillatingMotion.Axis.X, 48.0, 2.0)
	platform.oscillation.phase = PI
	platform.reset()
	var player := _spawn(room, STANDARD_SCENE, Vector2(wall_x + 30, FLOOR_Y))
	_crushed = false
	for _frame in 120:
		await physics_frame
		if _crushed:
			break
	_expect(_crushed, "a platform pinning the player against a wall did not crush")
	await _free(room, player)


## The player used to sit on the world layer, so its crush sensor counted the
## player as one of the two solids and one deep overlap was enough. Frozen, as in
## hitstop, so movement cannot push the player out of the wall first. The player
## moves into the wall rather than a block appearing on it: Godot's broadphase does
## not pair a new static body with an area that is standing still.
func _check_one_solid_does_not_crush() -> void:
	var room := _empty_room()
	var player := _spawn(room, STANDARD_SCENE, Vector2(240, FLOOR_Y))
	await _physics_frames(2)
	_crushed = false
	player.frozen = true
	player.global_position.x += TILE - 5.0 - player.body_rect().position.x
	await _physics_frames(10)
	_expect(not _crushed, "the player 5px inside one wall reported a crush")
	await _free(room, player)


func _check_spin_spreads_present_arms() -> void:
	var room := _empty_room()
	var hub := Rooms.add_prop(room, WINDMILL_SCENE, Vector2(240, 120), Vector2(16, 16), Room.Kind.EMPTY)
	var arms: Array[TileProp] = []
	for surface in [Room.Kind.SOLID, Room.Kind.GRAPPLE, Room.Kind.SOLID]:
		arms.append(Rooms.add_prop(hub, BLOCK_SCENE, Vector2.ZERO, Vector2(32, 16), surface))
	var player := _spawn(room, STANDARD_SCENE, Vector2(80, FLOOR_Y))
	await _physics_frames(2)
	var first := arms[0].global_position - hub.global_position
	var last := arms[2].global_position - hub.global_position
	_expect((first + last).length() < 1.0, "two present arms were not spread opposite each other (%s, %s)" % [first, last])
	_expect(is_equal_approx(first.length(), hub.spin.radius), "an arm is %.1fpx from the hub, radius is %.1f" % [first.length(), hub.spin.radius])
	await _free(room, player)


func _check_switch_modes_and_reset() -> void:
	var room := _empty_room()
	var player := STANDARD_SCENE.instantiate() as PlayerBody
	var toggle := _add_switch(room, &"toggle", SwitchProp.Mode.TOGGLE)
	toggle._on_body_entered(player)
	_expect(toggle.is_on, "toggle switch did not turn on at overlap entry")
	toggle._on_body_entered(player)
	_expect(toggle.is_on, "toggle switch changed while overlap continued")
	toggle._on_body_exited(player)
	toggle._on_body_entered(player)
	_expect(not toggle.is_on, "toggle switch did not change on the next overlap entry")

	var momentary := _add_switch(room, &"momentary", SwitchProp.Mode.MOMENTARY)
	momentary._on_body_entered(player)
	_expect(momentary.is_on, "momentary switch did not follow overlap entry")
	momentary._on_body_exited(player)
	_expect(not momentary.is_on, "momentary switch did not follow overlap exit")

	var once := _add_switch(room, &"once", SwitchProp.Mode.ONCE)
	once._on_body_entered(player)
	once._on_body_exited(player)
	once._on_body_entered(player)
	_expect(once.is_on, "once switch did not stay latched")
	toggle.starts_on = true
	room.reset_entities()
	_expect(toggle.is_on, "reset did not restore switch starts_on")
	_expect(not momentary.is_on and not once.is_on, "reset did not clear switch state")
	player.free()
	room.free()
	await process_frame


func _check_switch_detects_player() -> void:
	var room := _empty_room()
	var room_switch := _add_switch(room, &"physical", SwitchProp.Mode.MOMENTARY)
	room_switch.position = Vector2(240, FLOOR_Y - 8)
	var player := _spawn(room, STANDARD_SCENE, Vector2(240, FLOOR_Y))
	await _physics_frames(3)
	_expect(room_switch.is_on, "switch Area2D did not detect the player's body")
	await _free(room, player)


func _check_power_needs_and_effects() -> void:
	var room := _empty_room()
	var player := STANDARD_SCENE.instantiate() as PlayerBody
	var switch_a := _add_switch(room, &"a", SwitchProp.Mode.TOGGLE)
	var switch_b := _add_switch(room, &"b", SwitchProp.Mode.TOGGLE)
	var all_gate := _add_powered_prop(room, GATE_SCENE, Vector2(160, 120), [&"a", &"b"], Power.Need.ALL, Power.Effect.VANISHES)
	var any_prop := _add_powered_prop(room, BLOCK_SCENE, Vector2(200, 120), [&"a", &"b"], Power.Need.ANY, Power.Effect.APPEARS)
	var runner := _add_powered_prop(room, MOVING_PLATFORM_SCENE, Vector2(240, 120), [&"a"], Power.Need.ALL, Power.Effect.RUNS)
	var stopper := _add_powered_prop(room, MOVING_PLATFORM_SCENE, Vector2(280, 120), [&"a"], Power.Need.ALL, Power.Effect.STOPS)
	var starts_open := _add_powered_prop(room, GATE_SCENE, Vector2(320, 120), [], Power.Need.ALL, Power.Effect.VANISHES)
	starts_open.power.starts_on_when_unwatched = true
	await process_frame
	await process_frame

	_expect(all_gate.is_present(), "all gate started vanished before every switch was on")
	_expect(not any_prop.is_present() and any_prop.collision_layer == 0, "appears prop started present")
	_expect(not starts_open.is_present(), "legacy starts_open gate started closed")
	var runner_start := runner.position
	var stopper_start := stopper.position
	await _physics_frames(5)
	_expect(runner.position.is_equal_approx(runner_start), "runs effect advanced while unpowered")
	_expect(not stopper.position.is_equal_approx(stopper_start), "stops effect did not run while unpowered")

	switch_a._on_body_entered(player)
	await physics_frame
	_expect(all_gate.is_present(), "all gate vanished with only one switch on")
	_expect(any_prop.is_present() and any_prop.collision_layer != 0, "any/appears did not become present")
	runner_start = runner.position
	stopper_start = stopper.position
	await _physics_frames(5)
	_expect(not runner.position.is_equal_approx(runner_start), "runs effect did not advance while powered")
	_expect(stopper.position.is_equal_approx(stopper_start), "stops effect advanced while powered")

	switch_b._on_body_entered(player)
	await physics_frame
	_expect(not all_gate.is_present() and all_gate.collision_layer == 0, "all/vanishes gate stayed present")
	_expect(room.prop_at(all_gate.global_position, Room.Kind.SOLID) == null, "hidden gate remained usable as a surface")
	player.free()
	room.free()
	await process_frame


func _check_switch_room_isolation() -> void:
	var room_a := _empty_room()
	var room_b := _empty_room()
	var player := STANDARD_SCENE.instantiate() as PlayerBody
	var switch_a := _add_switch(room_a, &"shared", SwitchProp.Mode.TOGGLE)
	_add_switch(room_b, &"shared", SwitchProp.Mode.TOGGLE)
	var gate_a := _add_powered_prop(room_a, GATE_SCENE, Vector2(160, 120), [&"shared"], Power.Need.ANY, Power.Effect.VANISHES)
	var gate_b := _add_powered_prop(room_b, GATE_SCENE, Vector2(160, 120), [&"shared"], Power.Need.ANY, Power.Effect.VANISHES)
	await process_frame
	await process_frame
	switch_a._on_body_entered(player)
	await physics_frame
	_expect(not gate_a.is_present(), "switch did not affect its own room")
	_expect(gate_b.is_present(), "switch leaked into another loaded room")
	player.free()
	room_a.free()
	room_b.free()
	await process_frame


func _check_fall_block() -> void:
	var room := _empty_room()
	var block := Rooms.add_prop(room, FALL_BLOCK_SCENE, Vector2(240, 80), Vector2(16, 16))
	block.falling.delay = 0.1
	block.falling.gravity = 10_000.0
	block.falling.max_speed = 400.0
	block.surface = Room.Kind.POGO
	block.stood_on()
	_expect(block.falling.state == FallingBehavior.State.IDLE, "non-solid fall block armed")
	block.surface = Room.Kind.SOLID
	block.stood_on()
	_expect(block.falling.state == FallingBehavior.State.ARMING, "solid fall block did not arm")
	await _physics_frames(4)
	_expect(block.falling.state == FallingBehavior.State.ARMING, "fall block ignored its delay")
	for _frame in 120:
		await physics_frame
		if block.falling.state == FallingBehavior.State.LANDED:
			break
	_expect(block.falling.state == FallingBehavior.State.LANDED, "fall block did not land")
	_expect(absf(block.rect().end.y - FLOOR_Y) < 0.1, "fall block landed at %.2f instead of %.2f" % [block.rect().end.y, FLOOR_Y])
	block.reset()
	_expect(block.falling.state == FallingBehavior.State.IDLE, "fall block reset did not restore idle")
	_expect(block.position.is_equal_approx(Vector2(240, 80)), "fall block reset did not restore home")
	room.free()
	await process_frame


func _check_moving_platform_carries_prop() -> void:
	var room := _empty_room()
	var platform := Rooms.add_prop(room, MOVING_PLATFORM_SCENE, Vector2(200, 120), Vector2(16, 16), Room.Kind.EMPTY)
	platform.oscillation.travel = 24.0
	platform.oscillation.speed = 2.0
	var cargo := Rooms.add_prop(platform, BLOCK_SCENE, Vector2.ZERO, Vector2(48, 16))
	await physics_frame
	var offset := cargo.global_position - platform.global_position
	await _physics_frames(10)
	_expect((cargo.global_position - platform.global_position).is_equal_approx(offset), "moving-platform cargo did not retain its offset")
	_expect(not platform.position.is_equal_approx(Vector2(200, 120)), "moving platform did not move")
	room.free()
	await process_frame


func _empty_room() -> Room:
	return Rooms.make_room(root, func(_layers: Dictionary) -> void: pass)


func _moving_platform(room: Room, center: Vector2, size: Vector2, axis: OscillatingMotion.Axis, travel: float, speed: float) -> TileProp:
	var platform := Rooms.add_prop(room, MOVING_PLATFORM_SCENE, center, size)
	platform.oscillation.axis = axis
	platform.oscillation.travel = travel
	platform.oscillation.speed = speed
	platform.oscillation.phase = 0.0
	platform.reset()
	return platform


func _add_switch(room: Room, switch_id: StringName, mode: SwitchProp.Mode) -> SwitchProp:
	var room_switch := SWITCH_SCENE.instantiate() as SwitchProp
	room_switch.switch_id = switch_id
	room_switch.mode = mode
	room.add_child(room_switch)
	return room_switch


func _add_powered_prop(
	room: Room,
	scene: PackedScene,
	center: Vector2,
	watches: Array[StringName],
	need: Power.Need,
	effect: Power.Effect,
) -> TileProp:
	var prop := scene.instantiate() as TileProp
	prop.position = center
	if prop.power == null:
		var component := Power.new()
		component.name = "Power"
		prop.add_child(component)
		prop.power = component
	prop.power.watches = watches
	prop.power.need = need
	prop.power.effect = effect
	room.add_child(prop)
	return prop


func _spawn(room: Room, scene: PackedScene, feet: Vector2) -> PlayerBody:
	var player := Rooms.spawn_player(root, room, scene, feet)
	player.trigger_touched.connect(func(layer: int) -> void: _touched.append(layer))
	player.crushed.connect(func() -> void: _crushed = true)
	return player


func _send_action(action: StringName, pressed: bool) -> void:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()


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
