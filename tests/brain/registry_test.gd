extends TestCase

func test_lookup_by_id() -> void:
	var r := NodeRegistry.create_default()
	assert_true(r.has_type(&"threshold"))
	assert_eq(r.get_type(&"threshold").display_name, "Threshold")

func test_palette_grouping() -> void:
	var r := NodeRegistry.create_default()
	assert_eq(r.by_category("Memory").size(), 1, "editor palette reads this, not a hand list")

func test_every_input_port_declares_a_default() -> void:
	for type: NodeType in NodeRegistry.create_default().all():
		for port: Port in type.inputs:
			assert_true(port.default_value != null,
				"%s.%s must declare a default" % [type.id, port.id])

func test_each_type_implements_its_contract() -> void:
	for type: NodeType in NodeRegistry.create_default().all():
		if type.stateful:
			assert_true(type.emit.is_valid() and type.commit.is_valid() and type.init_state.is_valid(),
				"%s is stateful: needs init_state, emit, commit" % type.id)
		else:
			assert_true(type.eval.is_valid(), "%s needs eval" % type.id)