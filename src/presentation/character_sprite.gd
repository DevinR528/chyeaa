class_name CharacterSprite
extends AnimatedSprite2D
## Plays the character's SpriteFrames (built by `src/tools/sync_art.gd`) from the
## body's state: the clip the ability asks for (its own, or the body's movement clip
## while inactive), else the first `fallback` clip the frames have. With no clip to play,
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
var _events := {}
var _entered_clip: StringName = NO_CLIP
var _entered_frame := -1

@onready var body: PlayerBody = get_parent()


func _ready() -> void:
	centered = false
	# Children are ready before the body, so its @onready `body_shape` is not set yet.
	var shape := body.get_node(^"CollisionShape2D") as CollisionShape2D
	position = shape.position + Vector2(0.0, (shape.shape as RectangleShape2D).size.y / 2.0)
	if sprite_frames != null:
		offset = -sprite_frames.get_meta(&"origin", Vector2.ZERO)
		_art_scale = sprite_frames.get_meta(&"art_scale", 1.0)
		_events = sprite_frames.get_meta(&"frame_events", {})
	frame_changed.connect(_enter_frame)
	_show(resolve_clip(), true)


func _process(_delta: float) -> void:
	scale = Vector2(body.facing * _art_scale, _art_scale)
	_show(resolve_clip())


func resolve_clip() -> StringName:
	if sprite_frames == null:
		return NO_CLIP
	var wanted := body.movement_clip()
	if body.ability != null:
		wanted = body.ability.animation_clip(wanted)
	if sprite_frames.has_animation(wanted):
		return wanted
	for name in fallback:
		if sprite_frames.has_animation(name):
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
		play(clip)
		_enter_frame()
	else:
		stop()
	clip_changed.emit(clip)


## `frame_changed` also fires while switching clips, so the same frame is entered once.
func _enter_frame() -> void:
	if animation == _entered_clip and frame == _entered_frame:
		return
	_entered_clip = animation
	_entered_frame = frame
	var clip_events: Dictionary = _events.get(String(animation), {})
	for event_name in clip_events.get(frame, PackedStringArray()):
		frame_event.emit(StringName(event_name), animation, frame)
