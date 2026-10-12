class_name ContactLog
extends RefCounted
## Structured stomp, hurt, and bounce decisions. Off unless a test or the
## readout turns it on. Recording only appends; it never changes motion.

static var enabled := false
static var records: Array[Dictionary] = []


static func clear() -> void:
	records.clear()


static func record(entry: Dictionary) -> void:
	if enabled:
		records.append(entry)
