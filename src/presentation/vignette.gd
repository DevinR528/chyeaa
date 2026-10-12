class_name Vignette
extends CanvasLayer
## Screen-space veil centered on the player's body after camera shake.

const TILE := MovementStats.TILE

@export var runner: RoomRunner
@export var camera: FollowCamera
@export var inner_tiles := 11.0
@export var outer_tiles := 26.0
@export_range(0.0, 1.0, 0.01) var darkness := 0.45

@onready var veil: ColorRect = $Veil


func _process(_delta: float) -> void:
	if runner == null or runner.player == null or camera == null:
		visible = false
		return
	visible = darkness > 0.0
	#print("center body: {body}\n c_transform: {tr}".format({
		#"body": runner.player.body_rect().get_center(),
		#"tr": get_viewport().get_canvas_transform(),
	#}))
	var values := screen_values(
		runner.player.body_rect().get_center(),
		get_viewport().get_canvas_transform(),
		camera.zoom,
		inner_tiles * TILE,
		outer_tiles * TILE,
		darkness,
	)
	var material := veil.material as ShaderMaterial
	material.set_shader_parameter(&"center_px", values.center)
	material.set_shader_parameter(&"inner_px", values.inner)
	material.set_shader_parameter(&"outer_px", values.outer)
	material.set_shader_parameter(&"darkness", values.darkness)


static func screen_values(
	world_center: Vector2,
	canvas_transform: Transform2D,
	camera_zoom: Vector2,
	inner_world: float,
	outer_world: float,
	alpha: float,
) -> Dictionary:
	var scale := minf(absf(camera_zoom.x), absf(camera_zoom.y))
	var inner := maxf(0.0, inner_world * scale)
	return {
		"center": canvas_transform * world_center,
		"inner": inner,
		"outer": maxf(inner + 1.0, outer_world * scale),
		"darkness": clampf(alpha, 0.0, 1.0),
	}
