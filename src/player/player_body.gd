class_name PlayerBody
extends CharacterBody2D

signal dashed(facing: float)
signal dash_ready
signal jumped
signal landed(fall_duration: float)
## The whole sim should freeze; the room runner owns the countdown.
signal hitstop_requested(seconds: float)
## The touch sensor entered a room trigger. `layer` is one of TRIGGER_LAYERS' bits.
signal trigger_touched(layer: int)
## Pinned between two solids, such as a moving prop against a wall.
signal crushed
## Touched a walker or throwable that kills on contact.
signal hurt(source: RoomActor)
## Bounced off the top of a walker or moving throwable.
signal stomped(target: RoomActor)

## DASH is entered by the dash input and left when its timer runs out. The rest are
## read from the floor contact and velocity at the end of every tick.
enum MovementState {
	IDLE,
	RUN,
	JUMP,
	FALL,
	DASH,
}

const MOVEMENT_CLIPS: Dictionary[MovementState, StringName] = {
	MovementState.IDLE: &"idle",
	MovementState.RUN: &"run",
	MovementState.JUMP: &"jump",
	MovementState.FALL: &"fall",
	MovementState.DASH: &"dash",
}

const TRIGGER_LAYERS := PhysicsLayers.HAZARD | PhysicsLayers.EXIT | PhysicsLayers.FALL
## The sensor is this much smaller than the body on each side, so flush edge contact
## (standing beside an exit) is not an overlap, matching the prototype's cell rounding.
const TOUCH_SENSOR_INSET := 0.01
## Sinking this deep into two solids at once is a crush. Movement recovers from
## shallower overlaps, so props must move less than this per tick.
const CRUSH_SENSOR_INSET := 3.0

@export var stats: MovementStats
## Per-character changes applied to a copy of `stats`, keyed by MovementStats property.
@export var stat_overrides: Dictionary[StringName, float] = {}
@export var input_path: NodePath = ^"PlayerInput"
## Rooms enable their grapple and pogo tile layers only for characters that use them.
@export var uses_grapple_surfaces := false
@export var uses_pogo_surfaces := false
## The character's ability child node; empty for Standard.
@export var ability: PlayerAbility

## Set by the room runner. Abilities read tiles through it.
var room: Room
## True during hitstop: the tick is skipped and latched presses wait for the next live tick.
var frozen := false

var facing := 1.0
var move_state := MovementState.FALL

var coyote_time_left := 0.0
var jump_buffer_left := 0.0
var air_jumps_left := 0
var jump_cuttable := true
var jump_held_previous := false

var dash_time_left := 0.0
var dash_cooldown_left := 0.0
var dash_velocity_x := 0.0

var was_airborne := false
var fall_duration := 0.0
## Feet at the start of the last tick; a stomp may sweep through a body's top.
var previous_feet_y := 0.0
var contact_box: ContactBox

var _stomp_target: RoomActor
var _stomp_surface_y := 0.0

@onready var player_input: PlayerInput = get_node(input_path)
@onready var body_shape: CollisionShape2D = $CollisionShape2D
@onready var carrier: Carrier = $Carrier


func _ready() -> void:
	stats = MovementStats.new() if stats == null else stats.copy()
	for property in stat_overrides:
		stats.set(property, stat_overrides[property])
	air_jumps_left = stats.air_jumps
	var touch_sensor := _add_sensor(&"TouchSensor", TOUCH_SENSOR_INSET, TRIGGER_LAYERS)
	touch_sensor.body_shape_entered.connect(_on_touch_sensor_body_shape_entered)
	var crush_sensor := _add_sensor(&"CrushSensor", CRUSH_SENSOR_INSET, PhysicsLayers.WORLD)
	crush_sensor.body_entered.connect(func(_body: Node2D) -> void:
		if crush_sensor.get_overlapping_bodies().size() >= 2:
			crushed.emit())
	contact_box = ContactBox.attach(self, (body_shape.shape as RectangleShape2D).size, body_shape.position)
	contact_box.touched.connect(_on_contact_touched)


func _physics_process(delta: float) -> void:
	if frozen:
		return
	_apply_stomp()
	previous_feet_y = body_rect().end.y
	var input_frame := player_input.consume()
	var was_on_floor := is_on_floor()

	_tick_timers(delta, input_frame, was_on_floor)
	if ability != null:
		ability.tick(delta)
		if ability.update_active(delta, input_frame):
			# A release during the ability must not read as a fresh release edge afterwards.
			jump_held_previous = input_frame.jump_held
			_finish_tick(was_on_floor, input_frame)
			return

	_try_dash(input_frame)
	_update_motion(delta, input_frame, was_on_floor)
	if ability != null and ability.try_start(input_frame):
		ability.update_active(delta, input_frame)
	else:
		move_and_slide()
	_finish_tick(was_on_floor, input_frame)


## World-space collision box; triggers and debug hitboxes read this.
func body_rect() -> Rect2:
	var size := (body_shape.shape as RectangleShape2D).size
	return Rect2(body_shape.global_position - size / 2.0, size)


## Places the body standing on `feet`, so characters of any height spawn grounded.
func respawn(feet: Vector2) -> void:
	var rect := body_rect()
	global_position = feet - Vector2(rect.get_center().x - global_position.x, rect.end.y - global_position.y)
	velocity = Vector2.ZERO
	frozen = false
	facing = 1.0
	move_state = MovementState.FALL
	coyote_time_left = 0.0
	jump_buffer_left = 0.0
	air_jumps_left = stats.air_jumps
	jump_cuttable = true
	jump_held_previous = false
	dash_time_left = 0.0
	dash_cooldown_left = 0.0
	dash_velocity_x = 0.0
	was_airborne = false
	fall_duration = 0.0
	previous_feet_y = feet.y
	_stomp_target = null
	player_input.clear_edges()
	carrier.reset()
	if ability != null:
		ability.reset()
	reset_physics_interpolation()


func apply_jump(
	vertical_velocity := NAN,
	consume := false,
	fresh_coyote_time := -1.0,
	cuttable := true,
) -> void:
	velocity.y = stats.jump_velocity if is_nan(vertical_velocity) else vertical_velocity
	jump_cuttable = cuttable
	jump_buffer_left = 0.0
	if consume:
		coyote_time_left = 0.0
		if ability != null:
			ability.on_jump_consumed()
	if fresh_coyote_time >= 0.0:
		coyote_time_left = fresh_coyote_time
	jumped.emit()


func refresh_dash() -> void:
	dash_cooldown_left = 0.0
	dash_ready.emit()


func request_hitstop(seconds: float) -> void:
	hitstop_requested.emit(seconds)


func stomp_bounce_velocity(base_velocity: float, jump_held: bool) -> float:
	if jump_held:
		return stats.jump_velocity * stats.stomp_bounce_multiplier
	return base_velocity


## Built from the body shape, `inset` smaller on each side, so each character's
## sensors always match its body.
func _add_sensor(sensor_name: StringName, inset: float, mask: int) -> Area2D:
	var rect := RectangleShape2D.new()
	rect.size = (body_shape.shape as RectangleShape2D).size - Vector2.ONE * inset * 2.0
	var shape := CollisionShape2D.new()
	shape.shape = rect
	shape.position = body_shape.position
	# Keep `monitorable` on: Godot 2D physics treats a non-monitorable area as static,
	# and static areas never pair with static bodies such as tiles.
	var sensor := Area2D.new()
	sensor.name = sensor_name
	sensor.collision_layer = 0
	sensor.collision_mask = mask
	sensor.add_child(shape)
	add_child(sensor)
	return sensor


## Tile layers report the touched tile's physics layer through the body RID.
func _on_touch_sensor_body_shape_entered(body_rid: RID, _body: Node, _body_shape: int, _local_shape: int) -> void:
	var layer := PhysicsServer2D.body_get_collision_layer(body_rid) & TRIGGER_LAYERS
	if layer != 0:
		trigger_touched.emit(layer)


## Decides only. The bounce lands at the start of the next tick, so actors deciding
## in the same flush still read this tick's feet and velocity (see ContactBox).
func _on_contact_touched(other: Node2D) -> void:
	var actor := other as RoomActor
	if actor == null:
		return
	var target := actor.body_rect()
	if actor.accepts_stomp() and ContactBox.is_stomp(body_rect().end.y, previous_feet_y, velocity.y, target):
		_stomp_target = actor
		_stomp_surface_y = target.position.y
	elif actor.hurts(self):
		hurt.emit(actor)


func _apply_stomp() -> void:
	if _stomp_target == null:
		return
	var target := _stomp_target
	_stomp_target = null
	global_position.y += _stomp_surface_y - body_rect().end.y
	apply_jump(stomp_bounce_velocity(target.stomp_bounce, jump_held_previous), false, stats.stomp_coyote_time)
	stomped.emit(target)


func _tick_timers(delta: float, input_frame: PlayerInputFrame, was_on_floor: bool) -> void:
	if not is_zero_approx(input_frame.move.x):
		facing = signf(input_frame.move.x)

	if was_on_floor:
		coyote_time_left = stats.coyote_time
		air_jumps_left = stats.air_jumps
	else:
		coyote_time_left = maxf(0.0, coyote_time_left - delta)

	if input_frame.jump_pressed:
		jump_buffer_left = stats.jump_buffer_time
	else:
		jump_buffer_left = maxf(0.0, jump_buffer_left - delta)

	if dash_cooldown_left > 0.0:
		dash_cooldown_left = maxf(0.0, dash_cooldown_left - delta)
		if is_zero_approx(dash_cooldown_left):
			dash_ready.emit()

	if dash_time_left > 0.0:
		dash_time_left = maxf(0.0, dash_time_left - delta)
		if is_zero_approx(dash_time_left):
			move_state = _read_move_state()


func _try_dash(input_frame: PlayerInputFrame) -> void:
	if move_state == MovementState.DASH or dash_cooldown_left > 0.0 or not input_frame.dash_pressed:
		return

	var direction := signf(input_frame.move.x) if not is_zero_approx(input_frame.move.x) else facing
	facing = direction
	move_state = MovementState.DASH
	dash_time_left = stats.dash_duration
	dash_cooldown_left = stats.dash_cooldown
	dash_velocity_x = velocity.x * stats.dash_air_momentum + direction * stats.dash_speed
	velocity = Vector2(dash_velocity_x, 0.0)
	dashed.emit(direction)


func _update_motion(
	delta: float,
	input_frame: PlayerInputFrame,
	was_on_floor: bool,
) -> void:
	if move_state == MovementState.DASH:
		velocity = Vector2(dash_velocity_x, 0.0)
		jump_held_previous = input_frame.jump_held
		return

	var move_x := input_frame.move.x
	if ability != null and ability.locks_horizontal_input():
		move_x = 0.0
	var target_x := move_x * stats.max_run
	if was_on_floor:
		var rate := stats.ground_accel if not is_zero_approx(move_x) else stats.ground_friction
		velocity.x = move_toward(velocity.x, target_x, rate * delta)
	elif not is_zero_approx(move_x):
		velocity.x = move_toward(velocity.x, target_x, stats.air_accel * delta)
	else:
		velocity.x = move_toward(velocity.x, 0.0, stats.air_friction * delta)

	if jump_buffer_left > 0.0:
		if _can_jump():
			apply_jump(_jump_velocity(), true)
		elif air_jumps_left > 0:
			air_jumps_left -= 1
			apply_jump()

	if jump_cuttable and not input_frame.jump_held and jump_held_previous and velocity.y < 0.0:
		velocity.y *= stats.jump_cut
	jump_held_previous = input_frame.jump_held

	var current_gravity := stats.gravity
	if velocity.y > 0.0:
		current_gravity = stats.hold_fall_gravity if input_frame.jump_held else stats.fall_gravity
	velocity.y += current_gravity * delta

	var fall_cap := stats.hold_max_fall if input_frame.jump_held else stats.max_fall
	velocity.y = minf(velocity.y, fall_cap)


func _can_jump() -> bool:
	return coyote_time_left > 0.0 or (ability != null and ability.grants_jump())


func _jump_velocity() -> float:
	return ability.jump_velocity_override() if ability != null else NAN


func _finish_tick(was_on_floor: bool, input_frame: PlayerInputFrame) -> void:
	_update_contacts(was_on_floor)
	carrier.update(input_frame)
	if move_state != MovementState.DASH:
		move_state = _read_move_state()


func _update_contacts(was_on_floor: bool) -> void:
	var on_floor := is_on_floor()
	if on_floor:
		_notify_stood_on()
	if on_floor and not was_on_floor and was_airborne:
		refresh_dash()
		landed.emit(fall_duration)
		was_airborne = false

	if not on_floor:
		was_airborne = true
		fall_duration += get_physics_process_delta_time()
	else:
		fall_duration = 0.0


## Breakable props arm when stood on.
func _notify_stood_on() -> void:
	for index in get_slide_collision_count():
		var collision := get_slide_collision(index)
		var prop := collision.get_collider() as TileProp
		if prop != null and collision.get_normal().dot(up_direction) > 0.5:
			prop.stood_on()


## The clip for `move_state`. An active ability may play another (see `PlayerAbility.animation_clip`).
func movement_clip() -> StringName:
	return MOVEMENT_CLIPS[move_state]


## Every state except DASH, read from the last move's floor contact and velocity.
func _read_move_state() -> MovementState:
	if not is_on_floor():
		return MovementState.JUMP if velocity.y < 0.0 else MovementState.FALL
	return MovementState.IDLE if is_zero_approx(velocity.x) else MovementState.RUN


#region Placeholder visuals
# `PlaceholderBody` (a box with an eye) shows while `CharacterSprite` has no clip
# for the current state. Delete this region with that node once every clip exists.

@onready var _placeholder_body: Node2D = get_node_or_null(^"PlaceholderBody")


func _process(_delta: float) -> void:
	if _placeholder_body != null:
		_placeholder_body.scale.x = facing

#endregion
