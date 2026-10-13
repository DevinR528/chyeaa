class_name RewindLog
extends RefCounted
## Input history since the last respawn. Step `i` is what moved state `i` to
## state `i + 1`. Potion uses sit on a state: a use at `step` happened once the
## room had already reached that state.

var recording := false
var spawn := Vector2.ZERO
var steps: Array[Step] = []
var trail := PackedVector2Array()
var potion_uses: Array[Dictionary] = []
var deaths: Array[int] = []
var respawns: Array[int] = []


func begin(at: Vector2) -> void:
	recording = true
	spawn = at
	steps.clear()
	trail = PackedVector2Array()
	potion_uses.clear()
	deaths.clear()
	respawns.clear()


func stop() -> void:
	recording = false
	steps.clear()
	trail = PackedVector2Array()
	potion_uses.clear()
	deaths.clear()
	respawns.clear()


func push(frame: PlayerInputFrame, real_delta: float, stats: MovementStats) -> void:
	var step := Step.new()
	step.frame = frame.duplicate_data()
	step.real_delta = real_delta
	step.stats = stats
	steps.append(step)


func push_trail(at: Vector2) -> void:
	if trail.size() < steps.size():
		trail.append(at)


## `index` is the step that just finished. Replay writes back over the live path.
func put_trail(index: int, at: Vector2) -> void:
	if index < 0:
		return
	if index < trail.size():
		trail[index] = at
	elif index == trail.size():
		trail.append(at)


func cut_trail(state: int) -> void:
	if trail.size() > state:
		trail.resize(state)


func mark_death() -> void:
	deaths.append(steps.size())


func mark_respawn() -> void:
	respawns.append(steps.size())


func log_use(use: PotionUse) -> void:
	potion_uses.append({"step": steps.size(), "use": use})


func respawn_floor() -> int:
	return 0 if respawns.is_empty() else int(respawns.back())


func undo_uses_through(state: int) -> void:
	for index in range(potion_uses.size() - 1, -1, -1):
		var entry: Dictionary = potion_uses[index]
		if int(entry.step) <= state:
			(entry.use as PotionUse).undo()


func redo_uses_at(state: int) -> void:
	for entry: Dictionary in potion_uses:
		if int(entry.step) == state:
			(entry.use as PotionUse).redo()


func truncate(state: int) -> void:
	var kept := mini(state, steps.size())
	steps.resize(kept)
	if trail.size() > kept:
		trail.resize(kept)
	var uses: Array[Dictionary] = []
	for entry: Dictionary in potion_uses:
		if int(entry.step) <= state:
			uses.append(entry)
	potion_uses = uses
	deaths = _keep_marks(deaths, state)
	respawns = _keep_marks(respawns, state)


static func _keep_marks(marks: Array[int], state: int) -> Array[int]:
	var kept: Array[int] = []
	for at: int in marks:
		if at <= state:
			kept.append(at)
	return kept


## Payload only: one step is the frame, the delta, a stats pointer, and a trail point.
func payload_bytes() -> int:
	return steps.size() * 65


class Step:
	extends RefCounted
	var frame: PlayerInputFrame
	var real_delta := 0.0
	var stats: MovementStats
