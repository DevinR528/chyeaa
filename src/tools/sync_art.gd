extends SceneTree
## Ongoing pixel-art translation from the authoring repo's ../idea/assets into Godot.
## The TypeScript game still reads that tree, so this copies only what Godot uses: the sheets
## every animation in art/index.json plays, the backdrop layer images, the
## shader textures those layers sample, and the tile sheets in tilesets/index.json.
## Then it rebuilds one AnimationLibrary per animation next to its sheets.
##
## Re-run after exporting art from the pixel app. Imported tracks are regenerated
## from the anim documents; tracks added by hand are left in place.
##
## Run from the repo root:
##   godot --headless --path . --script res://src/tools/sync_art.gd

const SOURCE_ROOT := "../idea/assets"
const ART_INDEX := "art/index.json"
const BACKGROUNDS_DIR := "backgrounds"
const SHADERS_DIR := "shaders"
const TILESETS_INDEX := "tilesets/index.json"
const USED_AUDIO: Array[String] = [
	"audio/fanfare.ogg",
	"audio/bash.ogg",
	"audio/footstep.wav",
	"audio/footstep_cane.wav",
	"audio/jump_land.wav",
]
## Godot 4.7 does not import the prototype's FLAC files. Their PCM WAV
## conversions are committed as `audio/dash2.wav` and `audio/bird_poo.wav`.
const DEST_ROOT := "res://assets"
const ANIMATION_LIBRARY_SUFFIX := ".animation_library.tres"

## AnimationLibrary metadata the sprite node reads.
const META_SCALE := &"art_scale"
const EVENT_METHOD := &"_animation_event"


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
	for audio: String in USED_AUDIO:
		copies[audio] = true

	var changed := 0
	for source: String in copies:
		var result := _copy(source)
		if result < 0:
			return 1
		changed += result
	if changed > 0 and not _reimport():
		return 1

	for anim: Dictionary in anims:
		if not _save_animation_library(anim):
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


func _save_animation_library(anim: Dictionary) -> bool:
	var path := DEST_ROOT.path_join("art").path_join(anim.id).path_join(String(anim.id) + ANIMATION_LIBRARY_SUFFIX)
	var library: AnimationLibrary
	if FileAccess.file_exists(path):
		library = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as AnimationLibrary
	if library == null:
		library = AnimationLibrary.new()
	if not _build_animation_library(anim, library):
		return false
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	var error := ResourceSaver.save(library, path)
	if error != OK:
		push_error("Could not save %s: %s" % [path, error_string(error)])
		return false
	return true


## Replaces only the texture/region/pivot and generated event tracks. Other
## properties and method tracks are authored work and survive every sync.
static func _build_animation_library(anim: Dictionary, library: AnimationLibrary) -> bool:
	var doc: Dictionary = anim.doc
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
		var fallback_duration := 1.0 / float(clip.fps)
		var animation: Animation
		if library.has_animation(clip_name):
			animation = library.get_animation(clip_name)
		if animation == null:
			animation = Animation.new()
			library.add_animation(clip_name, animation)
		for track_index in range(animation.get_track_count() - 1, -1, -1):
			if _is_generated_track(animation, track_index):
				animation.remove_track(track_index)
		animation.loop_mode = Animation.LOOP_LINEAR if clip.get("loop", true) != false else Animation.LOOP_NONE
		var texture_track := _add_value_track(animation, ^".:texture")
		var region_track := _add_value_track(animation, ^".:region_rect")
		var offset_track := _add_value_track(animation, ^".:offset")
		var stride_track := -1
		var stride_offsets := _footstep_stride_offsets(clip.frames)
		if stride_offsets.any(func(value: float) -> bool: return not is_zero_approx(value)):
			stride_track = _add_value_track(animation, ^".:visual_stride_offset")
		var event_track := -1
		var time := 0.0
		var raw_frames: Array = clip.frames
		for index in raw_frames.size():
			var frame: Variant = raw_frames[index]
			var cell := int(frame) if frame is float else int(frame.cell)
			var region := Rect2(Vector2(cell % columns, cell / columns) * frame_size, frame_size)
			var duration := fallback_duration if frame is float else float(frame.get("duration", fallback_duration))
			animation.track_insert_key(texture_track, time, sheet)
			animation.track_insert_key(region_track, time, region)
			animation.track_insert_key(offset_track, time, -_clip_origin(doc, clip))
			if stride_track >= 0:
				animation.track_insert_key(stride_track, time, stride_offsets[index])
			if frame is Dictionary:
				for event_name: String in frame.get("events", []):
					if event_track < 0:
						event_track = animation.add_track(Animation.TYPE_METHOD)
						animation.track_set_path(event_track, ^".")
					animation.track_insert_key(event_track, time, {
						"method": EVENT_METHOD,
						"args": [StringName(event_name), StringName(clip_name), index],
					})
			time += duration
		animation.length = time

	library.set_meta(META_SCALE, float(doc.get("scale", 1.0)))
	return true


static func _add_value_track(animation: Animation, property: NodePath) -> int:
	var track := animation.add_track(Animation.TYPE_VALUE)
	animation.track_set_path(track, property)
	animation.value_track_set_update_mode(track, Animation.UPDATE_DISCRETE)
	return track


static func _is_generated_track(animation: Animation, track: int) -> bool:
	if animation.track_is_imported(track):
		return true
	var path := animation.track_get_path(track)
	if animation.track_get_type(track) == Animation.TYPE_VALUE:
		return path in [^".:texture", ^".:region_rect", ^".:offset", ^".:visual_stride_offset"]
	if animation.track_get_type(track) != Animation.TYPE_METHOD or animation.track_get_key_count(track) == 0:
		return false
	for key in animation.track_get_key_count(track):
		var call: Dictionary = animation.track_get_key_value(track, key)
		if call.get("method") != EVENT_METHOD:
			return false
	return true


## Hold the drawing one and two pixels behind the body on the two animation
## frames before each plant, then catch up on its footstep frame.
static func _footstep_stride_offsets(frames: Array) -> Array[float]:
	var offsets: Array[float] = []
	offsets.resize(frames.size())
	offsets.fill(0.0)
	for plant in frames.size():
		var frame: Variant = frames[plant]
		if not frame is Dictionary:
			continue
		var events: Array = frame.get("events", [])
		if not events.any(func(event: String) -> bool: return event.begins_with("footstep")):
			continue
		for frames_before in range(1, mini(2, frames.size() - 1) + 1):
			var index := posmod(plant - frames_before, frames.size())
			offsets[index] = minf(offsets[index], -float(3 - frames_before))
	return offsets


static func _clip_sheet(anim: Dictionary, clip: Dictionary) -> String:
	return _resolve(String(clip.get("sheet", anim.doc.sheet)), anim.json)


static func _clip_frame_size(doc: Dictionary, clip: Dictionary) -> Vector2:
	return Vector2(clip.get("frame_w", doc.frame_w), clip.get("frame_h", doc.frame_h)).floor()


## A clip's own pivot, else the set's, else the frame's bottom centre.
static func _clip_origin(doc: Dictionary, clip: Dictionary) -> Vector2:
	var size := _clip_frame_size(doc, clip)
	return Vector2(
		clip.get("origin_x", doc.get("origin_x", size.x / 2.0)),
		clip.get("origin_y", doc.get("origin_y", size.y)),
	)


## Prototype URLs: `/x` is under SOURCE_ROOT (Vite's public dir); anything else is
## relative to the document at `from`.
static func _resolve(url: String, from: String) -> String:
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
