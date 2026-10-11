class_name PogoStrike
extends PlayerAbility
## Directional strike. Hitting a pogo tile reacts by strike direction: down bounces,
## sideways pops up off the face, up stops the rise. An up strike into a ceiling bonks.

signal strike_started(direction: StrikeDirection)
## A side strike connected and launched the player away from the surface.
signal side_bashed

enum State {
	## Not striking; locomotion is in control.
	INACTIVE,
	STRIKE,
}

enum StrikeDirection {
	DOWN,
	UP,
	LEFT,
	RIGHT,
}

const TILE := MovementStats.TILE

@export_group("Strike")
@export_range(0.0, 1.0, 0.01) var strike_duration := 0.22
## How long a strike press made during a dash stays queued once the dash ends.
@export_range(0.0, 0.5, 0.005) var strike_buffer := 0.1
## Reach from the body edge; the Standard body height.
@export var slash_radius := 28.0
## Above 1 widens the up and down aim cones.
@export var aim_vertical_bias := 1.4
## Horizontal drift during an up or down strike, as a fraction of max_run.
@export_range(0.0, 1.0, 0.01) var strike_drift := 0.35
@export var stomp_speed := 130.0 * TILE
## Up strike launch as a fraction of the jump velocity.
@export_range(0.0, 1.0, 0.01) var up_strike_fraction := 0.25

@export_group("Bounce")
## Down-bounce apex height; the launch speed is derived from the current gravity.
@export var bounce_tiles := 11.4
## Window for one timed jump after a bounce; intentionally about two ticks.
@export_range(0.0, 0.2, 0.005) var bounce_coyote_time := 0.035

@export_group("Side bash")
@export var side_speed := 22.5 * TILE
@export var side_vertical_damp := 100.0 * TILE
## Side pop apex height: up off the struck face, not back.
@export var side_pop_tiles := 11.0
## Push off the struck face so the pop clears it.
@export var side_recoil := 10.0 * TILE
## Held horizontal input is ignored this long after a side pop.
@export_range(0.0, 0.5, 0.005) var side_lock := 0.08
@export_range(0.0, 0.3, 0.005) var side_hitstop := 0.1

var state := State.INACTIVE
var strike_direction := StrikeDirection.DOWN
var strike_left := 0.0
var side_lock_left := 0.0
## Counts down only once the dash is over.
var strike_buffer_left := 0.0


func reset() -> void:
	state = State.INACTIVE
	strike_left = 0.0
	side_lock_left = 0.0
	strike_buffer_left = 0.0


func animation_clip(movement_clip: StringName) -> StringName:
	if state != State.STRIKE:
		return movement_clip
	match strike_direction:
		StrikeDirection.DOWN:
			return &"strike_down"
		StrikeDirection.UP:
			return &"strike_up"
	return &"strike_side"


func tick(delta: float) -> void:
	if state == State.STRIKE:
		strike_left = maxf(0.0, strike_left - delta)
	side_lock_left = maxf(0.0, side_lock_left - delta)
	if strike_buffer_left > 0.0 and body.move_state != PlayerBody.MovementState.DASH:
		strike_buffer_left = maxf(0.0, strike_buffer_left - delta)


func update_active(delta: float, input: PlayerInputFrame) -> bool:
	if state != State.STRIKE:
		return false
	_apply_strike_velocity(input, delta)
	if _try_slash_connect():
		body.move_and_slide()
		return true
	body.move_and_slide()
	if not _try_slash_connect() and strike_left <= 0.0:
		state = State.INACTIVE
	return true


## The strike aims from the stick when it comes out, not when the button went down.
func try_start(input: PlayerInputFrame) -> bool:
	if state != State.INACTIVE:
		return false
	var dashing := body.move_state == PlayerBody.MovementState.DASH
	if input.action_pressed and dashing:
		strike_buffer_left = strike_buffer
	var wants_strike := input.action_pressed or strike_buffer_left > 0.0
	if not wants_strike or dashing or body.is_on_floor():
		return false
	var aim := PlayerInput.aim_quadrant(input.move, 0.2, aim_vertical_bias)
	if aim == PlayerInputFrame.Aim.NONE:
		return false

	strike_buffer_left = 0.0
	state = State.STRIKE
	strike_direction = _direction_from_aim(aim)
	strike_left = strike_duration
	body.jump_cuttable = true
	_apply_strike_velocity(input, 1.0 / Engine.physics_ticks_per_second)
	strike_started.emit(strike_direction)
	return true


func locks_horizontal_input() -> bool:
	return side_lock_left > 0.0


func slash() -> HalfDisk:
	return slash_toward(strike_direction)


func slash_toward(direction: StrikeDirection) -> HalfDisk:
	var rect := body.body_rect()
	match direction:
		StrikeDirection.UP:
			return HalfDisk.new(Vector2(rect.get_center().x, rect.position.y), slash_radius, Vector2.UP)
		StrikeDirection.LEFT:
			return HalfDisk.new(Vector2(rect.position.x, rect.get_center().y), slash_radius, Vector2.LEFT)
		StrikeDirection.RIGHT:
			return HalfDisk.new(Vector2(rect.end.x, rect.get_center().y), slash_radius, Vector2.RIGHT)
	return HalfDisk.new(Vector2(rect.get_center().x, rect.end.y), slash_radius, Vector2.DOWN)


func _direction_from_aim(aim: PlayerInputFrame.Aim) -> StrikeDirection:
	match aim:
		PlayerInputFrame.Aim.UP:
			return StrikeDirection.UP
		PlayerInputFrame.Aim.LEFT:
			return StrikeDirection.LEFT
		PlayerInputFrame.Aim.RIGHT:
			return StrikeDirection.RIGHT
	return StrikeDirection.DOWN


func _apply_strike_velocity(input: PlayerInputFrame, delta: float) -> void:
	match strike_direction:
		StrikeDirection.DOWN:
			body.velocity = Vector2(input.move.x * body.stats.max_run * strike_drift, stomp_speed)
		StrikeDirection.UP:
			body.velocity = Vector2(
				input.move.x * body.stats.max_run * strike_drift,
				body.stats.jump_velocity * up_strike_fraction,
			)
		StrikeDirection.LEFT, StrikeDirection.RIGHT:
			var side := -1.0 if strike_direction == StrikeDirection.LEFT else 1.0
			body.velocity.x = side * side_speed
			body.velocity.y = move_toward(body.velocity.y, 0.0, side_vertical_damp * delta)
			body.facing = side


## Returns true when the strike ended on a pogo tile or a ceiling.
func _try_slash_connect() -> bool:
	var disk := slash()
	var pogo_props := _slash_hits_props(disk, func(prop: TileProp) -> bool: return prop.surface == Room.Kind.POGO)
	var hits_pogo_tile: bool = body.room.tiles_overlap(disk.center, disk.convex_points(), PhysicsLayers.POGO)
	if hits_pogo_tile or not pogo_props.is_empty():
		for prop in pogo_props:
			prop.use_surface(Room.Kind.POGO)
		_on_pogo_connect()
		return true
	if strike_direction == StrikeDirection.UP:
		var solid_props := _slash_hits_props(disk, func(prop: TileProp) -> bool: return prop.is_solid())
		var hits_ceiling: bool = body.room.tiles_overlap(disk.center, disk.convex_points(), PhysicsLayers.WORLD) or _slash_hits_out_of_bounds(disk)
		if hits_ceiling or not solid_props.is_empty():
			_bonk_ceiling()
			return true
	return false


func _slash_hits_props(disk: HalfDisk, accepts: Callable) -> Array[TileProp]:
	var hit: Array[TileProp] = []
	for prop in body.room.props():
		if prop.is_present() and accepts.call(prop) and disk.overlaps_rect(prop.rect()):
			hit.append(prop)
	return hit


## Cells outside the room are solid even though no tile shape is there.
func _slash_hits_out_of_bounds(disk: HalfDisk) -> bool:
	var bounds := disk.bounds()
	var first := body.room.cell_at(bounds.position)
	var last := body.room.cell_at(bounds.end)
	for y in range(first.y, last.y + 1):
		for x in range(first.x, last.x + 1):
			var cell := Vector2i(x, y)
			if body.room.is_out_of_bounds_solid(cell) and disk.overlaps_rect(body.room.cell_rect(cell)):
				return true
	return false


func _on_pogo_connect() -> void:
	state = State.INACTIVE
	strike_left = 0.0
	body.refresh_dash()
	body.air_jumps_left = body.stats.air_jumps
	match strike_direction:
		StrikeDirection.DOWN:
			body.apply_jump(_apex_launch_velocity(bounce_tiles), false, bounce_coyote_time)
		StrikeDirection.UP:
			body.velocity.y = 0.0
			body.jump_buffer_left = 0.0
		StrikeDirection.LEFT:
			_side_pop(-1.0)
		StrikeDirection.RIGHT:
			_side_pop(1.0)


## A fixed launch: no jump cut and no timed-jump coyote, either of which would weaken it.
## A strike buffered during the hitstop or the rise still cuts it and chains another pogo.
func _side_pop(side: float) -> void:
	body.apply_jump(_apex_launch_velocity(side_pop_tiles), false, -1.0, false)
	body.velocity.x = -side * side_recoil
	side_lock_left = side_lock
	body.request_hitstop(side_hitstop)
	side_bashed.emit()


func _bonk_ceiling() -> void:
	state = State.INACTIVE
	strike_left = 0.0
	body.velocity.y = 0.0
	body.jump_buffer_left = 0.0


## Launch speed that peaks `tiles` above the start under the current gravity.
func _apex_launch_velocity(tiles: float) -> float:
	return -sqrt(2.0 * body.stats.gravity * tiles * TILE)


#region Placeholder visuals
# Slash and spike drawn in code until the pogo has real art. Strike animations
# should replace this region, driven by `strike_started` and `state`.

## Minimum time the slash shows, so a strike that connects on its first tick still draws.
const SLASH_SHOW_TIME := 0.1
const SPIKE_LENGTH := 1.25 * TILE
const SLASH_FILL := Color(0.752941, 0.517647, 0.988235, 0.35)
const SLASH_RIM := Color("#e9d5ff")
const SPIKE_IDLE_COLOR := Color("#a855f7")
const SPIKE_STRIKE_COLOR := Color("#e9d5ff")

var _slash_show_left := 0.0


func _ready() -> void:
	strike_started.connect(func(_direction: StrikeDirection) -> void: _slash_show_left = SLASH_SHOW_TIME)


func _process(delta: float) -> void:
	_slash_show_left = maxf(0.0, _slash_show_left - delta)
	queue_redraw()


func _draw() -> void:
	var striking := state == State.STRIKE
	if striking or _slash_show_left > 0.0:
		var disk := slash()
		var local := HalfDisk.new(to_local(disk.center), disk.radius, disk.facing)
		var arc := local.arc_points()
		draw_colored_polygon(arc, SLASH_FILL)
		arc.append(arc[0])
		draw_polyline(arc, SLASH_RIM, 1.0)
	_draw_spike(striking)


func _draw_spike(striking: bool) -> void:
	var rect := body.body_rect()
	rect.position = to_local(rect.position)
	var direction := Vector2.DOWN
	if striking:
		direction = [Vector2.DOWN, Vector2.UP, Vector2.LEFT, Vector2.RIGHT][strike_direction]
	var tip_length := SPIKE_LENGTH + 3.0 if striking else SPIKE_LENGTH
	var half_width := 3.5 if striking else 2.5
	var base := rect.get_center() + direction * rect.size / 2.0
	var across := Vector2(-direction.y, direction.x) * half_width
	draw_colored_polygon(
		PackedVector2Array([base - across, base + across, base + direction * tip_length]),
		SPIKE_STRIKE_COLOR if striking else SPIKE_IDLE_COLOR,
	)

#endregion
