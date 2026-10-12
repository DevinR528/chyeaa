class_name DashTrail
extends Node2D
## Copies of the body left behind while dashing. They fade on their own after
## the dash ends, and a new dash replaces them.

const MAX_GHOSTS := 14
const FADE := 0.22
const MIN_SPACING_SQ := 9.0

var _ghosts: Array[Dictionary] = []


func _ready() -> void:
	z_index = -1


func ghost_count() -> int:
	return _ghosts.size()


func trailing_behind(x: float) -> bool:
	for ghost in _ghosts:
		if (ghost.position as Vector2).x < x - 1.0:
			return true
	return false


func clear() -> void:
	_ghosts.clear()
	queue_redraw()


## The body at the moment the dash starts, before this tick's motion.
func begin(origin: Vector2) -> void:
	_ghosts = [{"position": origin, "age": 0.0}]
	queue_redraw()


func tick(dt: float, dashing: bool, origin: Vector2) -> void:
	var kept: Array[Dictionary] = []
	for ghost in _ghosts:
		ghost.age = float(ghost.age) + dt
		if float(ghost.age) < FADE:
			kept.append(ghost)
	_ghosts = kept
	if dashing:
		var last := origin
		if not _ghosts.is_empty():
			last = _ghosts.back().position
		var delta := origin - last
		if _ghosts.is_empty() or delta.length_squared() >= MIN_SPACING_SQ:
			_ghosts.append({"position": origin, "age": 0.0})
			if _ghosts.size() > MAX_GHOSTS:
				_ghosts.pop_front()
	queue_redraw()


#region Placeholder visuals
# Body-colored rectangles stand in for an authored dash afterimage.

const _PEAK_ALPHA := 0.55


func _draw() -> void:
	var body := get_parent() as PlayerBody
	if body == null or _ghosts.is_empty():
		return
	var size := body.body_rect().size
	var color := _body_color(body)
	for ghost in _ghosts:
		var faded := color
		faded.a = (1.0 - float(ghost.age) / FADE) * _PEAK_ALPHA
		draw_rect(Rect2(to_local(ghost.position), size), faded)


func _body_color(body: PlayerBody) -> Color:
	var poly := body.get_node_or_null(^"PlaceholderBody") as Polygon2D
	if poly != null:
		return poly.color
	return Color("#e8f0ff")

#endregion
