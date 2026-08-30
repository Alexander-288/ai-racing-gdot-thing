class_name NodeType
extends RefCounted
## Describes one kind of node — its name, its sockets, and how it computes.
## This is pure description: it never runs anything itself.

var id: StringName = &""          # stable key used in save files
var display_name: String = ""
var category: String = ""         # which palette group the editor shows it in
var budget_class: StringName = &""  # what the validator counts for fairness caps

var inputs: Array[Port] = []
var outputs: Array[Port] = []

var stateful: bool = false        # true = may sit inside a cycle, uses emit/commit

# Pure nodes fill in eval. Stateful nodes fill in the other three instead.
var eval: Callable = Callable()        # func(inp, cfg) -> Dictionary of outputs
var init_state: Callable = Callable()  # func() -> Dictionary, the starting state
var emit: Callable = Callable()        # func(state, cfg) -> outputs, from LAST tick
var commit: Callable = Callable()      # func(inp, cfg, state) -> void, ends the tick

## Starting values for every input. The evaluator overwrites only the wired ones,
## so whatever is left keeps its default instead of being missing.
func input_defaults() -> Dictionary:
	var d: Dictionary = {}
	for p: Port in inputs:
		d[p.id] = p.default_value
	return d
