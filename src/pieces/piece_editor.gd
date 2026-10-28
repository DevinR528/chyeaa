class_name PieceEditor
extends Node
## In-game piece authoring. Gameplay stays paused; this node keeps processing.
## Playtest builds a temporary room and does not write art tiles back onto the piece.

enum Tool { PAINT, ERASE, SELECT, ENTRY, EXIT, SPAWN }

const LIBRARY := preload("res://resources/pieces/library.tres")
const TILE := MovementStats.TILE

var runner: RoomRunner
var board: PieceBoard
var tool := Tool.PAINT
var active := false
var playing := false
## Set when Esc leaves the editor, so the pause menu does not also open.
var ate_pause := false

var _world: Node2D
var _camera: Camera2D
var _overlay: Overlay
var _hud: CanvasLayer
var _status: Label
var _brush_label: Label
var _id_edit: LineEdit
var _cols: SpinBox
var _rows: SpinBox
var _difficulty: SpinBox
var _unique: CheckButton
var _cap_start: CheckButton
var _cap_end: CheckButton
var _sliders: VBoxContainer
var _library: VBoxContainer
var _info: Control
var _stashed: Room
var _syncing := false
var _dragging := false
var _drag_start := Vector2i.ZERO
var _pan := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_world = Node2D.new()
	_world.name = &"World"
	_world.process_mode = Node.PROCESS_MODE_DISABLED
	_world.visible = false
	add_child(_world)
	_camera = Camera2D.new()
	_camera.enabled = false
	_camera.zoom = Vector2(2, 2)
	# The world node does not process, and the game pauses while editing.
	# Interpolation would keep the view on the last physics tick, so wheel
	# zoom and middle-mouse pan would not show up.
	_camera.process_mode = Node.PROCESS_MODE_ALWAYS
	_camera.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_world.add_child(_camera)
	var plate := Plate.new()
	plate.editor = self
	plate.z_index = -10
	_world.add_child(plate)
	_overlay = Overlay.new()
	_overlay.editor = self
	_overlay.z_index = 10
	_world.add_child(_overlay)
	_hud = CanvasLayer.new()
	_hud.name = &"Hud"
	_hud.layer = 40
	_hud.visible = false
	add_child(_hud)
	_build_hud()


func open(host: RoomRunner) -> void:
	if active or host == null:
		return
	runner = host
	ate_pause = false
	if get_parent() != host:
		host.add_child(self)
	if board == null:
		set_board(PieceBoard.blank(&"new_piece"))
	else:
		_load_fields()
	_stashed = host.detach_room()
	_set_play_visible(false)
	_world.visible = true
	_hud.visible = true
	active = true
	playing = false
	_use_editor_camera()
	_frame_camera()
	_set_status("Wheel zooms. Middle or right mouse pans.")
	if get_tree() != null:
		get_tree().paused = true


func close() -> void:
	if playing:
		end_playtest()
	if not active and _stashed == null:
		return
	active = false
	ate_pause = true
	_world.visible = false
	_hud.visible = false
	_use_play_camera()
	_set_play_visible(true)
	if runner != null and _stashed != null:
		runner.load_room(_stashed)
		_stashed = null
	if get_tree() != null:
		get_tree().paused = false


func playtest() -> void:
	if runner == null or board == null or playing:
		return
	var room := RoomGenerator.build_room(board.play_layout())
	if room == null:
		_set_status("Could not build a playtest room")
		return
	_world.visible = false
	_hud.visible = false
	_set_play_visible(true)
	_use_play_camera()
	playing = true
	runner.load_room(room)
	if get_tree() != null:
		get_tree().paused = false


func end_playtest() -> void:
	if not playing or runner == null:
		return
	playing = false
	var play_room := runner.detach_room()
	if play_room != null:
		play_room.free()
	if get_tree() != null:
		get_tree().paused = true
	_set_play_visible(false)
	_world.visible = true
	_hud.visible = true
	_use_editor_camera()
	_frame_camera()


func set_board(next: PieceBoard) -> void:
	if board != null and board.root != null and is_instance_valid(board.root):
		if board.root.get_parent() == _world:
			_world.remove_child(board.root)
		board.root.free()
	board = next
	if next == null or next.root == null:
		return
	next.root.process_mode = Node.PROCESS_MODE_DISABLED
	_world.add_child(next.root)
	_load_fields()
	_rebuild_sliders()
	_rebuild_library()
	_frame_camera()


func _input(event: InputEvent) -> void:
	if active and not playing and _handle_camera(event):
		get_viewport().set_input_as_handled()
		if _overlay != null:
			_overlay.queue_redraw()
		return
	if not active or not event.is_action_pressed(&"pause") or event.is_echo():
		return
	if playing:
		end_playtest()
	else:
		close()
	get_viewport().set_input_as_handled()


## Wheel and middle/right drag. Applied here, before the panels, and flushed
## immediately: while the game is paused the camera's physics tick does not run,
## so a position change would otherwise never reach the view.
func _handle_camera(event: InputEvent) -> bool:
	if event is InputEventMouseMotion and _pan:
		var motion := event as InputEventMouseMotion
		_camera.position -= motion.relative / _camera.zoom
		_camera.force_update_scroll()
		return true
	if event is InputEventMouseButton and _blocks_camera((event as InputEventMouseButton).position):
		return false
	if event is InputEventMouseButton:
		var button := event as InputEventMouseButton
		if button.button_index == MOUSE_BUTTON_WHEEL_UP and button.pressed:
			_set_zoom(_camera.zoom * 1.25)
			return true
		if button.button_index == MOUSE_BUTTON_WHEEL_DOWN and button.pressed:
			_set_zoom(_camera.zoom / 1.25)
			return true
		if button.button_index == MOUSE_BUTTON_MIDDLE or button.button_index == MOUSE_BUTTON_RIGHT:
			_pan = button.pressed
			return true
	return false


func _set_zoom(next: Vector2) -> void:
	_camera.zoom = next.clamp(Vector2(0.5, 0.5), Vector2(8, 8))
	_camera.force_update_scroll()


func _blocks_camera(screen_pos: Vector2) -> bool:
	var hovered := get_viewport().gui_get_hovered_control()
	if hovered == null or hovered.mouse_filter == Control.MOUSE_FILTER_IGNORE:
		return false
	return hovered.get_global_rect().has_point(screen_pos)


func _unhandled_input(event: InputEvent) -> void:
	if not active or playing or board == null:
		return
	if event is InputEventMouseButton:
		var button := event as InputEventMouseButton
		if button.button_index == MOUSE_BUTTON_LEFT:
			var cell := _cell_at(_world.get_global_mouse_position())
			if button.pressed:
				_dragging = true
				_drag_start = cell
				_press(cell)
			else:
				_dragging = false
				_release(cell)
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion and _dragging:
		_stroke(_cell_at(_world.get_global_mouse_position()))
		get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.pressed and not event.echo:
		var key := event as InputEventKey
		if key.keycode == KEY_DELETE or key.keycode == KEY_BACKSPACE:
			if not _text_focused():
				_delete_selected()
				get_viewport().set_input_as_handled()
		elif key.keycode == KEY_BRACKETLEFT:
			board.step_brush(-1)
			_refresh_brush()
		elif key.keycode == KEY_BRACKETRIGHT:
			board.step_brush(1)
			_refresh_brush()
	_overlay.queue_redraw()


func _press(cell: Vector2i) -> void:
	var point := _world.get_global_mouse_position()
	match tool:
		Tool.PAINT:
			board.paint_cell(_brush_origin(cell))
		Tool.ERASE:
			var removed := board.remove_at(point)
			board.paint_cell(_brush_origin(cell), true)
			if not removed.is_empty():
				_rebuild_sliders()
				_set_status("Removed %s" % removed)
		Tool.SELECT:
			board.pick(point)
			_rebuild_sliders()
		Tool.SPAWN:
			board.set_spawn(board.root.to_local(point))
		Tool.ENTRY, Tool.EXIT:
			pass


func _stroke(cell: Vector2i) -> void:
	match tool:
		Tool.PAINT:
			board.paint_cell(_brush_origin(cell))
		Tool.ERASE:
			board.paint_cell(_brush_origin(cell), true)
		Tool.SELECT:
			if board.selected is Node2D:
				(board.selected as Node2D).global_position = _world.get_global_mouse_position()


func _release(cell: Vector2i) -> void:
	if tool != Tool.ENTRY and tool != Tool.EXIT:
		return
	var snapped: Dictionary = board.snap_segment(_drag_start, cell)
	var which := PieceBoard.PortalEnd.ENTRY if tool == Tool.ENTRY else PieceBoard.PortalEnd.EXIT
	if not board.set_portal(which, snapped.a, snapped.b):
		_set_status("Portal must sit on the outer edge and stay open enough for the player.")
	else:
		_set_status("")


func _brush_origin(cell: Vector2i) -> Vector2i:
	var half := board.brush_size / 2
	return cell - Vector2i(half, half)


func _cell_at(global_point: Vector2) -> Vector2i:
	var local := board.root.to_local(global_point)
	return Vector2i(floori(local.x / TILE), floori(local.y / TILE))


func _build_hud() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud.add_child(root)
	var scroller := ScrollContainer.new()
	scroller.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	scroller.offset_left = 8
	scroller.offset_top = 8
	scroller.offset_right = 196
	scroller.offset_bottom = -36
	scroller.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(scroller)
	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(168, 0)
	scroller.add_child(left)
	left.add_child(_button("Info", func() -> void: _set_info(true)))
	left.add_child(_section("Paint"))
	for kind in [Room.Kind.SOLID, Room.Kind.DEATH, Room.Kind.GRAPPLE, Room.Kind.POGO, Room.Kind.EXIT]:
		left.add_child(_button(_kind_name(kind), _bind_kind(kind)))
	var brush_row := HBoxContainer.new()
	brush_row.add_child(_button("-", func() -> void:
		board.step_brush(-1)
		_refresh_brush()
	))
	_brush_label = _label("Brush 8")
	brush_row.add_child(_brush_label)
	brush_row.add_child(_button("+", func() -> void:
		board.step_brush(1)
		_refresh_brush()
	))
	left.add_child(brush_row)
	left.add_child(_button("Erase", func() -> void: tool = Tool.ERASE))
	left.add_child(_button("Select", func() -> void: tool = Tool.SELECT))
	left.add_child(_button("Delete", _delete_selected))
	left.add_child(_section("Portals"))
	left.add_child(_button("Entry", func() -> void: tool = Tool.ENTRY))
	left.add_child(_button("Exit", func() -> void: tool = Tool.EXIT))
	left.add_child(_button("Spawn", func() -> void: tool = Tool.SPAWN))
	left.add_child(_section("Stamps"))
	for stamp in PieceBoard.Stamp.values():
		left.add_child(_button(_stamp_name(stamp), _bind_stamp(stamp)))
	left.add_child(_section("Piece"))
	left.add_child(_button("New", func() -> void: set_board(PieceBoard.blank(&"new_piece"))))
	left.add_child(_button("Duplicate", func() -> void:
		if board != null:
			set_board(board.duplicate_board())
	))
	left.add_child(_button("Save", _save))
	left.add_child(_button("Playtest", playtest))
	left.add_child(_button("Back", close))
	left.add_child(_section("Library"))
	_library = VBoxContainer.new()
	left.add_child(_library)

	var right := VBoxContainer.new()
	right.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	right.offset_left = -220
	right.offset_top = 8
	right.offset_right = -8
	right.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(right)
	right.add_child(_section("Properties"))
	_id_edit = LineEdit.new()
	_id_edit.placeholder_text = "piece id"
	_id_edit.text_submitted.connect(func(text: String) -> void: _apply_id(text))
	_id_edit.focus_exited.connect(func() -> void: _apply_id(_id_edit.text))
	right.add_child(_id_edit)
	_cols = _spin(3, 128, func(value: float) -> void: _apply_size(int(value), int(_rows.value)))
	_rows = _spin(4, 128, func(value: float) -> void: _apply_size(int(_cols.value), int(value)))
	_difficulty = _spin(1, 10, func(value: float) -> void:
		if board != null and not _syncing:
			board.difficulty = int(value)
	)
	right.add_child(_labeled("Cols", _cols))
	right.add_child(_labeled("Rows", _rows))
	right.add_child(_labeled("Difficulty", _difficulty))
	_unique = _check("Unique", func(on: bool) -> void:
		if board != null and not _syncing:
			board.unique = on
	)
	_cap_start = _check("cap_start", func(on: bool) -> void:
		if board != null and not _syncing:
			board.set_tag(&"cap_start", on)
	)
	_cap_end = _check("cap_end", func(on: bool) -> void:
		if board != null and not _syncing:
			board.set_tag(&"cap_end", on)
	)
	right.add_child(_unique)
	right.add_child(_cap_start)
	right.add_child(_cap_end)
	_sliders = VBoxContainer.new()
	right.add_child(_sliders)

	_status = _label("")
	_status.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_status.offset_bottom = -8
	_status.offset_top = -28
	_status.offset_left = 188
	root.add_child(_status)
	_build_info(root)


func _stamp(stamp: PieceBoard.Stamp) -> void:
	if board == null:
		return
	var at := Vector2(board.cols, board.rows) * TILE * 0.5
	board.place_prefab(stamp, at)
	tool = Tool.SELECT
	_rebuild_sliders()


func _save() -> void:
	if board == null:
		return
	_apply_id(_id_edit.text)
	var error := PieceWriter.save_editor_piece(board, LIBRARY)
	_set_status("Saved %s" % board.piece_id if error.is_empty() else error)
	if error.is_empty():
		_rebuild_library()


func _apply_id(text: String) -> void:
	if board == null or _syncing:
		return
	var id := text.strip_edges().to_lower().replace(" ", "_")
	board.piece_id = StringName(id)
	if _id_edit.text != id:
		_syncing = true
		_id_edit.text = id
		_syncing = false


func _apply_size(next_cols: int, next_rows: int) -> void:
	if board == null or _syncing:
		return
	if board.cols == next_cols and board.rows == next_rows:
		return
	if not board.set_size(next_cols, next_rows):
		_set_status("That size cuts off an entrance or exit.")
		_load_fields()
	else:
		_set_status("")
		_frame_camera()


func _load_fields() -> void:
	if board == null or _id_edit == null:
		return
	_syncing = true
	_id_edit.text = String(board.piece_id)
	_cols.value = board.cols
	_rows.value = board.rows
	_difficulty.value = board.difficulty
	_unique.button_pressed = board.unique
	_cap_start.button_pressed = board.tags.has(&"cap_start")
	_cap_end.button_pressed = board.tags.has(&"cap_end")
	_refresh_brush()
	_syncing = false


func _rebuild_sliders() -> void:
	if _sliders == null:
		return
	for child in _sliders.get_children():
		child.free()
	if board == null or board.selected == null:
		return
	_sliders.add_child(_section(String(board.selected.name)))
	_sliders.add_child(_button("Delete", _delete_selected))
	for row in board.tuning_rows(board.selected):
		var property: StringName = row.property
		var slider := HSlider.new()
		slider.min_value = row.min
		slider.max_value = row.max
		slider.step = row.step
		slider.custom_minimum_size = Vector2(180, 16)
		slider.set_value_no_signal(row.value)
		slider.value_changed.connect(func(value: float) -> void:
			board.set_tuned_value(board.selected, property, value)
			_overlay.queue_redraw()
		)
		_sliders.add_child(_labeled(row.label, slider))


## The list is rebuilt from a click on one of its own buttons. Those buttons are
## still emitting, so they cannot be freed until the click returns.
func _rebuild_library() -> void:
	if _library == null:
		return
	for child in _library.get_children():
		_library.remove_child(child)
		child.queue_free()
	for piece in LIBRARY.pieces:
		_library.add_child(_button(String(piece.piece_id), _bind_open(piece.piece_id)))


func _open_library(id: StringName) -> void:
	for piece in LIBRARY.pieces:
		if piece.piece_id == id and piece.scene != null:
			set_board(PieceBoard.from_data(piece))
			_set_status("Opened %s" % id)
			return


func _refresh_brush() -> void:
	if _brush_label != null and board != null:
		_brush_label.text = "Brush %d" % board.brush_size


func _delete_selected() -> void:
	if board == null:
		return
	var removed := board.remove_selected()
	if removed.is_empty():
		_set_status("Select a stamp, then Delete.")
		return
	_rebuild_sliders()
	_set_status("Removed %s" % removed)


func _text_focused() -> bool:
	var focus := get_viewport().gui_get_focus_owner()
	return focus is LineEdit or focus is TextEdit


func _set_info(shown: bool) -> void:
	if _info != null:
		_info.visible = shown


func _build_info(parent: Control) -> void:
	var shade := ColorRect.new()
	shade.name = &"InfoPanel"
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.color = Color(0, 0, 0, 0.55)
	shade.mouse_filter = Control.MOUSE_FILTER_STOP
	shade.visible = false
	shade.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
			_set_info(false)
			get_viewport().set_input_as_handled()
	)
	parent.add_child(shade)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	shade.add_child(center)
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.09, 0.12, 0.98)
	style.border_color = Color(0.45, 0.58, 0.82)
	style.set_border_width_all(1)
	style.set_content_margin_all(20)
	panel.add_theme_stylebox_override(&"panel", style)
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override(&"separation", 16)
	panel.add_child(box)
	var header := HBoxContainer.new()
	header.add_theme_constant_override(&"separation", 16)
	box.add_child(header)
	var title := _section("How to edit")
	title.add_theme_font_size_override(&"font_size", 18)
	title.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	header.add_child(title)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(spacer)
	var close := _button("Close", func() -> void: _set_info(false))
	close.custom_minimum_size = Vector2(88, 0)
	header.add_child(close)
	var columns := HBoxContainer.new()
	columns.add_theme_constant_override(&"separation", 28)
	box.add_child(columns)
	columns.add_child(_info_column([
		["Paint", "Drag a kind onto the grid. The brush is a square. Change it with - +, or [ ]."],
		["Erase", "Drag to clear painted cells. Click a placed object to remove it."],
		["Select", "Click an object, then drag to move it. The sliders change its size and speed. The Delete button removes it."],
		["Stamps", "Block, windmill, enemy, and the other buttons drop one in the middle of the piece."],
	], &"InfoText"))
	columns.add_child(_info_column([
		["Entry and Exit", "Drag along an outer edge. The opening has to fit the player."],
		["Spawn", "Click where the player starts."],
		["Camera", "Scroll to zoom. Drag with the middle or right mouse button to pan, over the piece."],
		["Piece", "Save writes the library. Playtest does not save. Back returns to the game."],
	], &""))
	_info = shade


func _info_column(sections: Array, named: StringName) -> VBoxContainer:
	var column := VBoxContainer.new()
	column.add_theme_constant_override(&"separation", 14)
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for section in sections:
		var block := VBoxContainer.new()
		block.add_theme_constant_override(&"separation", 2)
		column.add_child(block)
		var heading := _section(section[0])
		block.add_child(heading)
		var body := _label(section[1])
		if heading.text == "Select":
			body.name = named
		body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		body.add_theme_constant_override(&"line_spacing", 4)
		body.custom_minimum_size = Vector2(300, 0)
		body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		block.add_child(body)
	return column


func _set_status(text: String) -> void:
	if _status != null:
		_status.text = text


func _frame_camera() -> void:
	if board == null or _camera == null:
		return
	_camera.position = Vector2(board.cols, board.rows) * TILE * 0.5
	_camera.force_update_scroll()
	for child in _world.get_children():
		child.queue_redraw()


func _use_editor_camera() -> void:
	if runner != null and runner.camera != null:
		runner.camera.enabled = false
	_camera.enabled = true
	_camera.make_current()


func _use_play_camera() -> void:
	_camera.enabled = false
	if runner != null and runner.camera != null:
		runner.camera.enabled = true
		runner.camera.make_current()


func _set_play_visible(shown: bool) -> void:
	if runner == null:
		return
	if runner.player != null:
		runner.player.visible = shown
	if runner.backdrop != null:
		runner.backdrop.visible = shown


func _spin(minimum: int, maximum: int, on_change: Callable) -> SpinBox:
	var box := SpinBox.new()
	box.min_value = minimum
	box.max_value = maximum
	box.rounded = true
	box.value_changed.connect(on_change)
	return box


func _check(text: String, on_change: Callable) -> CheckButton:
	var box := CheckButton.new()
	box.text = text
	box.toggled.connect(on_change)
	return box


func _labeled(text: String, control: Control) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.add_child(_label(text))
	box.add_child(control)
	return box


func _button(text: String, on_press: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.pressed.connect(on_press)
	return button


func _section(text: String) -> Label:
	var label := _label(text)
	label.add_theme_color_override(&"font_color", Color(0.65, 0.78, 1))
	return label


func _label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_color_override(&"font_color", Color(0.91, 0.94, 1))
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


func _bind_kind(kind: Room.Kind) -> Callable:
	return func() -> void:
		if board == null:
			return
		board.paint_kind = kind
		tool = Tool.PAINT


func _bind_stamp(stamp: PieceBoard.Stamp) -> Callable:
	return func() -> void: _stamp(stamp)


func _bind_open(id: StringName) -> Callable:
	return func() -> void: _open_library(id)


func _kind_name(kind: Room.Kind) -> String:
	match kind:
		Room.Kind.SOLID:
			return "Solid"
		Room.Kind.DEATH:
			return "Death"
		Room.Kind.GRAPPLE:
			return "Grapple"
		Room.Kind.POGO:
			return "Pogo"
		Room.Kind.EXIT:
			return "Exit"
	return "Empty"


func _stamp_name(stamp: PieceBoard.Stamp) -> String:
	match stamp:
		PieceBoard.Stamp.BLOCK:
			return "Block"
		PieceBoard.Stamp.WINDMILL:
			return "Windmill"
		PieceBoard.Stamp.MOVING_PLATFORM:
			return "Moving platform"
		PieceBoard.Stamp.BREAKABLE:
			return "Breakable"
		PieceBoard.Stamp.GATE:
			return "Gate"
		PieceBoard.Stamp.FALL_BLOCK:
			return "Fall block"
		PieceBoard.Stamp.SWITCH:
			return "Switch"
		PieceBoard.Stamp.WALKER:
			return "Walker"
		PieceBoard.Stamp.THROWABLE:
			return "Throwable"
	return "Stamp"


class Overlay extends Node2D:
	var editor: PieceEditor

	func _draw() -> void:
		if editor == null or editor.board == null:
			return
		var board := editor.board
		var tile := MovementStats.TILE
		var bounds := Rect2(Vector2.ZERO, Vector2(board.cols, board.rows) * tile)
		for x in board.cols + 1:
			draw_line(Vector2(x * tile, 0), Vector2(x * tile, bounds.size.y), Color(1, 1, 1, 0.08))
		for y in board.rows + 1:
			draw_line(Vector2(0, y * tile), Vector2(bounds.size.x, y * tile), Color(1, 1, 1, 0.08))
		draw_rect(bounds, Color(0.9, 0.95, 1, 0.8), false, 1.0)
		_draw_portal(board.entry_a, board.entry_b, Color(0.35, 0.9, 0.55))
		_draw_portal(board.exit_a, board.exit_b, Color(0.95, 0.55, 0.25))
		draw_line(board.spawn_feet + Vector2(-4, 0), board.spawn_feet + Vector2(4, 0), Color(0.4, 0.7, 1))
		draw_line(board.spawn_feet + Vector2(0, -4), board.spawn_feet + Vector2(0, 6), Color(0.4, 0.7, 1))
		var spin := board._spin(board.selected)
		if spin != null and board.selected is Node2D:
			var hub := (board.selected as Node2D).position
			var arm := Vector2(cos(spin.start_turn * TAU), sin(spin.start_turn * TAU)) * spin.radius
			draw_arc(hub, spin.radius, 0, TAU, 32, Color(0.95, 0.85, 0.35, 0.8), 1.0)
			draw_rect(Rect2(hub + arm - Vector2(8, 8), Vector2(16, 16)), Color(0.95, 0.85, 0.35, 0.9), false)
		if editor.tool == PieceEditor.Tool.PAINT or editor.tool == PieceEditor.Tool.ERASE:
			var origin := editor._brush_origin(editor._cell_at(get_global_mouse_position()))
			var rect := Rect2(Vector2(origin) * tile, Vector2.ONE * board.brush_size * tile)
			draw_rect(rect, Color(1, 1, 1, 0.35), false)


	func _draw_portal(a: Vector2i, b: Vector2i, color: Color) -> void:
		var tile := MovementStats.TILE
		var from := (Vector2(a) + Vector2(0.5, 0.5)) * tile
		var to := (Vector2(b) + Vector2(0.5, 0.5)) * tile
		draw_line(from, to, color, 2.0)


class Plate extends Node2D:
	var editor: PieceEditor

	func _draw() -> void:
		if editor == null or editor.board == null:
			return
		var size := Vector2(editor.board.cols, editor.board.rows) * MovementStats.TILE
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.12, 0.14, 0.18), true)
