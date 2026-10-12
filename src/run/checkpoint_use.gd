class_name CheckpointUse
extends RefCounted
## One checkpoint plant. `undo` and `redo` put the room's respawn and flag back.
## Neither refunds the charge that was spent to plant it.

var _undo: Callable
var _redo: Callable


func bind(undo_plant: Callable, redo_plant: Callable) -> void:
	_undo = undo_plant
	_redo = redo_plant


func undo() -> void:
	_undo.call()


func redo() -> void:
	_redo.call()
