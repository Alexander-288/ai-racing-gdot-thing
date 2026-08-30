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

	# Only worth sorting once the wires are known to point at real sockets.
	if errors.is_empty():
		var order := sort_pure_nodes(graph, registry)
		if order.size() != _pure_ids(graph, registry).size():
			errors.append("graph contains a cycle that does not pass through a memory node")

	return errors

## Evaluation order for the pure nodes. Empty-ish result means a cycle (see validate).
##
## The trick: a stateful node's output is already known before the tick starts, so
## wires leaving one impose no ordering, and wires entering one are not followed at
## all. Cut those and a legal loop stops being a loop. Anything still circular is
## the error the editor highlights.
static func sort_pure_nodes(graph: BrainGraph, registry: NodeRegistry) -> Array[StringName]:
	var pure := _pure_ids(graph, registry)

	var waiting_on: Dictionary = {}  # node id -> how many inputs are not ready yet
	var feeds: Dictionary = {}       # node id -> the nodes downstream of it
	for id: StringName in pure:
		waiting_on[id] = 0
		feeds[id] = [] as Array[StringName]

	for w: BrainGraph.Wire in graph.wires:
		# Skip unless both ends are pure — that is the cut described above.
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

static func _pure_ids(graph: BrainGraph, registry: NodeRegistry) -> Array[StringName]:
	var out: Array[StringName] = []
	for inst: BrainGraph.Instance in graph.instances.values():
		var t := registry.get_type(inst.type_id)
		if t != null and not t.stateful:
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
	elif from_port != null and from_port.kind != to_port.kind:
		errors.append("%s: cannot wire %s into %s" % [label, Port.Kind.keys()[from_port.kind], Port.Kind.keys()[to_port.kind]])

	return errors

static func _find_port(ports: Array[Port], id: StringName) -> Port:
	for p: Port in ports:
		if p.id == id:
			return p
	return null
