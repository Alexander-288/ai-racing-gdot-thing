class_name ControlNodes
## The four things a brain can do to the car. All sinks: inputs, no outputs.
## The value is clamped by CarControls, so a graph cannot ask for anything silly.

static func steering() -> NodeType:
	return _control(&"out_steering", "Steering", &"steering", -1.0, 1.0)

static func throttle() -> NodeType:
	return _control(&"out_throttle", "Throttle", &"throttle", 0.0, 1.0)

static func brake() -> NodeType:
	return _control(&"out_brake", "Brake", &"brake", 0.0, 1.0)

static func drs() -> NodeType:
	return _control(&"out_drs", "DRS", &"drs", 0.0, 1.0, Port.Kind.BOOL)

## All four are the same node with a different label, so they are built the same way.
static func _control(id: StringName, label: String, control: StringName,
		low: float, high: float, kind: Port.Kind = Port.Kind.FLOAT) -> NodeType:
	var t := NodeType.new()
	t.id = id
	t.display_name = label
	t.category = "Outputs"
	t.role = NodeType.Role.OUTPUT

	# Unwired means "do nothing", which for steering is straight and for throttle is off.
	t.inputs = [
		Port.make_input(&"value", label, clampf(0.0, low, high), kind),
	]

	t.write = func(inp: Dictionary, _cfg: Dictionary, controls: CarControls) -> void:
		controls.apply(control, float(inp[&"value"]))

	return t
