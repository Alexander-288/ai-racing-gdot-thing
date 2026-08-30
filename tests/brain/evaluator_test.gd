extends TestCase

func _eval(g: BrainGraph) -> BrainEvaluator:
	var registry := NodeRegistry.create_default()
	assert_eq(BrainValidator.validate(g, registry).size(), 0, "fixture graph must be valid")
	return BrainEvaluator.create(g, registry)

func test_values_flow_along_the_wires() -> void:
	var g := BrainGraph.new()
	g.add_node(&"c", &"constant", { &"value": 5.0 })
	g.add_node(&"t", &"threshold", {})
	g.connect_ports(&"c", &"out", &"t", &"value")  # target stays at its default 0.0
	var e := _eval(g)
	e.tick(SensorSnapshot.blank())
	assert_almost_eq(e.output_of(&"t", &"out"), 1.0, 1e-6, "5 is above 0")

func test_unwired_input_uses_its_default() -> void:
	var g := BrainGraph.new()
	g.add_node(&"sum", &"add")  # nothing connected at all
	var e := _eval(g)
	e.tick(SensorSnapshot.blank())
	assert_almost_eq(e.output_of(&"sum", &"out"), 0.0)

func test_output_is_clamped_to_its_declared_range() -> void:
	var g := BrainGraph.new()
	g.add_node(&"c", &"constant", { &"value": 900.0 })
	g.add_node(&"t", &"threshold")
	g.connect_ports(&"c", &"out", &"t", &"value")
	var e := _eval(g)
	e.tick(SensorSnapshot.blank())
	assert_almost_eq(e.output_of(&"t", &"out"), 1.0, 1e-6, "threshold declares 0..1")

func test_loop_through_memory_counts_up_one_per_tick() -> void:
	# acc -> add(+1) -> back into acc. Legal only because it passes through memory.
	var g := BrainGraph.new()
	g.add_node(&"acc", &"accumulator")
	g.add_node(&"one", &"constant", { &"value": 1.0 })
	g.add_node(&"sum", &"add")
	g.connect_ports(&"one", &"out", &"sum", &"a")
	g.connect_ports(&"sum", &"out", &"acc", &"add")
	var e := _eval(g)

	e.tick(SensorSnapshot.blank())
	assert_almost_eq(e.output_of(&"acc", &"out"), 0.0, 1e-6, "tick 1 still reports the start value")
	e.tick(SensorSnapshot.blank())
	assert_almost_eq(e.output_of(&"acc", &"out"), 1.0, 1e-6)
	e.tick(SensorSnapshot.blank())
	assert_almost_eq(e.output_of(&"acc", &"out"), 2.0, 1e-6)

func test_reset_wipes_memory_so_brains_spawn_clean() -> void:
	var g := BrainGraph.new()
	g.add_node(&"acc", &"accumulator")
	g.add_node(&"one", &"constant", { &"value": 1.0 })
	g.connect_ports(&"one", &"out", &"acc", &"add")
	var e := _eval(g)
	e.tick(SensorSnapshot.blank())
	e.tick(SensorSnapshot.blank())
	e.tick(SensorSnapshot.blank())
	assert_almost_eq(e.output_of(&"acc", &"out"), 2.0, 1e-6)
	e.reset()
	e.tick(SensorSnapshot.blank())
	assert_almost_eq(e.output_of(&"acc", &"out"), 0.0, 1e-6, "no map survives across races")

func test_same_inputs_give_the_same_trace_twice() -> void:
	# The determinism promise in miniature: two fresh runs, identical numbers.
	var trace_a := _run_trace()
	var trace_b := _run_trace()
	assert_eq(trace_a, trace_b)

func _run_trace() -> Array[float]:
	var g := BrainGraph.new()
	g.add_node(&"acc", &"accumulator")
	g.add_node(&"half", &"constant", { &"value": 0.5 })
	g.add_node(&"sum", &"add")
	g.connect_ports(&"half", &"out", &"sum", &"a")
	g.connect_ports(&"acc", &"out", &"sum", &"b")
	g.connect_ports(&"sum", &"out", &"acc", &"add")
	var e := _eval(g)
	var trace: Array[float] = []
	for i in 20:
		e.tick(SensorSnapshot.blank())
		trace.append(e.output_of(&"acc", &"out"))
	return trace
