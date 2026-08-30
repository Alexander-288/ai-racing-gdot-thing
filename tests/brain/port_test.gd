extends TestCase

func test_input_port_carries_its_default() -> void:
	var p := Port.make_input(&"value", "Value", 0.0)
	assert_eq(p.id, &"value")
	assert_almost_eq(p.default_value, 0.0)
	assert_eq(p.kind, Port.Kind.FLOAT)

func test_output_port_carries_its_clamp_range() -> void:
	var p := Port.make_output(&"out", "Out", 0.0, 1.0)
	assert_almost_eq(p.min_value, 0.0)
	assert_almost_eq(p.max_value, 1.0)