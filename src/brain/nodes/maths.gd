class_name MathNodes
## The rest of the arithmetic. Small, dull, and the difference between a brain
## you can express and one you cannot.

static func subtract() -> NodeType:
	var t := _two_in(&"subtract", "Subtract")
	t.eval = func(inp: Dictionary, _cfg: Dictionary) -> Dictionary:
		return { &"out": float(inp[&"a"]) - float(inp[&"b"]) }
	return t

## Dividing by nothing gives nothing, rather than an infinity that then poisons
## every node downstream. A brain misbehaves; it does not produce NaN.
static func divide() -> NodeType:
	var t := _two_in(&"divide", "Divide")
	t.inputs[1].default_value = 1.0
	t.eval = func(inp: Dictionary, _cfg: Dictionary) -> Dictionary:
		var divisor := float(inp[&"b"])
		return { &"out": 0.0 if absf(divisor) < 0.000001 else float(inp[&"a"]) / divisor }
	return t

## How far from zero, ignoring the sign. Needed far more often than it looks:
## "is this corner sharp" is a question about size, not direction.
static func absolute() -> NodeType:
	var t := NodeType.new()
	t.id = &"abs"
	t.display_name = "Absolute"
	t.category = "Math"
	t.inputs = [Port.make_input(&"value", "Value", 0.0)]
	t.outputs = [Port.make_output(&"out", "Out")]
	t.eval = func(inp: Dictionary, _cfg: Dictionary) -> Dictionary:
		return { &"out": absf(float(inp[&"value"])) }
	return t

## Picks the smaller of two, which is how a brain applies a ceiling to something.
static func minimum() -> NodeType:
	var t := _two_in(&"min", "Minimum")
	t.eval = func(inp: Dictionary, _cfg: Dictionary) -> Dictionary:
		return { &"out": minf(float(inp[&"a"]), float(inp[&"b"])) }
	return t

static func maximum() -> NodeType:
	var t := _two_in(&"max", "Maximum")
	t.eval = func(inp: Dictionary, _cfg: Dictionary) -> Dictionary:
		return { &"out": maxf(float(inp[&"a"]), float(inp[&"b"])) }
	return t

static func _two_in(id: StringName, label: String) -> NodeType:
	var t := NodeType.new()
	t.id = id
	t.display_name = label
	t.category = "Math"
	t.inputs = [
		Port.make_input(&"a", "A", 0.0),
		Port.make_input(&"b", "B", 0.0),
	]
	t.outputs = [Port.make_output(&"out", "Out")]
	return t
