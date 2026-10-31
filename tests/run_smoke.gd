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
	_expect(RunBuild.rarity_of(RunBuild.Id.DOUBLE_JUMP) == RunBuild.Rarity.RARE, "double jump was not rare")
	_expect(RunBuild.rarity_of(RunBuild.Id.TOP_SPEED) == RunBuild.Rarity.COMMON, "top speed was not common")
	_expect(
		RunBuild.describe(RunBuild.Id.DOUBLE_JUMP).contains("air jump")
		and RunBuild.describe(RunBuild.Id.DOUBLE_JUMP).contains("12%"),
		"double jump card did not name the air jump and height penalty",
	)
	var only_double := RunBuild.new()
	for id: RunBuild.Id in RunBuild._ORDER:
		if id == RunBuild.Id.DOUBLE_JUMP:
			continue
		while only_double.stack_count(id) < RunBuild.MAX_STACKS[id]:
			only_double.add_stack(id)
	_expect(
		only_double.roll_offer() == [RunBuild.Id.DOUBLE_JUMP],
		"a build with room only for double jump did not offer it",
	)
	var pogo := POGO_SCENE.instantiate() as PlayerBody
	var grappler := preload("res://scenes/player/grappler.tscn").instantiate() as PlayerBody
	var for_pogo := RunBuild.new().roll_offer(20, func() -> float: return 0.0, pogo)
	var for_grappler := RunBuild.new().roll_offer(20, func() -> float: return 0.0, grappler)
	var for_anyone := RunBuild.new().roll_offer(20, func() -> float: return 0.0)
	_expect(for_pogo.has(RunBuild.Id.POGO_HEIGHT), "pogo was not offered pogo height")
	_expect(not for_pogo.has(RunBuild.Id.GRAPPLE_REACH), "pogo was offered grapple reach")
	_expect(for_grappler.has(RunBuild.Id.GRAPPLE_REACH), "grappler was not offered grapple reach")
	_expect(not for_grappler.has(RunBuild.Id.POGO_HEIGHT), "grappler was offered pogo height")
	_expect(not for_anyone.has(RunBuild.Id.POGO_HEIGHT), "a character-less offer included pogo height")
	_expect(not for_anyone.has(RunBuild.Id.GRAPPLE_REACH), "a character-less offer included grapple reach")
	pogo.free()
	grappler.free()


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

	var double_jump := RunBuild.new()
	double_jump.add_stack(RunBuild.Id.DOUBLE_JUMP)
	var with_air := double_jump.recompute(base)
	_expect(with_air.air_jumps == base.air_jumps + 1, "double jump did not add one air jump")
	_expect(
		is_equal_approx(with_air.jump_velocity, base.jump_velocity * 0.88),
		"double jump was not −12% |jump velocity|",
	)
	double_jump.add_stack(RunBuild.Id.JUMP_HEIGHT)
	var composed := double_jump.recompute(base)
	_expect(
		is_equal_approx(composed.jump_velocity, base.jump_velocity * 1.08 * 0.88),
		"double jump did not multiply after jump height",
	)
	_expect(composed.air_jumps == base.air_jumps + 1, "jump height stacks changed air jumps")

	var double_dash := RunBuild.new()
	double_dash.add_stack(RunBuild.Id.DOUBLE_DASH)
	var with_dash := double_dash.recompute(base)
	_expect(with_dash.dash_charges == base.dash_charges + 1, "double dash did not add one dash charge")
	_expect(
		is_equal_approx(with_dash.dash_duration, base.dash_duration * 0.88),
		"double dash was not −12% dash distance",
	)


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

	var pogo_body := POGO_SCENE.instantiate() as PlayerBody
	var grappler_body := preload("res://scenes/player/grappler.tscn").instantiate() as PlayerBody
	root.add_child(pogo_body)
	root.add_child(grappler_body)
	var strike := pogo_body.ability as PogoStrike
	var hook := grappler_body.ability as Grapple
	var bounce := strike.bounce_tiles
	var reach := hook.reach_tiles
	var height := RunBuild.new()
	height.add_stack(RunBuild.Id.POGO_HEIGHT)
	var reach_build := RunBuild.new()
	reach_build.add_stack(RunBuild.Id.GRAPPLE_REACH)
	pogo_body.apply_build(height)
	pogo_body.apply_build(height)
	grappler_body.apply_build(reach_build)
	grappler_body.apply_build(reach_build)
	_expect(is_equal_approx(strike.bounce_tiles, bounce * 1.08), "pogo height was not +8%")
	_expect(is_equal_approx(hook.reach_tiles, reach * 1.08), "grapple reach was not +8%")
	pogo_body.apply_build(RunBuild.new())
	grappler_body.apply_build(RunBuild.new())
	_expect(is_equal_approx(strike.bounce_tiles, bounce), "clearing the build left the pogo taller")
	_expect(is_equal_approx(hook.reach_tiles, reach), "clearing the build left the grapple longer")
	pogo_body.free()
	grappler_body.free()


func _check_jump_and_slow_time() -> void:
	var ticks := Engine.physics_ticks_per_second
	var room := Rooms.make_room(root, func(_layers: Dictionary) -> void: pass)
	var player := Rooms.spawn_player(root, room, STANDARD_SCENE, Vector2(80, Rooms.FLOOR_ROW * Rooms.TILE))
	await _settle(player)

	var plain_rise := await _jump_rise(player)
	_expect(player.is_on_floor(), "player was not grounded before double-jump apply")
	player.air_jumps_left = 0
	var air_build := RunBuild.new()
	air_build.add_stack(RunBuild.Id.DOUBLE_JUMP)
	player.apply_build(air_build)
	_expect(player.stats.air_jumps == 1, "double jump build did not set air_jumps")
	_expect(player.air_jumps_left == 1, "grounded apply_build did not refill air_jumps_left")
	player.apply_build(RunBuild.new())
	_expect(player.air_jumps_left == 0, "clearing double jump left air jumps")

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
