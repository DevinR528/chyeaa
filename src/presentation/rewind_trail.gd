class_name RewindTrail
extends Node2D
## Debug path of the player's position through the rewind log, up to the scrub
## point. Hidden unless a debug overlay is on. Keeps drawing while rewind pauses
## the tree.

var runner: RoomRunner


func _ready() -> void:
	z_index = 8
	visible = false
	process_mode = Node.PROCESS_MODE_ALWAYS


func _physics_process(_delta: float) -> void:
	var show := runner != null and runner.log.recording and _debug_on()
	visible = show
	if show:
		queue_redraw()


func _debug_on() -> bool:
	var reach := runner.get_node_or_null(^"ReachOverlay")
	if reach is CanvasItem and (reach as CanvasItem).visible:
		return true
	var readout := runner.get_node_or_null(^"PlayReadout")
	return readout != null and bool(readout.get(&"shown"))


func _draw() -> void:
	if runner == null or runner.log.trail.is_empty():
		return
	_span(0, mini(runner._cursor, runner.log.trail.size()), Color(0.98, 0.8, 0.08, 0.85))


## State 0 is the spawn. State `i` after that is `trail[i - 1]`.
func _span(from: int, to: int, color: Color) -> void:
	if to <= from:
		return
	var points := PackedVector2Array()
	for index in range(from, to + 1):
		if index == 0:
			points.append(to_local(runner.log.spawn))
		elif index - 1 < runner.log.trail.size():
			points.append(to_local(runner.log.trail[index - 1]))
	if points.size() >= 2:
		draw_polyline(points, color, 1.0)
