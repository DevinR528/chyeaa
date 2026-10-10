class_name PlayerInput
extends Node

const EDGE_ACTIONS: Array[StringName] = [
	&"jump",
	&"action",
	&"dash",
	&"interact",
]

var _latched_pressed: Dictionary[StringName, bool] = {}
var _interact_released := false


func _input(event: InputEvent) -> void:
	for action in EDGE_ACTIONS:
		if event.is_action_pressed(action):
			_latched_pressed[action] = true

	if event.is_action_released(&"interact"):
		_interact_released = true


func consume() -> PlayerInputFrame:
	var frame := PlayerInputFrame.new()
	frame.move = Vector2(
		Input.get_axis(&"move_left", &"move_right"),
		Input.get_axis(&"move_up", &"move_down"),
	)
	frame.aim = aim_quadrant(frame.move)

	frame.jump_held = Input.is_action_pressed(&"jump")
	frame.jump_pressed = _consume_pressed(&"jump")
	frame.action_held = Input.is_action_pressed(&"action")
	frame.action_pressed = _consume_pressed(&"action")
	frame.dash_held = Input.is_action_pressed(&"dash")
	frame.dash_pressed = _consume_pressed(&"dash")
	frame.interact_held = Input.is_action_pressed(&"interact")
	frame.interact_pressed = _consume_pressed(&"interact")
	frame.interact_released = _interact_released
	_interact_released = false

	return frame


func clear_edges() -> void:
	_latched_pressed.clear()
	_interact_released = false


static func aim_quadrant(intent: Vector2, deadzone := 0.2, vertical_bias := 1.0) -> PlayerInputFrame.Aim:
	if intent.length() < deadzone:
		return PlayerInputFrame.Aim.NONE
	if absf(intent.y) * vertical_bias >= absf(intent.x):
		return PlayerInputFrame.Aim.DOWN if intent.y > 0.0 else PlayerInputFrame.Aim.UP
	return PlayerInputFrame.Aim.RIGHT if intent.x > 0.0 else PlayerInputFrame.Aim.LEFT


func _consume_pressed(action: StringName) -> bool:
	var pressed : bool = _latched_pressed.get(action, false) or Input.is_action_just_pressed(action)
	_latched_pressed.erase(action)
	return pressed
