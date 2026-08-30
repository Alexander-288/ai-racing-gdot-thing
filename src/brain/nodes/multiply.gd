class_name MultiplyNode
## Multiplies two numbers. The usual way to scale a sensor reading into a control,
## and the way a boolean gate works: anything times 0.0 is off.

static func define() -> NodeType:
	var t := NodeType.new()
	t.id = &"multiply"
	t.display_name = "Multiply"
	t.category = "Math"

	t.inputs = [
		Port.make_input(&"a", "A", 0.0),
		Port.make_input(&"b", "B", 1.0),  # defaults to 1.0 so an unwired B changes nothing
	]
	t.outputs = [
		Port.make_output(&"out", "Out"),
	]

	t.eval = func(inp: Dictionary, _cfg: Dictionary) -> Dictionary:
		return { &"out": float(inp[&"a"]) * float(inp[&"b"]) }

	return t
