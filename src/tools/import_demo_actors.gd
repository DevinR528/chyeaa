extends SceneTree
## One-time import of the prototype demo room's walkers and throwables into
## scenes/rooms/demo.tscn. Adds an `Actors` node and leaves the rest of the room,
## props included, as edited in Godot. Re-running replaces only `Actors`.
##
## Run from lil-guy/:
##   godot --headless --path . --script res://src/tools/import_demo_actors.gd

const SOURCE_JSON := "../assets/levels/demo.json"
const ROOM_SCENE_PATH := "res://scenes/rooms/demo.tscn"
const ACTORS_NODE := "Actors"
const TILE := MovementStats.TILE

## Prototype `EntityKind` numbers.
const WALKER_KIND := 2
const THROWABLE_KIND := 3

const WALKER_SCENE := preload("res://scenes/actors/walker.tscn")
const THROWABLE_SCENE := preload("res://scenes/actors/throwable.tscn")


func _initialize() -> void:
	quit(_import())


func _import() -> int:
	var doc := _read_room_json()
	if doc.is_empty():
		return 1
	var room := (load(ROOM_SCENE_PATH) as PackedScene).instantiate(PackedScene.GEN_EDIT_STATE_INSTANCE)
	var previous := room.get_node_or_null(ACTORS_NODE)
	if previous != null:
		room.remove_child(previous)
		previous.free()
	var actors := Node2D.new()
	actors.name = ACTORS_NODE
	room.add_child(actors)
	actors.owner = room

	var imported := 0
	for def: Dictionary in doc.get("entities", []):
		var actor := _make_actor(def)
		if actor == null:
			continue
		var size := Vector2(def.w, def.h)
		actor.size = size
		actor.position = Vector2(def.x, def.y) + size / 2.0
		actor.z_index = int(def.get("z", 0))
		actors.add_child(actor, true)
		actor.owner = room
		imported += 1

	var packed := PackedScene.new()
	var pack_error := packed.pack(room)
	room.free()
	if pack_error != OK:
		push_error("Could not pack the demo room: %s" % error_string(pack_error))
		return 1
	# A fresh PackedScene has no UID; keep the one the editor gave the room.
	var uid := ResourceLoader.get_resource_uid(ROOM_SCENE_PATH)
	var save_error := ResourceSaver.save(packed, ROOM_SCENE_PATH)
	if save_error != OK:
		push_error("Could not save %s: %s" % [ROOM_SCENE_PATH, error_string(save_error)])
		return 1
	if uid != ResourceUID.INVALID_ID:
		ResourceSaver.set_uid(ROOM_SCENE_PATH, uid)
	print("Imported %d actors into %s." % [imported, ROOM_SCENE_PATH])
	return 0


## Prototype tuning is in tile units; Godot exports are in pixels.
func _make_actor(def: Dictionary) -> RoomActor:
	match int(def.kind):
		WALKER_KIND:
			var walker := WALKER_SCENE.instantiate(PackedScene.GEN_EDIT_STATE_INSTANCE) as Walker
			walker.speed = float(def.get("speed", 5.0)) * TILE
			walker.start_facing = -1 if int(def.get("facing", 1)) < 0 else 1
			walker.turn_on_ledges = int(def.get("turn_on_ledge", 1)) == 1
			_set_body_tuning(walker, def)
			return walker
		THROWABLE_KIND:
			var ball := THROWABLE_SCENE.instantiate(PackedScene.GEN_EDIT_STATE_INSTANCE) as Throwable
			ball.throw_speed = float(def.get("throw_speed", 42.0)) * TILE
			ball.throw_up = float(def.get("throw_up", -6.0)) * TILE
			ball.slide_friction = float(def.get("slide_friction", 18.0)) * TILE
			ball.hazard_speed = float(def.get("hazard_speed", 14.0)) * TILE
			_set_body_tuning(ball, def)
			return ball
	return null


func _set_body_tuning(actor: RoomActor, def: Dictionary) -> void:
	actor.gravity = float(def.get("gravity", 350.0)) * TILE
	actor.stomp_bounce = float(def.get("stomp_vy", -40.0)) * TILE


func _read_room_json() -> Dictionary:
	var path := ProjectSettings.globalize_path("res://").path_join(SOURCE_JSON)
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary:
		push_error("Could not read a room document from %s" % path)
		return {}
	return parsed
