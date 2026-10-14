class_name OptionMenu
extends Container

@onready var _slider = $HBoxContainer/VBoxContainer/HSlider
@onready var _exit = $HBoxContainer/VBoxContainer2/ExitButton

@onready var _audio_bus_idx: int = AudioServer.get_bus_index("Master")

var _slider_max: float

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_slider_max = _slider.max_value
	_slider.value = db_to_linear(AudioServer.get_bus_volume_linear(_audio_bus_idx) * _slider_max)


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(_delta: float) -> void:
	pass


func _make_label(text: String, label_name := &"") -> Label:
	var label := Label.new()
	if label_name != &"":
		label.name = label_name
	label.text = text
	label.add_theme_color_override(&"font_color", Color(0.91, 0.94, 1))
	return label


func _on_h_slider_value_changed(value: float) -> void:
	var vol := linear_to_db(value / _slider_max)
	AudioServer.set_bus_volume_db(_audio_bus_idx, vol)
