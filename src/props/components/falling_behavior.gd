class_name FallingBehavior
extends Node
## Arms from a solid footstep, then integrates a downward drop in small steps.

enum State {
	IDLE,
	ARMING,
	FALLING,
	LANDED,
}

const MAX_STEP := MovementStats.TILE / 2.0

@export var delay := 0.3
## Gravity in tiles/s², matching the prototype data.
@export var gravity := 350.0
## Terminal speed in tiles/s, matching the prototype data.
@export var max_speed := 90.0

var state := State.IDLE
var time_left := 0.0
var shake_phase := 0.0
var velocity_y := 0.0


func reset() -> void:
	state = State.IDLE
	time_left = 0.0
	shake_phase = 0.0
	velocity_y = 0.0


func arm(surface: Room.Kind) -> void:
	if surface != Room.Kind.SOLID or state != State.IDLE:
		return
	state = State.ARMING if delay > 0.0 else State.FALLING
	time_left = delay
	shake_phase = 0.0


func tick(delta: float) -> void:
	if state != State.ARMING:
		return
	time_left -= delta
	shake_phase += delta * 40.0
	if time_left <= 0.0:
		state = State.FALLING
		shake_phase = 0.0


## Returns the new global top edge of `box`.
func fall(delta: float, box: Rect2, blocked: Callable) -> float:
	velocity_y = minf(velocity_y + gravity * MovementStats.TILE * delta, max_speed * MovementStats.TILE)
	var y := box.position.y
	var remaining := velocity_y * delta
	while remaining > 0.0:
		var step := minf(remaining, MAX_STEP)
		remaining -= step
		var next := y + step
		if not blocked.call(Rect2(Vector2(box.position.x, next), box.size)):
			y = next
			continue
		y = floorf(next)
		var guard := int(MAX_STEP) + 2
		while guard > 0 and blocked.call(Rect2(Vector2(box.position.x, y), box.size)):
			y -= 1.0
			guard -= 1
		state = State.LANDED
		velocity_y = 0.0
		break
	return y


func draw_offset_x() -> float:
	return sin(shake_phase) * 1.5 if state == State.ARMING else 0.0
