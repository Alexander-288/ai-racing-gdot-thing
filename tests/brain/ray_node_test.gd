extends TestCase
## The Ray node grows: one node can carry up to eight readings, each naming its
## ray by set and index rather than by a flat number.

func _registry() -> NodeRegistry:
	return NodeRegistry.create_default()

func _type() -> NodeType:
	return _registry().get_type(&"ray")

# ------------------------------------------------------------------ geometry

func test_the_cone_is_symmetric_with_nothing_on_the_nose() -> void:
	var angles := SensorBuilder.cone_angles()
	assert_eq(angles.size(), SensorSnapshot.CONE_RAYS)
	for a: float in angles:
		assert_true(absf(a) > 0.001, "no cone ray may point dead ahead, found %f" % a)
	# Six rays, so they pair up either side of the nose.
	for i in angles.size():
		assert_almost_eq(angles[i], -angles[angles.size() - 1 - i], 1e-9, "cone is not symmetric")

func test_straight_ahead_is_the_rings_first_ray() -> void:
	assert_almost_eq(SensorBuilder.ray_angles()[0], 0.0, 1e-9)

func test_the_two_sets_do_not_overlap() -> void:
	# They used to: the old aimed set had a ray at 0 and one at PI, both already
	# in the ring, which wasted two of the six.
	var seen: Dictionary = {}
	for a: float in SensorBuilder.ray_angles():
		var key := snappedf(a, 0.0001)
		assert_false(seen.has(key), "two rays point the same way: %f" % a)
		seen[key] = true

func test_a_set_and_index_names_a_place_in_the_flat_arrays() -> void:
	assert_eq(SensorSnapshot.flat_ray(&"ring", 0), 0)
	assert_eq(SensorSnapshot.flat_ray(&"ring", 7), 7)
	assert_eq(SensorSnapshot.flat_ray(&"cone", 0), 8)
	assert_eq(SensorSnapshot.flat_ray(&"cone", 5), 13)

func test_an_index_past_the_end_wraps_within_its_own_set() -> void:
	assert_eq(SensorSnapshot.flat_ray(&"cone", 6), 8, "a cone has six, so the seventh is the first")
	assert_eq(SensorSnapshot.flat_ray(&"ring", -1), 7)

# ------------------------------------------------------------------ growing

func test_a_fresh_ray_node_has_one_segment() -> void:
	var type := _type()
	var outputs := type.outputs_for(type.config_defaults)
	assert_eq(outputs.size(), 4, "distance and three hit flags")
	assert_eq(outputs[0].id, &"distance", "the first segment keeps the plain names")

func test_growing_adds_four_sockets_each_time() -> void:
	var type := _type()
	assert_eq(type.outputs_for({ &"segments": 3.0 }).size(), 12)
	assert_eq(type.outputs_for({ &"segments": 8.0 }).size(), 32)

func test_later_segments_are_numbered() -> void:
	var ids: Array[StringName] = []
	for p: Port in _type().outputs_for({ &"segments": 2.0 }):
		ids.append(p.id)
	assert_true(ids.has(&"distance"), "segment one stays unnumbered")
	assert_true(ids.has(&"distance_1"))
	assert_true(ids.has(&"hit_car_1"))

func test_it_will_not_grow_past_its_limit() -> void:
	var type := _type()
	assert_eq(type.grow_min, 1)
	assert_eq(type.grow_max, 8)
	assert_true(type.can_grow())

func test_each_segment_gets_its_own_settings() -> void:
	var fields := _type().fields_for({ &"segments": 2.0 })
	var keys: Array[StringName] = []
	for f: ConfigField in fields:
		keys.append(f.key)
	assert_eq(keys, [&"arc", &"index", &"arc_1", &"index_1"] as Array[StringName])

func test_the_set_is_a_dropdown_and_the_index_a_number() -> void:
	var fields := _type().fields_for(_type().config_defaults)
	assert_eq(fields[0].kind, ConfigField.Kind.CHOICE)
	assert_eq(fields[0].choices, ["ring", "cone"] as Array[String])
	assert_eq(fields[1].kind, ConfigField.Kind.NUMBER)

func test_choosing_the_cone_shortens_the_index_range() -> void:
	# A cone has six rays, so offering eight would let you pick one that is not there.
	var ring := _type().fields_for({ &"arc": "ring" })
	var cone := _type().fields_for({ &"arc": "cone" })
	assert_almost_eq(ring[1].maximum, 7.0)
	assert_almost_eq(cone[1].maximum, 5.0)

# ------------------------------------------------------------------ reading

func _read(config: Dictionary, snapshot: SensorSnapshot) -> BrainEvaluator:
	var g := BrainGraph.new()
	g.add_node(&"r", &"ray", config)
	var e := BrainEvaluator.create(g, _registry())
	e.tick(snapshot)
	return e

func test_one_node_reads_several_rays_at_once() -> void:
	var snapshot := SensorSnapshot.blank()
	snapshot.ray_distance[0] = 0.11    # ring 0
	snapshot.ray_distance[7] = 0.22    # ring 7
	snapshot.ray_distance[8] = 0.33    # cone 0

	var e := _read({
		&"segments": 3.0,
		&"arc": "ring", &"index": 0.0,
		&"arc_1": "ring", &"index_1": 7.0,
		&"arc_2": "cone", &"index_2": 0.0,
	}, snapshot)

	assert_almost_eq(e.output_of(&"r", &"distance"), 0.11)
	assert_almost_eq(e.output_of(&"r", &"distance_1"), 0.22)
	assert_almost_eq(e.output_of(&"r", &"distance_2"), 0.33)

func test_a_segment_with_no_settings_falls_back_to_ring_zero() -> void:
	var snapshot := SensorSnapshot.blank()
	snapshot.ray_distance[0] = 0.45
	var e := _read({ &"segments": 2.0 }, snapshot)
	assert_almost_eq(e.output_of(&"r", &"distance_1"), 0.45, 1e-6, "unset means ring 0, not a crash")

func test_hit_flags_come_through_per_segment() -> void:
	var snapshot := SensorSnapshot.blank()
	snapshot.ray_hit_car[8] = true     # cone 0
	var e := _read({ &"segments": 2.0, &"arc_1": "cone", &"index_1": 0.0 }, snapshot)
	assert_almost_eq(e.output_of(&"r", &"hit_car_1"), 1.0)
	assert_almost_eq(e.output_of(&"r", &"hit_car"), 0.0)

func test_a_grown_node_still_saves_and_loads() -> void:
	var g := BrainGraph.new()
	g.add_node(&"r", &"ray", { &"segments": 3.0, &"arc_2": "cone", &"index_2": 4.0 })
	var back := BrainFormat.parse(BrainFormat.serialize(g))
	assert_true(back.ok(), "  ".join(back.errors))
	assert_almost_eq(back.graph.instances[&"r"].config[&"segments"], 3.0)
	assert_eq(back.graph.instances[&"r"].config[&"arc_2"], "cone")
	assert_eq(BrainValidator.validate(back.graph, _registry()).size(), 0)

func test_a_wire_from_a_grown_socket_validates() -> void:
	var g := BrainGraph.new()
	g.add_node(&"r", &"ray", { &"segments": 2.0 })
	g.add_node(&"gas", &"out_throttle")
	g.connect_ports(&"r", &"distance_1", &"gas", &"value")
	assert_eq(BrainValidator.validate(g, _registry()).size(), 0)

func test_a_wire_from_a_socket_the_node_does_not_have_is_rejected() -> void:
	var g := BrainGraph.new()
	g.add_node(&"r", &"ray", { &"segments": 1.0 })
	g.add_node(&"gas", &"out_throttle")
	g.connect_ports(&"r", &"distance_5", &"gas", &"value")
	var errors := BrainValidator.validate(g, _registry())
	assert_eq(errors.size(), 1)
	assert_true(errors[0].contains("no output called"), errors[0])
