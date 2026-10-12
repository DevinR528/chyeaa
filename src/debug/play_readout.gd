class_name PlayReadout
extends CanvasLayer
## Live player readout on the same debug toggle as ReachOverlay. Reads state
## only; it does not write velocity, input, or room data.

@export var runner: RoomRunner
var player: PlayerBody
var shown := false

var _label: Label


func _ready() -> void:
	layer = 40
	# After the player and actors, so reading kind cannot flush a stale body
	# transform over a position just committed.
	process_physics_priority = 100
	_label = Label.new()
	_label.position = Vector2(8, 8)
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.focus_mode = Control.FOCUS_NONE
	_label.visible = shown
	add_child(_label)


func _input(event: InputEvent) -> void:
	if event.is_action_pressed(&"toggle_debug"):
		shown = not shown
		_label.visible = shown


func _physics_process(_delta: float) -> void:
	if not shown:
		return
	var body := _body()
	_label.text = "" if body == null else _text(body)


func _body() -> PlayerBody:
	if runner != null and is_instance_valid(runner.player):
		return runner.player
	if is_instance_valid(player):
		return player
	return null


func _text(body: PlayerBody) -> String:
	return "\n".join([
		"fps %d" % Engine.get_frames_per_second(),
		"vel %s" % body.velocity,
		"grounded %s" % body.is_on_floor(),
		"move %s" % PlayerBody.MovementState.keys()[body.move_state],
		"ability %s" % _ability_state(body),
		"coyote %.3f" % body.coyote_time_left,
		"jump_buffer %.3f" % body.jump_buffer_left,
		"dash_cd %.3f" % body.dash_cooldown_left,
		"kind %s" % _kind_under(body),
	])


func _ability_state(body: PlayerBody) -> String:
	var ability := body.ability
	if ability == null:
		return "none"
	if ability is Grapple:
		return Grapple.State.keys()[(ability as Grapple).state]
	if ability is PogoStrike:
		return PogoStrike.State.keys()[(ability as PogoStrike).state]
	return "active"


func _kind_under(body: PlayerBody) -> String:
	var room := _room_of(body)
	if room == null:
		return "?"
	var feet := Vector2(body.global_position.x, body.body_rect().end.y + 1.0)
	return Room.Kind.keys()[room.kind_at(feet)]


func _room_of(body: Node) -> Room:
	var here: Node = body
	while here != null:
		if here is Room:
			return here as Room
		here = here.get_parent()
	return null
