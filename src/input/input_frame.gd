class_name PlayerInputFrame
extends RefCounted

enum Aim {
	NONE,
	RIGHT,
	DOWN,
	LEFT,
	UP,
}

var move := Vector2.ZERO
var aim := Aim.NONE

var jump_held := false
var jump_pressed := false
var action_held := false
var action_pressed := false
var dash_held := false
var dash_pressed := false
var interact_held := false
var interact_pressed := false
var interact_released := false


func duplicate_data() -> PlayerInputFrame:
	var copy := PlayerInputFrame.new()
	copy.move = move
	copy.aim = aim
	copy.jump_held = jump_held
	copy.jump_pressed = jump_pressed
	copy.action_held = action_held
	copy.action_pressed = action_pressed
	copy.dash_held = dash_held
	copy.dash_pressed = dash_pressed
	copy.interact_held = interact_held
	copy.interact_pressed = interact_pressed
	copy.interact_released = interact_released
	return copy
