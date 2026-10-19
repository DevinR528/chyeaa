extends SceneTree
## One-time import of the prototype demo room's props into scenes/rooms/demo.tscn.
## Adds a `Props` node and leaves the rest of the room as edited in Godot.
## Re-running replaces only `Props`, which overwrites Godot edits to props.
## Walkers and throwables are skipped; import_demo_actors.gd brings them in.
##
## Run from the repo root:
##   godot --headless --path . --script res://src/tools/import_demo_entities.gd

const SOURCE_JSON := "../idea/assets/levels/demo.json"
const ROOM_SCENE_PATH := "res://scenes/rooms/demo.tscn"
const PROPS_NODE := "Props"
const TILE := MovementStats.TILE

## Prototype `EntityKind` numbers.
enum PrototypeKind {
	MOVING_PLATFORM = 0,
	BREAKABLE = 1,
	WALKER = 2,
	THROWABLE = 3,
	SWITCH = 4,
	GATE = 5,
	FALL_BLOCK = 6,
	WINDMILL = 7,
	BLOCK = 8,
	TRACK = 9,
}

const PREFABS := {
	PrototypeKind.MOVING_PLATFORM: preload("res://scenes/props/moving_platform.tscn"),
	PrototypeKind.BREAKABLE: preload("res://scenes/props/breakable.tscn"),
	PrototypeKind.SWITCH: preload("res://scenes/props/switch.tscn"),
	PrototypeKind.GATE: preload("res://scenes/props/gate.tscn"),
	PrototypeKind.FALL_BLOCK: preload("res://scenes/props/fall_block.tscn"),
	PrototypeKind.WINDMILL: preload("res://scenes/props/windmill.tscn"),
	PrototypeKind.BLOCK: preload("res://scenes/props/block.tscn"),
	# Track is the prototype editor's name for a moving platform carrying a child.
	PrototypeKind.TRACK: preload("res://scenes/props/moving_platform.tscn"),
}

## Prototype `solid` field: 1 forces solid, 0 forces pass-through, anything else is the kind default.
const SOLID_FORCED := 1
const SOLID_NEVER := 0


func _initialize() -> void:
	quit(_import())


func _import() -> int:
	var doc := _read_room_json()
	if doc.is_empty():
		return 1
	var room := (load(ROOM_SCENE_PATH) as PackedScene).instantiate(PackedScene.GEN_EDIT_STATE_INSTANCE)
	var previous := room.get_node_or_null(PROPS_NODE)
	if previous != null:
		room.remove_child(previous)
		previous.free()
	var props := Node2D.new()
	props.name = PROPS_NODE
	room.add_child(props)
	props.owner = room

	var skipped := {}
	var imported := 0
	for def: Dictionary in doc.get("entities", []):
		imported += _add_entity(def, props, room, true, skipped)

	var packed := PackedScene.new()
	var pack_error := packed.pack(room)
	room.free()
	if pack_error != OK:
		push_error("Could not pack the demo room: %s" % error_string(pack_error))
		return 1
	var save_error := ResourceSaver.save(packed, ROOM_SCENE_PATH)
	if save_error != OK:
		push_error("Could not save %s: %s" % [ROOM_SCENE_PATH, error_string(save_error)])
		return 1

	var skipped_names: Array[String] = []
	for kind: int in skipped:
		skipped_names.append("%s x%d" % [PrototypeKind.find_key(kind), skipped[kind]])
	print("Imported %d props into %s. Skipped: %s." % [imported, ROOM_SCENE_PATH, ", ".join(skipped_names) if not skipped_names.is_empty() else "none"])
	return 0


## Returns how many props were added, counting carried ones.
func _add_entity(def: Dictionary, parent: Node, room: Node, is_root: bool, skipped: Dictionary) -> int:
	var kind := int(def.kind)
	if not PREFABS.has(kind):
		skipped[kind] = skipped.get(kind, 0) + 1
		return 0
	var entity := (PREFABS[kind] as PackedScene).instantiate(PackedScene.GEN_EDIT_STATE_INSTANCE)
	var size := Vector2(def.w, def.h)
	if entity is SwitchProp:
		var room_switch := entity as SwitchProp
		room_switch.name = _prop_name(kind, Room.Kind.EMPTY)
		room_switch.size = size
		room_switch.switch_id = StringName(def.get("id", "sw"))
		room_switch.mode = int(def.get("mode", 0)) as SwitchProp.Mode
		room_switch.starts_on = int(def.get("starts_on", 0)) == 1
		room_switch.z_index = int(def.get("z", 0))
		room_switch.position = Vector2(def.x, def.y) + size / 2.0
		parent.add_child(room_switch, true)
		room_switch.owner = room
		return 1

	var prop := entity as TileProp
	var surface := int(def.get("surface", Room.Kind.SOLID))
	prop.name = _prop_name(kind, surface)
	prop.size = size
	prop.surface = surface as Room.Kind
	prop.solidity = _solidity(def)
	prop.z_index = int(def.get("z", 0))
	# Roots store a world top-left; carried props store an offset between centres.
	prop.position = Vector2(def.x, def.y) + size / 2.0 if is_root else Vector2(def.x, def.y)
	parent.add_child(prop, true)
	prop.owner = room
	# Godot only saves changes to an instance's own children when they are editable,
	# and the prefab's components need per-prop values.
	room.set_editable_instance(prop, true)

	_add_oscillation(prop, def, room)
	_add_path(prop, def, room)
	_add_spin(prop, def, room)
	_add_breakable(prop, def, kind, room)
	_add_falling(prop, def, kind, room)
	_add_power(prop, def, room)

	var added := 1
	for child_def: Dictionary in def.get("children", []):
		added += _add_entity(child_def, prop, room, false, skipped)
	return added


func _add_oscillation(prop: TileProp, def: Dictionary, room: Node) -> void:
	if not (def.has("travel") and def.has("speed")):
		return
	if prop.oscillation == null:
		prop.oscillation = _add_component(prop, OscillatingMotion.new(), "OscillatingMotion", room)
	prop.oscillation.travel = float(def.travel)
	prop.oscillation.speed = float(def.speed)
	prop.oscillation.axis = int(def.get("axis", 0)) as OscillatingMotion.Axis
	prop.oscillation.phase = float(def.get("phase", 0.0))


## Path points are tile coordinates in the prototype; the prop's centre walks the tile centres.
func _add_path(prop: TileProp, def: Dictionary, room: Node) -> void:
	var points: Array = def.get("path", [])
	if points.size() < 2:
		return
	var curve := Curve2D.new()
	for point: Array in points:
		curve.add_point(Vector2(point[0], point[1]) * TILE + Vector2.ONE * TILE / 2.0)
	var path := PathMotion.new()
	path.curve = curve
	path.top_level = true
	path.speed = float(def.get("path_speed", 4.0)) * TILE
	path.mode = int(def.get("path_mode", 0)) as PathMotion.Mode
	prop.path = _add_component(prop, path, "PathMotion", room)
	prop.position = curve.get_point_position(0)


func _add_spin(prop: TileProp, def: Dictionary, room: Node) -> void:
	var radius_tiles := float(def.get("spin_radius", 0.0))
	if radius_tiles <= 0.0:
		return
	if prop.spin == null:
		prop.spin = _add_component(prop, SpinMotion.new(), "SpinMotion", room)
	prop.spin.radius = radius_tiles * TILE
	prop.spin.turns_per_second = float(def.get("spin_speed", 0.25))
	prop.spin.start_turn = float(def.get("spin_phase", 0.0))


func _add_breakable(prop: TileProp, def: Dictionary, kind: int, room: Node) -> void:
	if kind != PrototypeKind.BREAKABLE and int(def.get("fragile", 0)) != 1:
		return
	if prop.breakable == null:
		prop.breakable = _add_component(prop, Breakable.new(), "Breakable", room)
	prop.breakable.respawn = float(def.get("respawn", 2.5))
	prop.breakable.delay = float(def.get("delay", 0.4))


func _add_falling(prop: TileProp, def: Dictionary, kind: int, room: Node) -> void:
	if kind != PrototypeKind.FALL_BLOCK:
		return
	if prop.falling == null:
		prop.falling = _add_component(prop, FallingBehavior.new(), "FallingBehavior", room)
	prop.falling.delay = float(def.get("fall_delay", 0.3))
	prop.falling.gravity = float(def.get("fall_gravity", 350.0))
	prop.falling.max_speed = float(def.get("fall_max", 90.0))


func _add_power(prop: TileProp, def: Dictionary, room: Node) -> void:
	if (prop.power == null
		and not def.has("watches")
		and not def.has("power_effect")
		and not def.has("starts_open")
	):
		return

	if prop.power == null:
		prop.power = _add_component(prop, Power.new(), "Power", room)

	var watched: Array[StringName] = []
	for switch_id in def.get("watches", []):
		watched.append(StringName(switch_id))
	prop.power.watches = watched
	prop.power.need = int(def.get("need", 0)) as Power.Need
	prop.power.effect = int(def.get("power_effect", Power.Effect.RUNS)) as Power.Effect
	prop.power.starts_on_when_unwatched = int(def.get("starts_open", 0)) == 1


func _add_component(prop: TileProp, component: Node, component_name: String, room: Node) -> Node:
	component.name = component_name
	prop.add_child(component)
	component.owner = room
	return component


## Surface first so the scene tree reads as what the player meets: PogoMovingPlatform.
func _prop_name(kind: int, surface: int) -> String:
	var kind_name := String(PrototypeKind.find_key(kind)).to_pascal_case()
	if surface == Room.Kind.EMPTY:
		return kind_name
	return String(Room.Kind.find_key(surface)).to_pascal_case() + kind_name


func _solidity(def: Dictionary) -> TileProp.Solidity:
	match int(def.get("solid", -1)):
		SOLID_FORCED:
			return TileProp.Solidity.SOLID
		SOLID_NEVER:
			return TileProp.Solidity.PASS_THROUGH
	return TileProp.Solidity.KIND_DEFAULT


func _read_room_json() -> Dictionary:
	var path := ProjectSettings.globalize_path("res://").path_join(SOURCE_JSON)
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary:
		push_error("Could not read a room document from %s" % path)
		return {}
	return parsed
