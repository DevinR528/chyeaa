extends SceneTree
## Stack formulas, and a live player whose jump apex and run distance follow the build.

const Rooms := preload("res://tests/test_room_builder.gd")
const STANDARD_SCENE := preload("res://scenes/player/standard.tscn")
const POGO_SCENE := preload("res://scenes/player/pogo.tscn")

var _failed := false


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_check_stack_limits()
	_check_offer()
	_check_formulas()
	_check_summary()
	_check_character_switch()
	await _check_jump_and_slow_time()
	quit(1 if _failed else 0)


func _check_stack_limits() -> void:
	var build := RunBuild.new()
	for _i in 10:
		build.add_stack(RunBuild.Id.SLOW_TIME)
	_expect(build.stack_count(RunBuild.Id.SLOW_TIME) == RunBuild.MAX_STACKS[RunBuild.Id.SLOW_TIME], "slow time stacked past its max")

	var before := RunBuild.new()
	before.add_stack(RunBuild.Id.TOP_SPEED)
	var after := before.duplicate_build()
	after.add_stack(RunBuild.Id.TOP_SPEED)
	_expect(before.stack_count(RunBuild.Id.TOP_SPEED) == 1, "adding a stack mutated the copied build")
	_expect(after.stack_count(RunBuild.Id.TOP_SPEED) == 2, "copied build did not take a second stack")

	after.remove_stack(RunBuild.Id.TOP_SPEED)
	after.remove_stack(RunBuild.Id.TOP_SPEED)
	_expect(after.stack_count(RunBuild.Id.TOP_SPEED) == 0, "removing the last stack left an entry")


func _check_offer() -> void:
	var full := RunBuild.new()
	full.add_stack(RunBuild.Id.CHECKPOINT)
	var offer := full.roll_offer(3, func() -> float: return 0.0)
	_expect(offer.size() == 3, "offer was not three cards: %s" % [offer])
	_expect(not offer.has(RunBuild.Id.CHECKPOINT), "offer included a maxed checkpoint")
	var only_rewind := RunBuild.new()
	for id: RunBuild.Id in RunBuild._ORDER:
		if id == RunBuild.Id.REWIND:
			continue
		while only_rewind.stack_count(id) < RunBuild.MAX_STACKS[id]:
			only_rewind.add_stack(id)
	_expect(only_rewind.roll_offer() == [RunBuild.Id.REWIND], "a build with room only for rewind did not offer it")
	var again := full.roll_offer(3, func() -> float: return 0.0)
	_expect(offer == again, "the same rolls did not give the same offer")
	for id: RunBuild.Id in RunBuild._ORDER:
		while full.stack_count(id) < RunBuild.MAX_STACKS[id]:
			full.add_stack(id)
	_expect(full.roll_offer().is_empty(), "a maxed build still offered a card")
	_expect(
		RunBuild.describe(RunBuild.Id.CHECKPOINT).contains("plant a respawn flag"),
		"checkpoint card did not say what the potion does",
	)


func _check_formulas() -> void:
	var base := MovementStats.new()
	var untouched := base.max_run
	var build := RunBuild.new()
	build.add_stack(RunBuild.Id.TOP_SPEED)
	build.add_stack(RunBuild.Id.TOP_SPEED)
	var sped := build.recompute(base)
	_expect(base.max_run == untouched, "recompute mutated the baseline")
	_expect(is_equal_approx(sped.max_run, untouched * 1.24), "two top-speed stacks were not +24%")

	var empty := RunBuild.new()
	empty.recompute(base)
	_expect(is_equal_approx(empty.time_scale, 1.0), "an empty build changed the sim scale")
	var slowed := RunBuild.new()
	slowed.add_stack(RunBuild.Id.SLOW_TIME)
	slowed.add_stack(RunBuild.Id.SLOW_TIME)
	slowed.recompute(base)
	_expect(is_equal_approx(slowed.time_scale, 0.9), "two slow-time stacks were not ×0.90")
	slowed.stacks[RunBuild.Id.SLOW_TIME] = 99
	slowed.recompute(base)
	_expect(is_equal_approx(slowed.time_scale, 0.8), "slow time did not floor at 0.8")

	var jump := RunBuild.new()
	for _i in RunBuild.MAX_STACKS[RunBuild.Id.JUMP_HEIGHT]:
		jump.add_stack(RunBuild.Id.JUMP_HEIGHT)
	var higher := jump.recompute(base)
	_expect(
		is_equal_approx(higher.jump_velocity, base.jump_velocity * 1.4),
		"five jump-height stacks were not +40% |jump velocity|",
	)
	_expect(higher.jump_velocity < base.jump_velocity, "jump height did not increase upward speed")

	var fall := RunBuild.new()
	for _i in 5:
		fall.add_stack(RunBuild.Id.SLOW_FALL)
	var softer := fall.recompute(base)
	var factor := 1.0 / 1.6
	_expect(is_equal_approx(softer.fall_gravity, base.fall_gravity * factor), "slow fall missed fall gravity")
	_expect(is_equal_approx(softer.hold_fall_gravity, base.hold_fall_gravity * factor), "slow fall missed hold fall gravity")
	_expect(is_equal_approx(softer.max_fall, base.max_fall * factor), "slow fall missed max fall")
	_expect(is_equal_approx(softer.hold_max_fall, base.hold_max_fall * factor), "slow fall missed hold max fall")
	_expect(is_equal_approx(softer.gravity, base.gravity), "slow fall changed rise gravity")

	var once := jump.recompute(base)
	var twice := jump.recompute(base)
	_expect(is_equal_approx(twice.jump_velocity, once.jump_velocity), "recomputing compounded jump height")


func _check_summary() -> void:
	var build := RunBuild.new()
	build.add_stack(RunBuild.Id.TOP_SPEED)
	build.add_stack(RunBuild.Id.TOP_SPEED)
	build.add_stack(RunBuild.Id.CHECKPOINT)
	_expect(
		build.summary(0.9, 1, {RunBuild.Id.CHECKPOINT: 1}) == "Top Speed×2 · Checkpoint (1 left) · sim 90% · bank 1",
		"summary was '%s'" % build.summary(0.9, 1, {RunBuild.Id.CHECKPOINT: 1}),
	)
	var rewind := RunBuild.new()
	rewind.add_stack(RunBuild.Id.REWIND)
	_expect(
		rewind.summary(1.0, 0, {RunBuild.Id.REWIND: 2}) == "Rewind (2 left)",
		"rewind summary was '%s'" % rewind.summary(1.0, 0, {RunBuild.Id.REWIND: 2}),
	)
	_expect(RunBuild.new().summary(1.0) == "No power-ups", "empty summary was not 'No power-ups'")


func _check_character_switch() -> void:
	var build := RunBuild.new()
	build.add_stack(RunBuild.Id.TOP_SPEED)
	var standard := STANDARD_SCENE.instantiate() as PlayerBody
	var pogo := POGO_SCENE.instantiate() as PlayerBody
	root.add_child(standard)
	root.add_child(pogo)
	var standard_base := standard.base_stats.max_run
	var pogo_base := pogo.base_stats.max_run
	standard.apply_build(build)
	standard.apply_build(build)
	pogo.apply_build(build)
	_expect(is_equal_approx(standard.stats.max_run, standard_base * 1.12), "standard did not get +12% from its own baseline")
	_expect(is_equal_approx(pogo.stats.max_run, pogo_base * 1.12), "pogo inherited the previous character's modified run speed")
	_expect(is_equal_approx(pogo.stats.ground_accel, pogo.base_stats.ground_accel), "top speed changed pogo's ground accel")
	_expect(not is_equal_approx(standard_base, pogo_base), "the two characters shared a baseline, so the switch check is vacuous")
	standard.free()
	pogo.free()


func _check_jump_and_slow_time() -> void:
	var ticks := Engine.physics_ticks_per_second
	var room := Rooms.make_room(root, func(_layers: Dictionary) -> void: pass)
	var player := Rooms.spawn_player(root, room, STANDARD_SCENE, Vector2(80, Rooms.FLOOR_ROW * Rooms.TILE))
	await _settle(player)

	var plain_rise := await _jump_rise(player)
	var jump_build := RunBuild.new()
	for _i in 5:
		jump_build.add_stack(RunBuild.Id.JUMP_HEIGHT)
	player.apply_build(jump_build)
	player.respawn(Vector2(80, Rooms.FLOOR_ROW * Rooms.TILE))
	await _settle(player)
	var boosted_rise := await _jump_rise(player)
	var ratio := boosted_rise / plain_rise
	_expect(ratio > 1.7 and ratio < 2.2, "jump height apex ratio was %s (rises %s -> %s)" % [ratio, plain_rise, boosted_rise])

	var runner := RoomRunner.new()
	runner.room = room
	runner.player = player
	for _i in 4:
		runner.build.add_stack(RunBuild.Id.SLOW_TIME)
	var full := await _run_distance(player, 1.0)
	runner.apply_build()
	_expect(is_equal_approx(room.sim_scale, 0.8), "four slow-time stacks did not set the room scale to 0.8")
	var slowed := await _run_distance(player, room.sim_scale)
	_expect(is_equal_approx(player.velocity.x, player.stats.max_run), "slow time left the gameplay run speed scaled")
	_expect(
		slowed < full * 0.92 and slowed > full * 0.65,
		"slow time distance %s was not about 80%% of %s" % [slowed, full],
	)
	_expect(Engine.time_scale == 1.0, "slow time changed Engine.time_scale")
	_expect(Engine.physics_ticks_per_second == ticks, "slow time changed the physics tick rate")
	runner.free()
	player.free()
	room.free()


func _run_distance(player: PlayerBody, scale: float) -> float:
	player.room.sim_scale = scale
	player.respawn(Vector2(80, Rooms.FLOOR_ROW * Rooms.TILE))
	await _settle(player)
	player.velocity.x = player.stats.max_run
	var start := player.position.x
	Input.action_press(&"move_right")
	for _frame in 60:
		await physics_frame
	Input.action_release(&"move_right")
	return player.position.x - start


func _jump_rise(player: PlayerBody) -> float:
	var start_y := player.body_rect().end.y
	Input.action_press(&"jump")
	var peak_y := start_y
	for _frame in 240:
		await physics_frame
		peak_y = minf(peak_y, player.body_rect().end.y)
		if player.velocity.y > 0.0 and peak_y < start_y - 1.0:
			break
	Input.action_release(&"jump")
	await _settle(player)
	return start_y - peak_y


func _settle(player: PlayerBody) -> void:
	for _frame in 180:
		await physics_frame
		if player.is_on_floor() and is_zero_approx(player.velocity.y):
			return


func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	_failed = true
	push_error(message)
