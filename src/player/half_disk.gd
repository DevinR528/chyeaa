class_name HalfDisk
extends RefCounted
## A half circle on the side `facing` points to (one of the four cardinal unit vectors).
## The pogo slash hitbox; the flat edge passes through `center`.

var center: Vector2
var radius: float
var facing: Vector2


func _init(disk_center: Vector2, disk_radius: float, disk_facing: Vector2) -> void:
	center = disk_center
	radius = disk_radius
	facing = disk_facing


func overlaps_rect(rect: Rect2) -> bool:
	var left := rect.position.x
	var right := rect.end.x
	var top := rect.position.y
	var bottom := rect.end.y
	if facing == Vector2.DOWN:
		top = maxf(top, center.y)
	elif facing == Vector2.UP:
		bottom = minf(bottom, center.y)
	elif facing == Vector2.LEFT:
		right = minf(right, center.x)
	else:
		left = maxf(left, center.x)
	if left >= right or top >= bottom:
		return false
	var closest := Vector2(clampf(center.x, left, right), clampf(center.y, top, bottom))
	return center.distance_squared_to(closest) <= radius * radius


## Convex outline around the centre, for a physics shape query.
func convex_points(segments := 16) -> PackedVector2Array:
	var start_angle := facing.angle() - PI / 2.0
	var points := PackedVector2Array()
	for step in segments + 1:
		points.append(Vector2.from_angle(start_angle + PI * float(step) / float(segments)) * radius)
	return points


## World-space bounds of the half circle.
func bounds() -> Rect2:
	var full := Rect2(center - Vector2(radius, radius), Vector2(radius, radius) * 2.0)
	if facing == Vector2.DOWN:
		return Rect2(full.position.x, center.y, full.size.x, radius)
	if facing == Vector2.UP:
		return Rect2(full.position.x, full.position.y, full.size.x, radius)
	if facing == Vector2.LEFT:
		return Rect2(full.position.x, full.position.y, radius, full.size.y)
	return Rect2(center.x, full.position.y, radius, full.size.y)


#region Drawing
# Used by the placeholder pogo slash and by the reach overlay; the overlay keeps
# this once strike animations replace the placeholder.

## Arc points from one end of the flat edge to the other, in the same space as `center`.
func arc_points(segments := 16) -> PackedVector2Array:
	var start_angle := facing.angle() - PI / 2.0
	var points := PackedVector2Array()
	for step in segments + 1:
		points.append(center + Vector2.from_angle(start_angle + PI * step / segments) * radius)
	return points

#endregion
