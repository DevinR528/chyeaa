@tool
class_name Throwable
extends RoomActor
## A ball to carry and throw (Mario shell crossed with a snowball). Idle, it is a
## solid to stand on. Moving fast, it hurts the player and kills walkers, and it
## bounces off whatever it hits: floors, walls, ceilings, walkers, other balls.

signal picked_up
signal thrown
## Left its carrier: thrown, dropped, or reset while carried.
signal released

enum State {
	IDLE,
	CARRIED,
	THROWN,
	SLIDING,
}

## Carriers look for throwables through this group.
const CARRYABLE_GROUP := &"carryables"
const THROW_GAP := 4.0
## Sliding slower than this fraction of `hazard_speed` stops the ball.
const STOP_FRACTION := 0.35

@export_group("Throw")
@export var throw_speed := 42.0 * TILE
## Vertical velocity of a sideways throw (negative is up).
@export var throw_up := -6.0 * TILE
@export var slide_friction := 18.0 * TILE
## A thrown ball is always a hazard; after landing it stays one above this speed.
@export var hazard_speed := 14.0 * TILE

@export_group("Bounce")
## Fraction of the landing speed kept as an upward bounce.
@export_range(0.0, 1.0, 0.05) var floor_bounce := 0.5
## Landing slower than this does not bounce, so the ball settles.
@export var min_bounce_speed := 10.0 * TILE
@export_range(0.0, 1.5, 0.05) var wall_bounce := 1.0
@export_range(0.0, 1.0, 0.05) var ceiling_bounce := 0.35
## Fraction of horizontal speed kept when knocking out a walker.
@export_range(0.0, 1.5, 0.05) var walker_bounce := 0.8
## Upward speed after knocking out a walker.
@export var walker_pop := 16.0 * TILE

var state := State.IDLE
var carrier: Carrier

## A ball cannot hurt its thrower until it first lands, so a throw that starts
## inside the carrier, or one the carrier runs into, is safe.
var _thrown_by: Carrier
var _pending_stop := false
var _pending_walker_x := NAN
var _pending_rebound_velocity_x := NAN
var _pending_rebound_x := NAN


func _ready() -> void:
	super._ready()
	if not Engine.is_editor_hint():
		add_to_group(CARRYABLE_GROUP)


static func throw_direction(aim: PlayerInputFrame.Aim, facing: float) -> Vector2:
	var face := signf(facing) if not is_zero_approx(facing) else 1.0
	match aim:
		PlayerInputFrame.Aim.UP:
			return Vector2(0.0, -1.0)
		PlayerInputFrame.Aim.DOWN:
			return Vector2(face, 1.0)
		PlayerInputFrame.Aim.LEFT:
			return Vector2.LEFT
		PlayerInputFrame.Aim.RIGHT:
			return Vector2.RIGHT
	return Vector2(face, 0.0)


func reset() -> void:
	if carrier != null:
		_release()
	super.reset()
	_pending_stop = false
	_pending_walker_x = NAN
	_pending_rebound_velocity_x = NAN
	_set_state(State.IDLE)


func is_hazard() -> bool:
	if state == State.IDLE or state == State.CARRIED:
		return false
	return state == State.THROWN or absf(velocity.x) >= hazard_speed or absf(velocity.y) >= hazard_speed


## Stomping a moving ball stops it; an idle ball is stood on instead.
func accepts_stomp() -> bool:
	return state == State.THROWN or state == State.SLIDING


func hurts(player: PlayerBody) -> bool:
	return is_hazard() and not (_thrown_by != null and _thrown_by == player.carrier)


func can_pick_up() -> bool:
	return state == State.IDLE or state == State.SLIDING


func pick_up(by: Carrier) -> bool:
	if not can_pick_up():
		return false
	carrier = by
	velocity = Vector2.ZERO
	_set_state(State.CARRIED)
	picked_up.emit()
	return true


## Held low, nudged toward the facing side.
func hold_at(carrier_rect: Rect2, facing: float) -> void:
	var face := signf(facing) if not is_zero_approx(facing) else 1.0
	global_position = Vector2(
		carrier_rect.get_center().x + face * carrier_rect.size.x * 0.28,
		carrier_rect.position.y + carrier_rect.size.y * 0.55 + size.y / 2.0,
	)


## Throws leave from the carrier's feet, except up, which leaves from above the
## head, so the ball never starts inside the carrier unless every spot is walled in.
func throw_from(carrier_rect: Rect2, direction: Vector2) -> bool:
	if state != State.CARRIED:
		return false
	var thrower := carrier
	_release()
	var center_x := carrier_rect.get_center().x
	var under_feet := Vector2(center_x, carrier_rect.end.y + THROW_GAP + size.y / 2.0)
	var spot: Vector2
	var launch_velocity: Vector2
	if direction.y < 0.0 and is_zero_approx(direction.x):
		spot = Vector2(center_x, carrier_rect.position.y - THROW_GAP - size.y / 2.0)
		launch_velocity = Vector2(0.0, -throw_speed)
		if _solid_at(spot):
			spot.y -= TILE
	elif direction.y > 0.0:
		spot = under_feet
		launch_velocity = Vector2(direction.x * throw_speed * 0.35, throw_speed * 0.75)
	else:
		var side := direction.x
		var ahead := carrier_rect.end.x + THROW_GAP + size.x / 2.0 if side > 0.0 else carrier_rect.position.x - THROW_GAP - size.x / 2.0
		spot = Vector2(ahead, carrier_rect.end.y - size.y / 2.0)
		launch_velocity = Vector2(side * throw_speed, throw_up)
		if _solid_at(spot):
			spot.x += side * TILE
			if _solid_at(spot):
				spot = under_feet
				launch_velocity = Vector2(side * throw_speed * 0.5, throw_speed * 0.45)
	# Under the feet of a grounded carrier is inside the floor; rest on it instead.
	if _solid_at(spot):
		spot = Vector2(center_x, carrier_rect.end.y - size.y / 2.0)
	global_position = spot
	launch(launch_velocity)
	_thrown_by = thrower
	thrown.emit()
	return true


func launch(launch_velocity: Vector2) -> void:
	velocity = launch_velocity
	_set_state(State.THROWN)


## Let go without throwing: the ball rests where it is.
func drop() -> void:
	if state != State.CARRIED:
		return
	_release()
	_set_state(State.IDLE)


func _physics_process(delta: float) -> void:
	if driven:
		return
	tick(delta)


## One ballistic step. Carried balls stay on the carrier.
func tick(delta: float) -> void:
	if frozen or state == State.CARRIED:
		return
	var sim_delta := SimStep.delta(self, delta)
	_apply_contacts()
	_fall(sim_delta)
	var before := velocity
	SimStep.slide(self)
	_sync_physics_transform()
	_bounce(before)
	_settle(sim_delta)


func _on_contact_touched(other: Node2D) -> void:
	if other is PlayerBody:
		var player := other as PlayerBody
		if accepts_stomp() and ContactBox.is_stomp(player.body_rect().end.y, player.previous_feet_y, player.velocity.y, body_rect()):
			_pending_stop = true
	elif other is Walker:
		if is_hazard() and (other as Walker).alive:
			_pending_walker_x = other.global_position.x
	elif other is Throwable:
		var ball := other as Throwable
		if is_hazard() and ball.is_hazard():
			_pending_rebound_velocity_x = _rebound_velocity_x(velocity.x, ball.velocity.x)
			_pending_rebound_x = _rebound_x(ball)


## Applied in this ball's own tick; see ContactBox.
func _apply_contacts() -> void:
	if not is_nan(_pending_walker_x):
		var away := signf(global_position.x - _pending_walker_x)
		if is_zero_approx(away):
			away = -signf(velocity.x)
		velocity.x = away * absf(velocity.x) * walker_bounce
		velocity.y = minf(velocity.y, -walker_pop)
		_pending_walker_x = NAN
	if not is_nan(_pending_rebound_velocity_x):
		velocity.x = _pending_rebound_velocity_x
		global_position.x = _pending_rebound_x
		_pending_rebound_velocity_x = NAN
	if _pending_stop:
		velocity = Vector2.ZERO
		_set_state(State.IDLE)
		_pending_stop = false


## Floors bounce in every state so a dropped ball bounces too; walls and ceilings
## only bounce a ball in flight.
func _bounce(before: Vector2) -> void:
	var in_flight := state == State.THROWN or state == State.SLIDING
	var decisions: PackedStringArray = []
	if in_flight and is_on_wall() and not is_zero_approx(before.x):
		velocity.x = -before.x * wall_bounce
		decisions.append("bounce_wall")
	if state == State.THROWN and is_on_ceiling() and before.y < 0.0:
		velocity.y = -before.y * ceiling_bounce
		decisions.append("bounce_ceiling")
	if is_on_floor() and before.y > min_bounce_speed:
		velocity.y = -before.y * floor_bounce
		decisions.append("bounce_floor")
	if ContactLog.enabled and not decisions.is_empty():
		ContactLog.record({
			"decision": ", ".join(decisions),
			"participants": [name, "tile"],
			"normal": _bounce_normal(decisions, before),
			"velocity_before": before,
			"velocity_after": velocity,
		})


func _bounce_normal(decisions: PackedStringArray, before: Vector2) -> Vector2:
	var normal := Vector2.ZERO
	if decisions.has("bounce_floor"):
		normal.y = -1.0
	elif decisions.has("bounce_ceiling"):
		normal.y = 1.0
	if decisions.has("bounce_wall"):
		normal.x = -signf(before.x)
	return normal


func _settle(delta: float) -> void:
	if state == State.THROWN and is_on_floor():
		_set_state(State.SLIDING)
	if state != State.SLIDING:
		return
	if absf(velocity.x) < hazard_speed * STOP_FRACTION:
		velocity.x = 0.0
		_set_state(State.IDLE)
	else:
		velocity.x = move_toward(velocity.x, 0.0, slide_friction * delta)


## My half of a ball-on-ball hit: head-on hits swap speeds, rear-ends and hits on
## a still ball reverse.
func _rebound_velocity_x(mine: float, theirs: float) -> float:
	if is_zero_approx(mine):
		return -signf(theirs) * absf(theirs)
	if is_zero_approx(theirs) or signf(mine) == signf(theirs):
		return -mine
	return theirs


## Separates the pair about their midpoint; on a tie the older ball goes left.
func _rebound_x(other: Throwable) -> float:
	var mid := (global_position.x + other.global_position.x) / 2.0
	var on_left := global_position.x < other.global_position.x
	if is_equal_approx(global_position.x, other.global_position.x):
		on_left = get_instance_id() < other.get_instance_id()
	if on_left:
		return mid - size.x / 2.0 - 1.0
	return mid + size.x / 2.0 + 1.0


func _release() -> void:
	carrier = null
	released.emit()


## Idle balls are solid; a carried ball has no contacts. Deferred, since contact
## reactions can run inside the physics flush.
func _set_state(next: State) -> void:
	state = next
	if next != State.THROWN:
		_thrown_by = null
	set_deferred(&"collision_layer", PhysicsLayers.WORLD if next == State.IDLE else 0)
	contact_box.set_active(next != State.CARRIED)
	queue_redraw()


func _solid_at(center: Vector2) -> bool:
	return _solid_in(Rect2(center - size / 2.0, size).grow(-ContactBox.INSET))


#region Placeholder visuals
# The prototype's ball: warm while it is a hazard. A sprite with a spin and a
# squash on bounce replaces this region.

const COLD_COLOR := Color("#d4c48a")
const HOT_COLOR := Color("#e8a838")
const RIM_COLOR := Color("#5a4a28")


func _process(_delta: float) -> void:
	if not Engine.is_editor_hint():
		queue_redraw()


func _draw() -> void:
	var hot := not Engine.is_editor_hint() and is_hazard()
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, size.y / size.x))
	draw_circle(Vector2.ZERO, size.x / 2.0, HOT_COLOR if hot else COLD_COLOR)
	draw_arc(Vector2.ZERO, size.x / 2.0, 0.0, TAU, 32, RIM_COLOR, 1.0)
	draw_set_transform(Vector2.ZERO)

#endregion
