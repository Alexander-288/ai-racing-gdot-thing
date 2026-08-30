extends TestCase

func test_threshold_fires_above_target() -> void:
	var t := ThresholdNode.define()
	var out: Dictionary = t.eval.call({ &"value": 5.0, &"target": 3.0 }, {})
	assert_almost_eq(out[&"out"], 1.0)

func test_threshold_is_strict() -> void:
	var t := ThresholdNode.define()
	var out: Dictionary = t.eval.call({ &"value": 3.0, &"target": 3.0 }, {})
	assert_almost_eq(out[&"out"], 0.0, 1e-6, "equal is not above")

func test_defaults_cover_every_input() -> void:
	var t := ThresholdNode.define()
	var out: Dictionary = t.eval.call(t.input_defaults(), {})
	assert_almost_eq(out[&"out"], 0.0, 1e-6, "an unwired node must still evaluate")