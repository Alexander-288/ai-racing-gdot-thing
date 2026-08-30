class_name ConstantNode
## A fixed number typed into the node itself. Every graph needs somewhere to start.

static func define() -> NodeType:
	var t := NodeType.new()
	t.id = &"constant"
	t.display_name = "Constant"
	t.category = "Math"

	t.config_defaults = { &"value": 0.0 }  # a setting in the inspector, not a socket
	t.outputs = [
		Port.make_output(&"out", "Out"),
	]

	t.eval = func(_inp: Dictionary, cfg: Dictionary) -> Dictionary:
		return { &"out": float(cfg[&"value"]) }

	return t
