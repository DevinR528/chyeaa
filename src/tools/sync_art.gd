extends SceneTree
## Ongoing pixel-art translation from the prototype's ../assets into Godot. The JS
## game still reads ../assets, so this copies only what Godot uses: the sheets
## every animation in art/index.json plays, the backdrop layer images, the
## shader textures those layers sample, and the tile sheets in tilesets/index.json.
## Then it rebuilds one SpriteFrames per animation next to its sheets.
##
## Re-run after exporting art from the pixel app. Generated SpriteFrames are
## rebuilt from the anim documents; a SpriteFrames edited in Godot since the last
## sync stops the sync instead of being overwritten.
##
## Run from lil-guy/:
##   godot --headless --path . --script res://src/tools/sync_art.gd

const SOURCE_ROOT := "../assets"
const ART_INDEX := "art/index.json"
const BACKGROUNDS_DIR := "backgrounds"
const SHADERS_DIR := "shaders"
const TILESETS_INDEX := "tilesets/index.json"
const DEST_ROOT := "res://assets"
const SPRITE_FRAMES_SUFFIX := ".sprite_frames.tres"

## SpriteFrames metadata the sprite node reads.
const META_ORIGIN := &"origin"
const META_SCALE := &"art_scale"
const META_EVENTS := &"frame_events"
## What this tool wrote, so a re-sync can tell a hand edit from its own output.
const META_FINGERPRINT := &"sync_fingerprint"


func _initialize() -> void:
	quit(_sync())


func _sync() -> int:
	var anims := _read_anims()
	var copies := {}
	for anim: Dictionary in anims:
		for clip_name: String in anim.doc.clips:
			copies[_clip_sheet(anim, anim.doc.clips[clip_name])] = true
	for image: String in _backdrop_images() + _tileset_images():
		copies[image] = true

	var changed := 0
	for source: String in copies:
		var result := _copy(source)
		if result < 0:
			return 1
		changed += result
	if changed > 0 and not _reimport():
		return 1

	for anim: Dictionary in anims:
		if not _save_sprite_frames(anim):
			return 1
	print("Synced %d files (%d changed) and %d animations." % [copies.size(), changed, anims.size()])
	return 0


## Each entry: { id, doc, json } where `json` is the doc's path under SOURCE_ROOT.
func _read_anims() -> Array[Dictionary]:
	var anims: Array[Dictionary] = []
	var index: Dictionary = _read_json(ART_INDEX)
	for entry: Dictionary in index.get("anims", []):
		var json := "art/" + String(entry.path)
		var doc: Dictionary = _read_json(json)
		if doc.is_empty():
			continue
		anims.append({id = String(entry.id), doc = doc, json = json})
	return anims


## Layer images and the shader textures their effects sample.
func _backdrop_images() -> Array[String]:
	var images: Array[String] = []
	var dir := _source_path(BACKGROUNDS_DIR)
	for file in DirAccess.get_files_at(dir):
		if not file.ends_with(".json"):
			continue
		var json := BACKGROUNDS_DIR.path_join(file)
		var doc: Dictionary = _read_json(json)
		for layer: Dictionary in doc.get("layers", []):
			images.append(_resolve(String(layer.image), json))
			for effect: Dictionary in layer.get("effects", []):
				images.append_array(_shader_textures(String(effect.shader)))
	return images


## Tile sheets. The TileSets using them are authored in Godot, so a sheet whose
## pieces move needs its TileSet atlas updated by hand.
func _tileset_images() -> Array[String]:
	var images: Array[String] = []
	for entry: Dictionary in _read_json_array(TILESETS_INDEX):
		images.append("art/%s/%s.png" % [entry.art, entry.art])
	return images


func _shader_textures(shader: String) -> Array[String]:
	var textures: Array[String] = []
	var json := SHADERS_DIR.path_join(shader + ".shader.json")
	if not FileAccess.file_exists(_source_path(json)):
		return textures
	var doc: Dictionary = _read_json(json)
	for sampler: String in doc.get("textures", {}):
		textures.append(SHADERS_DIR.path_join(String(doc.textures[sampler].image)))
	return textures


## Returns 1 when the file was written, 0 when it was already current, -1 on error.
func _copy(source: String) -> int:
	var bytes := FileAccess.get_file_as_bytes(_source_path(source))
	if bytes.is_empty():
		push_error("Missing source art: %s" % _source_path(source))
		return -1
	var dest := DEST_ROOT.path_join(source)
	if FileAccess.file_exists(dest) and FileAccess.get_file_as_bytes(dest) == bytes:
		return 0
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dest.get_base_dir()))
	var file := FileAccess.open(dest, FileAccess.WRITE)
	if file == null:
		push_error("Could not write %s: %s" % [dest, error_string(FileAccess.get_open_error())])
		return -1
	file.store_buffer(bytes)
	return 1


## New or changed PNGs must be imported before they can be loaded as textures.
func _reimport() -> bool:
	var output := []
	var code := OS.execute(OS.get_executable_path(), ["--headless", "--path", ProjectSettings.globalize_path("res://"), "--import"], output, true)
	if code != 0:
		push_error("Import failed (%d): %s" % [code, "\n".join(output)])
		return false
	return true


## Every clip is drawn on one shared canvas with one origin, so the sprite node
## keeps a single offset however the clips' frame sizes and pivots differ.
func _save_sprite_frames(anim: Dictionary) -> bool:
	var doc: Dictionary = anim.doc
	var origin := Vector2.ZERO
	var canvas := Vector2.ZERO
	for clip: Dictionary in doc.clips.values():
		origin = origin.max(_clip_origin(doc, clip))
	for clip: Dictionary in doc.clips.values():
		canvas = canvas.max(origin - _clip_origin(doc, clip) + _clip_frame_size(doc, clip))

	var frames := SpriteFrames.new()
	frames.remove_animation(&"default")
	var events := {}
	for clip_name: String in doc.clips:
		var clip: Dictionary = doc.clips[clip_name]
		var sheet_path := DEST_ROOT.path_join(_clip_sheet(anim, clip))
		var sheet := load(sheet_path) as Texture2D
		if sheet == null:
			push_error("%s: could not load %s" % [anim.id, sheet_path])
			return false
		if not (clip.get("effects", []) as Array).is_empty():
			push_warning("%s.%s: clip shader effects are not translated yet" % [anim.id, clip_name])
		var frame_size := _clip_frame_size(doc, clip)
		var columns := int(clip.get("columns", doc.get("columns", floori(sheet.get_width() / frame_size.x))))
		var margin := Rect2(origin - _clip_origin(doc, clip), canvas - frame_size)
		var fallback_duration := 1.0 / float(clip.fps)
		# Speed 1 FPS makes each frame's duration plain seconds, as in the anim document.
		frames.add_animation(clip_name)
		frames.set_animation_speed(clip_name, 1.0)
		frames.set_animation_loop(clip_name, clip.get("loop", true) != false)
		var clip_events := {}
		var raw_frames: Array = clip.frames
		for index in raw_frames.size():
			var frame: Variant = raw_frames[index]
			var cell := int(frame) if frame is float else int(frame.cell)
			var atlas := AtlasTexture.new()
			atlas.atlas = sheet
			atlas.region = Rect2(Vector2(cell % columns, cell / columns) * frame_size, frame_size)
			atlas.margin = margin
			var duration := fallback_duration if frame is float else float(frame.get("duration", fallback_duration))
			frames.add_frame(clip_name, atlas, duration)
			if frame is Dictionary and not (frame.get("events", []) as Array).is_empty():
				clip_events[index] = PackedStringArray(frame.events)
		if not clip_events.is_empty():
			events[clip_name] = clip_events

	frames.set_meta(META_ORIGIN, origin)
	frames.set_meta(META_SCALE, float(doc.get("scale", 1.0)))
	frames.set_meta(META_EVENTS, events)
	frames.set_meta(META_FINGERPRINT, _fingerprint(frames))
	var path := DEST_ROOT.path_join("art").path_join(anim.id).path_join(String(anim.id) + SPRITE_FRAMES_SUFFIX)
	if _edited_since_sync(path):
		push_error("%s was edited in Godot since the last sync. Move the change into %s (or the pixel app), or delete the .tres, then sync again." % [path, anim.json])
		return false
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	var error := ResourceSaver.save(frames, path)
	if error != OK:
		push_error("Could not save %s: %s" % [path, error_string(error)])
		return false
	return true


## True when the saved SpriteFrames no longer matches what the last sync wrote.
## Files from before the fingerprint existed are treated as unedited.
func _edited_since_sync(path: String) -> bool:
	if not FileAccess.file_exists(path):
		return false
	var saved := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as SpriteFrames
	if saved == null or not saved.has_meta(META_FINGERPRINT):
		return false
	return saved.get_meta(META_FINGERPRINT) != _fingerprint(saved)


## Hash of everything a sync writes that the SpriteFrames editor can change.
func _fingerprint(frames: SpriteFrames) -> int:
	var parts := []
	var names := frames.get_animation_names()
	names.sort()
	for clip_name in names:
		parts.append([clip_name, frames.get_animation_loop(clip_name), frames.get_animation_speed(clip_name)])
		for index in frames.get_frame_count(clip_name):
			var texture := frames.get_frame_texture(clip_name, index)
			var atlas := texture as AtlasTexture
			parts.append([
				frames.get_frame_duration(clip_name, index),
				atlas.atlas.resource_path if atlas != null and atlas.atlas != null else texture.resource_path if texture != null else "",
				atlas.region if atlas != null else Rect2(),
				atlas.margin if atlas != null else Rect2(),
			])
	return var_to_str(parts).hash()


func _clip_sheet(anim: Dictionary, clip: Dictionary) -> String:
	return _resolve(String(clip.get("sheet", anim.doc.sheet)), anim.json)


func _clip_frame_size(doc: Dictionary, clip: Dictionary) -> Vector2:
	return Vector2(clip.get("frame_w", doc.frame_w), clip.get("frame_h", doc.frame_h)).floor()


## A clip's own pivot, else the set's, else the frame's bottom centre.
func _clip_origin(doc: Dictionary, clip: Dictionary) -> Vector2:
	var size := _clip_frame_size(doc, clip)
	return Vector2(
		clip.get("origin_x", doc.get("origin_x", size.x / 2.0)),
		clip.get("origin_y", doc.get("origin_y", size.y)),
	)


## Prototype URLs: `/x` is under SOURCE_ROOT (Vite's public dir); anything else is
## relative to the document at `from`.
func _resolve(url: String, from: String) -> String:
	if url.begins_with("/"):
		return url.trim_prefix("/")
	return from.get_base_dir().path_join(url)


func _source_path(relative: String) -> String:
	return ProjectSettings.globalize_path("res://").path_join(SOURCE_ROOT).path_join(relative).simplify_path()


func _read_json_array(relative: String) -> Array:
	var path := _source_path(relative)
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Array:
		push_error("Could not read a JSON list from %s" % path)
		return []
	return parsed


func _read_json(relative: String) -> Dictionary:
	var path := _source_path(relative)
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary:
		push_error("Could not read JSON from %s" % path)
		return {}
	return parsed
