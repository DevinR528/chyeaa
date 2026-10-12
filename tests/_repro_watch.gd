extends Node

var body: PlayerBody
var ticks := 0


func _physics_process(_delta: float) -> void:
	if body == null:
		return
	ticks += 1
	var interpolated := body.get_global_transform_interpolated().origin
	print(
		"tick ", ticks,
		" phys ", body.global_position,
		" interp ", interpolated,
		" vel ", body.velocity,
		" real ", body.get_real_velocity(),
	)
