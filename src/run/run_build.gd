class_name RunBuild
extends RefCounted
## Stack counts for one run, kept off the live player. `recompute` always starts
## from a character's baseline, so switching characters cannot compound modifiers.

enum Id {
	SLOW_TIME,
	TOP_SPEED,
	JUMP_HEIGHT,
	SLOW_FALL,
	CHECKPOINT,
	REWIND,
}

const MAX_STACKS: Dictionary[Id, int] = {
	Id.SLOW_TIME: 4,
	Id.TOP_SPEED: 5,
	Id.JUMP_HEIGHT: 5,
	Id.SLOW_FALL: 5,
	Id.CHECKPOINT: 1,
	Id.REWIND: 1,
}

const _ORDER: Array[Id] = [
	Id.SLOW_TIME,
	Id.TOP_SPEED,
	Id.JUMP_HEIGHT,
	Id.SLOW_FALL,
	Id.CHECKPOINT,
	Id.REWIND,
]

const SLOW_TIME_PER_STACK := 0.05
const SLOW_TIME_MAX := 0.2
const TOP_SPEED_PER_STACK := 0.12
const JUMP_HEIGHT_PER_STACK := 0.08
const SLOW_FALL_PER_STACK := 0.12

var stacks: Dictionary[Id, int] = {}
## 1 is normal. Slow Time lowers it to a floor of 0.8. Gameplay multiplies its
## own delta by this; Engine.time_scale stays 1.
var time_scale := 1.0


func stack_count(id: Id) -> int:
	return stacks.get(id, 0)


func add_stack(id: Id) -> void:
	var current := stack_count(id)
	if current >= MAX_STACKS[id]:
		return
	stacks[id] = current + 1


func remove_stack(id: Id) -> void:
	var current := stack_count(id)
	if current <= 0:
		return
	if current == 1:
		stacks.erase(id)
	else:
		stacks[id] = current - 1


func duplicate_build() -> RunBuild:
	var copy := RunBuild.new()
	copy.stacks = stacks.duplicate()
	copy.time_scale = time_scale
	return copy


## Fresh stats. `base` is not modified. Also stores `time_scale` for this build.
func recompute(base: MovementStats) -> MovementStats:
	var stats := base.copy()
	var slow := minf(SLOW_TIME_MAX, stack_count(Id.SLOW_TIME) * SLOW_TIME_PER_STACK)
	time_scale = maxf(1.0 - SLOW_TIME_MAX, 1.0 - slow)

	var top := mini(stack_count(Id.TOP_SPEED), MAX_STACKS[Id.TOP_SPEED])
	stats.max_run *= 1.0 + TOP_SPEED_PER_STACK * top

	var jump := mini(stack_count(Id.JUMP_HEIGHT), MAX_STACKS[Id.JUMP_HEIGHT])
	stats.jump_velocity *= 1.0 + JUMP_HEIGHT_PER_STACK * jump

	var fall := mini(stack_count(Id.SLOW_FALL), MAX_STACKS[Id.SLOW_FALL])
	var fall_factor := 1.0 / (1.0 + SLOW_FALL_PER_STACK * fall)
	stats.fall_gravity *= fall_factor
	stats.hold_fall_gravity *= fall_factor
	stats.max_fall *= fall_factor
	stats.hold_max_fall *= fall_factor
	return stats


## Compact HUD line. `charges` is remaining uses per potion id; those print as
## "N left" instead of a stack count. `scale` is the sim time scale to show.
func summary(scale: float, bank_count := 0, charges: Dictionary = {}) -> String:
	var parts: PackedStringArray = []
	for id: Id in _ORDER:
		var count := stack_count(id)
		if count <= 0:
			continue
		if charges.has(id):
			parts.append("%s (%d left)" % [name_of(id), int(charges[id])])
		else:
			parts.append("%s×%d" % [name_of(id), count])
	if scale < 1.0:
		parts.append("sim %d%%" % roundi(scale * 100.0))
	if bank_count > 0:
		parts.append("bank %d" % bank_count)
	if parts.is_empty():
		return "No power-ups"
	return " · ".join(parts)


static func name_of(id: Id) -> String:
	match id:
		Id.SLOW_TIME:
			return "Slow Time"
		Id.TOP_SPEED:
			return "Top Speed"
		Id.JUMP_HEIGHT:
			return "Jump Height"
		Id.SLOW_FALL:
			return "Slow Fall"
		Id.CHECKPOINT:
			return "Checkpoint"
		Id.REWIND:
			return "Rewind"
	return ""


## Up to `count` distinct power-ups that can still take a stack, in offer order.
## `rng` returns a float in [0, 1), the same contract as `randf`.
func roll_offer(count := 3, rng: Callable = Callable()) -> Array[Id]:
	var pool: Array[Id] = []
	for id: Id in _ORDER:
		# Rewind has no drink yet, so offering it would add a stack the picker cannot use.
		if id == Id.REWIND:
			continue
		if stack_count(id) < MAX_STACKS[id]:
			pool.append(id)
	var random := rng if rng.is_valid() else func() -> float: return randf()
	for i in range(pool.size() - 1, 0, -1):
		var j := mini(i, int(float(random.call()) * float(i + 1)))
		var swap := pool[i]
		pool[i] = pool[j]
		pool[j] = swap
	if pool.size() > count:
		pool.resize(count)
	return pool


## Card text. Potions name the Potion action; charges are rolled when equipped.
static func describe(id: Id) -> String:
	match id:
		Id.SLOW_TIME:
			return "Sim dt ×0.95 per stack (max ×0.80). Full FPS and input every frame."
		Id.TOP_SPEED:
			return "+12% max run speed per stack."
		Id.JUMP_HEIGHT:
			return "Higher jumps (+8% jump speed per stack)."
		Id.SLOW_FALL:
			return "Softer falls. Lower fall gravity and fall speed."
		Id.CHECKPOINT:
			return "Potion: press Potion to plant a respawn flag. Limited charges (usually 1)."
		Id.REWIND:
			return "Potion: press Potion to rewind to any moment since your last respawn. Limited charges (usually 1)."
	return ""
