class_name PieceEntityImport
extends RefCounted
## Standalone prototype entity conversion shared by piece import.

const TILE := MovementStats.TILE

enum Kind {
	MOVING_PLATFORM,
	BREAKABLE,
	WALKER,
	THROWABLE,
	SWITCH,
	GATE,
	FALL_BLOCK,
	WINDMILL,
	BLOCK,
	TRACK,
}

const PREFABS := {
	Kind.MOVING_PLATFORM: preload("res://scenes/props/moving_platform.tscn"),
	Kind.BREAKABLE: preload("res://scenes/props/breakable.tscn"),
	Kind.SWITCH: preload("res://scenes/props/switch.tscn"),
	Kind.GATE: preload("res://scenes/props/gate.tscn"),
	Kind.FALL_BLOCK: preload("res://scenes/props/fall_block.tscn"),
	Kind.WINDMILL: preload("res://scenes/props/windmill.tscn"),
	Kind.BLOCK: preload("res://scenes/props/block.tscn"),
	Kind.TRACK: preload("res://scenes/props/moving_platform.tscn"),
}
const WALKER_SCENE := preload("res://scenes/actors/walker.tscn")
const THROWABLE_SCENE := preload("res://scenes/actors/throwable.tscn")


static func add_root(def: Dictionary, props: Node, actors: Node, owner: Node) -> bool:
	var kind := int(def.get("kind", -1))
	if kind == Kind.WALKER or kind == Kind.THROWABLE:
		var actor := _make_actor(def)
		if actor == null:
			return false
		var size := Vector2(def.get("w", 16), def.get("h", 16))
		actor.size = size
		actor.position = Vector2(def.get("x", 0), def.get("y", 0)) + size / 2.0
		actor.z_index = int(def.get("z", 0))
		actors.add_child(actor, true)
		actor.owner = owner
		return true
	return _add_prop(def, props, owner, true)


static func _add_prop(def: Dictionary, parent: Node, owner: Node, is_root: bool) -> bool:
	var kind := int(def.get("kind", -1))
	if not PREFABS.has(kind):
		push_error("Unsupported piece entity kind %d" % kind)
		return false
	var entity := (PREFABS[kind] as PackedScene).instantiate(PackedScene.GEN_EDIT_STATE_INSTANCE)
	var size := Vector2(def.get("w", 16), def.get("h", 16))
	if entity is SwitchProp:
		var room_switch := entity as SwitchProp
		room_switch.name = &"Switch"
		room_switch.size = size
		room_switch.switch_id = StringName(def.get("id", "sw"))
		room_switch.mode = int(def.get("mode", 0)) as SwitchProp.Mode
		room_switch.starts_on = int(def.get("starts_on", 0)) == 1
		room_switch.z_index = int(def.get("z", 0))
		room_switch.position = Vector2(def.get("x", 0), def.get("y", 0)) + size / 2.0
		parent.add_child(room_switch, true)
		room_switch.owner = owner
		return true

	var prop := entity as TileProp
	prop.name = String(Kind.find_key(kind)).to_pascal_case()
	prop.size = size
	prop.surface = int(def.get("surface", Room.Kind.SOLID)) as Room.Kind
	prop.solidity = _solidity(def)
	prop.z_index = int(def.get("z", 0))
	prop.position = (
		Vector2(def.get("x", 0), def.get("y", 0)) + size / 2.0
		if is_root
		else Vector2(def.get("x", 0), def.get("y", 0))
	)
	parent.add_child(prop, true)
	prop.owner = owner
	owner.set_editable_instance(prop, true)
	_add_oscillation(prop, def, owner)
	_add_path(prop, def, owner)
	_add_spin(prop, def, owner)
	_add_breakable(prop, def, kind, owner)
	_add_falling(prop, def, kind, owner)
	_add_power(prop, def, owner)
	for child_def: Dictionary in def.get("children", []):
		if not _add_prop(child_def, prop, owner, false):
			return false
	return true


static func _add_oscillation(prop: TileProp, def: Dictionary, owner: Node) -> void:
	if not (def.has("travel") and def.has("speed")):
		return
	if prop.oscillation == null:
		prop.oscillation = _add_component(prop, OscillatingMotion.new(), &"OscillatingMotion", owner)
	prop.oscillation.travel = float(def.travel)
	prop.oscillation.speed = float(def.speed)
	prop.oscillation.axis = int(def.get("axis", 0)) as OscillatingMotion.Axis
	prop.oscillation.phase = float(def.get("phase", 0.0))


static func _add_path(prop: TileProp, def: Dictionary, owner: Node) -> void:
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
	prop.path = _add_component(prop, path, &"PathMotion", owner)
	prop.position = curve.get_point_position(0)


static func _add_spin(prop: TileProp, def: Dictionary, owner: Node) -> void:
	var radius := float(def.get("spin_radius", 0.0))
	if radius <= 0.0:
		return
	if prop.spin == null:
		prop.spin = _add_component(prop, SpinMotion.new(), &"SpinMotion", owner)
	prop.spin.radius = radius * TILE
	prop.spin.turns_per_second = float(def.get("spin_speed", 0.25))
	prop.spin.start_turn = float(def.get("spin_phase", 0.0))


static func _add_breakable(prop: TileProp, def: Dictionary, kind: int, owner: Node) -> void:
	if kind != Kind.BREAKABLE and int(def.get("fragile", 0)) != 1:
		return
	if prop.breakable == null:
		prop.breakable = _add_component(prop, Breakable.new(), &"Breakable", owner)
	prop.breakable.respawn = float(def.get("respawn", 2.5))
	prop.breakable.delay = float(def.get("delay", 0.4))


static func _add_falling(prop: TileProp, def: Dictionary, kind: int, owner: Node) -> void:
	if kind != Kind.FALL_BLOCK:
		return
	if prop.falling == null:
		prop.falling = _add_component(prop, FallingBehavior.new(), &"FallingBehavior", owner)
	prop.falling.delay = float(def.get("fall_delay", 0.3))
	prop.falling.gravity = float(def.get("fall_gravity", 350.0))
	prop.falling.max_speed = float(def.get("fall_max", 90.0))


static func _add_power(prop: TileProp, def: Dictionary, owner: Node) -> void:
	if prop.power == null and not def.has("watches") and not def.has("power_effect") and not def.has("starts_open"):
		return
	if prop.power == null:
		prop.power = _add_component(prop, Power.new(), &"Power", owner)
	var watches: Array[StringName] = []
	for switch_id in def.get("watches", []):
		watches.append(StringName(switch_id))
	prop.power.watches = watches
	prop.power.need = int(def.get("need", 0)) as Power.Need
	prop.power.effect = int(def.get("power_effect", Power.Effect.RUNS)) as Power.Effect
	prop.power.starts_on_when_unwatched = int(def.get("starts_open", 0)) == 1


static func _add_component(prop: TileProp, component: Node, component_name: StringName, owner: Node) -> Node:
	component.name = component_name
	prop.add_child(component)
	component.owner = owner
	return component


static func _make_actor(def: Dictionary) -> RoomActor:
	match int(def.kind):
		Kind.WALKER:
			var walker := WALKER_SCENE.instantiate(PackedScene.GEN_EDIT_STATE_INSTANCE) as Walker
			walker.speed = float(def.get("speed", 5.0)) * TILE
			walker.start_facing = -1 if int(def.get("facing", 1)) < 0 else 1
			walker.turn_on_ledges = int(def.get("turn_on_ledge", 1)) == 1
			_set_body_tuning(walker, def)
			return walker
		Kind.THROWABLE:
			var ball := THROWABLE_SCENE.instantiate(PackedScene.GEN_EDIT_STATE_INSTANCE) as Throwable
			ball.throw_speed = float(def.get("throw_speed", 42.0)) * TILE
			ball.throw_up = float(def.get("throw_up", -6.0)) * TILE
			ball.slide_friction = float(def.get("slide_friction", 18.0)) * TILE
			ball.hazard_speed = float(def.get("hazard_speed", 14.0)) * TILE
			_set_body_tuning(ball, def)
			return ball
	return null


static func _set_body_tuning(actor: RoomActor, def: Dictionary) -> void:
	actor.gravity = float(def.get("gravity", 350.0)) * TILE
	actor.stomp_bounce = float(def.get("stomp_vy", -40.0)) * TILE


static func _solidity(def: Dictionary) -> TileProp.Solidity:
	match int(def.get("solid", -1)):
		1:
			return TileProp.Solidity.SOLID
		0:
			return TileProp.Solidity.PASS_THROUGH
	return TileProp.Solidity.KIND_DEFAULT
