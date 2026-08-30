class_name NodeType
extends RefCounted
## Describes one kind of node — its name, its sockets, and how it computes.
## This is pure description: it never runs anything itself.

## What a node is for. Each role has its own contract, and the registry test
## checks that a node type actually implements the one it claims.
enum Role {
	PURE,    # maths: inputs in, outputs out, same answer every time
	SENSOR,  # reads the car's senses; has no inputs
	MEMORY,  # remembers between ticks; the only role allowed inside a loop
	OUTPUT,  # drives the car; has no outputs
}

var id: StringName = &""          # stable key used in save files
var display_name: String = ""
var category: String = ""         # which palette group the editor shows it in
var budget_class: StringName = &""  # what the validator counts for fairness caps
var role: Role = Role.PURE

var config_defaults: Dictionary = {}  # baked-in settings, not wires (e.g. a constant's value)

var inputs: Array[Port] = []
var outputs: Array[Port] = []

# Each role fills in only its own callables and leaves the rest empty.
var eval: Callable = Callable()        # PURE:   func(inp, cfg) -> outputs
var sense: Callable = Callable()       # SENSOR: func(snapshot, cfg) -> outputs
var init_state: Callable = Callable()  # MEMORY: func() -> the starting state
var emit: Callable = Callable()        # MEMORY: func(state, cfg) -> outputs, from LAST tick
var commit: Callable = Callable()      # MEMORY: func(inp, cfg, state) -> void, ends the tick
var write: Callable = Callable()       # OUTPUT: func(inp, cfg, controls) -> void

## Sensors and memory both have their numbers ready before the tick's maths
## starts, so nothing needs evaluating ahead of them. That is what lets a loop
## through memory be sorted like an ordinary chain.
func is_source() -> bool:
	return role == Role.SENSOR or role == Role.MEMORY

## Starting values for every input. The evaluator overwrites only the wired ones,
## so whatever is left keeps its default instead of being missing.
func input_defaults() -> Dictionary:
	var d: Dictionary = {}
	for p: Port in inputs:
		d[p.id] = p.default_value
	return d
