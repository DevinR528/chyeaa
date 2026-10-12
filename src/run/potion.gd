class_name Potion
extends RefCounted
## A live potion in the belt. Checkpoint is one; the belt only talks to this.

enum Action {
	INSTANT,
	REWIND,
}

const CONTINUE_CHANCE := 0.28
const MAX_USES := 5

var action := Action.INSTANT
var uses := 1


static func roll_uses(rng: Callable = Callable()) -> int:
	var count := 1
	while count < MAX_USES:
		var roll: float = rng.call() if rng.is_valid() else randf()
		if roll >= CONTINUE_CHANCE:
			break
		count += 1
	return count


func _init(rng: Callable = Callable()) -> void:
	uses = roll_uses(rng)


func can_use(_player: PlayerBody) -> bool:
	return uses > 0


## Instant potions spend a charge and return the room change. Rewind does not.
func use(_feet: Vector2, _room: Room) -> PotionUse:
	return null


## Drop whatever this potion left in the room. Charges stay as they are.
func clear(_room: Room) -> void:
	pass


func on_room_exit(room: Room) -> void:
	clear(room)
