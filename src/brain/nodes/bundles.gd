class_name BundleNodes
## Pack and Unpack: the two nodes that let a bundle exist at all (spec 2.8).
##
## A bundle is one wire carrying Port.VECTOR_WIDTH numbers. It exists so a Dense
## Layer can take many inputs through one socket, and so the eight-ray ring stops
## being eight separate wires across the canvas.

## Loose numbers in, one bundle out. Unwired sockets contribute their default 0.0,
## so a Pack is always full width and downstream nodes never see a short bundle.
static func pack() -> NodeType:
	var t := NodeType.new()
	t.id = &"pack"
	t.display_name = "Pack"
	t.category = "Bundles"

	var inputs: Array[Port] = []
	for i in Port.VECTOR_WIDTH:
		inputs.append(Port.make_input(StringName("in_%d" % i), "In %d" % i, 0.0))
	t.inputs = inputs
	t.outputs = [Port.make_vector_output(&"out", "Bundle")]

	t.eval = func(inp: Dictionary, _cfg: Dictionary) -> Dictionary:
		var bundle: Array[float] = []
		for i in Port.VECTOR_WIDTH:
			bundle.append(float(inp[StringName("in_%d" % i)]))
		return { &"out": bundle }

	return t

## One bundle in, loose numbers out. A bundle that arrives shorter than the full
## width — say from a Dense Layer with fewer outputs — reads as zeros past its end.
static func unpack() -> NodeType:
	var t := NodeType.new()
	t.id = &"unpack"
	t.display_name = "Unpack"
	t.category = "Bundles"

	t.inputs = [Port.make_vector_input(&"in", "Bundle")]
	var outputs: Array[Port] = []
	for i in Port.VECTOR_WIDTH:
		outputs.append(Port.make_output(StringName("out_%d" % i), "Out %d" % i))
	t.outputs = outputs

	t.eval = func(inp: Dictionary, _cfg: Dictionary) -> Dictionary:
		var bundle: Array = inp[&"in"]
		var out: Dictionary = {}
		for i in Port.VECTOR_WIDTH:
			out[StringName("out_%d" % i)] = float(bundle[i]) if i < bundle.size() else 0.0
		return out

	return t
