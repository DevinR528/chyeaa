class_name SpinMotion
extends Node
## Spreads the props a carrier holds evenly around its centre and turns them.
## The carrier itself never orbits; one orbiting platform is a hub carrying one child.
## Carried boxes do not rotate, so their collision stays axis-aligned.

@export var radius := 64.0
## Turns per second; negative spins counter-clockwise.
@export var turns_per_second := 0.25
## Starting angle in turns.
@export var start_turn := 0.0

var _angle := 0.0


func _ready() -> void:
	reset()


func reset() -> void:
	_angle = start_turn * TAU


func advance(delta: float) -> void:
	_angle += delta * turns_per_second * TAU


## Offset from the carrier's centre for arm `index` of `count`.
func offset_for(index: int, count: int) -> Vector2:
	var angle := _angle + (float(index) / count * TAU if count > 0 else 0.0)
	return Vector2(cos(angle), sin(angle)) * radius
