class_name PotionBelt
extends RefCounted
## Live potions for the current build. Spent potions stay: their room effect is
## still there. Unspent potions that leave the build are cleared.

## Power-ups that are potions. `make` builds the live one.
const POTION_IDS: Array[RunBuild.Id] = [RunBuild.Id.CHECKPOINT, RunBuild.Id.REWIND]

var potions: Dictionary[RunBuild.Id, Potion] = {}


static func make(id: RunBuild.Id) -> Potion:
	match id:
		RunBuild.Id.CHECKPOINT:
			return CheckpointPotion.new()
		RunBuild.Id.REWIND:
			return RewindPotion.new()
	return null


func sync(build: RunBuild, room: Room) -> bool:
	var changed := false
	for id: RunBuild.Id in POTION_IDS:
		var want := build.stack_count(id) > 0
		var have: Potion = potions.get(id)
		if want and have == null:
			potions[id] = make(id)
			changed = true
		elif want and have != null and have.uses <= 0:
			have.uses = Potion.roll_uses()
			changed = true
		elif not want and have != null and have.uses > 0:
			have.clear(room)
			potions.erase(id)
			changed = true
	return changed


func potion(id: RunBuild.Id) -> Potion:
	var item: Potion = potions.get(id)
	return item


func spent() -> Array[RunBuild.Id]:
	var ids: Array[RunBuild.Id] = []
	for id: RunBuild.Id in potions:
		if potions[id].uses <= 0:
			ids.append(id)
	return ids


func charges() -> Dictionary:
	var out := {}
	for id: RunBuild.Id in potions:
		var item := potions[id]
		if item.uses > 0:
			out[id] = item.uses
	return out


## Rows for the picker. Spent potions are omitted. `blocked` is empty when the
## potion can be drunk.
func choices(player: PlayerBody) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for id: RunBuild.Id in POTION_IDS:
		var item: Potion = potions.get(id)
		if item == null or item.uses <= 0:
			continue
		var blocked := "" if item.can_use(player) else "Can't use it here"
		rows.append({
			"id": id,
			"name": RunBuild.name_of(id),
			"uses": item.uses,
			"action": item.action,
			"blocked": blocked,
		})
	return rows


func use(id: RunBuild.Id, feet: Vector2, room: Room) -> PotionUse:
	var item: Potion = potions.get(id)
	if item == null or item.action != Potion.Action.INSTANT:
		return null
	return item.use(feet, room)


func on_room_exit(room: Room) -> void:
	for id: RunBuild.Id in potions:
		potions[id].on_room_exit(room)
