class_name ReachOverlay
extends Node2D
## Debug guides for how far the current character can jump, dash, grapple, and
## pogo, read from its live stats and ability exports. Hidden until `toggle_debug`.
## Run its physics after the player's, so it follows the moved body and
## interpolates with it.

const TILE := MovementStats.TILE
const WALL_PROBE_MAX := 320.0
const WALL_PROBE_WIDTH := 2.0
## cast_motion ignores colliders the probe touches at its start, so the probe
## starts this far behind the leading edge to still see a flush wall.
const WALL_PROBE_BACKOFF := 2.0
const LABEL_FONT_SIZE := 8

const JUMP_HIGH_COLOR := Color("#4ade80", 0.9)
const JUMP_LOW_COLOR := Color("#86efac", 0.75)
const DASH_COLOR := Color("#38bdf8", 0.85)
const GRAPPLE_COLOR := Color("#fb923c", 0.7)
const POGO_BOUNCE_COLOR := Color("#c084fc", 0.95)
const POGO_SIDE_POP_COLOR := Color("#d8b4fe", 0.8)
const POGO_SLASH_COLOR := Color("#a78bfa", 0.45)
const WALL_COLOR := Color("#7dd3fc", 0.9)

## Supplies the player and snaps the overlay on respawn. Tests can set `player` instead.
@export var runner: RoomRunner

@export_group("Layers")
@export var show_jump := true
@export var show_dash := true
@export var show_grapple := true
@export var show_pogo_bounce := true
@export var show_pogo_side_pop := true
@export var show_pogo_slash := true
## Facing wall distance, cast through physics from the leading edge.
@export var show_wall_probe := false

var player: PlayerBody
var _wall_distance := -1.0


## Peak rise in px, stepped the way `PlayerBody` integrates: gravity is added before
## each move, and a jump cut lands on the second tick (the earliest release).
## Analytic v²/2g overstates a held Standard jump by about 0.7 tiles.
static func jump_rise(launch_velocity: float, gravity: float, cut := 1.0) -> float:
	var delta := 1.0 / Engine.physics_ticks_per_second
	var velocity := launch_velocity + gravity * delta
	var rise := 0.0
	var tick := 0
	while velocity < 0.0:
		rise -= velocity * delta
		tick += 1
		if tick == 1:
			velocity *= cut
		velocity += gravity * delta
	return rise


## Dash-phase travel in px. The dash moves on every tick until its timer reaches
## zero, so a 0.12s dash at 60 ticks lasts 8 ticks, not 7.2. Carry after the dash
## is not included.
static func dash_distance(stats: MovementStats) -> float:
	var ticks_per_second := float(Engine.physics_ticks_per_second)
	var ticks := ceilf(stats.dash_duration * ticks_per_second - 0.0001)
	return absf(stats.dash_speed) * ticks / ticks_per_second


## Gap in px between the body's leading edge and the first world collider, up to `max_distance`.
static func wall_distance(target: PlayerBody, direction: float, max_distance := WALL_PROBE_MAX) -> float:
	var rect := target.body_rect()
	var probe := RectangleShape2D.new()
	probe.size = Vector2(WALL_PROBE_WIDTH, rect.size.y * 0.6)
	var lead_x := rect.end.x if direction > 0.0 else rect.position.x
	var start_x := lead_x - direction * (WALL_PROBE_BACKOFF + WALL_PROBE_WIDTH / 2.0)
	var travel := max_distance + WALL_PROBE_BACKOFF
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = probe
	query.transform = Transform2D(0.0, Vector2(start_x, rect.get_center().y))
	query.motion = Vector2(direction * travel, 0.0)
	query.collision_mask = PhysicsLayers.WORLD
	query.exclude = [target.get_rid()]
	var fractions := target.get_world_2d().direct_space_state.cast_motion(query)
	return maxf(0.0, fractions[0] * travel - WALL_PROBE_BACKOFF)


func _ready() -> void:
	visible = false
	z_index = 100
	if runner == null:
		return
	runner.character_changed.connect(func(_index: int) -> void: follow(runner.player))
	runner.restarted.connect(func(_reason: RoomRunner.RestartReason) -> void: _snap())
	if runner.player != null:
		follow(runner.player)


func follow(target: PlayerBody) -> void:
	player = target
	_snap()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"toggle_debug"):
		visible = not visible
		get_viewport().set_input_as_handled()


func _physics_process(_delta: float) -> void:
	if not is_instance_valid(player):
		return
	global_position = player.global_position
	if not visible:
		return
	_wall_distance = wall_distance(player, player.facing) if show_wall_probe else -1.0
	queue_redraw()


func _snap() -> void:
	if not is_instance_valid(player):
		return
	global_position = player.global_position
	reset_physics_interpolation()


func _draw() -> void:
	if not is_instance_valid(player):
		return
	var stats := player.stats
	var rect := player.body_rect()
	rect.position -= global_position
	var face := player.facing
	var feet_y := rect.end.y
	var mid := rect.get_center()
	var lead_x := rect.end.x if face > 0.0 else rect.position.x

	if show_jump:
		var high := jump_rise(stats.jump_velocity, stats.gravity)
		var low := jump_rise(stats.jump_velocity, stats.gravity, stats.jump_cut)
		_draw_height_mark(Vector2(mid.x, feet_y - high), 18.0, JUMP_HIGH_COLOR, "jump hi %.1ft" % (high / TILE))
		_draw_height_mark(Vector2(mid.x, feet_y - low), 12.0, JUMP_LOW_COLOR, "lo %.1ft" % (low / TILE))

	if show_dash:
		var dash := dash_distance(stats)
		_draw_span(lead_x, lead_x + face * dash, mid.y, DASH_COLOR, "dash %.1ft" % (dash / TILE))

	var grapple := player.ability as Grapple
	if show_grapple and grapple != null:
		# Reach is measured from the chest, not the leading edge.
		var chest := grapple.chest() - global_position
		var reach_end := chest.x + face * grapple.reach()
		_draw_span(chest.x, reach_end, chest.y, GRAPPLE_COLOR, "grapple %.1ft" % grapple.reach_tiles)

	var pogo := player.ability as PogoStrike
	if pogo != null:
		if show_pogo_bounce:
			var bounce_y := feet_y - pogo.bounce_tiles * TILE
			_draw_height_mark(Vector2(mid.x, bounce_y), 22.0, POGO_BOUNCE_COLOR, "bounce %.1ft" % pogo.bounce_tiles)
		if show_pogo_side_pop:
			var edge_x := rect.end.x + 6.0 if face > 0.0 else rect.position.x - 6.0
			var pop_y := feet_y - pogo.side_pop_tiles * TILE
			_draw_height_mark(Vector2(edge_x, pop_y), 6.0, POGO_SIDE_POP_COLOR, "side pop %.1ft" % pogo.side_pop_tiles)
		if show_pogo_slash:
			for direction: PogoStrike.StrikeDirection in PogoStrike.StrikeDirection.values():
				var disk := pogo.slash_toward(direction)
				_draw_dashed_half_disk(HalfDisk.new(disk.center - global_position, disk.radius, disk.facing))

	if show_wall_probe and _wall_distance >= 0.0:
		var probe_y := rect.position.y + rect.size.y * 0.85
		var wall_x := lead_x + face * _wall_distance
		draw_line(Vector2(lead_x, probe_y), Vector2(wall_x, probe_y), WALL_COLOR, 1.25)
		draw_line(Vector2(wall_x, probe_y - 4.0), Vector2(wall_x, probe_y + 4.0), WALL_COLOR, 1.5)
		var label_at := Vector2(wall_x + face * 3.0, probe_y - 2.0)
		_draw_label(label_at, "wall %.1ft" % (_wall_distance / TILE), WALL_COLOR, face < 0.0)


## A horizontal tick of half width `half` at a height, with end caps.
func _draw_height_mark(center: Vector2, half: float, color: Color, label: String) -> void:
	draw_line(center + Vector2(-half, 0.0), center + Vector2(half, 0.0), color, 1.5)
	draw_line(center + Vector2(-half, -2.0), center + Vector2(-half, 2.0), color, 1.0)
	draw_line(center + Vector2(half, -2.0), center + Vector2(half, 2.0), color, 1.0)
	_draw_label(center + Vector2(half + 3.0, 0.0), label, color)


## A horizontal distance between two x positions, with end caps.
func _draw_span(from_x: float, to_x: float, y: float, color: Color, label: String) -> void:
	var low := minf(from_x, to_x)
	var high := maxf(from_x, to_x)
	draw_line(Vector2(low, y), Vector2(high, y), color, 1.25)
	draw_line(Vector2(low, y - 3.0), Vector2(low, y + 3.0), color, 1.25)
	draw_line(Vector2(high, y - 3.0), Vector2(high, y + 3.0), color, 1.25)
	_draw_label(Vector2((low + high) / 2.0, y - 5.0), label, color)


func _draw_dashed_half_disk(disk: HalfDisk) -> void:
	var arc := disk.arc_points(24)
	for index in range(0, arc.size() - 1, 2):
		draw_line(arc[index], arc[index + 1], POGO_SLASH_COLOR, 1.0)
	draw_dashed_line(arc[arc.size() - 1], arc[0], POGO_SLASH_COLOR, 1.0, 3.0)


## `at` is the text baseline start, or its end when `align_right`.
func _draw_label(at: Vector2, text: String, color: Color, align_right := false) -> void:
	var font := ThemeDB.fallback_font
	if align_right:
		at.x -= font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, LABEL_FONT_SIZE).x
	draw_string(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, LABEL_FONT_SIZE, color)
