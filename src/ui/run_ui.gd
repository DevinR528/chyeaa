class_name RunUI
extends CanvasLayer
## HUD, pause menu, and potion picker. This layer keeps processing while the
## tree is paused; gameplay nodes do not.

@export var runner: RoomRunner

var ticks := 0
var picker_open := false
var pause_open := false

var _rows: Array[Dictionary] = []
var _selected := 0
var _hud: Label
var _pause: Control
var _pause_summary: Label
var _picker: Control
var _picker_rows: VBoxContainer


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 30
	_hud = _make_label("No power-ups")
	_hud.position = Vector2(8, 8)
	add_child(_hud)
	_pause = _make_panel(&"Pause")
	_pause_summary = _pause.get_node(^"Panel/Summary") as Label
	_picker = _make_panel(&"Picker")
	_picker.get_node(^"Panel/Title").text = "Potions"
	_picker_rows = _picker.get_node(^"Panel/Rows") as VBoxContainer
	_pause.hide()
	_picker.hide()


func _process(_delta: float) -> void:
	ticks += 1
	_refresh_hud()
	if picker_open:
		_steer_picker()
		return
	if pause_open:
		if Input.is_action_just_pressed(&"pause") or Input.is_action_just_pressed(&"jump"):
			close_pause()
		return
	if Input.is_action_just_pressed(&"pause"):
		open_pause()
	elif Input.is_action_just_pressed(&"potion"):
		open_picker()


func summary_text() -> String:
	if runner == null:
		return ""
	return runner.build.summary(runner.build.time_scale, 0, runner.belt.charges())


static func line_for(choice: Dictionary) -> String:
	if str(choice.get("blocked", "")) != "":
		return "%s — %s" % [choice.name, choice.blocked]
	var count := int(choice.uses)
	var suffix := "" if count == 1 else "s"
	return "%s — %d charge%s" % [choice.name, count, suffix]


func open_pause() -> void:
	pause_open = true
	_pause_summary.text = summary_text()
	_pause.show()
	get_tree().paused = true


func close_pause() -> void:
	pause_open = false
	_pause.hide()
	if not picker_open:
		get_tree().paused = false


func open_picker() -> void:
	if runner == null or runner.player == null:
		return
	show_choices(runner.belt.choices(runner.player))


func show_choices(rows: Array[Dictionary]) -> void:
	_rows = rows
	_selected = 0
	picker_open = true
	_rebuild_picker()
	_picker.show()
	get_tree().paused = true


func close_picker() -> void:
	picker_open = false
	_picker.hide()
	if not pause_open:
		get_tree().paused = false


## Drinks the selected row. A blocked row stays open and spends nothing.
func confirm_selection() -> bool:
	if not picker_open or _selected < 0 or _selected >= _rows.size():
		return false
	var choice := _rows[_selected]
	if str(choice.get("blocked", "")) != "":
		return false
	if runner != null:
		runner.drink_potion(choice.id)
	close_picker()
	return true


func _steer_picker() -> void:
	if Input.is_action_just_pressed(&"move_up"):
		_selected = posmod(_selected - 1, maxi(_rows.size(), 1))
		_rebuild_picker()
	elif Input.is_action_just_pressed(&"move_down"):
		_selected = posmod(_selected + 1, maxi(_rows.size(), 1))
		_rebuild_picker()
	elif Input.is_action_just_pressed(&"jump"):
		confirm_selection()
	elif Input.is_action_just_pressed(&"potion") or Input.is_action_just_pressed(&"pause"):
		close_picker()


func _refresh_hud() -> void:
	if _hud == null or runner == null:
		return
	_hud.text = summary_text()
	if pause_open:
		_pause_summary.text = _hud.text


func _rebuild_picker() -> void:
	for child in _picker_rows.get_children():
		child.queue_free()
	if _rows.is_empty():
		_picker_rows.add_child(_make_label("No potions equipped."))
		return
	for index in _rows.size():
		var prefix := "> " if index == _selected else "  "
		var row := _make_label(prefix + line_for(_rows[index]))
		_picker_rows.add_child(row)


func _make_panel(panel_name: StringName) -> Control:
	var root := Control.new()
	root.name = panel_name
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0, 0, 0, 0.55)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(dim)
	var panel := VBoxContainer.new()
	panel.name = &"Panel"
	panel.position = Vector2(24, 24)
	panel.add_child(_make_label("Paused", &"Title"))
	panel.add_child(_make_label("", &"Summary"))
	if panel_name == &"Pause":
		panel.add_child(_make_label("Jump or Esc to resume"))
	else:
		panel.add_child(_make_label("Jump drinks. Potion or Esc cancels."))
		var rows := VBoxContainer.new()
		rows.name = &"Rows"
		panel.add_child(rows)
	root.add_child(panel)
	add_child(root)
	return root


func _make_label(text: String, label_name := &"") -> Label:
	var label := Label.new()
	if label_name != &"":
		label.name = label_name
	label.text = text
	label.add_theme_color_override(&"font_color", Color(0.91, 0.94, 1))
	return label
