class_name Breakable
extends Node
## Arm, vanish, then optionally come back. Solid props arm when stood on; grapple
## and pogo props arm when that ability uses them.

enum State {
	ACTIVE,
	ARMING,
	GONE,
}

## Seconds until it comes back; 0 means never.
@export var respawn := 2.5
## Warning time between being used and vanishing; 0 vanishes at once.
@export var delay := 0.4

var state := State.ACTIVE
var time_left := 0.0


func reset() -> void:
	state = State.ACTIVE
	time_left = 0.0


func is_present() -> bool:
	return state != State.GONE


func tick(delta: float) -> void:
	match state:
		State.ARMING:
			time_left -= delta
			if time_left <= 0.0:
				_vanish()
		State.GONE:
			if respawn <= 0.0:
				return
			time_left -= delta
			if time_left <= 0.0:
				reset()


func on_stood_on(surface: Room.Kind) -> void:
	if surface == Room.Kind.SOLID:
		_arm()


## Returns true when this use armed it.
func on_surface_used(use: Room.Kind, surface: Room.Kind) -> bool:
	if state == State.GONE or use != surface:
		return false
	if use != Room.Kind.GRAPPLE and use != Room.Kind.POGO:
		return false
	_arm()
	return true


func _arm() -> void:
	if state != State.ACTIVE:
		return
	if delay <= 0.0:
		_vanish()
		return
	state = State.ARMING
	time_left = delay


func _vanish() -> void:
	state = State.GONE
	time_left = respawn
