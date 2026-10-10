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
