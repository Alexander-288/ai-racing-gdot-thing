extends TestCase

func test_lookup_by_id() -> void:
	var r := NodeRegistry.create_default()
	assert_true(r.has_type(&"threshold"))
	assert_eq(r.get_type(&"threshold").display_name, "Threshold")

func test_palette_grouping() -> void:
	var r := NodeRegistry.create_default()
	assert_eq(r.by_category("Outputs").size(), 4, "editor palette reads this, not a hand list")

func test_every_input_port_declares_a_default() -> void:
	for type: NodeType in NodeRegistry.create_default().all():
		for port: Port in type.inputs:
			assert_true(port.default_value != null,
				"%s.%s must declare a default" % [type.id, port.id])

func test_each_type_implements_the_role_it_claims() -> void:
	for type: NodeType in NodeRegistry.create_default().all():
		match type.role:
			NodeType.Role.PURE:
				assert_true(type.eval.is_valid(), "%s is PURE: needs eval" % type.id)
			NodeType.Role.SENSOR:
				assert_true(type.sense.is_valid(), "%s is SENSOR: needs sense" % type.id)
				assert_eq(type.inputs.size(), 0, "%s is SENSOR: must have no inputs" % type.id)
			NodeType.Role.MEMORY:
				assert_true(type.emit.is_valid() and type.commit.is_valid() and type.init_state.is_valid(),
					"%s is MEMORY: needs init_state, emit, commit" % type.id)
			NodeType.Role.OUTPUT:
				assert_true(type.write.is_valid(), "%s is OUTPUT: needs write" % type.id)
				assert_eq(type.outputs.size(), 0, "%s is OUTPUT: must have no outputs" % type.id)