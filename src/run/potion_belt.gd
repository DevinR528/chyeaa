class_name PotionBelt
extends RefCounted
## Live potions for the current build. Spent potions stay: their flag is still
## in the room. Unspent potions that leave the build are cleared.

const POTION_IDS: Array[RunBuild.Id] = [RunBuild.Id.CHECKPOINT]

var potions: Dictionary = {}


func sync(build: RunBuild, room: Room) -> bool:
	var changed := false
	for id: RunBuild.Id in POTION_IDS:
		var want := build.stack_count(id) > 0
		var have := potions.get(id) as CheckpointPotion
		if want and have == null:
			potions[id] = CheckpointPotion.new()
			changed = true
		elif want and have != null and have.uses <= 0:
			have.uses = CheckpointPotion.roll_uses()
			changed = true
		elif not want and have != null and have.uses > 0:
			have.clear(room)
			potions.erase(id)
			changed = true
	return changed


func potion(id: RunBuild.Id) -> CheckpointPotion:
	return potions.get(id) as CheckpointPotion


func spent() -> Array[RunBuild.Id]:
	var ids: Array[RunBuild.Id] = []
	for id: RunBuild.Id in potions:
		var item := potions[id] as CheckpointPotion
		if item.uses <= 0:
			ids.append(id)
	return ids


func charges() -> Dictionary:
	var out := {}
	for id: RunBuild.Id in potions:
		var item := potions[id] as CheckpointPotion
		if item.uses > 0:
			out[id] = item.uses
	return out


## Rows for the picker. Spent potions are omitted. `blocked` is empty when the
## potion can be drunk.
func choices(player: PlayerBody) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for id: RunBuild.Id in POTION_IDS:
		var item := potions.get(id) as CheckpointPotion
		if item == null or item.uses <= 0:
			continue
		var blocked := "" if item.can_use(player) else "Can't use it here"
		rows.append({
			"id": id,
			"name": "Checkpoint",
			"uses": item.uses,
			"blocked": blocked,
		})
	return rows


func use(id: RunBuild.Id, feet: Vector2, room: Room) -> CheckpointUse:
	var item := potions.get(id) as CheckpointPotion
	if item == null or not item.instant:
		return null
	return item.use(feet, room)


func on_room_exit(room: Room) -> void:
	for id: RunBuild.Id in potions:
		(potions[id] as CheckpointPotion).clear(room)
