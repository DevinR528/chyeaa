class_name RewindPotion
extends Potion
## Opens the scrub screen. The charge is spent on commit, never logged, and
## never refunded. Debug history does not spend it.


func _init(rng: Callable = Callable()) -> void:
	super(rng)
	action = Action.REWIND


func can_use(_player: PlayerBody) -> bool:
	return uses > 0


func use(_feet: Vector2, _room: Room) -> PotionUse:
	return null


func spend() -> bool:
	if uses <= 0:
		return false
	uses -= 1
	return true
