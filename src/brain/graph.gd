class_name BrainGraph
extends RefCounted
## One brain: which nodes exist, how each is configured, and what is wired to what.
## Pure data — it does not know how to run itself.

## A node placed in the graph. type_id says which NodeType it is.
class Instance extends RefCounted:
	var id: StringName = &""
	var type_id: StringName = &""
	var config: Dictionary = {}
	var position: Vector2 = Vector2.ZERO  # where it sits on the editor canvas

## A wire, always from an output socket to an input socket.
class Wire extends RefCounted:
	var from_node: StringName = &""
	var from_port: StringName = &""
	var to_node: StringName = &""
	var to_port: StringName = &""

var name: String = ""  # shown on the leaderboard, not used by the runtime

# Insertion-ordered, which is what keeps evaluation order the same every load.
var instances: Dictionary = {}
var wires: Array[Wire] = []

func add_node(id: StringName, type_id: StringName, config: Dictionary = {},
		position: Vector2 = Vector2.ZERO) -> Instance:
	assert(not instances.has(id), "duplicate node id: %s" % id)
	var n := Instance.new()
	n.id = id
	n.type_id = type_id
	n.config = config
	n.position = position
	instances[id] = n
	return n

## Named connect_ports because Object.connect already exists.
func connect_ports(from_node: StringName, from_port: StringName, to_node: StringName, to_port: StringName) -> Wire:
	var w := Wire.new()
	w.from_node = from_node
	w.from_port = from_port
	w.to_node = to_node
	w.to_port = to_port
	wires.append(w)
	return w

## Forgets a node and every wire touching it, so the editor cannot leave a
## dangling connection behind.
func remove_node(id: StringName) -> void:
	instances.erase(id)
	var kept: Array[Wire] = []
	for w: Wire in wires:
		if w.from_node != id and w.to_node != id:
			kept.append(w)
	wires = kept

func disconnect_ports(from_node: StringName, from_port: StringName, to_node: StringName, to_port: StringName) -> void:
	var kept: Array[Wire] = []
	for w: Wire in wires:
		if not (w.from_node == from_node and w.from_port == from_port
				and w.to_node == to_node and w.to_port == to_port):
			kept.append(w)
	wires = kept

func node_ids() -> Array[StringName]:
	var out: Array[StringName] = []
	for id: StringName in instances.keys():
		out.append(id)
	return out
