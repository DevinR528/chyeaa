class_name PathMotion
extends Path2D
## Walks the curve's points at constant speed in straight legs; the carrying prop's
## centre follows. Edit the points with the Path2D tools. Top level, so the path
## stays where it was drawn while the prop moves along it.

enum Mode {
	PING_PONG,
	LOOP,
	ONCE,
}

@export var speed := 4.0 * MovementStats.TILE
@export var mode := Mode.PING_PONG

## Leg being walked, from point `_from` to point `_to`.
var _from := 0
var _to := 0
var _travelled := 0.0
var _direction := 1
var _done := false


func _ready() -> void:
	top_level = true
	reset()


func reset() -> void:
	_from = 0
	_to = mini(1, _point_count() - 1)
	_travelled = 0.0
	_direction = 1
	_done = _point_count() < 2


## World-space centre after advancing `delta` seconds.
func advance(delta: float) -> Vector2:
	# Duplicate points cost no distance, so cap the legs walked per tick.
	var guard := _point_count() * 2 + 8
	var budget := speed * delta
	while budget > 0.0 and not _done and guard > 0:
		guard -= 1
		var remaining := _leg_length() - _travelled
		if budget < remaining:
			_travelled += budget
			break
		budget -= maxf(remaining, 0.0)
		_arrive()
	return position_now()


func position_now() -> Vector2:
	if _point_count() == 0:
		return global_position
	var length := _leg_length()
	if length <= 0.0:
		return _point(_from)
	return _point(_from).lerp(_point(_to), minf(_travelled / length, 1.0))


func _arrive() -> void:
	_from = _to
	_travelled = 0.0
	var last := _point_count() - 1
	var next := _from + _direction
	if next < 0 or next > last:
		match mode:
			Mode.LOOP:
				next = 0 if _direction > 0 else last
			Mode.PING_PONG:
				_direction = -_direction
				next = _from + _direction
			Mode.ONCE:
				_done = true
				next = _from
	_to = next


func _leg_length() -> float:
	return _point(_from).distance_to(_point(_to))


func _point(index: int) -> Vector2:
	return global_transform * curve.get_point_position(index)


func _point_count() -> int:
	return curve.get_point_count() if curve != null else 0
