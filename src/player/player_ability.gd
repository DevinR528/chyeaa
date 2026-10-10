class_name PlayerAbility
extends Node2D
## A character's special move, added as a child of its PlayerBody. The body calls
## these hooks from its physics tick; the defaults are a character with no ability.

@onready var body: PlayerBody = get_parent()


func reset() -> void:
	pass


## Timers that run every tick, before the ability or locomotion update.
func tick(_delta: float) -> void:
	pass


## Return true to own this tick (locomotion is skipped). Move the body here if it should move.
func update_active(_delta: float, _input: PlayerInputFrame) -> bool:
	return false


## Return true when the ability started; `update_active` then runs in the same tick.
func try_start(_input: PlayerInputFrame) -> bool:
	return false


## An extra window in which a buffered jump may fire, on top of coyote time.
func grants_jump() -> bool:
	return false


## Velocity for the next normal jump, or NAN to use the stats jump.
func jump_velocity_override() -> float:
	return NAN


func on_jump_consumed() -> void:
	pass


## True while held horizontal input must not steer locomotion.
func locks_horizontal_input() -> bool:
	return false
