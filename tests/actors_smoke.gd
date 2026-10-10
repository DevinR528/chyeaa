extends SceneTree
## Walker and throwable checks: patrol turns, stomps, side hurts, pickup and throw,
## the ball's bounces (floor, walker, ball), standing on an idle ball, and a
## thrower's immunity to their own ball in flight.

const Rooms := preload("res://tests/test_room_builder.gd")
const STANDARD_SCENE := preload("res://scenes/player/standard.tscn")
const WALKER_SCENE := preload("res://scenes/actors/walker.tscn")
const THROWABLE_SCENE := preload("res://scenes/actors/throwable.tscn")
const FLOOR_ROW := Rooms.FLOOR_ROW
const TILE := Rooms.TILE
const FLOOR_Y := FLOOR_ROW * TILE

var _failed := false
var _hurt_by: Array[RoomActor] = []
var _stomp_velocity := NAN
var _deaths: Array[Walker.DeathCause] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	await _check_walker_turns_at_wall()
	await _check_walker_turns_at_ledge()
	await _check_stomp_kills_walker()
	await _check_walker_side_hurts()
	await _check_pickup_and_throw()
	await _check_ball_kills_walker_and_bounces()
	await _check_ball_bounces_on_floor()
	await _check_idle_ball_is_solid()
	await _check_own_ball_in_flight_is_safe()
	await _check_balls_rebound()
	quit(1 if _failed else 0)


func _check_walker_turns_at_wall() -> void:
	var room := Rooms.make_room(root, func(layers: Dictionary) -> void:
		Rooms.paint_column(layers.Terrain, 20, 0, FLOOR_ROW - 1, Rooms.SOLID_TILE))
	var walker := _walker(room, Vector2(140, FLOOR_Y - 8))
	var wall_x := 20 * TILE
	var turned := false
	var furthest := 0.0
	for _frame in 120:
		await physics_frame
		furthest = maxf(furthest, walker.body_rect().end.x)
		if walker.facing < 0.0:
			turned = true
			break
	_expect(turned, "walker did not turn at a wall")
	_expect(furthest <= wall_x + 0.01, "walker walked into the wall (right edge %.2f, wall %.1f)" % [furthest, wall_x])
	await _free(room)


func _check_walker_turns_at_ledge() -> void:
	var ledge_row := 20
	var room := Rooms.make_room(root, func(layers: Dictionary) -> void:
		Rooms.paint_row(layers.Terrain, ledge_row, 10, 20, Rooms.SOLID_TILE))
	var walker := _walker(room, Vector2(120, ledge_row * TILE - 8))
	var turns := 0
	var facing := walker.facing
	for _frame in 360:
		await physics_frame
		if walker.facing != facing:
			facing = walker.facing
			turns += 1
	_expect(turns >= 2, "walker turned %d times on a ledge, expected both ends" % turns)
	_expect(absf(walker.body_rect().end.y - ledge_row * TILE) < 0.5, "walker fell off the ledge (feet at %.1f)" % walker.body_rect().end.y)
	await _free(room)


func _check_stomp_kills_walker() -> void:
	var room := _empty_room()
	var walker := _walker(room, Vector2(240, FLOOR_Y - 8), 0.0)
	var player := _spawn(room, Vector2(240, FLOOR_Y - 60))
	for _frame in 60:
		await physics_frame
		if not _deaths.is_empty():
			break
	_expect(_deaths == [Walker.DeathCause.STOMPED], "falling onto a walker did not stomp it: %s" % [_deaths])
	_expect(_hurt_by.is_empty(), "stomping a walker hurt the player")
	_expect(is_equal_approx(_stomp_velocity, walker.stomp_bounce), "stomp bounced at %f, expected %f" % [_stomp_velocity, walker.stomp_bounce])
	await _free(room, player)


func _check_walker_side_hurts() -> void:
	var room := _empty_room()
	var walker := _walker(room, Vector2(300, FLOOR_Y - 8), -1.0, -1)
	var player := _spawn(room, Vector2(240, FLOOR_Y))
	for _frame in 180:
		await physics_frame
		if not _hurt_by.is_empty():
			break
	_expect(_hurt_by == [walker], "a walker walking into the player did not hurt them")
	_expect(walker.alive and _deaths.is_empty(), "a side touch killed the walker")
	await _free(room, player)


func _check_pickup_and_throw() -> void:
	var room := _empty_room()
	var ball := _ball(room, Vector2(266, FLOOR_Y - 12))
	var player := _spawn(room, Vector2(240, FLOOR_Y))
	await _physics_frames(2)

	_send_action(&"interact", true)
	await _physics_frames(2)
	_expect(ball.state == Throwable.State.CARRIED, "holding interact beside an idle ball did not pick it up")
	_expect(player.carrier.held == ball, "the carrier does not know it holds the ball")
	_send_action(&"interact", false)
	await _physics_frames(1)
	_expect(ball.state == Throwable.State.THROWN, "releasing interact did not throw the ball")
	_expect(player.carrier.held == null, "the carrier still holds a thrown ball")
	_expect(is_equal_approx(ball.velocity.x, ball.throw_speed), "throw left at %.1f, expected %.1f" % [ball.velocity.x, ball.throw_speed])
	_expect(ball.global_position.x > player.body_rect().end.x, "the ball did not leave ahead of the player")

	for _frame in 240:
		await physics_frame
		if ball.state == Throwable.State.IDLE:
			break
	_expect(ball.state == Throwable.State.IDLE, "a thrown ball never came to rest")
	_expect(_hurt_by.is_empty(), "throwing the ball hurt the player")
	await _free(room, player)


## The user's ask: a ball that kills a walker bounces off him too.
func _check_ball_kills_walker_and_bounces() -> void:
	var room := _empty_room()
	var walker := _walker(room, Vector2(300, FLOOR_Y - 8), 0.0)
	var ball := _ball(room, Vector2(200, FLOOR_Y - 12))
	ball.launch(Vector2(ball.throw_speed, 0.0))
	for _frame in 60:
		await physics_frame
		if not _deaths.is_empty():
			break
	_expect(_deaths == [Walker.DeathCause.HIT], "a thrown ball did not kill the walker: %s" % [_deaths])
	await physics_frame
	_expect(ball.velocity.x < 0.0, "the ball kept going through the walker (vx %.1f)" % ball.velocity.x)
	_expect(ball.velocity.y < 0.0, "the ball did not pop up off the walker (vy %.1f)" % ball.velocity.y)
	await _free(room)


func _check_ball_bounces_on_floor() -> void:
	var room := _empty_room()
	var ball := _ball(room, Vector2(240, FLOOR_Y - 80))
	var landed := false
	var bounce_top := INF
	for _frame in 240:
		await physics_frame
		if ball.is_on_floor():
			landed = true
		elif landed:
			bounce_top = minf(bounce_top, ball.body_rect().end.y)
	var rise := FLOOR_Y - bounce_top
	_expect(rise > 8.0, "a dropped ball bounced %.1fpx, expected a visible bounce" % rise)
	_expect(ball.is_on_floor() and is_zero_approx(ball.velocity.y), "the ball never settled after bouncing")
	_expect(ball.state == Throwable.State.IDLE, "a dropped ball is not idle after settling")
	await _free(room)


func _check_idle_ball_is_solid() -> void:
	var room := _empty_room()
	var ball := _ball(room, Vector2(240, FLOOR_Y - 12))
	var player := _spawn(room, Vector2(240, FLOOR_Y - 60))
	await _physics_frames(60)
	_expect(player.is_on_floor(), "player did not land on an idle ball")
	# Two moving bodies rest a collision margin apart.
	_expect(absf(player.body_rect().end.y - ball.body_rect().position.y) < 0.1, "player stood at %.2f, ball top is %.2f" % [player.body_rect().end.y, ball.body_rect().position.y])
	_expect(_hurt_by.is_empty() and ball.state == Throwable.State.IDLE, "landing on an idle ball hurt the player or moved the ball")
	await _free(room, player)


## A ball thrown straight up falls back through its thrower without hurting them.
func _check_own_ball_in_flight_is_safe() -> void:
	var room := _empty_room()
	var ball := _ball(room, Vector2(266, FLOOR_Y - 12))
	var player := _spawn(room, Vector2(240, FLOOR_Y))
	await _physics_frames(2)

	_send_action(&"interact", true)
	await _physics_frames(2)
	_send_action(&"move_up", true)
	await _physics_frames(1)
	_send_action(&"interact", false)
	await _physics_frames(1)
	_send_action(&"move_up", false)
	_expect(ball.state == Throwable.State.THROWN and ball.velocity.y < 0.0, "aiming up did not throw the ball up")
	var overlapped := false
	for _frame in 90:
		await physics_frame
		overlapped = overlapped or ball.body_rect().intersects(player.body_rect())
	_expect(overlapped, "the ball never came back down onto its thrower")
	_expect(_hurt_by.is_empty(), "the player's own ball hurt them in flight")
	await _free(room, player)


func _check_balls_rebound() -> void:
	var room := _empty_room()
	var left := _ball(room, Vector2(160, FLOOR_Y - 12))
	var right := _ball(room, Vector2(320, FLOOR_Y - 12))
	left.launch(Vector2(300.0, 0.0))
	right.launch(Vector2(-300.0, 0.0))
	var met := false
	for _frame in 60:
		await physics_frame
		if left.velocity.x < 0.0 and right.velocity.x > 0.0:
			met = true
			break
	_expect(met, "two hazardous balls did not rebound off each other")
	_expect(left.body_rect().end.x <= right.body_rect().position.x, "rebounding balls still overlap")
	await _free(room)


func _empty_room() -> Room:
	return Rooms.make_room(root, func(_layers: Dictionary) -> void: pass)


func _walker(room: Room, center: Vector2, speed := -1.0, facing := 1) -> Walker:
	var walker := Rooms.add_actor(room, WALKER_SCENE, center, func(actor: RoomActor) -> void:
		var setup := actor as Walker
		if speed >= 0.0:
			setup.speed = speed
		setup.start_facing = facing) as Walker
	walker.died.connect(func(cause: Walker.DeathCause) -> void: _deaths.append(cause))
	return walker


func _ball(room: Room, center: Vector2) -> Throwable:
	return Rooms.add_actor(room, THROWABLE_SCENE, center) as Throwable


func _spawn(room: Room, feet: Vector2) -> PlayerBody:
	var player := Rooms.spawn_player(root, room, STANDARD_SCENE, feet)
	player.hurt.connect(func(source: RoomActor) -> void: _hurt_by.append(source))
	player.stomped.connect(func(_target: RoomActor) -> void: _stomp_velocity = player.velocity.y)
	return player


func _send_action(action: StringName, pressed: bool) -> void:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()


func _free(room: Room, player: PlayerBody = null) -> void:
	if player != null:
		player.free()
	room.free()
	_hurt_by.clear()
	_deaths.clear()
	_stomp_velocity = NAN
	await process_frame


func _physics_frames(count: int) -> void:
	for _frame in count:
		await physics_frame


func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	_failed = true
	push_error(message)
