class_name RoomFx
extends Node2D
## Death shatter or exit confetti. The effect ends on its duration, which is the
## delay before a respawn or the reward menu, so a random particle life cannot
## move that moment earlier or later.

enum Kind { NONE, DEATH, EXIT }

const TILE := MovementStats.TILE
const DEATH_DURATION := 0.85
const EXIT_DURATION := 1.1
const EXIT_BODY_FADE := 0.12

class Particle extends RefCounted:
	var position := Vector2.ZERO
	var velocity := Vector2.ZERO
	var life := 0.0
	var age := 0.0
	var size := 2.0
	var color := Color.WHITE
	var spin := 0.0

var kind := Kind.NONE
var age := 0.0
var duration := 0.0

var _particles: Array[Particle] = []


func is_playing() -> bool:
	return kind != Kind.NONE


## 1 while the body should show, fading out at the start of an exit.
func player_alpha() -> float:
	if kind == Kind.EXIT and age < EXIT_BODY_FADE:
		return 1.0 - age / EXIT_BODY_FADE
	if is_playing():
		return 0.0
	return 1.0


func clear() -> void:
	kind = Kind.NONE
	age = 0.0
	duration = 0.0
	_particles.clear()
	queue_redraw()


func start_death(player: PlayerBody) -> void:
	_begin(Kind.DEATH, DEATH_DURATION)
	_spawn_death(player)


func start_exit(player: PlayerBody) -> void:
	_begin(Kind.EXIT, EXIT_DURATION)
	_spawn_exit(player)


## True once `duration` has elapsed.
func update(dt: float) -> bool:
	if not is_playing():
		return true
	age += dt
	var gravity := _DEATH_GRAVITY if kind == Kind.DEATH else _EXIT_GRAVITY
	var alive: Array[Particle] = []
	for particle in _particles:
		particle.age += dt
		particle.velocity.y += gravity * dt
		particle.position += particle.velocity * dt
		if kind == Kind.EXIT:
			particle.velocity.x *= 1.0 - 1.2 * dt
		if particle.age < particle.life:
			alive.append(particle)
	_particles = alive
	queue_redraw()
	return age >= duration


func _begin(next: Kind, seconds: float) -> void:
	kind = next
	age = 0.0
	duration = seconds
	_particles.clear()
	queue_redraw()


#region Placeholder visuals
# Pixel shatter and confetti stand in for authored death and clear effects.

const _DEATH_GRAVITY := 112.5 * TILE
const _EXIT_GRAVITY := 52.5 * TILE
const _CONFETTI: Array[Color] = [
	Color("#f0c040"),
	Color("#3ecf6e"),
	Color("#60a5fa"),
	Color("#f472b6"),
	Color("#e9d5ff"),
	Color("#fb923c"),
	Color("#e8f0ff"),
]
const _EYE_COLOR := Color("#1a2230")


func _spawn_death(player: PlayerBody) -> void:
	var rect := player.body_rect()
	var color := _body_color(player)
	var px := maxf(2.0, TILE / 4.0)
	var row := 0.0
	while row < rect.size.y:
		var col := 0.0
		while col < rect.size.x:
			var particle := Particle.new()
			particle.position = rect.position + Vector2(col + px * 0.5, row + px * 0.5)
			particle.velocity = Vector2(
				randf_range(-17.5 * TILE, 17.5 * TILE) + (col - rect.size.x * 0.5) * TILE,
				randf_range(-10.0 * TILE, 10.0 * TILE) + (row / rect.size.y) * 15.0 * TILE,
			)
			particle.life = randf_range(0.45, DEATH_DURATION)
			particle.size = px
			particle.color = color
			_particles.append(particle)
			col += px
		row += px
	var eye_inset := 0.75 * TILE
	var eye := Particle.new()
	eye.position = Vector2(
		rect.end.x - eye_inset if player.facing >= 0.0 else rect.position.x + eye_inset,
		rect.position.y + 1.25 * TILE,
	)
	eye.velocity = Vector2(randf_range(-10.0 * TILE, 10.0 * TILE), randf_range(-5.0 * TILE, 7.5 * TILE))
	eye.life = DEATH_DURATION * 0.9
	eye.size = maxf(2.0, TILE / 4.0)
	eye.color = _EYE_COLOR
	_particles.append(eye)


func _spawn_exit(player: PlayerBody) -> void:
	var rect := player.body_rect()
	var center := rect.get_center()
	for index in 48:
		var angle := randf_range(0.0, TAU)
		var speed := randf_range(10.0 * TILE, 32.5 * TILE)
		var particle := Particle.new()
		particle.position = center + Vector2(
			randf_range(-0.5 * TILE, 0.5 * TILE),
			randf_range(-0.75 * TILE, 0.75 * TILE),
		)
		particle.velocity = Vector2(
			cos(angle) * speed,
			sin(angle) * speed - randf_range(5.0 * TILE, 15.0 * TILE),
		)
		particle.life = randf_range(0.55, EXIT_DURATION)
		particle.size = maxf(3.0, TILE / 3.0) if randf() < 0.35 else maxf(2.0, TILE / 4.0)
		particle.color = _CONFETTI[index % _CONFETTI.size()]
		particle.spin = randf_range(-8.0, 8.0)
		_particles.append(particle)


func _draw() -> void:
	for particle in _particles:
		var fade := 1.0 - particle.age / particle.life
		var color := particle.color
		color.a = clampf(fade, 0.0, 1.0)
		var size := particle.size
		var at := to_local(particle.position)
		if kind == Kind.EXIT and particle.spin != 0.0:
			draw_set_transform(at, particle.age * particle.spin, Vector2.ONE)
			draw_rect(Rect2(-size * 0.5, -size * 0.5, size, size), color)
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		else:
			draw_rect(Rect2(Vector2(round(at.x), round(at.y)), Vector2(size, size)), color)


func _body_color(player: PlayerBody) -> Color:
	var poly := player.get_node_or_null(^"PlaceholderBody") as Polygon2D
	if poly != null:
		return poly.color
	return Color("#e8f0ff")

#endregion
