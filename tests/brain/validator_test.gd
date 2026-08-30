extends TestCase

func _registry() -> NodeRegistry:
	return NodeRegistry.create_default()

func test_a_plain_chain_is_valid() -> void:
	var g := BrainGraph.new()
	g.add_node(&"c", &"constant", { &"value": 5.0 })
	g.add_node(&"t", &"threshold")
	g.connect_ports(&"c", &"out", &"t", &"value")
	assert_eq(BrainValidator.validate(g, _registry()).size(), 0)

func test_unknown_node_type_is_rejected() -> void:
	var g := BrainGraph.new()
	g.add_node(&"x", &"rocket_launcher")
	var errors := BrainValidator.validate(g, _registry())
	assert_eq(errors.size(), 1)
	assert_true(errors[0].contains("unknown type"), errors[0])

func test_wire_to_a_socket_that_does_not_exist_is_rejected() -> void:
	var g := BrainGraph.new()
	g.add_node(&"c", &"constant")
	g.add_node(&"t", &"threshold")
	g.connect_ports(&"c", &"out", &"t", &"nonsense")
	var errors := BrainValidator.validate(g, _registry())
	assert_eq(errors.size(), 1)
	assert_true(errors[0].contains("no input called 'nonsense'"), errors[0])

func test_cycle_without_memory_is_rejected() -> void:
	var g := BrainGraph.new()
	g.add_node(&"a", &"add")
	g.add_node(&"b", &"add")
	g.connect_ports(&"a", &"out", &"b", &"a")
	g.connect_ports(&"b", &"out", &"a", &"a")  # straight back — impossible to order
	var errors := BrainValidator.validate(g, _registry())
	assert_eq(errors.size(), 1)
	assert_true(errors[0].contains("cycle"), errors[0])

func test_cycle_through_memory_is_allowed() -> void:
	var g := BrainGraph.new()
	g.add_node(&"acc", &"accumulator")
	g.add_node(&"sum", &"add")
	g.connect_ports(&"acc", &"out", &"sum", &"a")
	g.connect_ports(&"sum", &"out", &"acc", &"add")  # loops, but through memory
	assert_eq(BrainValidator.validate(g, _registry()).size(), 0,
		"a loop is legal exactly when it passes through a stateful node")

func test_sort_puts_producers_before_consumers() -> void:
	var g := BrainGraph.new()
	g.add_node(&"t", &"threshold")  # added first, but depends on the constant
	g.add_node(&"c", &"constant")
	g.connect_ports(&"c", &"out", &"t", &"value")
	var order := BrainValidator.sort_pure_nodes(g, _registry())
	assert_eq(order, [&"c", &"t"] as Array[StringName])
