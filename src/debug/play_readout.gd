class_name PlayReadout
extends CanvasLayer
## Live player readout on the same debug toggle as ReachOverlay. Drag the title
## with the mouse, or collapse it. Reads state only.

const FONT_SIZE := 8

@export var runner: RoomRunner
var player: PlayerBody
var shown := false

var _panel: PanelContainer
var _title: Label
var _collapse: Button
var _label: Label
var _collapsed := false
var _dragging := false
var _drag_offset := Vector2.ZERO


func _ready() -> void:
	layer = 40
	# After the player and actors, so reading kind cannot flush a stale body
	# transform over a position just committed.
	process_physics_priority = 100
	_panel = PanelContainer.new()
	_panel.position = Vector2(8, 8)
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, 0.72)
	style.content_margin_left = 4
	style.content_margin_top = 2
	style.content_margin_right = 4
	style.content_margin_bottom = 2
	_panel.add_theme_stylebox_override(&"panel", style)
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var header := HBoxContainer.new()
	header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_collapse = Button.new()
	_collapse.text = "–"
	_collapse.focus_mode = Control.FOCUS_NONE
	_collapse.custom_minimum_size = Vector2(14, 12)
	_style_control(_collapse)
	_collapse.pressed.connect(_toggle_collapsed)
	_title = Label.new()
	_title.text = "debug"
	_title.mouse_filter = Control.MOUSE_FILTER_STOP
	_title.mouse_default_cursor_shape = Control.CURSOR_MOVE
	_style_control(_title)
	_title.gui_input.connect(_on_title_input)
	header.add_child(_collapse)
	header.add_child(_title)
	_label = Label.new()
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_style_control(_label)
	box.add_child(header)
	box.add_child(_label)
	_panel.add_child(box)
	add_child(_panel)
	_apply_shown()


func _input(event: InputEvent) -> void:
	if event.is_action_pressed(&"toggle_debug"):
		shown = not shown
		_apply_shown()
		return
	if not _dragging or not event is InputEventMouse:
		return
	if event is InputEventMouseButton and not (event as InputEventMouseButton).pressed:
		_dragging = false
	elif event is InputEventMouseMotion:
		_panel.position = (event as InputEventMouseMotion).global_position - _drag_offset


func _physics_process(_delta: float) -> void:
	if not shown:
		return
	var body := _body()
	_label.text = "" if body == null else _text(body)


func _apply_shown() -> void:
	_panel.visible = shown
	_label.visible = shown and not _collapsed


func _toggle_collapsed() -> void:
	_collapsed = not _collapsed
	_collapse.text = "+" if _collapsed else "–"
	_apply_shown()


func _on_title_input(event: InputEvent) -> void:
	if not event is InputEventMouseButton:
		return
	var button := event as InputEventMouseButton
	if button.button_index != MOUSE_BUTTON_LEFT or not button.pressed:
		return
	_dragging = true
	_drag_offset = button.global_position - _panel.position


func _style_control(control: Control) -> void:
	control.add_theme_font_size_override(&"font_size", FONT_SIZE)


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
