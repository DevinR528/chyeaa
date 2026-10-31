class_name MovementStats
extends Resource

const TILE := 8.0

@export_group("Horizontal")
@export var max_run := 50.0 * TILE
@export var ground_accel := 275.0 * TILE
@export var air_accel := 1125.0 * TILE
@export var ground_friction := 350.0 * TILE
@export var air_friction := 100.0 * TILE

@export_group("Vertical")
@export var gravity := 350.0 * TILE
@export var fall_gravity := 475.0 * TILE
@export var hold_fall_gravity := 220.0 * TILE
@export var hold_max_fall := 80.0 * TILE
@export var max_fall := 150.0 * TILE
@export var jump_velocity := -85.0 * TILE
@export_range(0.0, 1.0, 0.01) var jump_cut := 0.45
@export_range(0.0, 0.3, 0.005) var coyote_time := 0.09
@export_range(0.0, 0.3, 0.005) var jump_buffer_time := 0.1
@export_range(0, 3, 1) var air_jumps := 0

@export_group("Dash")
@export var dash_speed := 98.0 * TILE
@export_range(0.0, 0.5, 0.005) var dash_duration := 0.12
@export_range(0.0, 5.0, 0.05) var dash_cooldown := 2.0
## Dashes available before a refresh. Landing and the cooldown both refill this.
@export_range(1, 3, 1) var dash_charges := 1
@export_range(0.0, 1.0, 0.01) var dash_air_momentum := 0.0

@export_group("Contacts")
@export_range(0.0, 3.0, 0.05) var stomp_bounce_multiplier := 1.25
@export_range(0.0, 0.3, 0.005) var stomp_coyote_time := 0.05


func copy() -> MovementStats:
	return duplicate(true) as MovementStats
