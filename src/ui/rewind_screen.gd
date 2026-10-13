class_name RewindScreen
extends CanvasLayer
## Bottom scrub bar. Left and right step one frame; holding ramps the rate.
## Up and down jump one second. Jump commits. Esc cancels.

const SCRUB_RATE_START := 30.0
const SCRUB_RATE_MAX := 600.0
const SCRUB_RAMP_PER_S := 240.0
const SCRUB_DELAY := 0.25

var open := false

var _runner: RoomRunner
var _floor := 0
var _total := 0
var _deaths: Array[int] = []
var _step_seconds := 1.0 / 60.0
var _pretty_bytes := "0 B"
var _k := 0
var _hold_dir := 0
var _hold_t := 0.0
var _acc := 0.0
var _track: Control
var _head: ColorRect
var _locked: ColorRect
var _readout: Label
var _death_marks: Array[ColorRect] = []
## The jump that opened this screen is still just-pressed for the rest of that frame.
var _accepts_input := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 35
	_build()
	hide()


func bind_runner(runner: RoomRunner) -> void:
	_runner = runner


static func pretty_bytes(bytes: int) -> String:
	var units := ["B", "KB", "MB", "GB", "TB"]
	var size := float(bytes)
	var unit_index := 0
	while size >= 1024.0 and unit_index < units.size() - 1:
		size /= 1024.0
		unit_index += 1
	return "%.2f %s" % [size, units[unit_index]]

func show_timeline(timeline: Dictionary) -> void:
	open = true
	_floor = int(timeline.floor)
	_total = int(timeline.total)
	_deaths = []
	for at: int in timeline.deaths:
		_deaths.append(at)
	_step_seconds = float(timeline.step_seconds)

	_pretty_bytes = pretty_bytes(timeline.bytes)
	_k = _total
	_hold_dir = 0
	_hold_t = 0.0
	_acc = 0.0
	_accepts_input = false
	_hold_camera(true)
	_layout_marks()
	_layout_head()
	show()


func close_screen() -> void:
	open = false
	_hold_camera(false)
	hide()


func _hold_camera(held: bool) -> void:
	if _runner == null or _runner.camera == null:
		return
	_runner.camera.hold_for_rewind(held)


func _process(delta: float) -> void:
	if not open or _runner == null:
		return
	if not _accepts_input:
		_accepts_input = true
		return
	if Input.is_action_just_pressed(&"pause"):
		_cancel()
		return
	if Input.is_action_just_pressed(&"jump"):
		_commit()
		return
	var second := maxi(1, roundi(1.0 / _step_seconds))
	if Input.is_action_just_pressed(&"move_up"):
		_seek(_k + second)
	elif Input.is_action_just_pressed(&"move_down"):
		_seek(_k - second)
	var left := Input.is_action_pressed(&"move_left")
	var right := Input.is_action_pressed(&"move_right")
	var dir := (1 if right else 0) - (1 if left else 0)
	if dir != _hold_dir:
		_hold_dir = dir
		_hold_t = 0.0
		_acc = 0.0
		if dir != 0:
			_seek(_k + dir)
	elif dir != 0:
		_hold_t += delta
		if _hold_t >= SCRUB_DELAY:
			var held := _hold_t - SCRUB_DELAY
			var rate := minf(SCRUB_RATE_MAX, SCRUB_RATE_START + SCRUB_RAMP_PER_S * held)
			_acc += rate * delta
			var steps := int(_acc)
			if steps > 0:
				_acc -= float(steps)
				_seek(_k + dir * steps)


func _seek(k: int) -> void:
	var next := clampi(k, _floor, _total)
	if next == _k:
		return
	_k = next
	_runner.preview_rewind(_k)
	_layout_head()


func _commit() -> void:
	var k := _k
	close_screen()
	_runner.commit_rewind(k, _runner.rewind_is_free())
	get_tree().paused = false


func _cancel() -> void:
	close_screen()
	_runner.preview_rewind(_total)
	get_tree().paused = false


func _layout_marks() -> void:
	for mark in _death_marks:
		mark.queue_free()
	_death_marks.clear()
	var span := maxi(_total, 1)
	_locked.visible = _floor > 0
	_locked.offset_right = _track.size.x * float(_floor) / float(span)
	for at: int in _deaths:
		var mark := ColorRect.new()
		mark.color = Color("f87171")
		mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
		mark.position = Vector2(_track.size.x * float(at) / float(span), 0)
		mark.size = Vector2(2, _track.size.y)
		_track.add_child(mark)
		_death_marks.append(mark)


func _layout_head() -> void:
	var span := maxi(_total, 1)
	_head.position.x = _track.size.x * float(_k) / float(span)
	var back := float(_total - _k) * _step_seconds
	_readout.text = "-%.2f s · frame %d / %d · log %s" % [back, _k, _total, _pretty_bytes]


func _build() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bar := VBoxContainer.new()
	bar.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	bar.offset_top = -72
	bar.offset_bottom = -8
	bar.offset_left = 24
	bar.offset_right = -24
	bar.add_child(_label("Rewind"))
	_track = Control.new()
	_track.custom_minimum_size = Vector2(0, 18)
	_track.gui_input.connect(_on_track_input)
	var back := ColorRect.new()
	back.set_anchors_preset(Control.PRESET_FULL_RECT)
	back.color = Color(1, 1, 1, 0.16)
	back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_track.add_child(back)
	_locked = ColorRect.new()
	_locked.color = Color(0, 0, 0, 0.45)
	_locked.offset_bottom = 18
	_locked.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_track.add_child(_locked)
	_head = ColorRect.new()
	_head.color = Color("facc15")
	_head.offset_top = -2
	_head.offset_bottom = 20
	_head.offset_right = 2
	_head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_track.add_child(_head)
	bar.add_child(_track)
	_readout = _label("")
	bar.add_child(_readout)
	bar.add_child(_label("Left / right steps. Up / down jumps a second. Jump plays. Esc cancels."))
	root.add_child(bar)
	add_child(root)


func _on_track_input(event: InputEvent) -> void:
	if not open or not event is InputEventMouseButton:
		return
	var button := event as InputEventMouseButton
	if not button.pressed or button.button_index != MOUSE_BUTTON_LEFT:
		return
	var width := maxf(_track.size.x, 1.0)
	var t := clampf(button.position.x / width, 0.0, 1.0)
	_seek(roundi(t * float(_total)))


func _label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_color_override(&"font_color", Color(0.91, 0.94, 1))
	return label
