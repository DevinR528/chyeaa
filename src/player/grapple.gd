class_name Grapple
extends PlayerAbility
## Celeste 2 style horizontal hook: throw, latch onto grapple tiles, reel in, jump off.
## https://github.com/EXOK/Celeste2/blob/main/player.lua

enum State {
	## Not grappling (also during the cooldown); locomotion is in control.
	INACTIVE,
	THROW,
	ATTACHED,
	RETRACT,
}

const TILE := MovementStats.TILE
const THROW_SUBSTEP := TILE / 4.0
const RETRACT_SNAP := TILE / 2.0
## Hook height, as a fraction of body height from the top.
const CHEST_HEIGHT := 0.35
## Below this vertical speed (px/s) the body eases toward the hook's height.
const HEIGHT_CORRECT_MAX_SPEED := 20.0

@export_group("Throw")
@export var reach_tiles := 28.0
@export var throw_speed := 130.0 * TILE
## Vertical forgiveness when the hook tests for a latch.
@export var latch_slop := TILE / 4.0
@export_range(0.0, 1.0, 0.01) var cooldown := 0.18
@export_range(0.0, 0.3, 0.005) var hitstop := 0.08

@export_group("Pull")
@export var boost_speed := 105.0 * TILE
@export var pull_speed := 75.0 * TILE
@export var pull_accel := 225.0 * TILE
@export var vertical_damp := 350.0 * TILE
@export var height_correct_speed := 15.0 * TILE

@export_group("Release")
@export_range(0.0, 0.5, 0.005) var jump_grace := 0.14
@export var jump_velocity := -95.0 * TILE
## Horizontal speed cap after letting go: under the boost, over the pull.
@export var release_speed_cap := 95.0 * TILE
@export var retract_speed := Vector2(175.0, 100.0) * TILE

var state := State.INACTIVE
## World-space hook position.
var hook := Vector2.ZERO
var direction := 1.0
var boosted := false
var cooldown_left := 0.0
var jump_grace_left := 0.0
## The prop the hook rides, or null when latched to a tile.
var attached_prop: TileProp
var _hook_offset := Vector2.ZERO


func reset() -> void:
	state = State.INACTIVE
	attached_prop = null
	cooldown_left = 0.0
	jump_grace_left = 0.0


func reach() -> float:
	return reach_tiles * TILE


func animation_clip(movement_clip: StringName) -> StringName:
	return movement_clip if state == State.INACTIVE else &"grapple"


func tick(delta: float) -> void:
	jump_grace_left = maxf(0.0, jump_grace_left - delta)
	if cooldown_left > 0.0 and state == State.INACTIVE:
		cooldown_left = maxf(0.0, cooldown_left - delta)

	if state == State.RETRACT:
		var rope_start := chest()
		hook.x = move_toward(hook.x, rope_start.x, retract_speed.x * delta)
		hook.y = move_toward(hook.y, rope_start.y, retract_speed.y * delta)
		if absf(hook.x - rope_start.x) < RETRACT_SNAP and absf(hook.y - rope_start.y) < RETRACT_SNAP:
			state = State.INACTIVE


func update_active(delta: float, input: PlayerInputFrame) -> bool:
	if state == State.THROW:
		_update_throw(delta, input)
		if state == State.ATTACHED:
			_update_attached(delta, input)
			body.request_hitstop(hitstop)
		return true
	if state == State.ATTACHED:
		_update_attached(delta, input)
		return true
	return false


func try_start(input: PlayerInputFrame) -> bool:
	if not input.action_pressed or cooldown_left > 0.0 or state != State.INACTIVE:
		return false
	state = State.THROW
	body.velocity = Vector2.ZERO
	hook = chest()
	direction = signf(input.move.x) if not is_zero_approx(input.move.x) else body.facing
	body.facing = direction
	boosted = false
	cooldown_left = cooldown
	return true


func grants_jump() -> bool:
	return jump_grace_left > 0.0


func jump_velocity_override() -> float:
	if jump_grace_left > 0.0 and body.coyote_time_left <= 0.0:
		return jump_velocity
	return NAN


func on_jump_consumed() -> void:
	jump_grace_left = 0.0


## Hook travel stays frozen in place: the body does not move while throwing.
func _update_throw(delta: float, input: PlayerInputFrame) -> void:
	var remaining := minf(throw_speed * delta, reach() - absf(hook.x - chest().x))
	while remaining > 0.0:
		var step := minf(THROW_SUBSTEP, remaining)
		var next_x := hook.x + direction * step
		for y in [hook.y, hook.y - latch_slop, hook.y + latch_slop]:
			var point := Vector2(next_x, y)
			if body.room.kind_at(point) == Room.Kind.GRAPPLE:
				_latch(point)
				return
			var grapple_prop := body.room.prop_at(point, Room.Kind.GRAPPLE)
			if grapple_prop != null:
				_latch_prop(grapple_prop, Vector2(next_x, hook.y))
				return
			if body.room.is_solid_cell(body.room.cell_at(point)) or body.room.prop_at(point, Room.Kind.SOLID) != null:
				_cancel()
				return
		hook.x = next_x
		remaining -= step

	if absf(hook.x - chest().x) >= reach() or not input.action_held:
		_cancel()


## Snaps to the centre of the grapple cell that was hit. The prototype snapped to
## the hook's own row, which let a slop hit latch onto air and drop next tick.
func _latch(point: Vector2) -> void:
	hook = body.room.cell_rect(body.room.cell_at(point)).get_center()
	attached_prop = null
	_attach()


## Props are not snapped: the hook stays where it hit and rides the prop from there.
func _latch_prop(prop: TileProp, at: Vector2) -> void:
	hook = at
	attached_prop = prop
	_hook_offset = at - prop.global_position
	_attach()
	prop.use_surface(Room.Kind.GRAPPLE)


func _attach() -> void:
	state = State.ATTACHED
	boosted = false
	body.coyote_time_left = body.stats.coyote_time
	body.air_jumps_left = body.stats.air_jumps


func _update_attached(delta: float, input: PlayerInputFrame) -> void:
	var latched := false
	if attached_prop != null:
		latched = attached_prop.is_present()
		hook = attached_prop.global_position + _hook_offset
	else:
		latched = body.room.kind_at(hook) == Room.Kind.GRAPPLE
	if not latched:
		_release(false)
		body.move_and_slide()
		return

	if not boosted:
		boosted = true
		body.velocity.x = direction * boost_speed
	body.velocity.x = move_toward(body.velocity.x, direction * pull_speed, pull_accel * delta)
	body.velocity.y = move_toward(body.velocity.y, 0.0, vertical_damp * delta)

	if absf(body.velocity.y) < HEIGHT_CORRECT_MAX_SPEED:
		var rect := body.body_rect()
		var target_top := hook.y - rect.size.y * CHEST_HEIGHT
		if rect.position.y > target_top + 1.0:
			body.move_and_collide(Vector2(0.0, -height_correct_speed * delta))
		elif rect.position.y < target_top - 1.0:
			body.move_and_collide(Vector2(0.0, height_correct_speed * delta))

	if input.jump_pressed or body.jump_buffer_left > 0.0:
		body.jump_buffer_left = 0.0
		_jump_off()
	elif not input.action_held:
		_release(true)
	elif signf(chest().x - hook.x) == direction:
		_release(false)
	body.move_and_slide()


func _cancel() -> void:
	state = State.RETRACT
	attached_prop = null


func _release(flip_facing: bool) -> void:
	_cancel()
	jump_grace_left = jump_grace
	if flip_facing:
		body.facing *= -1.0
	_cap_release_speed()


func _jump_off() -> void:
	_cancel()
	jump_grace_left = 0.0
	body.apply_jump(jump_velocity, true)
	_cap_release_speed()


func _cap_release_speed() -> void:
	body.velocity.x = clampf(body.velocity.x, -release_speed_cap, release_speed_cap)


## Where the rope leaves the body; the hook is thrown from this height.
func chest() -> Vector2:
	var rect := body.body_rect()
	return Vector2(rect.get_center().x, rect.position.y + rect.size.y * CHEST_HEIGHT)


#region Placeholder visuals
# Rope and hook drawn in code until the grapple has real art. A rope animation
# should replace this region; it still needs `chest()` and `hook` as end points.

const ROPE_COLOR := Color("#f0d080")
const HOOK_COLOR := Color("#ffe8a0")
const WAVE_AMPLITUDE := 2.5 * TILE
const WAVE_PERIOD_MS := 18.0
const WAVE_CYCLES := 2.5
const WAVE_SEGMENTS := 14
## Fraction of reach after which the thrown rope straightens out.
const WAVE_REACH_FADE := 0.85

## 0..1 rope wiggle while throwing.
var _wave := 0.0


func _process(delta: float) -> void:
	_wave = move_toward(_wave, 1.0, 4.0 * delta) if state == State.THROW else 0.0
	queue_redraw()


func _draw() -> void:
	if state == State.INACTIVE:
		return
	var from := to_local(chest())
	var to := to_local(hook)
	draw_polyline(_rope_points(from, to), ROPE_COLOR, 1.0)
	draw_rect(Rect2(to - Vector2(1.5, 1.5), Vector2(3.0, 3.0)), HOOK_COLOR)


## A travelling sine along the rope while it is thrown, straightening near full reach.
func _rope_points(from: Vector2, to: Vector2) -> PackedVector2Array:
	var extension := absf(to.x - from.x) / reach()
	var amount := 0.0
	if state == State.THROW and extension < 1.0:
		var reach_fade := 1.0 if extension <= WAVE_REACH_FADE else (1.0 - extension) / (1.0 - WAVE_REACH_FADE)
		amount = _wave * reach_fade
	if amount <= 0.0 or from.distance_to(to) < 1.0:
		return PackedVector2Array([from, to])

	var along := (to - from).normalized()
	var normal := Vector2(-along.y, along.x)
	var phase := Time.get_ticks_msec() / WAVE_PERIOD_MS
	var points := PackedVector2Array([from])
	for segment in range(1, WAVE_SEGMENTS + 1):
		var t := float(segment) / WAVE_SEGMENTS
		var offset := sin(t * WAVE_CYCLES * TAU + phase) * WAVE_AMPLITUDE * amount
		points.append(from.lerp(to, t) + normal * offset)
	return points

#endregion
