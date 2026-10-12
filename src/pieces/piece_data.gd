class_name PieceData
extends Resource
## Imported metadata beside one generated piece scene.

enum Facing {
	LEFT,
	RIGHT,
	UP,
	DOWN,
}

@export var piece_id := &""
## Importer version plus source JSON hash; unchanged pieces are not rewritten.
@export var source_hash := ""
@export var cols := 0
@export var rows := 0
@export_range(1, 10, 1) var difficulty := 1
@export var tags: Array[StringName] = []
@export var unique := false
@export var entry_a := Vector2i.ZERO
@export var entry_b := Vector2i.ZERO
@export var entry_facing := Facing.LEFT
@export var exit_a := Vector2i.ZERO
@export var exit_b := Vector2i.ZERO
@export var exit_facing := Facing.RIGHT
## Player feet in local piece pixels.
@export var spawn_feet := Vector2.ZERO
@export var scene: PackedScene


func has_tag(tag: StringName) -> bool:
	return tags.has(tag)


func entry() -> Dictionary:
	return {"a": entry_a, "b": entry_b, "facing": entry_facing}


func exit() -> Dictionary:
	return {"a": exit_a, "b": exit_b, "facing": exit_facing}
