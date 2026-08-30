class_name AddNode
## Adds two numbers.

static func define() -> NodeType:
	var t := NodeType.new()
	t.id = &"add"
	t.display_name = "Add"
	t.category = "Math"

	t.inputs = [
		Port.make_input(&"a", "A", 0.0),
		Port.make_input(&"b", "B", 0.0),
	]
	t.outputs = [
		Port.make_output(&"out", "Out"),
	]

	t.eval = func(inp: Dictionary, _cfg: Dictionary) -> Dictionary:
		return { &"out": float(inp[&"a"]) + float(inp[&"b"]) }

	return t
