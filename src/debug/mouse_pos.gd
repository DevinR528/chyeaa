extends Node2D

@export var _debug: bool = true;
@onready var _label: Label = $Label


# Called when the node enters the scene tree for the first time.
func _set_pos_label() -> void:
	var mouse_pos = get_global_mouse_position() * 1.02
	_label.text = str(mouse_pos)
	_label.global_position = mouse_pos


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(_delta: float) -> void:
	if _debug: _set_pos_label()
	
