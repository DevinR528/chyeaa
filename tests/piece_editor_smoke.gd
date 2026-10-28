extends SceneTree
## Piece editor paint, portals, save round-trip, biome art at room build, and pause.

const Rooms := preload("res://tests/test_room_builder.gd")
const STANDARD_SCENE := preload("res://scenes/player/standard.tscn")
const KIND_TILES := preload("res://resources/tiles/kind_tiles.tres")
const EARTH := preload("res://resources/biomes/earth.tres")
const SCENE_PATH := "user://piece_editor_smoke.tscn"
const DATA_PATH := "user://piece_editor_smoke.tres"

var _failed := false


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_check_paint_portals_and_roundtrip()
	_check_skin()
	_check_pause_row()
	await _check_editor_session()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SCENE_PATH))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(DATA_PATH))
	quit(1 if _failed else 0)


func _check_paint_portals_and_roundtrip() -> void:
	var board := PieceBoard.blank(&"smoke_piece", 16, 12)
	_expect(board.brush_size == 8, "brush did not start at 8")
	board.step_brush(-7)
	_expect(board.brush_size == 1, "brush did not step down to 1")
	board.step_brush(-4)
	_expect(board.brush_size == 1, "brush stepped below 1")
	board.paint_kind = Room.Kind.SOLID
	board.paint_cell(Vector2i(1, 1))
	board.paint_kind = Room.Kind.DEATH
	board.paint_cell(Vector2i(4, 1))
	board.paint_kind = Room.Kind.GRAPPLE
	board.paint_cell(Vector2i(5, 1))
	var wide := PieceBoard.blank(&"wide", 16, 12)
	wide.paint_kind = Room.Kind.SOLID
	wide.paint_cell(Vector2i(0, 0))
	_expect(_solid_count(wide) == 64, "brush 8 painted %d cells" % _solid_count(wide))
	wide.paint_cell(Vector2i(14, 0))
	_expect(_solid_count(wide) == 64 + 16, "brush 8 did not clip, count %d" % _solid_count(wide))

	var kept_entry := board.entry_a
	_expect(
		not board.set_portal(PieceBoard.PortalEnd.ENTRY, Vector2i(3, 2), Vector2i(3, 8)),
		"an interior portal was accepted",
	)
	_expect(board.entry_a == kept_entry, "a rejected portal replaced the entry")
	_expect(
		not board.set_portal(PieceBoard.PortalEnd.ENTRY, Vector2i(0, 0), Vector2i(0, 1)),
		"a short portal was accepted",
	)
	_expect(
		board.set_portal(PieceBoard.PortalEnd.ENTRY, Vector2i(0, 2), Vector2i(0, 5)),
		"a left-edge portal was rejected",
	)
	_expect(board.entry_facing == PieceData.Facing.LEFT, "left edge was not facing left")
	board.set_spawn(Vector2(40, 70))
	var block := board.place_prefab(PieceBoard.Stamp.BLOCK, Vector2(40, 40))
	_expect(board.remove_at(Vector2(8, 8)).is_empty(), "erase removed a block it did not hit")
	_expect(board.selected == block, "a miss cleared the selection")
	var removed := board.remove_selected()
	_expect(removed == "Block", "delete did not remove the block, got %s" % removed)
	_expect(not is_instance_valid(block), "deleted block stayed in the tree")
	_expect(board.remove_selected().is_empty(), "delete worked with nothing selected")
	var mill := board.place_prefab(PieceBoard.Stamp.WINDMILL, Vector2(80, 64))
	_expect(board.set_tuned_value(mill, &"radius", 96.0), "windmill radius was not tunable")
	_expect(board.set_tuned_value(mill, &"turns_per_second", 0.4), "windmill turn speed was not tunable")
	_expect(mill.get_node_or_null(^"Arm") is TileProp, "windmill stamp has no carried block")
	var other := board.place_prefab(PieceBoard.Stamp.WINDMILL, Vector2(200, 64))
	_expect(board.set_tuned_value(other, &"radius", 96.0), "second windmill radius was not tunable")
	var swept := board.remove_at(Vector2(280, 64))
	_expect(swept.begins_with("Windmill"), "a click on the windmill sweep missed, got %s" % swept)
	_expect(not is_instance_valid(other), "the swept windmill stayed in the piece")
	_expect(is_instance_valid(mill), "deleting one windmill removed the other")
	var plain := PieceData.new()
	_expect(not PieceWriter.import_should_keep(null) and not PieceWriter.import_should_keep(plain), "import would keep an unedited piece")

	var error := PieceWriter.save_to(board, SCENE_PATH, DATA_PATH)
	_expect(error.is_empty(), "save failed: %s" % error)
	var data := load(DATA_PATH) as PieceData
	var scene := (load(SCENE_PATH) as PackedScene).instantiate()
	_expect(data.authored_in_editor, "save did not mark the piece as editor-authored")
	_expect(PieceWriter.import_should_keep(data), "import would overwrite an editor piece")
	_expect(data.entry_a == Vector2i(0, 2) and data.entry_b == Vector2i(0, 5), "saved entry portal drifted")
	_expect(data.spawn_feet.is_equal_approx(Vector2(40, 70)), "saved spawn drifted")
	var terrain := scene.get_node(^"Terrain") as TileMapLayer
	var grapple := scene.get_node(^"GrappleSurfaces") as TileMapLayer
	_expect(terrain.get_cell_atlas_coords(Vector2i(1, 1)) == Vector2i(0, 0), "solid cell did not round-trip")
	_expect(terrain.get_cell_atlas_coords(Vector2i(4, 1)) == Vector2i(4, 0), "death cell did not round-trip")
	_expect(grapple.get_cell_atlas_coords(Vector2i(5, 1)) == Vector2i(1, 0), "grapple cell did not round-trip")
	_expect(terrain.get_cell_source_id(Vector2i(1, 1)) != -1, "saved piece lost its kind tile")
	var loaded := scene.get_node(^"Props/Windmill") as TileProp
	_expect(loaded != null and loaded.spin != null, "saved windmill lost its spin")
	_expect(is_equal_approx(loaded.spin.radius, 96.0), "saved radius is %s" % loaded.spin.radius)
	_expect(is_equal_approx(loaded.spin.turns_per_second, 0.4), "saved turn speed is %s" % loaded.spin.turns_per_second)
	_expect((scene.get_node(^"Spawn") as Node2D).position.is_equal_approx(Vector2(40, 70)), "saved spawn marker drifted")
	scene.free()
	board.root.free()
	wide.root.free()


func _check_skin() -> void:
	_expect(EARTH.biome_id == &"earth" and EARTH.tileset == null and EARTH.rules.is_empty(), "earth skin is not an empty stub")
	var board := PieceBoard.blank(&"skin_probe", 8, 8)
	board.brush_size = 1
	board.paint_kind = Room.Kind.SOLID
	board.paint_cell(Vector2i(2, 2))
	board.paint_kind = Room.Kind.DEATH
	board.paint_cell(Vector2i(3, 2))
	var layout := board.play_layout()
	var plain := RoomGenerator.build_room(layout, BiomeSkin.new())
	var terrain := plain.get_node(^"Terrain") as TileMapLayer
	_expect(terrain.tile_set == KIND_TILES, "empty skin swapped the kind tileset")
	_expect(terrain.get_cell_atlas_coords(Vector2i(2, 2)) == Vector2i(0, 0), "empty skin recolored a solid cell")
	_expect(terrain.get_cell_atlas_coords(Vector2i(3, 2)) == Vector2i(4, 0), "empty skin recolored a death cell")
	var generated := RoomGenerator.build_room(layout)
	var generated_terrain := generated.get_node(^"Terrain") as TileMapLayer
	_expect(generated_terrain.get_cell_atlas_coords(Vector2i(2, 2)) == Vector2i(0, 0), "default earth skin recolored a cell")

	var skin := BiomeSkin.new()
	skin.biome_id = &"test"
	skin.tileset = KIND_TILES
	var rule := BiomeSkinRule.new()
	rule.kind = Room.Kind.SOLID
	rule.layer = &"Terrain"
	rule.atlas = Vector2i(5, 0)
	rule.neighbor_mask = -1
	var rules: Array[BiomeSkinRule] = [rule]
	skin.rules = rules
	var skinned := RoomGenerator.build_room(layout, skin)
	var skinned_terrain := skinned.get_node(^"Terrain") as TileMapLayer
	_expect(skinned_terrain.get_cell_atlas_coords(Vector2i(2, 2)) == Vector2i(5, 0), "solid cell was not reskinned")
	_expect(skinned_terrain.get_cell_atlas_coords(Vector2i(3, 2)) == Vector2i(4, 0), "death cell was reskinned")
	plain.free()
	generated.free()
	skinned.free()
	board.root.free()


func _check_pause_row() -> void:
	var ui := RunUI.new()
	root.add_child(ui)
	ui.open_pause()
	var text := ""
	for child in ui._pause_rows.get_children():
		text += (child as Label).text + "\n"
	_expect("Piece editor" in text, "pause menu has no piece editor row")
	_expect(text.find("Restart room") < text.find("Generated run"), "pause row order changed before the editor")
	_expect(text.find("Generated run") < text.find("Piece editor"), "piece editor is not after generated run")
	ui.close_pause()
	ui.free()


func _check_editor_session() -> void:
	var camera := FollowCamera.new()
	var runner := RoomRunner.new()
	runner.camera = camera
	runner.characters = [STANDARD_SCENE]
	runner.character_index = 0
	runner.add_child(camera)
	var room := Rooms.make_room(runner, func(_layers: Dictionary) -> void: pass)
	runner.room = room
	root.add_child(runner)
	await process_frame
	var editor := PieceEditor.new()
	editor.open(runner)
	_expect(editor.active and editor.board != null, "editor did not open")
	_expect(editor.board.brush_size == 8, "opened editor brush was %d" % editor.board.brush_size)
	_expect(runner.room == null, "editor left the live room in the tree")
	var view := runner.get_viewport().get_camera_2d()
	_expect(view != null and view != camera, "editor did not take the view, camera is %s" % view)
	if view != null:
		var canvas_before := runner.get_viewport().get_canvas_transform()
		var wheel := InputEventMouseButton.new()
		wheel.button_index = MOUSE_BUTTON_WHEEL_UP
		wheel.pressed = true
		wheel.position = Vector2(420, 250)
		runner.get_viewport().push_input(wheel)
		var canvas_zoomed := runner.get_viewport().get_canvas_transform()
		_expect(
			canvas_zoomed.get_scale().x > canvas_before.get_scale().x + 0.01,
			"wheel did not zoom the view, scale stayed %s" % canvas_zoomed.get_scale(),
		)
		var held := InputEventMouseButton.new()
		held.button_index = MOUSE_BUTTON_MIDDLE
		held.pressed = true
		held.position = Vector2(420, 250)
		var motion := InputEventMouseMotion.new()
		motion.relative = Vector2(40, 0)
		motion.position = Vector2(460, 250)
		motion.button_mask = MOUSE_BUTTON_MASK_MIDDLE
		var pos_before := view.position
		runner.get_viewport().push_input(held)
		runner.get_viewport().push_input(motion)
		var canvas_panned := runner.get_viewport().get_canvas_transform()
		_expect(
			view.position.distance_to(pos_before) > 1.0,
			"middle drag did not move the camera, position stayed %s" % view.position,
		)
		_expect(
			canvas_panned.origin.distance_to(canvas_zoomed.origin) > 1.0,
			"middle drag did not pan the view, origin stayed %s camera %s" % [canvas_panned.origin, view.position],
		)
	var info := _button_named(editor, "Info")
	_expect(info != null, "editor has no info button")
	if info != null:
		info.pressed.emit()
	var panel := editor.find_child("InfoPanel", true, false) as CanvasItem
	var help := editor.find_child("InfoText", true, false) as Label
	_expect(panel != null and panel.visible, "info did not open")
	_expect(help != null and "Delete" in help.text, "info does not explain delete")
	var placed := editor.board.place_prefab(PieceBoard.Stamp.BLOCK, Vector2(48, 48))
	var delete_key := InputEventKey.new()
	delete_key.keycode = KEY_DELETE
	delete_key.pressed = true
	editor.get_viewport().push_input(delete_key)
	_expect(not is_instance_valid(placed), "delete key left the block in the piece")
	var library_button := _button_named(editor, "cap_start")
	_expect(library_button != null, "library has no cap_start")
	if library_button != null:
		var library := library_button.get_parent()
		var listed := library.get_child_count()
		library_button.pressed.emit()
		_expect(editor.board.piece_id == &"cap_start", "opening cap_start left %s" % editor.board.piece_id)
		_expect(library.get_child_count() == listed, "opening a piece duplicated the library, count %d" % library.get_child_count())
	var kept := editor.board
	editor.playtest()
	_expect(editor.playing and runner.room != null, "playtest did not build a room")
	editor.end_playtest()
	_expect(not editor.playing and editor.board == kept, "playtest replaced the unsaved piece")
	editor.close()
	_expect(not editor.active and runner.room == room, "closing the editor did not restore the room")
	editor.free()
	runner.free()


func _solid_count(board: PieceBoard) -> int:
	var layer := board.root.get_node(^"Terrain") as TileMapLayer
	var count := 0
	for cell in layer.get_used_cells():
		if layer.get_cell_atlas_coords(cell) == Vector2i(0, 0):
			count += 1
	return count


func _button_named(node: Node, text: String) -> Button:
	if node is Button and (node as Button).text == text:
		return node
	for child in node.get_children():
		var found := _button_named(child, text)
		if found != null:
			return found
	return null


func _expect(ok: bool, message: String) -> void:
	if not ok:
		_failed = true
		push_error(message)
