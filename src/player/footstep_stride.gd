class_name FootstepStride
extends RefCounted
## Pure timing and speed curve for Pogo's footstep-shaped ground run.

const RISE := 0.12
const STALL := 0.8
const PEAK := 1.2


## Returns `{u, span}` where `u` is 0 on a footstep and approaches 1 at
## the next mark. Times outside the clip wrap around its loop.
static func phase(time: float, times: Array[float], loop: float) -> Dictionary:
	if times.is_empty() or loop <= 0.0:
		return {"u": 0.0, "span": 0.0}
	var wrapped := fposmod(time, loop)
	var previous: float = times.back() - loop
	var next: float = times.front() + loop
	for mark in times:
		if mark <= wrapped:
			previous = mark
		else:
			next = mark
			break
	var span: float = next - previous
	if span <= 0.0:
		return {"u": 0.0, "span": 0.0}
	return {"u": clampf((wrapped - previous) / span, 0.0, 1.0), "span": span}


static func scale(u: float) -> float:
	var x := u / RISE if u < RISE else 1.0 - (u - RISE) / (1.0 - RISE)
	var t := clampf(x, 0.0, 1.0)
	var smooth := t * t * (3.0 - 2.0 * t)
	return STALL + (PEAK - STALL) * smooth


## Acceleration that can follow smoothstep's steepest part during the rise.
static func acceleration(max_run: float, span: float) -> float:
	var rise_seconds := maxf(RISE * span, 0.0001)
	return 1.5 * (PEAK - STALL) * max_run / rise_seconds
