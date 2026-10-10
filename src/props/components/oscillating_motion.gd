class_name OscillatingMotion
extends Node
## Sine patrol along one axis around the prop's home position.

enum Axis {
	X,
	Y,
}

## Distance from home to either end, in px.
@export var travel := 32.0
## Radians per second.
@export var speed := 1.0
@export var axis := Axis.X
## Starting angle in radians; the prop starts at sin(phase) * travel from home.
@export var phase := 0.0

var _angle := 0.0


func _ready() -> void:
	reset()


func reset() -> void:
	_angle = phase


## Offset from home after advancing `delta` seconds.
func advance(delta: float) -> Vector2:
	_angle += delta * speed
	var offset := sin(_angle) * travel
	return Vector2(offset, 0.0) if axis == Axis.X else Vector2(0.0, offset)
