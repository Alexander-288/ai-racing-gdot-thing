class_name NodeRegistry
extends RefCounted
## The list of every node type the game knows about.
## The editor palette, the serialiser, the validator and the evaluator all read
## from here, so adding a node type is one file plus one line in create_default().

var _types: Dictionary = {}  # StringName id -> NodeType

## Builds the registry every part of the game uses. Add new node types here.
static func create_default() -> NodeRegistry:
	var r := NodeRegistry.new()
	r.register(SensorNodes.ray())
	r.register(SensorNodes.ray_ring())
	r.register(SensorNodes.self_state())
	r.register(SensorNodes.checkpoint())
	r.register(SensorNodes.radar())
	r.register(ControlNodes.steering())
	r.register(ControlNodes.throttle())
	r.register(ControlNodes.brake())
	r.register(ControlNodes.drs())
	r.register(ConstantNode.define())
	r.register(AddNode.define())
	r.register(MultiplyNode.define())
	r.register(MathNodes.subtract())
	r.register(MathNodes.divide())
	r.register(MathNodes.absolute())
	r.register(MathNodes.minimum())
	r.register(MathNodes.maximum())
	r.register(BundleNodes.pack())
	r.register(BundleNodes.unpack())
	r.register(DenseLayerNode.define())
	r.register(ThresholdNode.define())
	r.register(AccumulatorNode.define())
	return r

func register(type: NodeType) -> void:
	# Two node types sharing an id would silently overwrite each other in save files.
	assert(not _types.has(type.id), "duplicate node type id: %s" % type.id)
	_types[type.id] = type

func has_type(id: StringName) -> bool:
	return _types.has(id)

func get_type(id: StringName) -> NodeType:
	return _types.get(id)

## Every registered type. Built by hand because values() gives an untyped Array.
func all() -> Array[NodeType]:
	var out: Array[NodeType] = []
	for t: NodeType in _types.values():
		out.append(t)
	return out

## Every category that has node types in it, in registration order. The editor
## reads this rather than keeping its own list, so a new category cannot go
## missing from the palette.
func categories() -> Array[String]:
	var out: Array[String] = []
	for t: NodeType in all():
		if not out.has(t.category):
			out.append(t.category)
	return out

## Used by the editor palette, so its groups can never drift out of sync.
func by_category(category: String) -> Array[NodeType]:
	var out: Array[NodeType] = []
	for t: NodeType in all():
		if t.category == category:
			out.append(t)
	return out
