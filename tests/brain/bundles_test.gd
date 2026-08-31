extends TestCase
## Vector ports, Pack / Unpack, and the Dense Layer (spec 2.8).

func _registry() -> NodeRegistry:
	return NodeRegistry.create_default()

# ------------------------------------------------------------------ pack / unpack

func test_pack_gathers_loose_numbers_into_one_wire() -> void:
	var g := BrainGraph.new()
	g.add_node(&"a", &"constant", { &"value": 3.0 })
	g.add_node(&"p", &"pack")
	g.connect_ports(&"a", &"out", &"p", &"in_0")
	var e := BrainEvaluator.create(g, _registry())
	e.tick(SensorSnapshot.blank())

	var bundle: Array = e._outputs[&"p"][&"out"]
	assert_eq(bundle.size(), Port.VECTOR_WIDTH, "a bundle is always full width")
	assert_almost_eq(bundle[0], 3.0)
	assert_almost_eq(bundle[1], 0.0, 1e-6, "unwired sockets contribute their default")

func test_unpack_takes_it_apart_again() -> void:
	var g := BrainGraph.new()
	g.add_node(&"a", &"constant", { &"value": 7.0 })
	g.add_node(&"p", &"pack")
	g.add_node(&"u", &"unpack")
	g.connect_ports(&"a", &"out", &"p", &"in_3")
	g.connect_ports(&"p", &"out", &"u", &"in")
	var e := BrainEvaluator.create(g, _registry())
	e.tick(SensorSnapshot.blank())

	assert_almost_eq(e.output_of(&"u", &"out_3"), 7.0, 1e-6, "same slot out as in")
	assert_almost_eq(e.output_of(&"u", &"out_2"), 0.0)

func test_unpacking_nothing_gives_zeros_not_a_crash() -> void:
	var g := BrainGraph.new()
	g.add_node(&"u", &"unpack")  # nothing wired in at all
	var e := BrainEvaluator.create(g, _registry())
	e.tick(SensorSnapshot.blank())
	assert_almost_eq(e.output_of(&"u", &"out_0"), 0.0)

# ------------------------------------------------------------------ wiring rules

func test_a_bundle_may_not_be_wired_into_a_number() -> void:
	var g := BrainGraph.new()
	g.add_node(&"p", &"pack")
	g.add_node(&"gas", &"out_throttle")
	g.connect_ports(&"p", &"out", &"gas", &"value")
	var errors := BrainValidator.validate(g, _registry())
	assert_eq(errors.size(), 1)
	assert_true(errors[0].contains("cannot wire VECTOR into FLOAT"), errors[0])

func test_a_number_may_not_be_wired_into_a_bundle() -> void:
	var g := BrainGraph.new()
	g.add_node(&"c", &"constant")
	g.add_node(&"u", &"unpack")
	g.connect_ports(&"c", &"out", &"u", &"in")
	var errors := BrainValidator.validate(g, _registry())
	assert_eq(errors.size(), 1)
	assert_true(errors[0].contains("cannot wire FLOAT into VECTOR"), errors[0])

# ------------------------------------------------------------------ the ray ring

func test_the_ray_ring_is_one_wire_carrying_all_eight() -> void:
	var snapshot := SensorSnapshot.blank()
	snapshot.ray_distance[2] = 0.4
	snapshot.ray_hit_track[2] = true

	var g := BrainGraph.new()
	g.add_node(&"ring", &"ray_ring")
	var e := BrainEvaluator.create(g, _registry())
	e.tick(snapshot)

	var distances: Array = e._outputs[&"ring"][&"distances"]
	assert_eq(distances.size(), SensorSnapshot.RING_RAYS)
	assert_almost_eq(distances[2], 0.4)
	var hits: Array = e._outputs[&"ring"][&"hits"]
	assert_almost_eq(hits[2], 1.0)

func test_the_ring_agrees_with_the_single_ray_node() -> void:
	# Two ways to read the same sensor must never disagree.
	var snapshot := SensorSnapshot.blank()
	snapshot.ray_distance[5] = 0.31

	var g := BrainGraph.new()
	g.add_node(&"ring", &"ray_ring")
	g.add_node(&"one", &"ray", { &"index": 5.0 })
	var e := BrainEvaluator.create(g, _registry())
	e.tick(snapshot)

	var distances: Array = e._outputs[&"ring"][&"distances"]
	assert_almost_eq(distances[5], e.output_of(&"one", &"distance"), 1e-9)

# ------------------------------------------------------------------ dense layer

func _identity_layer(size: int) -> Dictionary:
	# Weights are row-major: weight[i][j] sits at i * outputs + j.
	var weights: Array[float] = []
	for i in size:
		for j in size:
			weights.append(1.0 if i == j else 0.0)
	var biases: Array[float] = []
	for j in size:
		biases.append(0.0)
	return { &"inputs": float(size), &"outputs": float(size),
		&"weights": weights, &"biases": biases, &"activation": "relu" }

func test_a_layer_multiplies_its_matrix() -> void:
	var g := BrainGraph.new()
	g.add_node(&"c", &"constant", { &"value": 2.0 })
	g.add_node(&"p", &"pack")
	g.add_node(&"layer", &"dense", _identity_layer(4))
	g.connect_ports(&"c", &"out", &"p", &"in_1")
	g.connect_ports(&"p", &"out", &"layer", &"in")

	assert_eq(BrainValidator.validate(g, _registry()).size(), 0)
	var e := BrainEvaluator.create(g, _registry())
	e.tick(SensorSnapshot.blank())

	var out: Array = e._outputs[&"layer"][&"out"]
	assert_eq(out.size(), 4)
	assert_almost_eq(out[1], 2.0, 1e-6, "identity matrix passes the value through")
	assert_almost_eq(out[0], 0.0)

func test_relu_clips_negatives_and_tanh_squashes() -> void:
	assert_almost_eq(DenseLayerNode.activate(-5.0, &"relu"), 0.0)
	assert_almost_eq(DenseLayerNode.activate(5.0, &"relu"), 5.0)
	assert_almost_eq(DenseLayerNode.activate(0.0, &"tanh"), 0.0)
	assert_true(DenseLayerNode.activate(100.0, &"tanh") <= 1.0)
	assert_almost_eq(DenseLayerNode.activate(0.0, &"sigmoid"), 0.5)

func test_sigmoid_survives_an_absurd_input() -> void:
	# exp() of a big negative number overflows; a brain must not be able to
	# produce an infinity just by wiring a large constant into a layer.
	var v := DenseLayerNode.activate(-100000.0, &"sigmoid")
	assert_false(is_nan(v), "sigmoid produced NaN")
	assert_true(v >= 0.0 and v <= 1.0)

# ------------------------------------------------------------------ imported weights

func test_a_layer_with_the_wrong_number_of_weights_is_rejected() -> void:
	var g := BrainGraph.new()
	var bad := _identity_layer(4)
	bad[&"weights"] = [1.0, 2.0] as Array[float]  # nowhere near 4 x 4
	g.add_node(&"layer", &"dense", bad)
	var errors := BrainValidator.validate(g, _registry())
	assert_eq(errors.size(), 1)
	assert_true(errors[0].contains("expected 16"), errors[0])

func test_a_layer_with_the_wrong_number_of_biases_is_rejected() -> void:
	var g := BrainGraph.new()
	var bad := _identity_layer(4)
	bad[&"biases"] = [0.0] as Array[float]
	g.add_node(&"layer", &"dense", bad)
	var errors := BrainValidator.validate(g, _registry())
	assert_eq(errors.size(), 1)
	assert_true(errors[0].contains("biases"), errors[0])

func test_weights_survive_a_trip_through_a_brain_file() -> void:
	# The file format is the import path for anything trained outside the engine,
	# so the numbers have to come back bit for bit.
	var g := BrainGraph.new()
	var layer := _identity_layer(4)
	layer[&"weights"][0] = 1.0 / 3.0
	layer[&"biases"][2] = -0.7734375
	g.add_node(&"layer", &"dense", layer)

	var back := BrainFormat.parse(BrainFormat.serialize(g))
	assert_true(back.ok(), "  ".join(back.errors))
	var reloaded: Dictionary = back.graph.instances[&"layer"].config
	assert_eq(reloaded[&"weights"][0], 1.0 / 3.0)
	assert_eq(reloaded[&"biases"][2], -0.7734375)
	assert_eq(reloaded[&"activation"], "relu")
	assert_eq(BrainValidator.validate(back.graph, _registry()).size(), 0)

# ------------------------------------------------------------------ budgets

func test_too_many_neurons_is_rejected() -> void:
	# Nobody wins by importing a bigger net (spec 2.8).
	var g := BrainGraph.new()
	for i in 10:  # 10 layers of 8 outputs = 80 neurons, over the cap of 64
		g.add_node(StringName("l%d" % i), &"dense", _identity_layer(8))
	var errors := BrainValidator.validate(g, _registry())
	assert_eq(errors.size(), 1)
	assert_true(errors[0].contains("neuron"), errors[0])

func test_too_many_accumulators_is_rejected() -> void:
	var g := BrainGraph.new()
	for i in 9:
		g.add_node(StringName("a%d" % i), &"accumulator")
	var errors := BrainValidator.validate(g, _registry())
	assert_eq(errors.size(), 1)
	assert_true(errors[0].contains("accumulator"), errors[0])

func test_a_reasonable_brain_is_within_budget() -> void:
	var g := BrainGraph.new()
	g.add_node(&"l", &"dense", _identity_layer(8))
	g.add_node(&"a", &"accumulator")
	assert_eq(BrainValidator.validate(g, _registry()).size(), 0)

func test_the_matrix_is_read_row_major_not_transposed() -> void:
	# An identity matrix is the same transposed, so it cannot catch an index
	# mix-up. This one can: two inputs, three outputs, no symmetry anywhere.
	# weight[i][j] lives at i * outputs + j, so out[j] = sum over i of x[i]*w[i][j].
	var g := BrainGraph.new()
	g.add_node(&"one", &"constant", { &"value": 1.0 })
	g.add_node(&"ten", &"constant", { &"value": 10.0 })
	g.add_node(&"p", &"pack")
	g.add_node(&"layer", &"dense", {
		&"inputs": 2.0, &"outputs": 3.0, &"activation": "relu",
		&"weights": [1.0, 2.0, 3.0, 10.0, 20.0, 30.0] as Array[float],
		&"biases": [0.0, 0.0, 0.0] as Array[float],
	})
	g.connect_ports(&"one", &"out", &"p", &"in_0")
	g.connect_ports(&"ten", &"out", &"p", &"in_1")
	g.connect_ports(&"p", &"out", &"layer", &"in")

	assert_eq(BrainValidator.validate(g, _registry()).size(), 0)
	var e := BrainEvaluator.create(g, _registry())
	e.tick(SensorSnapshot.blank())

	var out: Array = e._outputs[&"layer"][&"out"]
	assert_eq(out.size(), 3)
	assert_almost_eq(out[0], 101.0, 1e-6)   # 1*1 + 10*10
	assert_almost_eq(out[1], 202.0, 1e-6)   # 1*2 + 10*20
	assert_almost_eq(out[2], 303.0, 1e-6)   # 1*3 + 10*30

func test_biases_are_added() -> void:
	var g := BrainGraph.new()
	g.add_node(&"layer", &"dense", {
		&"inputs": 1.0, &"outputs": 2.0, &"activation": "tanh",
		&"weights": [0.0, 0.0] as Array[float],
		&"biases": [0.0, 5.0] as Array[float],
	})
	assert_eq(BrainValidator.validate(g, _registry()).size(), 0)
	var e := BrainEvaluator.create(g, _registry())
	e.tick(SensorSnapshot.blank())
	var out: Array = e._outputs[&"layer"][&"out"]
	assert_almost_eq(out[0], 0.0, 1e-6)
	assert_true(out[1] > 0.99, "tanh(5) is nearly 1, got %f" % out[1])

# ------------------------------------------------------------------ end to end

func test_a_hybrid_brain_drives_a_car() -> void:
	# The intended use (spec 2.8): hand-built logic for the safety-critical part,
	# a layer for the part that is awkward to reason about. Here the layer reads
	# the whole ray ring and leans away from whichever side is closer — weights
	# set by hand, but shaped exactly as a trained import would be.
	var g := BrainGraph.new()
	g.name = "Hybrid"
	g.add_node(&"ring", &"ray_ring")
	g.add_node(&"layer", &"dense", {
		&"inputs": 8.0, &"outputs": 2.0, &"activation": "tanh",
		# ray 1 is 45 right, 2 is 90 right, 6 is 90 left, 7 is 45 left.
		# More clearance on the right leans right, and the other way round.
		&"weights": [
			0.0, 0.0,   1.0, 0.0,   0.5, 0.0,   0.0, 0.0,
			0.0, 0.0,   0.0, 0.0,  -0.5, 0.0,  -1.0, 0.0,
		] as Array[float],
		&"biases": [0.0, 0.5] as Array[float],
	})
	g.add_node(&"out", &"unpack")
	g.add_node(&"aim", &"checkpoint")
	g.add_node(&"gain", &"constant", { &"value": 1.5 })
	g.add_node(&"route", &"multiply")
	g.add_node(&"steer_sum", &"add")
	g.add_node(&"steer", &"out_steering")
	g.add_node(&"gas", &"out_throttle")

	g.connect_ports(&"ring", &"distances", &"layer", &"in")
	g.connect_ports(&"layer", &"out", &"out", &"in")
	g.connect_ports(&"aim", &"angle", &"route", &"a")
	g.connect_ports(&"gain", &"out", &"route", &"b")
	g.connect_ports(&"route", &"out", &"steer_sum", &"a")
	g.connect_ports(&"out", &"out_0", &"steer_sum", &"b")   # the layer's opinion
	g.connect_ports(&"steer_sum", &"out", &"steer", &"value")
	g.connect_ports(&"out", &"out_1", &"gas", &"value")

	assert_eq(BrainValidator.validate(g, _registry()).size(), 0, "hybrid must be legal")

	var session := RaceSession.create(g, _registry(), Track.grand_prix())
	for i in 600:
		session.tick()
	assert_true(session.car.checkpoints_passed > 0, "a network-driven car should get moving")
	assert_false(is_nan(session.car.position.x), "nothing may leak a NaN into the sim")
