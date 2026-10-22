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
## Keyed before foot plants; negative trails behind the body's facing direction.
var visual_stride_offset := 0.0:
	set(value):
		visual_stride_offset = value
		if is_node_ready():
			position = _body_pivot + Vector2(body.facing * visual_stride_offset, 0.0)
var _art_scale := 1.0
var _body_pivot := Vector2.ZERO

@onready var body: PlayerBody = get_parent()
@onready var animation_player: AnimationPlayer = $AnimationPlayer


func _ready() -> void:
	centered = false
	region_enabled = true
	# Children are ready before the body, so its @onready `body_shape` is not set yet.
	var shape := body.get_node(^"CollisionShape2D") as CollisionShape2D
	_body_pivot = shape.position + Vector2(0.0, (shape.shape as RectangleShape2D).size.y / 2.0)
	position = _body_pivot
	var library: AnimationLibrary
	if animation_player.has_animation_library(&""):
		library = animation_player.get_animation_library(&"")
	if library != null:
		_art_scale = library.get_meta(&"art_scale", 1.0)
	_show(resolve_clip(), true)


func _process(_delta: float) -> void:
	scale = Vector2(body.facing * _art_scale, _art_scale)
	position = _body_pivot + Vector2(body.facing * visual_stride_offset, 0.0)
	_show(resolve_clip())


func resolve_clip() -> StringName:
	var wanted := body.movement_clip()
	if body.ability != null:
		wanted = body.ability.animation_clip(wanted)
	if animation_player.has_animation(wanted):
		return wanted
	for n in fallback:
		if animation_player.has_animation(n):
			return n
	return NO_CLIP


func _show(next: StringName, force := false) -> void:
	if next == clip and not force:
		return
	clip = next
	var has_clip := clip != NO_CLIP
	visible = has_clip
	if placeholder != null:
		placeholder.visible = not has_clip
	visual_stride_offset = 0.0
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
