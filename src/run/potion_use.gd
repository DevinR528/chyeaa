class_name PotionUse
extends RefCounted
## One drink. `undo` and `redo` put the room back and forward.
## Neither refunds the charge that was spent.

var _undo: Callable
var _redo: Callable


func bind(undo_effect: Callable, redo_effect: Callable) -> void:
	_undo = undo_effect
	_redo = redo_effect


func undo() -> void:
	_undo.call()


func redo() -> void:
	_redo.call()
