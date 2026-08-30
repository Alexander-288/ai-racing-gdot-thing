extends TestCase

func test_emit_outputs_last_ticks_value_not_this_ticks() -> void:
	var t := AccumulatorNode.define()
	var state: Dictionary = t.init_state.call()

	# Tick 1: emit happens BEFORE commit, so the output is still the old value.
	var out1: Dictionary = t.emit.call(state, {})
	assert_almost_eq(out1[&"out"], 0.0, 1e-6, "tick 1 emits the initial value")
	t.commit.call({ &"add": 5.0, &"set_value": 0.0, &"set_trigger": 0.0, &"reset": 0.0 }, {}, state)

	# Tick 2: only now does the +5 become visible. This one-tick lag is what breaks cycles.
	var out2: Dictionary = t.emit.call(state, {})
	assert_almost_eq(out2[&"out"], 5.0, 1e-6, "tick 2 emits what tick 1 committed")

func test_reset_wins_over_add() -> void:
	var t := AccumulatorNode.define()
	var state: Dictionary = t.init_state.call()
	t.commit.call({ &"add": 5.0, &"set_value": 0.0, &"set_trigger": 0.0, &"reset": 0.0 }, {}, state)
	t.commit.call({ &"add": 5.0, &"set_value": 0.0, &"set_trigger": 0.0, &"reset": 1.0 }, {}, state)
	assert_almost_eq(t.emit.call(state, {})[&"out"], 0.0)