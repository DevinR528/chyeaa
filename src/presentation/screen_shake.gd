class_name ScreenShake
extends RefCounted
## Wall-time screen-pixel camera offset with quadratic decay.

const DEFAULT_FREQUENCY := 30.0
const TAU := PI * 2.0

var offset := Vector2.ZERO
var elapsed := 0.0
var duration := 0.0
var amplitude := 0.0
var frequency := DEFAULT_FREQUENCY
var direction := Vector2.ZERO
var _phase_x := 0.0
var _phase_y := 0.0


func is_active() -> bool:
	return elapsed < duration


func strength() -> float:
	if not is_active():
		return 0.0
	var remaining := 1.0 - elapsed / duration
	return amplitude * remaining * remaining


## A weaker request than the current eased strength does not replace it.
func request(seconds: float, peak: float, hz := DEFAULT_FREQUENCY, shake_direction := Vector2.ZERO) -> void:
	if peak < strength():
		return
	elapsed = 0.0
	duration = maxf(0.0, seconds)
	amplitude = peak
	frequency = hz
	direction = shake_direction.normalized()
	_phase_x = 0.0 if not direction.is_zero_approx() else randf() * TAU
	_phase_y = randf() * TAU


func tick(delta: float) -> void:
	if not is_active():
		offset = Vector2.ZERO
		return
	elapsed += delta
	var eased := strength()
	var wave := TAU * frequency * elapsed
	if not direction.is_zero_approx():
		offset = direction * (eased * sin(wave + _phase_x))
	else:
		offset = Vector2(
			eased * sin(wave + _phase_x),
			eased * sin(wave * 1.31 + _phase_y),
		)


func clear() -> void:
	elapsed = 0.0
	duration = 0.0
	offset = Vector2.ZERO
