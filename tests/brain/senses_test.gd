extends TestCase
## The sensor and control nodes, and a whole brain driving from senses to steering.

func _registry() -> NodeRegistry:
	return NodeRegistry.create_default()

# ------------------------------------------------------------------ sensors

func test_ray_node_reads_the_ray_it_was_configured_for() -> void:
	var snapshot := SensorSnapshot.blank()
	snapshot.ray_distance[3] = 0.25
	snapshot.ray_hit_car[3] = true

	var g := BrainGraph.new()
	g.add_node(&"r", &"ray", { &"index": 3.0 })
	var e := BrainEvaluator.create(g, _registry())
	e.tick(snapshot)

	assert_almost_eq(e.output_of(&"r", &"distance"), 0.25)
	assert_almost_eq(e.output_of(&"r", &"hit_car"), 1.0, 1e-6, "booleans travel as 1.0")
	assert_almost_eq(e.output_of(&"r", &"hit_track"), 0.0)

func test_a_silly_ray_index_wraps_rather_than_reading_clear() -> void:
	# The index comes out of a brain file, so it cannot be trusted to be sane.
	# It wraps to a real ray on purpose: reporting "nothing there" would tell the
	# brain the road ahead is open, which is the dangerous way to be wrong.
	var snapshot := SensorSnapshot.blank()
	snapshot.ray_distance[3] = 0.2   # ring 3

	var g := BrainGraph.new()
	g.add_node(&"r", &"ray", { &"arc": "ring", &"index": 11.0 })  # 11 wraps to 3
	var e := BrainEvaluator.create(g, _registry())
	e.tick(snapshot)
	assert_almost_eq(e.output_of(&"r", &"distance"), 0.2, 1e-6, "wrapped to a real reading")

func test_checkpoint_angle_is_measured_from_straight_ahead() -> void:
	var snapshot := SensorSnapshot.blank()
	snapshot.checkpoints = [Vector2(1.0, 1.0)]  # equally right and forward

	var g := BrainGraph.new()
	g.add_node(&"cp", &"checkpoint", { &"index": 0.0 })
	var e := BrainEvaluator.create(g, _registry())
	e.tick(snapshot)

	assert_almost_eq(e.output_of(&"cp", &"angle"), PI / 4.0, 1e-6, "45 degrees to the right")
	assert_almost_eq(e.output_of(&"cp", &"right"), 1.0)

func test_self_state_reports_the_car() -> void:
	var snapshot := SensorSnapshot.blank()
	snapshot.speed = 42.0
	snapshot.on_track = false

	var g := BrainGraph.new()
	g.add_node(&"me", &"self_state")
	var e := BrainEvaluator.create(g, _registry())
	e.tick(snapshot)

	assert_almost_eq(e.output_of(&"me", &"speed"), 42.0)
	assert_almost_eq(e.output_of(&"me", &"on_track"), 0.0)

# ------------------------------------------------------------------ controls

func test_controls_start_neutral_when_nothing_is_wired() -> void:
	var g := BrainGraph.new()
	g.add_node(&"steer", &"out_steering")
	var controls := BrainEvaluator.create(g, _registry()).tick(SensorSnapshot.blank())
	assert_almost_eq(controls.steering, 0.0, 1e-6, "an unwired brain drives straight")
	assert_almost_eq(controls.throttle, 0.0)

func test_a_brain_with_no_output_nodes_still_returns_controls() -> void:
	var g := BrainGraph.new()
	g.add_node(&"c", &"constant", { &"value": 1.0 })
	var controls := BrainEvaluator.create(g, _registry()).tick(SensorSnapshot.blank())
	assert_almost_eq(controls.throttle, 0.0, 1e-6, "does nothing, but does not crash")

func test_controls_are_clamped_however_mad_the_graph_is() -> void:
	var g := BrainGraph.new()
	g.add_node(&"huge", &"constant", { &"value": 500.0 })
	g.add_node(&"steer", &"out_steering")
	g.connect_ports(&"huge", &"out", &"steer", &"value")
	var controls := BrainEvaluator.create(g, _registry()).tick(SensorSnapshot.blank())
	assert_almost_eq(controls.steering, 1.0, 1e-6, "hard right, not 500")

func test_drs_is_a_yes_or_no() -> void:
	var g := BrainGraph.new()
	g.add_node(&"c", &"constant", { &"value": 0.9 })
	g.add_node(&"drs", &"out_drs")
	g.connect_ports(&"c", &"out", &"drs", &"value")
	assert_true(BrainEvaluator.create(g, _registry()).tick(SensorSnapshot.blank()).drs)

# ------------------------------------------------------------------ wiring rules

func test_a_bool_may_drive_a_float_socket() -> void:
	# Gating: multiply something by hit_car to switch it off when nothing is there.
	var g := BrainGraph.new()
	g.add_node(&"r", &"ray")
	g.add_node(&"gas", &"out_throttle")
	g.connect_ports(&"r", &"hit_car", &"gas", &"value")
	assert_eq(BrainValidator.validate(g, _registry()).size(), 0)

func test_a_float_may_not_drive_a_bool_socket() -> void:
	var g := BrainGraph.new()
	g.add_node(&"r", &"ray")
	g.add_node(&"drs", &"out_drs")
	g.connect_ports(&"r", &"distance", &"drs", &"value")  # a distance is not a yes or no
	var errors := BrainValidator.validate(g, _registry())
	assert_eq(errors.size(), 1)
	assert_true(errors[0].contains("cannot wire FLOAT into BOOL"), errors[0])

# ------------------------------------------------------------------ end to end

## A real, tiny brain: steer towards the next checkpoint, throttle unless something
## is close ahead. This is the shape the reference brains will take.
func _follower() -> BrainGraph:
	var g := BrainGraph.new()
	g.name = "Checkpoint Follower"
	g.add_node(&"cp", &"checkpoint", { &"index": 0.0 })
	g.add_node(&"gain", &"constant", { &"value": 2.0 })
	g.add_node(&"steer_amount", &"multiply")  # angle scaled up, so a small angle still steers
	g.add_node(&"steer", &"out_steering")
	g.add_node(&"cruise", &"constant", { &"value": 0.6 })
	g.add_node(&"gas", &"out_throttle")

	g.connect_ports(&"cp", &"angle", &"steer_amount", &"a")
	g.connect_ports(&"gain", &"out", &"steer_amount", &"b")
	g.connect_ports(&"steer_amount", &"out", &"steer", &"value")
	g.connect_ports(&"cruise", &"out", &"gas", &"value")
	return g

func test_follower_brain_is_valid() -> void:
	assert_eq(BrainValidator.validate(_follower(), _registry()).size(), 0)

func test_follower_steers_towards_a_checkpoint_on_the_right() -> void:
	var snapshot := SensorSnapshot.blank()
	snapshot.checkpoints = [Vector2(5.0, 5.0)]  # off to the right
	var controls := BrainEvaluator.create(_follower(), _registry()).tick(snapshot)
	assert_true(controls.steering > 0.0, "positive steering is right")
	assert_almost_eq(controls.throttle, 0.6)

func test_follower_steers_the_other_way_for_a_checkpoint_on_the_left() -> void:
	var snapshot := SensorSnapshot.blank()
	snapshot.checkpoints = [Vector2(-5.0, 5.0)]
	var controls := BrainEvaluator.create(_follower(), _registry()).tick(snapshot)
	assert_true(controls.steering < 0.0, "negative steering is left")

func test_follower_survives_a_full_round_trip_through_a_file() -> void:
	var text := BrainFormat.serialize(_follower())
	var loaded := BrainFormat.parse(text)
	assert_true(loaded.ok(), "  ".join(loaded.errors))
	assert_eq(BrainValidator.validate(loaded.graph, _registry()).size(), 0)

	var snapshot := SensorSnapshot.blank()
	snapshot.checkpoints = [Vector2(5.0, 5.0)]
	var from_file := BrainEvaluator.create(loaded.graph, _registry()).tick(snapshot)
	var from_memory := BrainEvaluator.create(_follower(), _registry()).tick(snapshot)
	assert_almost_eq(from_file.steering, from_memory.steering, 1e-9, "the file is the brain")
