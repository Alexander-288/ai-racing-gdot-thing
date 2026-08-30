class_name CarControls
extends RefCounted
## What a brain hands back each tick. The sim applies exactly this and nothing else.

var steering: float = 0.0  # -1 hard left .. 1 hard right
var throttle: float = 0.0  # 0..1
var brake: float = 0.0     # 0..1
var drs: bool = false      # faster in a straight line, much less grip in a corner

## Output nodes write through here so a brain can never set a nonsense value,
## no matter what its graph computed.
func apply(control: StringName, value: float) -> void:
	match control:
		&"steering":
			steering = clampf(value, -1.0, 1.0)
		&"throttle":
			throttle = clampf(value, 0.0, 1.0)
		&"brake":
			brake = clampf(value, 0.0, 1.0)
		&"drs":
			drs = value > 0.5  # wires carry floats, so a bool arrives as 0.0 / 1.0
