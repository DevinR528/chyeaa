class_name CharacterSprite
extends Sprite2D
## Plays the character's AnimationLibrary (built by `src/tools/sync_art.gd`) from the
## body's state: the clip the ability asks for (its own, or the body's movement clip
## while inactive), else the first `fallback` clip the library has. With no clip to play,
## the placeholder body shows. The pivot is the body's bottom-centre and facing flips around it.

## No clip resolved; the placeholder body is showing.
const NO_CLIP := &""

## A clip was chosen, or NO_CLIP.
signal clip_changed(clip: StringName)
## A frame carrying authored events was entered (footsteps and the like).
signal frame_event(event_name: StringName, clip: StringName, frame_index: int)

@export var placeholder: CanvasItem
## Tried in order when the wanted clip is not in the frames.
@export var fallback: Array[StringName] = []

## Clip being played, or NO_CLIP.
var clip: StringName = NO_CLIP
var _art_scale := 1.0

@onready var body: PlayerBody = get_parent()
@onready var animation_player: AnimationPlayer = $AnimationPlayer


func _ready() -> void:
	centered = false
	region_enabled = true
	# Children are ready before the body, so its @onready `body_shape` is not set yet.
	var shape := body.get_node(^"CollisionShape2D") as CollisionShape2D
	position = shape.position + Vector2(0.0, (shape.shape as RectangleShape2D).size.y / 2.0)
	var library: AnimationLibrary
	if animation_player.has_animation_library(&""):
		library = animation_player.get_animation_library(&"")
	if library != null:
		_art_scale = library.get_meta(&"art_scale", 1.0)
	_show(resolve_clip(), true)


func _process(_delta: float) -> void:
	scale = Vector2(body.facing * _art_scale, _art_scale)
	_show(resolve_clip())


func resolve_clip() -> StringName:
	var wanted := body.movement_clip()
	if body.ability != null:
		wanted = body.ability.animation_clip(wanted)
	if animation_player.has_animation(wanted):
		return wanted
	for name in fallback:
		if animation_player.has_animation(name):
			return name
	return NO_CLIP


func _show(next: StringName, force := false) -> void:
	if next == clip and not force:
		return
	clip = next
	var has_clip := clip != NO_CLIP
	visible = has_clip
	if placeholder != null:
		placeholder.visible = not has_clip
	if has_clip:
		animation_player.play(clip)
		# `play` applies on the next mixer tick; key frame zero now so pivots,
		# textures, and events change atomically with placeholder visibility.
		animation_player.advance(0.0)
	else:
		animation_player.stop()
		texture = null
	clip_changed.emit(clip)


## Called only by generated method keys. Presentation listeners subscribe to the
## signal so generated animation resources never decide how an event sounds.
func _animation_event(event_name: StringName, event_clip: StringName, frame_index: int) -> void:
	frame_event.emit(event_name, event_clip, frame_index)


## The active run clip's footstep marks and AnimationPlayer clock. Empty means
## locomotion should keep its ordinary constant-speed acceleration.
func run_stride() -> Dictionary:
	if clip != &"run" or animation_player.current_animation != &"run":
		return {}
	var animation := animation_player.get_animation(&"run")
	if animation == null or animation.length <= 0.0:
		return {}
	var times: Array[float] = []
	for track_index in animation.get_track_count():
		if animation.track_get_type(track_index) != Animation.TYPE_METHOD:
			continue
		for key_index in animation.track_get_key_count(track_index):
			var call: Dictionary = animation.track_get_key_value(track_index, key_index)
			if call.get("method") != &"_animation_event":
				continue
			var args: Array = call.get("args", [])
			if not args.is_empty() and String(args[0]).begins_with("footstep"):
				times.append(animation.track_get_key_time(track_index, key_index))
	if times.is_empty():
		return {}
	times.sort()
	return {
		"times": times,
		"loop": animation.length,
		"time": animation_player.current_animation_position,
	}
