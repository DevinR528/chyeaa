class_name RunUI
extends CanvasLayer
## HUD, pause menu, and potion picker. This layer keeps processing while the
## tree is paused; gameplay nodes do not.

@export var runner: RoomRunner

const OPTION_MENU := preload("res://scenes/ui/option_menu.tscn")

var ticks := 0
var picker_open := false
var pause_open := false
var option_open := false
var pause_index := 0

var _rows: Array[Dictionary] = []
var _selected := 0
var _hud: Label
var _pause: Control
var _pause_summary: Label
var _pause_rows: VBoxContainer
var _picker: Control
var _picker_rows: VBoxContainer
var _rewind: RewindScreen
var _opt_menu: OptionMenu
var _editor: PieceEditor


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 30
	_hud = _make_label("No power-ups")
	_hud.position = Vector2(8, 8)
	add_child(_hud)
	_pause = _make_pause()
	_pause_summary = _pause.get_node(^"Center/Panel/Summary") as Label
	_pause_rows = _pause.get_node(^"Center/Panel/Actions") as VBoxContainer

	_picker = _make_panel(&"Picker")
	_picker.get_node(^"Panel/Title").text = "Potions"
	_picker_rows = _picker.get_node(^"Panel/Rows") as VBoxContainer

	_rewind = RewindScreen.new()
	_rewind.name = &"Rewind"
	_rewind.bind_runner(runner)
	add_child(_rewind)

	_opt_menu = OPTION_MENU.instantiate() as OptionMenu
	add_child(_opt_menu)

	_opt_menu.hide()
	_pause.hide()
	_picker.hide()

func _process(_delta: float) -> void:
	ticks += 1
	if _editor_blocks():
		return
	_refresh_hud()
	if _reward_open() or (_rewind != null and _rewind.open):
		return
	if picker_open:
		_steer_picker()
		return
	if option_open:
		_steer_options()
		return
	if pause_open:
		_steer_pause()
		return
	if Input.is_action_just_pressed(&"pause"):
		open_pause()
	elif Input.is_action_just_pressed(&"potion"):
		open_picker()


func _reward_open() -> bool:
	return runner != null and runner.reward_menu != null and runner.reward_menu.open


func summary_text() -> String:
	if runner == null:
		return ""
	return runner.build.summary(runner.build.time_scale, 0, runner.belt.charges())


static func line_for(choice: Dictionary) -> String:
	if str(choice.get("blocked", "")) != "":
		return "%s — %s" % [choice.name, choice.blocked]
	if bool(choice.get("free", false)):
		return "%s — free (debug)" % choice.name
	var count := int(choice.uses)
	var suffix := "" if count == 1 else "s"
	return "%s — %d charge%s" % [choice.name, count, suffix]


func open_pause() -> void:
	pause_open = true
	pause_index = 0
	_pause_summary.text = summary_text()
	_mark_pause()
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
	show_choices(runner.potion_choices())


func open_rewind() -> void:
	if runner == null or not runner.can_rewind():
		return
	_rewind.show_timeline(runner.rewind_timeline())
	get_tree().paused = true


func open_option() -> void:
	if pause_open:
		_pause.hide()
	_opt_menu.show()
	option_open = true


func close_option() -> void:
	option_open = false
	_opt_menu.hide()
	if not pause_open:
		print("not pause open")
		get_tree().paused = false
	else:
		open_pause()

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
	if runner != null and int(choice.get("action", Potion.Action.INSTANT)) == Potion.Action.REWIND:
		close_picker()
		open_rewind()
		return true
	if runner != null:
		runner.drink_potion(choice.id)
	close_picker()
	return true


func _steer_pause() -> void:
	var count := _pause_actions().size()
	if Input.is_action_just_pressed(&"move_up"):
		pause_index = posmod(pause_index - 1, count)
		_mark_pause()
	elif Input.is_action_just_pressed(&"move_down"):
		pause_index = posmod(pause_index + 1, count)
		_mark_pause()
	elif Input.is_action_just_pressed(&"jump"):
		_confirm_pause()
	elif Input.is_action_just_pressed(&"pause"):
		close_pause()


func _confirm_pause() -> void:
	var actions := _pause_actions()
	if pause_index < 0 or pause_index >= actions.size():
		return
	var action := actions[pause_index]

	if action == "Volume":
		open_option()
		print("STUFF AND THANGS")
		return

	if action == "Piece editor":
		pause_open = false
		_pause.hide()
		if runner != null:
			get_tree().paused = true
			_ensure_editor().open(runner)
		return

	close_pause()
	if runner == null:
		return
	if action == "Restart room":
		runner.restart_room()
	elif action == "Generated run":
		runner.start_generated_run()
	elif action == "Demo room":
		runner.return_to_demo()
	elif action == "Regen room":
		runner.regen_room()


func _steer_options() -> void:
	if Input.is_action_just_pressed(&"move_up"):
		var next = _opt_menu.find_prev_valid_focus()
		if next:
			next.grab_focus()
		else:
			var sib = _opt_menu.find_valid_focus_neighbor(SIDE_RIGHT)
			if sib: sib.grab_focus()
	elif Input.is_action_just_pressed(&"move_down"):
		var next = _opt_menu.find_next_valid_focus()
		if next:
			next.grab_focus()
		else:
			var sib = _opt_menu.find_valid_focus_neighbor(SIDE_RIGHT)
			if sib: sib.grab_focus()

	elif Input.is_action_just_pressed(&"jump"):
		if _opt_menu.is_exit_pressed():
			close_option()
		else:
			# handle more strange options...
			pass
	elif Input.is_action_just_pressed(&"pause"):
		close_option()


func _editor_blocks() -> bool:
	if _editor == null:
		return false
	if _editor.ate_pause:
		_editor.ate_pause = false
		return true
	return _editor.active


func _ensure_editor() -> PieceEditor:
	if _editor == null:
		_editor = PieceEditor.new()
		_editor.name = &"PieceEditor"
	return _editor


func _pause_actions() -> Array[String]:
	var actions: Array[String] = ["Resume", "Restart room"]
	if runner != null and runner.gen_active:
		actions.append("Regen room")
	actions.append("Demo room" if runner != null and runner.gen_active else "Generated run")
	actions.append("Piece editor")
	actions.append("Volume")
	return actions


func _mark_pause() -> void:
	for child in _pause_rows.get_children():
		child.free()
	var actions := _pause_actions()
	for index in actions.size():
		var prefix := "> " if index == pause_index else "  "
		_pause_rows.add_child(_make_label(prefix + actions[index]))


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


func _make_pause() -> Control:
	var root := Control.new()
	root.name = &"Pause"
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0, 0, 0, 0.55)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(dim)
	var center := CenterContainer.new()
	center.name = &"Center"
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var panel := VBoxContainer.new()
	panel.name = &"Panel"
	panel.alignment = BoxContainer.ALIGNMENT_CENTER
	panel.add_child(_make_label("Paused", &"Title"))
	panel.add_child(_make_label("", &"Summary"))
	panel.add_child(_make_label("Up and down to move. Jump chooses. Esc resumes."))
	var actions := VBoxContainer.new()
	actions.name = &"Actions"
	panel.add_child(actions)
	center.add_child(panel)
	root.add_child(center)
	add_child(root)
	return root


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
