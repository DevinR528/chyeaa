class_name Power
extends Node
## Room-scoped switch subscription for optional motion and presence effects.

signal powered_changed(is_powered: bool)

enum Need {
	ALL,
	ANY,
}

enum Effect {
	RUNS,
	STOPS,
	APPEARS,
	VANISHES,
}

@export var watches: Array[StringName] = []
@export var need := Need.ALL
@export var effect := Effect.RUNS
## Legacy gates used this when they watched no switches.
@export var starts_on_when_unwatched := false

var is_powered := false
var _room: Room
var _states: Dictionary = {}


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	call_deferred("_bind_room")


func _exit_tree() -> void:
	for room_switch: SwitchProp in _states.keys():
		_untrack(room_switch)
	if _room != null and is_instance_valid(_room):
		if _room.switch_registered.is_connected(_on_switch_registered):
			_room.switch_registered.disconnect(_on_switch_registered)
		if _room.switch_unregistered.is_connected(_on_switch_unregistered):
			_room.switch_unregistered.disconnect(_on_switch_unregistered)
	_room = null


func reset() -> void:
	_recompute()


func motion_runs() -> bool:
	if effect == Effect.RUNS:
		return is_powered
	if effect == Effect.STOPS:
		return not is_powered
	return true


func is_present() -> bool:
	if effect == Effect.APPEARS:
		return is_powered
	if effect == Effect.VANISHES:
		return not is_powered
	return true


func _bind_room() -> void:
	var node := get_parent()
	while node != null and not node is Room:
		node = node.get_parent()
	_room = node as Room
	if _room == null:
		push_warning("Power must be below a Room")
		return
	_room.switch_registered.connect(_on_switch_registered)
	_room.switch_unregistered.connect(_on_switch_unregistered)
	for watched_id in watches:
		for room_switch in _room.switches_with_id(watched_id):
			_track(room_switch)
	_recompute()


func _on_switch_registered(room_switch: SwitchProp) -> void:
	if watches.has(room_switch.switch_id):
		_track(room_switch)
		_recompute()


func _on_switch_unregistered(room_switch: SwitchProp) -> void:
	if not _states.has(room_switch):
		return
	_untrack(room_switch)
	_recompute()


func _track(room_switch: SwitchProp) -> void:
	if _states.has(room_switch):
		return
	_states[room_switch] = room_switch.is_on
	var callback := _on_switch_state_changed.bind(room_switch)
	if not room_switch.state_changed.is_connected(callback):
		room_switch.state_changed.connect(callback)


func _untrack(room_switch: SwitchProp) -> void:
	_states.erase(room_switch)
	if not is_instance_valid(room_switch):
		return
	var callback := _on_switch_state_changed.bind(room_switch)
	if room_switch.state_changed.is_connected(callback):
		room_switch.state_changed.disconnect(callback)


func _on_switch_state_changed(_switch_id: StringName, value: bool, room_switch: SwitchProp) -> void:
	if not _states.has(room_switch):
		return
	_states[room_switch] = value
	_recompute()


func _recompute() -> void:
	var next := starts_on_when_unwatched if watches.is_empty() else need == Need.ALL
	if not watches.is_empty():
		for watched_id in watches:
			var id_on := false
			for room_switch: SwitchProp in _states:
				if room_switch.switch_id == watched_id and bool(_states[room_switch]):
					id_on = true
					break
			if need == Need.ALL and not id_on:
				next = false
				break
			if need == Need.ANY and id_on:
				next = true
				break
	if next == is_powered:
		return
	is_powered = next
	powered_changed.emit(is_powered)
