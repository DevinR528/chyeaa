extends SceneTree
## Art translation and presentation: synced SpriteFrames match their anim
## documents, character sprites pick clips like the prototype's bind files, and
## backdrop layers land where the prototype's placement put them.

const Rooms := preload("res://tests/test_room_builder.gd")
const SYNC_ART := preload("res://src/tools/sync_art.gd")
const STANDARD_SCENE := preload("res://scenes/player/standard.tscn")
const GRAPPLER_SCENE := preload("res://scenes/player/grappler.tscn")
const POGO_SCENE := preload("res://scenes/player/pogo.tscn")
const BACKDROP_SCENE := preload("res://scenes/backgrounds/eroded_earth.tscn")
const MAIN_SCENE := preload("res://scenes/main.tscn")
const FLOOR_ROW := Rooms.FLOOR_ROW
const TILE := Rooms.TILE
const VIEW := Vector2(840, 504)

var _failed := false


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_check_sprite_frames_match_documents()
	await _check_pogo_sprite()
	await _check_grappler_and_standard_sprites()
	_check_backdrop_placement()
	await _check_backdrop_follows_camera()
	quit(1 if _failed else 0)


func _check_sprite_frames_match_documents() -> void:
	var source := ProjectSettings.globalize_path("res://").path_join(SYNC_ART.SOURCE_ROOT)
	var index: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(source.path_join(SYNC_ART.ART_INDEX)))
	for entry: Dictionary in index.anims:
		var doc: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(source.path_join("art").path_join(entry.path)))
		var path := "res://assets/art/%s/%s%s" % [entry.id, entry.id, SYNC_ART.SPRITE_FRAMES_SUFFIX]
		var frames := load(path) as SpriteFrames
		if frames == null:
			_expect(false, "%s was not generated; run src/tools/sync_art.gd" % path)
			continue
		var origin: Vector2 = frames.get_meta(SYNC_ART.META_ORIGIN)
		for clip_name: String in doc.clips:
			var clip: Dictionary = doc.clips[clip_name]
			var label := "%s.%s" % [entry.id, clip_name]
			if not frames.has_animation(clip_name):
				_expect(false, "%s is missing" % label)
				continue
			_expect(frames.get_frame_count(clip_name) == clip.frames.size(), "%s has the wrong frame count" % label)
			_expect(frames.get_animation_loop(clip_name) == clip.get("loop", true), "%s loop does not match" % label)
			var clip_origin := Vector2(
				clip.get("origin_x", doc.get("origin_x", clip.get("frame_w", doc.frame_w) / 2.0)),
				clip.get("origin_y", doc.get("origin_y", clip.get("frame_h", doc.frame_h))),
			)
			for frame_index in clip.frames.size():
				var frame: Dictionary = clip.frames[frame_index]
				var atlas := frames.get_frame_texture(clip_name, frame_index) as AtlasTexture
				_expect(
					is_equal_approx(frames.get_frame_duration(clip_name, frame_index) / frames.get_animation_speed(clip_name), frame.duration),
					"%s frame %d duration differs from the document" % [label, frame_index],
				)
				_expect(
					(atlas.margin.position + clip_origin).is_equal_approx(origin),
					"%s frame %d pivot does not land on the shared origin" % [label, frame_index],
				)


func _check_pogo_sprite() -> void:
	var room := Rooms.make_room(root, func(_layers: Dictionary) -> void: pass)
	var player := Rooms.spawn_player(root, room, POGO_SCENE, Vector2(80, FLOOR_ROW * TILE))
	var sprite := player.get_node(^"CharacterSprite") as CharacterSprite
	var placeholder := player.get_node(^"PlaceholderBody") as CanvasItem
	var strike := player.ability as PogoStrike
	player.frozen = true
	var events: Array[StringName] = []
	sprite.frame_event.connect(func(event_name: StringName, _clip: StringName, _frame: int) -> void: events.append(event_name))

	player.move_state = PlayerBody.MovementState.IDLE
	await _next_frame()
	_expect(sprite.clip == &"idle" and sprite.visible and not placeholder.visible, "pogo standing still did not play idle over the placeholder")
	var feet := player.body_rect().end - Vector2(player.body_rect().size.x / 2.0, 0.0)
	_expect(sprite.global_position.is_equal_approx(feet), "sprite pivot %s is not the body's bottom-centre %s" % [sprite.global_position, feet])
	_expect(sprite.offset == -sprite.sprite_frames.get_meta(SYNC_ART.META_ORIGIN), "sprite offset does not put the art origin on the pivot")

	player.facing = -1.0
	player.move_state = PlayerBody.MovementState.RUN
	await _next_frame()
	_expect(sprite.clip == &"run" and sprite.scale.x < 0.0, "running left did not play a flipped run")
	_expect(events == [&"footstep_right"], "entering run did not fire its first frame's footstep: %s" % [events])
	sprite.frame = 4
	_expect(events.back() == &"footstep_left", "run frame 4 did not fire footstep_left")

	player.move_state = PlayerBody.MovementState.JUMP
	await _next_frame()
	_expect(sprite.clip == CharacterSprite.NO_CLIP and not sprite.visible and placeholder.visible, "pogo has no jump clip and no fallback, so the placeholder should show")

	player.move_state = PlayerBody.MovementState.IDLE
	strike.state = PogoStrike.State.STRIKE
	strike.strike_direction = PogoStrike.StrikeDirection.LEFT
	_expect(strike.animation_clip(&"idle") == &"strike_side", "a left strike should ask for strike_side")
	await _next_frame()
	_expect(sprite.clip == CharacterSprite.NO_CLIP, "a strike without a strike clip should not fall back to the movement clip")
	await _free(room, player)


func _check_grappler_and_standard_sprites() -> void:
	var room := Rooms.make_room(root, func(_layers: Dictionary) -> void: pass)
	var grappler := Rooms.spawn_player(root, room, GRAPPLER_SCENE, Vector2(80, FLOOR_ROW * TILE))
	var sprite := grappler.get_node(^"CharacterSprite") as CharacterSprite
	grappler.frozen = true
	grappler.move_state = PlayerBody.MovementState.IDLE
	await _next_frame()
	_expect(sprite.clip == &"idle", "grappler standing still did not play octo idle")
	(grappler.ability as Grapple).state = Grapple.State.ATTACHED
	await _next_frame()
	_expect(sprite.clip == CharacterSprite.NO_CLIP, "grappling asks for a grapple clip the octo set does not have")
	grappler.free()

	var standard := Rooms.spawn_player(root, room, STANDARD_SCENE, Vector2(80, FLOOR_ROW * TILE))
	await _next_frame()
	_expect(not standard.get_node(^"CharacterSprite").visible and standard.get_node(^"PlaceholderBody").visible, "standard has no art and should show the placeholder")
	await _free(room, standard)


func _check_backdrop_placement() -> void:
	var backdrop := BACKDROP_SCENE.instantiate() as Backdrop
	root.add_child(backdrop)
	var room_rect := Rect2(-96, 40, 2400, 960)
	backdrop.frame(room_rect, VIEW)
	var cameras: Array[Vector2] = [Vector2.ZERO, Vector2(310, 125), room_rect.size - VIEW, Vector2(1777, 13)]
	for layer in backdrop.layers():
		for camera in cameras:
			var top_left := room_rect.position + camera
			layer.screen_offset = top_left
			var screen := layer.position - top_left
			var expected := _prototype_first_tile(layer, camera, room_rect.size)
			_expect(screen.distance_to(expected) < 0.01, "%s at camera %s drew at %s, prototype %s" % [layer.name, camera, screen, expected])
	backdrop.free()


## The prototype's `layer_placement`, at camera scale 1: the screen top-left of the
## plate, or of the first repeat tile at or left of the view's edge.
func _prototype_first_tile(layer: BackdropLayer, camera: Vector2, level: Vector2) -> Vector2:
	var size := layer.plate.texture.get_size()
	var scroll := layer.scroll_scale
	var at := -camera * scroll
	if layer.anchor == BackdropLayer.Anchor.BOTTOM:
		var floor_camera_y := level.y - VIEW.y
		at.y = VIEW.y - size.y + (floor_camera_y - camera.y) * scroll.y
	if layer.repeat_x:
		at.x -= ceilf(at.x / size.x) * size.x
	return at


func _check_backdrop_follows_camera() -> void:
	var main := MAIN_SCENE.instantiate() as RoomRunner
	root.add_child(main)
	_expect(main.backdrop.get_index() < main.room.get_index(), "the backdrop must draw before the room")
	var backdrop_top: int = _z_values(main.backdrop).max()
	var room_bottom: int = _z_values(main.room).min()
	_expect(backdrop_top < room_bottom, "the backdrop (z up to %d) must draw below every room item (z from %d)" % [backdrop_top, room_bottom])
	for _frame in 10:
		await physics_frame
	var top_left := main.camera.get_screen_center_position() - VIEW / 2.0
	for layer in main.backdrop.layers():
		_expect(layer.screen_offset.distance_to(top_left) <= 1.0, "%s does not follow the camera (%s vs %s)" % [layer.name, layer.screen_offset, top_left])
	main.queue_free()
	await process_frame


## Effective z_index of every CanvasItem in `node`'s subtree.
func _z_values(node: Node) -> Array[int]:
	var found: Array[int] = []
	if node is CanvasItem:
		found.append(_effective_z(node))
	for child in node.get_children():
		found.append_array(_z_values(child))
	return found


func _effective_z(item: CanvasItem) -> int:
	var z := 0
	var at: Node = item
	while at is CanvasItem:
		z += at.z_index
		if not at.z_as_relative:
			break
		at = at.get_parent()
	return clampi(z, RenderingServer.CANVAS_ITEM_Z_MIN, RenderingServer.CANVAS_ITEM_Z_MAX)


## `process_frame` fires before nodes process, so wait for the frame after it.
func _next_frame() -> void:
	await process_frame
	await process_frame


func _free(room: Room, player: PlayerBody) -> void:
	player.free()
	room.free()
	await process_frame


func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	_failed = true
	push_error(message)
