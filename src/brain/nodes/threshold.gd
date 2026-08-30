class_name ThresholdNode
## Outputs 1.0 when value is above target, otherwise 0.0. The graph's "if".

static func define() -> NodeType:
	var t := NodeType.new()
	t.id = &"threshold"
	t.display_name = "Threshold"
	t.category = "Math"

	t.inputs = [
		Port.make_input(&"value", "Value", 0.0),
		Port.make_input(&"target", "Target", 0.0),
	]
	t.outputs = [
		Port.make_output(&"out", "Out", 0.0, 1.0),
	]

	# _cfg is unused: this node has no baked-in settings, its target is a wire.
	t.eval = func(inp: Dictionary, _cfg: Dictionary) -> Dictionary:
		return { &"out": 1.0 if inp[&"value"] > inp[&"target"] else 0.0 }

	return t
