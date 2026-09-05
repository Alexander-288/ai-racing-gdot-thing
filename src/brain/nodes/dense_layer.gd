class_name DenseLayerNode
## A whole neural network layer as one node (spec 2.8).
##
## Layer nodes, not neuron nodes: one box on the canvas holding an N x M weight
## matrix, M biases and a choice of activation. It obeys the same once-per-tick
## contract as every other node, so the execution model needs no special case
## for networks at all.
##
## The engine only ever runs a network forwards. Training happens outside, by
## whatever means the author likes, and the weights come back in through the
## brain file — which is why that format had to stay hand-editable.

const MAX_WIDTH := Port.VECTOR_WIDTH

static func define() -> NodeType:
	var t := NodeType.new()
	t.id = &"dense"
	t.display_name = "Dense Layer"
	t.category = "Bundles"
	t.budget_class = &"neuron"  # counted against the per-brain cap, so nobody
	                            # wins by importing a bigger net

	t.config_defaults = {
		&"inputs": 4.0,
		&"outputs": 4.0,
		&"activation": "tanh",   # tanh, relu or sigmoid
		&"weights": [] as Array[float],   # row-major: weight[i][j] at i * outputs + j
		&"biases": [] as Array[float],
	}
	# One layer costs as many neurons as it has outputs, so a brain cannot buy its
	# way past the cap by importing one enormous layer.
	t.budget_cost = func(cfg: Dictionary) -> int:
		return expected_biases(cfg)

	# Weights and biases are imported, not typed in, so they get no widget. The
	# shape and the activation do.
	t.config_fields = [
		ConfigField.number(&"inputs", "in", 1.0, float(MAX_WIDTH), 1.0),
		ConfigField.number(&"outputs", "out", 1.0, float(MAX_WIDTH), 1.0),
		ConfigField.choice(&"activation", "shape", ["tanh", "relu", "sigmoid"]),
	]

	t.inputs = [Port.make_vector_input(&"in", "In")]
	t.outputs = [Port.make_vector_output(&"out", "Out")]

	t.eval = func(inp: Dictionary, cfg: Dictionary) -> Dictionary:
		var n_in := clampi(int(cfg[&"inputs"]), 0, MAX_WIDTH)
		var n_out := clampi(int(cfg[&"outputs"]), 0, MAX_WIDTH)
		var weights: Array = cfg[&"weights"]
		var biases: Array = cfg[&"biases"]
		var x: Array = inp[&"in"]
		var activation := StringName(str(cfg[&"activation"]))

		var out: Array[float] = []
		for j in n_out:
			# Anything missing reads as zero rather than failing. A half-imported
			# weight matrix makes a bad driver, not a broken race (spec 3.3).
			var total := float(biases[j]) if j < biases.size() else 0.0
			for i in n_in:
				var value := float(x[i]) if i < x.size() else 0.0
				var w := i * n_out + j
				total += value * (float(weights[w]) if w < weights.size() else 0.0)
			out.append(activate(total, activation))
		return { &"out": out }

	return t

static func activate(value: float, kind: StringName) -> float:
	match kind:
		&"relu":
			return maxf(value, 0.0)
		&"sigmoid":
			return 1.0 / (1.0 + exp(-clampf(value, -30.0, 30.0)))  # clamped so exp cannot overflow
		_:
			return tanh(value)

## How many numbers a correctly filled layer needs. Used by the validator, so a
## mis-shaped import is caught when the brain loads rather than on track.
static func expected_weights(config: Dictionary) -> int:
	return clampi(int(config.get(&"inputs", 0)), 0, MAX_WIDTH) \
		* clampi(int(config.get(&"outputs", 0)), 0, MAX_WIDTH)

static func expected_biases(config: Dictionary) -> int:
	return clampi(int(config.get(&"outputs", 0)), 0, MAX_WIDTH)
