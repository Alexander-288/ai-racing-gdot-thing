class_name AccumulatorNode
## Holds a number between ticks. Mainly for hysteresis, so a brain sitting on a
## threshold does not flicker its decision every single tick.

static func define() -> NodeType:
	var t := NodeType.new()
	t.id = &"accumulator"
	t.display_name = "Accumulator"
	t.category = "Memory"
	t.stateful = true
	t.budget_class = &"accumulator"  # capped per brain, so nobody wins on quantity

	t.inputs = [
		Port.make_input(&"add", "Add", 0.0),
		Port.make_input(&"set_value", "Set Value", 0.0),
		Port.make_input(&"set_trigger", "Set", 0.0),
		Port.make_input(&"reset", "Reset", 0.0),
	]
	t.outputs = [
		Port.make_output(&"out", "Out"),
	]

	t.init_state = func() -> Dictionary:
		return { &"held": 0.0 }

	# Runs at the START of a tick. Has no inputs parameter on purpose: it can only
	# report last tick's number, which is what makes loops in the graph safe.
	t.emit = func(state: Dictionary, _cfg: Dictionary) -> Dictionary:
		return { &"out": state[&"held"] }

	# Runs at the END of a tick. Returns void on purpose: it can only store, not output.
	t.commit = func(inp: Dictionary, _cfg: Dictionary, state: Dictionary) -> void:
		if inp[&"reset"] > 0.5:  # wires carry floats, so booleans arrive as 0.0 / 1.0
			state[&"held"] = 0.0
		elif inp[&"set_trigger"] > 0.5:
			state[&"held"] = inp[&"set_value"]
		else:
			# Cast both: dictionary values are Variant, and a stray int would change the maths.
			state[&"held"] = float(state[&"held"]) + float(inp[&"add"])

	return t
