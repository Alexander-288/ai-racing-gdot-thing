class_name BrainEvaluator
extends RefCounted
## Runs one brain, once per physics tick. Sorted once when built, so the cost of a
## tick is known before the race starts and is the same on every tick.

var _graph: BrainGraph
var _registry: NodeRegistry
var _order: Array[StringName] = []      # pure nodes, in dependency order
var _stateful_ids: Array[StringName] = []
var _incoming: Dictionary = {}          # node id -> the wires feeding it
var _state: Dictionary = {}             # node id -> that node's memory
var _outputs: Dictionary = {}           # node id -> its outputs this tick

## Builds an evaluator. The graph must already have passed BrainValidator.
static func create(graph: BrainGraph, registry: NodeRegistry) -> BrainEvaluator:
	var e := BrainEvaluator.new()
	e._graph = graph
	e._registry = registry
	e._order = BrainValidator.sort_pure_nodes(graph, registry)

	for inst: BrainGraph.Instance in graph.instances.values():
		var t := registry.get_type(inst.type_id)
		if t != null and t.stateful:
			e._stateful_ids.append(inst.id)

	for w: BrainGraph.Wire in graph.wires:
		if not e._incoming.has(w.to_node):
			e._incoming[w.to_node] = [] as Array[BrainGraph.Wire]
		e._incoming[w.to_node].append(w)

	e.reset()
	return e

## Clears all memory. Brains spawn clean every race, so nothing carries over.
func reset() -> void:
	_state.clear()
	_outputs.clear()
	for id: StringName in _stateful_ids:
		_state[id] = _type_of(id).init_state.call()

## One physics tick. The order of these three steps is the determinism lock.
func tick() -> void:
	# 1. Memory nodes report last tick's numbers. Nothing is wired yet, so this is
	#    what lets a loop resolve: their outputs exist before evaluation starts.
	for id: StringName in _stateful_ids:
		var t := _type_of(id)
		_outputs[id] = _clean(t, t.emit.call(_state[id], _config_of(id)))

	# 2. Every pure node, once each, in dependency order.
	for id: StringName in _order:
		var t := _type_of(id)
		_outputs[id] = _clean(t, t.eval.call(_gather(id), _config_of(id)))

	# 3. Memory nodes swallow this tick's inputs, ready for the next one.
	for id: StringName in _stateful_ids:
		var t := _type_of(id)
		t.commit.call(_gather(id), _config_of(id), _state[id])

func output_of(node_id: StringName, port_id: StringName) -> float:
	var node_outputs: Dictionary = _outputs.get(node_id, {})
	return float(node_outputs.get(port_id, 0.0))

## Every input starts at its declared default, then wires overwrite the ones they
## reach. That is why an unconnected input can never be missing.
func _gather(node_id: StringName) -> Dictionary:
	var inp: Dictionary = _type_of(node_id).input_defaults()
	for w: BrainGraph.Wire in _incoming.get(node_id, []):
		var source: Dictionary = _outputs.get(w.from_node, {})
		if source.has(w.from_port):
			inp[w.to_port] = source[w.from_port]
	return inp

## Forces every output into its declared range, and NaN to zero. A broken brain
## drives badly; it does not get to take the race down with it.
func _clean(type: NodeType, raw: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for p: Port in type.outputs:
		var v: float = float(raw.get(p.id, 0.0))
		if is_nan(v):
			v = 0.0
		out[p.id] = clampf(v, p.min_value, p.max_value)
	return out

func _type_of(node_id: StringName) -> NodeType:
	return _registry.get_type(_graph.instances[node_id].type_id)

## Node settings, with anything the author did not set falling back to the type default.
func _config_of(node_id: StringName) -> Dictionary:
	var merged: Dictionary = _type_of(node_id).config_defaults.duplicate()
	merged.merge(_graph.instances[node_id].config, true)
	return merged
