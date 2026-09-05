class_name BrainEvaluator
extends RefCounted
## Runs one brain, once per physics tick. Sorted once when built, so the cost of a
## tick is known before the race starts and is the same on every tick.

var _graph: BrainGraph
var _registry: NodeRegistry
var _order: Array[StringName] = []      # everything that is not a source, in dependency order
var _sensor_ids: Array[StringName] = []
var _memory_ids: Array[StringName] = []
var _incoming: Dictionary = {}          # node id -> the wires feeding it
## Worked out once when the evaluator is built, because none of it changes during
## a race: the type, the settings, and the starting input values. Rebuilding the
## settings for every node on every tick meant a dictionary copy and a merge per
## node — five hundred of each per tick with a full grid.
var _types: Dictionary = {}
var _configs: Dictionary = {}
var _defaults: Dictionary = {}
## A node whose shape depends on its config would otherwise rebuild its whole
## port list on every tick — and a Ray node does exactly that. The config is
## settled, so the ports are too.
var _out_ports: Dictionary = {}
var _state: Dictionary = {}             # node id -> that node's memory
var _outputs: Dictionary = {}           # node id -> its outputs this tick

## Builds an evaluator. The graph must already have passed BrainValidator.
static func create(graph: BrainGraph, registry: NodeRegistry) -> BrainEvaluator:
	var e := BrainEvaluator.new()
	e._graph = graph
	e._registry = registry
	e._order = BrainValidator.sort_nodes(graph, registry)

	for inst: BrainGraph.Instance in graph.instances.values():
		var t := registry.get_type(inst.type_id)
		if t == null:
			continue
		if t.role == NodeType.Role.SENSOR:
			e._sensor_ids.append(inst.id)
		elif t.role == NodeType.Role.MEMORY:
			e._memory_ids.append(inst.id)

	for inst: BrainGraph.Instance in graph.instances.values():
		var type := registry.get_type(inst.type_id)
		if type == null:
			continue
		var merged: Dictionary = type.config_defaults.duplicate()
		merged.merge(inst.config, true)
		e._types[inst.id] = type
		e._configs[inst.id] = merged
		e._defaults[inst.id] = type.input_defaults(merged)
		e._out_ports[inst.id] = type.outputs_for(merged)
		e._incoming[inst.id] = [] as Array[BrainGraph.Wire]

	for w: BrainGraph.Wire in graph.wires:
		if e._incoming.has(w.to_node):
			e._incoming[w.to_node].append(w)

	e.reset()
	return e

## Clears all memory. Brains spawn clean every race, so no map of a track can be
## built up across runs (spec 2.5).
func reset() -> void:
	_state.clear()
	_outputs.clear()
	for id: StringName in _memory_ids:
		_state[id] = _type_of(id).init_state.call()

## One physics tick: senses in, controls out. The order of these four steps never
## changes, for any car, on any tick — that is the determinism lock (spec 3.2).
func tick(snapshot: SensorSnapshot) -> CarControls:
	var controls := CarControls.new()

	# 1. Senses. Fixed numbers for this tick, before any maths happens.
	for id: StringName in _sensor_ids:
		var t := _type_of(id)
		var sensor_config: Dictionary = _configs[id]
		_outputs[id] = _clean(id, t.sense.call(snapshot, sensor_config))

	# 2. Memory reports LAST tick's numbers. Together with step 1 this means every
	#    source is known up front, which is what lets a loop resolve.
	for id: StringName in _memory_ids:
		var t := _type_of(id)
		var memory_config: Dictionary = _configs[id]
		_outputs[id] = _clean(id, t.emit.call(_state[id], memory_config))

	# 3. Everything else, once each, in dependency order.
	for id: StringName in _order:
		var t := _type_of(id)
		var config: Dictionary = _configs[id]
		if t.role == NodeType.Role.OUTPUT:
			t.write.call(_gather(id), config, controls)
		else:
			_outputs[id] = _clean(id, t.eval.call(_gather(id), config))

	# 4. Memory swallows this tick's inputs, ready for the next one.
	for id: StringName in _memory_ids:
		var t := _type_of(id)
		t.commit.call(_gather(id), _config_of(id), _state[id])

	return controls

func output_of(node_id: StringName, port_id: StringName) -> float:
	var node_outputs: Dictionary = _outputs.get(node_id, {})
	return float(node_outputs.get(port_id, 0.0))

## Every input starts at its declared default, then wires overwrite the ones they
## reach. That is why an unconnected input can never be missing.
func _gather(node_id: StringName) -> Dictionary:
	var inp: Dictionary = (_defaults[node_id] as Dictionary).duplicate()
	for w: BrainGraph.Wire in _incoming[node_id]:
		var source: Dictionary = _outputs.get(w.from_node, {})
		if source.has(w.from_port):
			inp[w.to_port] = source[w.from_port]
	return inp

## Forces every output into its declared range, and NaN to zero. A broken brain
## drives badly; it does not get to take the race down with it (spec 3.3).
func _clean(node_id: StringName, raw: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for p: Port in _out_ports[node_id]:
		if p.kind == Port.Kind.VECTOR:
			out[p.id] = _clean_vector(raw.get(p.id, []), p)
		else:
			out[p.id] = _clean_number(raw.get(p.id, 0.0), p)
	return out

static func _clean_number(raw: Variant, p: Port) -> float:
	var v := float(raw)
	if is_nan(v):
		v = 0.0
	return clampf(v, p.min_value, p.max_value)

## Bundles get the same treatment, element by element. A node that returns the
## wrong sort of thing entirely gets an empty bundle rather than a crash.
static func _clean_vector(raw: Variant, p: Port) -> Array[float]:
	var values: Array[float] = []
	if raw is Array:
		for item: Variant in raw:
			values.append(_clean_number(item, p))
	return values

func _type_of(node_id: StringName) -> NodeType:
	return _types[node_id]

## Node settings, with anything the author did not set falling back to the type
## default. Settled when the evaluator was built; a race cannot change them.
func _config_of(node_id: StringName) -> Dictionary:
	return _configs[node_id]
