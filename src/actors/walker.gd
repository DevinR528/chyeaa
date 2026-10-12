@tool
class_name Walker
extends RoomActor
## Ground patrol at a constant speed; turns at walls and, optionally, ledges.
## Touching its sides kills the player. A stomp or a hazardous throwable kills it.

signal died(cause: DeathCause)

enum DeathCause {
	STOMPED,
	HIT,
}

const NO_DEATH := -1
const WALL_PROBE_WIDTH := 2.0
const LEDGE_PROBE_SIZE := Vector2(2.0, 4.0)
## A ledge only turns the walker once the ground is gone this far ahead, so it
## walks over gaps narrower than its body.
const LEDGE_LOOKAHEAD := 2.0

@export var speed := 5.0 * TILE
@export_enum("Left:-1", "Right:1") var start_facing := 1:
	set(value):
		start_facing = value
		facing = value
		queue_redraw()
@export var turn_on_ledges := true

var facing := 1.0
var alive := true

var _pending_death := NO_DEATH


func reset() -> void:
	super.reset()
	alive = true
	facing = start_facing
	_pending_death = NO_DEATH
	visible = true
	contact_box.set_active(true)
	queue_redraw()


func accepts_stomp() -> bool:
	return alive


func hurts(_player: PlayerBody) -> bool:
	return alive


func _physics_process(delta: float) -> void:
	if frozen:
		return
	if _pending_death != NO_DEATH:
		_die(_pending_death as DeathCause)
	if not alive:
		return
	if _wall_ahead() or (turn_on_ledges and _ledge_ahead()):
		facing = -facing
		queue_redraw()
	velocity.x = facing * speed
	_fall(SimStep.delta(self, delta))
	SimStep.slide(self)
	_sync_physics_transform()


func _on_contact_touched(other: Node2D) -> void:
	if not alive:
		return
	if other is PlayerBody:
		var player := other as PlayerBody
		if ContactBox.is_stomp(player.body_rect().end.y, player.previous_feet_y, player.velocity.y, body_rect()):
			_pending_death = DeathCause.STOMPED
	elif other is Throwable and (other as Throwable).is_hazard():
		_pending_death = DeathCause.HIT


func _die(cause: DeathCause) -> void:
	_pending_death = NO_DEATH
	alive = false
	velocity = Vector2.ZERO
	visible = false
	contact_box.set_active(false)
	died.emit(cause)


## Mid-body probe, so a step at the feet or a ceiling at the head does not turn it.
func _wall_ahead() -> bool:
	var rect := body_rect()
	var probe_x := rect.end.x if facing > 0.0 else rect.position.x - WALL_PROBE_WIDTH
	return _solid_in(Rect2(probe_x, rect.position.y + rect.size.y * 0.35, WALL_PROBE_WIDTH, rect.size.y * 0.3))


func _ledge_ahead() -> bool:
	if not is_on_floor():
		return false
	var rect := body_rect()
	var foot_x := rect.end.x + 1.0 if facing > 0.0 else rect.position.x - 1.0 - LEDGE_PROBE_SIZE.x
	if _solid_in(Rect2(Vector2(foot_x, rect.end.y + 1.0), LEDGE_PROBE_SIZE)):
		return false
	var shifted := global_transform.translated(Vector2(facing * LEDGE_LOOKAHEAD, 0.0))
	return not test_move(shifted, Vector2(0.0, 1.0))


#region Placeholder visuals
# The prototype's red box with an eye on the facing side. A walker sprite with a
# walk cycle and a squash on death replaces this region.

const BODY_COLOR := Color("#c45c5c")
const EYE_COLOR := Color("#2a1a1a")
const EYE_SIZE := 3.0


func _draw() -> void:
	if not Engine.is_editor_hint() and not alive:
		return
	var box := Rect2(-size / 2.0, size)
	draw_rect(box, BODY_COLOR)
	var eye_x := box.end.x - EYE_SIZE - 2.0 if facing > 0.0 else box.position.x + 2.0
	draw_rect(Rect2(eye_x, box.position.y + 4.0, EYE_SIZE, EYE_SIZE), EYE_COLOR)

#endregion
