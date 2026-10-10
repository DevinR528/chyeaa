class_name Carrier
extends Node
## Picks up and throws throwables for every character. Hold interact near one to
## pick it up and keep carrying; release interact to throw toward the aim. Chords
## with jump: hold interact, jump, release mid-air.

## Pickup reach beyond the body on every side.
const PICKUP_REACH := 6.0
## Airborne faster than this, an unaimed throw goes the way the player travels.
const AIR_THROW_SPEED := 40.0

var held: Throwable
## Last aim while carrying, so letting go of the stick a tick early still aims.
var sticky_aim := PlayerInputFrame.Aim.NONE

@onready var player: PlayerBody = get_parent()


## Runs after the player moves, so a held ball sits in this tick's hands.
func update(input_frame: PlayerInputFrame) -> void:
	if held != null:
		_remember_aim(input_frame)
		if input_frame.interact_released:
			var aim := _resolve_aim(input_frame)
			sticky_aim = PlayerInputFrame.Aim.NONE
			held.throw_from(player.body_rect(), Throwable.throw_direction(aim, player.facing))
		else:
			held.hold_at(player.body_rect(), player.facing)
		return
	if input_frame.interact_held:
		_try_pick_up(input_frame)


## Drops anything held where it is.
func reset() -> void:
	if held != null:
		held.drop()
	held = null
	sticky_aim = PlayerInputFrame.Aim.NONE


func _try_pick_up(input_frame: PlayerInputFrame) -> void:
	var reach := player.body_rect().grow(PICKUP_REACH)
	for node in get_tree().get_nodes_in_group(Throwable.CARRYABLE_GROUP):
		var ball := node as Throwable
		if player.room != null and not player.room.is_ancestor_of(ball):
			continue
		if not ball.can_pick_up() or not reach.intersects(ball.body_rect()):
			continue
		if ball.pick_up(self):
			held = ball
			ball.released.connect(_on_held_released, CONNECT_ONE_SHOT)
			sticky_aim = _facing_aim()
			_remember_aim(input_frame)
			ball.hold_at(player.body_rect(), player.facing)
			return


func _on_held_released() -> void:
	held = null


## Live aim, then live movement, then air travel, then the sticky aim, then facing.
## The sticky aim must not beat the direction the player is actually moving.
func _resolve_aim(input_frame: PlayerInputFrame) -> PlayerInputFrame.Aim:
	var moved := _aim_from_move(input_frame)
	if moved != PlayerInputFrame.Aim.NONE:
		return moved
	if not player.is_on_floor() and absf(player.velocity.x) > AIR_THROW_SPEED:
		return PlayerInputFrame.Aim.RIGHT if player.velocity.x > 0.0 else PlayerInputFrame.Aim.LEFT
	if sticky_aim != PlayerInputFrame.Aim.NONE:
		return sticky_aim
	return _facing_aim()


func _remember_aim(input_frame: PlayerInputFrame) -> void:
	var moved := _aim_from_move(input_frame)
	if moved != PlayerInputFrame.Aim.NONE:
		sticky_aim = moved


func _aim_from_move(input_frame: PlayerInputFrame) -> PlayerInputFrame.Aim:
	if input_frame.aim != PlayerInputFrame.Aim.NONE:
		return input_frame.aim
	if not is_zero_approx(input_frame.move.x):
		return PlayerInputFrame.Aim.RIGHT if input_frame.move.x > 0.0 else PlayerInputFrame.Aim.LEFT
	if not is_zero_approx(input_frame.move.y):
		return PlayerInputFrame.Aim.DOWN if input_frame.move.y > 0.0 else PlayerInputFrame.Aim.UP
	return PlayerInputFrame.Aim.NONE


func _facing_aim() -> PlayerInputFrame.Aim:
	return PlayerInputFrame.Aim.LEFT if player.facing < 0.0 else PlayerInputFrame.Aim.RIGHT
