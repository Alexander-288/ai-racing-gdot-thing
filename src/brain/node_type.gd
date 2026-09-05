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

## How much of that budget one of these costs. A Dense Layer costs its neuron
## count; everything else costs one. Set by node types that need it.
var budget_cost: Callable = Callable()
var role: Role = Role.PURE

var config_defaults: Dictionary = {}  # baked-in settings, not wires (e.g. a constant's value)

## How the editor should draw each setting. Left empty, every setting gets a
## number box, which is what almost all of them want.
var config_fields: Array[ConfigField] = []

## Some nodes grow. A Ray node can carry one reading or eight, and its sockets
## and settings have to follow — so for those, the ports are a function of the
## config rather than a fixed list.
##
## func(config) -> { inputs: Array[Port], outputs: Array[Port], fields: Array[ConfigField] }
var shape_for: Callable = Callable()

## Set when a node can be grown and shrunk from the editor. `grow_key` is the
## setting that counts its segments.
var grow_key: StringName = &""
var grow_min: int = 1
var grow_max: int = 8

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

## The sockets and settings this node has, given how it is configured. A node
## with a fixed shape ignores the config entirely, which is nearly all of them.
func shape(config: Dictionary) -> Dictionary:
	if not shape_for.is_valid():
		return { &"inputs": inputs, &"outputs": outputs, &"fields": config_fields }
	return shape_for.call(config)

func inputs_for(config: Dictionary) -> Array[Port]:
	return shape(config)[&"inputs"]

func outputs_for(config: Dictionary) -> Array[Port]:
	return shape(config)[&"outputs"]

## Declared fields win. Where a node has not declared any, one number box per
## numeric setting is derived — which is right for almost every node.
##
## Settings that are not numbers are deliberately left out unless the node says
## what they are: a text setting drawn as a number box shows a meaningless zero
## and overwrites the real value the moment you touch it, and a weight matrix has
## no business being a spinner at all.
func fields_for(config: Dictionary) -> Array[ConfigField]:
	var declared: Array[ConfigField] = shape(config)[&"fields"]
	if not declared.is_empty():
		return declared

	var derived: Array[ConfigField] = []
	for key: StringName in config_defaults:
		var value: Variant = config_defaults[key]
		if typeof(value) == TYPE_FLOAT or typeof(value) == TYPE_INT:
			derived.append(ConfigField.number(key, String(key)))
	return derived

func can_grow() -> bool:
	return grow_key != &""

## Starting values for every input. The evaluator overwrites only the wired ones,
## so whatever is left keeps its default instead of being missing.
func input_defaults(config: Dictionary = {}) -> Dictionary:
	var d: Dictionary = {}
	for p: Port in inputs_for(config):
		d[p.id] = p.default_value
	return d
