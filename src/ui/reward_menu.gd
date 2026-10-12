class_name RewardMenu
extends CanvasLayer
## Level-clear offer. The only way out is picking one card. Gameplay stays paused
## until `picked` fires; this layer keeps processing.

signal picked(id: RunBuild.Id)

var open := false

var _ids: Array[RunBuild.Id] = []
var _selected := 0
var _cards: Array[Button] = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 40
	_cards = [
		$Root/Panel/Cards/Card0,
		$Root/Panel/Cards/Card1,
		$Root/Panel/Cards/Card2,
	]
	for index in _cards.size():
		_cards[index].pressed.connect(_choose.bind(index))
	$Root.hide()


func open_offer(offer: Array) -> void:
	_ids.clear()
	for id: RunBuild.Id in offer:
		_ids.append(id)
	if _ids.is_empty():
		return
	_selected = 0
	open = true
	for index in _cards.size():
		var card := _cards[index]
		var shown := index < _ids.size()
		card.visible = shown
		if shown:
			var id := _ids[index]
			card.text = "%s\n%s" % [RunBuild.name_of(id), RunBuild.describe(id)]
	_mark()
	($Root as Control).show()


func choose_selected() -> void:
	_choose(_selected)


func _choose(index: int) -> void:
	if not open or index < 0 or index >= _ids.size():
		return
	var id := _ids[index]
	open = false
	($Root as Control).hide()
	picked.emit(id)


func _process(_delta: float) -> void:
	if not open or _ids.is_empty():
		return
	if Input.is_action_just_pressed(&"move_left") or Input.is_action_just_pressed(&"move_up"):
		_selected = posmod(_selected - 1, _ids.size())
		_mark()
	elif Input.is_action_just_pressed(&"move_right") or Input.is_action_just_pressed(&"move_down"):
		_selected = posmod(_selected + 1, _ids.size())
		_mark()
	elif Input.is_action_just_pressed(&"jump"):
		_choose(_selected)


func _mark() -> void:
	for index in _cards.size():
		_cards[index].modulate = Color(1, 1, 1) if index == _selected else Color(0.65, 0.65, 0.7)
