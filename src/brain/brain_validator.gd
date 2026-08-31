class_name BrainValidator
## Checks a graph before anything runs it — in the editor on save, and again on
## every brain file the race manager loads. A bad brain is rejected, never crashed on.

## Returns a list of problems. Empty list means the graph is safe to evaluate.
static func validate(graph: BrainGraph, registry: NodeRegistry) -> PackedStringArray:
	var errors: PackedStringArray = []

	for inst: BrainGraph.Instance in graph.instances.values():
		if not registry.has_type(inst.type_id):
			errors.append("node '%s': unknown type '%s'" % [inst.id, inst.type_id])

	for w: BrainGraph.Wire in graph.wires:
		errors.append_array(_check_wire(w, graph, registry))

	errors.append_array(_check_layers(graph, registry))
	errors.append_array(_check_budgets(graph, registry))

	# Only worth sorting once the wires are known to point at real sockets.
	if errors.is_empty():
		var order := sort_nodes(graph, registry)
		if order.size() != _sortable_ids(graph, registry).size():
			errors.append("graph contains a cycle that does not pass through a memory node")

	return errors

## Evaluation order for everything that is not a source. A short result means a cycle.
##
## The trick: a source (a sensor, or a memory node) already has its numbers before
## the tick starts, so wires leaving one impose no ordering and wires entering one
## are not followed at all. Cut those and a legal loop stops being a loop. Anything
## still circular is what the editor highlights (spec 2.7).
static func sort_nodes(graph: BrainGraph, registry: NodeRegistry) -> Array[StringName]:
	var pure := _sortable_ids(graph, registry)

	var waiting_on: Dictionary = {}  # node id -> how many inputs are not ready yet
	var feeds: Dictionary = {}       # node id -> the nodes downstream of it
	for id: StringName in pure:
		waiting_on[id] = 0
		feeds[id] = [] as Array[StringName]

	for w: BrainGraph.Wire in graph.wires:
		# Skip unless both ends need sorting — that is the cut described above.
		if not waiting_on.has(w.from_node) or not waiting_on.has(w.to_node):
			continue
		feeds[w.from_node].append(w.to_node)
		waiting_on[w.to_node] = int(waiting_on[w.to_node]) + 1

	var ready: Array[StringName] = []
	for id: StringName in pure:
		if int(waiting_on[id]) == 0:
			ready.append(id)

	var order: Array[StringName] = []
	while not ready.is_empty():
		var id: StringName = ready.pop_front()
		order.append(id)
		for downstream: StringName in feeds[id]:
			waiting_on[downstream] = int(waiting_on[downstream]) - 1
			if int(waiting_on[downstream]) == 0:
				ready.append(downstream)

	# Nodes left waiting are in a cycle, so they never became ready.
	return order

## Fairness caps (spec 2.6, 2.8). The numbers are tuning knobs the spec leaves
## open; what matters is that the check exists and runs before a race, so nobody
## wins by bringing more of something rather than by thinking better.
const BUDGETS := {
	&"accumulator": 8,
	&"neuron": 64,
}

static func _check_budgets(graph: BrainGraph, registry: NodeRegistry) -> PackedStringArray:
	var errors := PackedStringArray()
	var spent: Dictionary = {}

	for inst: BrainGraph.Instance in graph.instances.values():
		var type := registry.get_type(inst.type_id)
		if type == null or type.budget_class == &"":
			continue
		var cost := 1
		if type.budget_cost.is_valid():
			cost = int(type.budget_cost.call(_merged_config(type, inst)))
		spent[type.budget_class] = int(spent.get(type.budget_class, 0)) + cost

	for kind: StringName in spent:
		var cap: int = BUDGETS.get(kind, 0)
		if int(spent[kind]) > cap:
			errors.append("brain uses %d %s, the limit is %d" % [spent[kind], kind, cap])
	return errors

## A layer whose weight matrix is the wrong size loads silently and then drives
## on whatever happened to be there. Caught here instead, on ingest, with the
## shape it expected — because these numbers are imported from outside the engine
## and getting the shape wrong is the obvious way to get it wrong (spec 2.8).
static func _check_layers(graph: BrainGraph, registry: NodeRegistry) -> PackedStringArray:
	var errors := PackedStringArray()
	for inst: BrainGraph.Instance in graph.instances.values():
		var type := registry.get_type(inst.type_id)
		if type == null or type.id != &"dense":
			continue
		var cfg := _merged_config(type, inst)
		var weights: Array = cfg.get(&"weights", [])
		var biases: Array = cfg.get(&"biases", [])
		var want_weights := DenseLayerNode.expected_weights(cfg)
		var want_biases := DenseLayerNode.expected_biases(cfg)
		if weights.size() != want_weights:
			errors.append("layer '%s': %d weights for a %s x %s layer, expected %d"
				% [inst.id, weights.size(), cfg.get(&"inputs", 0), cfg.get(&"outputs", 0), want_weights])
		if biases.size() != want_biases:
			errors.append("layer '%s': %d biases, expected %d" % [inst.id, biases.size(), want_biases])
	return errors

static func _merged_config(type: NodeType, inst: BrainGraph.Instance) -> Dictionary:
	var merged: Dictionary = type.config_defaults.duplicate()
	merged.merge(inst.config, true)
	return merged

static func _sortable_ids(graph: BrainGraph, registry: NodeRegistry) -> Array[StringName]:
	var out: Array[StringName] = []
	for inst: BrainGraph.Instance in graph.instances.values():
		var t := registry.get_type(inst.type_id)
		if t != null and not t.is_source():
			out.append(inst.id)
	return out

static func _check_wire(w: BrainGraph.Wire, graph: BrainGraph, registry: NodeRegistry) -> PackedStringArray:
	var errors: PackedStringArray = []
	var label := "wire %s.%s -> %s.%s" % [w.from_node, w.from_port, w.to_node, w.to_port]

	if not graph.instances.has(w.from_node):
		errors.append("%s: no node called '%s'" % [label, w.from_node])
	if not graph.instances.has(w.to_node):
		errors.append("%s: no node called '%s'" % [label, w.to_node])
	if not errors.is_empty():
		return errors

	var from_type := registry.get_type(graph.instances[w.from_node].type_id)
	var to_type := registry.get_type(graph.instances[w.to_node].type_id)
	if from_type == null or to_type == null:
		return errors  # already reported as an unknown type

	var from_port := _find_port(from_type.outputs, w.from_port)
	var to_port := _find_port(to_type.inputs, w.to_port)
	if from_port == null:
		errors.append("%s: '%s' has no output called '%s'" % [label, w.from_node, w.from_port])
	if to_port == null:
		errors.append("%s: '%s' has no input called '%s'" % [label, w.to_node, w.to_port])
	elif from_port != null and not _kinds_fit(from_port.kind, to_port.kind):
		errors.append("%s: cannot wire %s into %s" % [label, Port.Kind.keys()[from_port.kind], Port.Kind.keys()[to_port.kind]])

	return errors

static func _find_port(ports: Array[Port], id: StringName) -> Port:
	for p: Port in ports:
		if p.id == id:
			return p
	return null

## A bool is allowed into a float socket, because 0.0 / 1.0 is a fine number to
## multiply by — that is how a brain gates one value with another. The reverse is
## refused: an arbitrary float is not a yes-or-no answer.
static func _kinds_fit(from_kind: Port.Kind, to_kind: Port.Kind) -> bool:
	if from_kind == to_kind:
		return true
	return from_kind == Port.Kind.BOOL and to_kind == Port.Kind.FLOAT
