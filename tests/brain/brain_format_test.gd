extends TestCase

func _counter_graph() -> BrainGraph:
	var g := BrainGraph.new()
	g.name = "Counter"
	g.add_node(&"one", &"constant", { &"value": 1.0 })
	g.add_node(&"acc", &"accumulator")
	g.connect_ports(&"one", &"out", &"acc", &"add")
	return g

func test_written_file_is_readable_by_a_human() -> void:
	var text := BrainFormat.serialize(_counter_graph())
	assert_true(text.contains("node one constant"), text)
	assert_true(text.contains("    value = 1.0"), text)
	assert_true(text.contains("wire one.out -> acc.add"), text)

func test_round_trip_keeps_the_graph() -> void:
	var result := BrainFormat.parse(BrainFormat.serialize(_counter_graph()))
	assert_true(result.ok(), "  ".join(result.errors))
	assert_eq(result.graph.name, "Counter")
	assert_eq(result.graph.instances.size(), 2)
	assert_eq(result.graph.instances[&"one"].type_id, &"constant")
	assert_almost_eq(result.graph.instances[&"one"].config[&"value"], 1.0)
	assert_eq(result.graph.wires.size(), 1)
	assert_eq(result.graph.wires[0].to_port, &"add")

func test_writing_twice_gives_identical_text() -> void:
	# Byte-stable output, so brain files diff cleanly in git.
	var once := BrainFormat.serialize(_counter_graph())
	var twice := BrainFormat.serialize(BrainFormat.parse(once).graph)
	assert_eq(once, twice)

func test_awkward_numbers_survive_the_round_trip() -> void:
	# str() would write 0.33333333333333 and lose the rest. Trained weights depend on this.
	var g := BrainGraph.new()
	g.add_node(&"c", &"constant", { &"value": 1.0 / 3.0 })
	var back := BrainFormat.parse(BrainFormat.serialize(g))
	assert_true(back.ok(), "  ".join(back.errors))
	assert_eq(back.graph.instances[&"c"].config[&"value"], 1.0 / 3.0)

func test_lists_of_weights_survive() -> void:
	var g := BrainGraph.new()
	g.add_node(&"layer", &"dense", { &"weights": [0.5, -0.25, 1.0 / 3.0] as Array[float] })
	var back := BrainFormat.parse(BrainFormat.serialize(g))
	assert_true(back.ok(), "  ".join(back.errors))
	assert_eq(back.graph.instances[&"layer"].config[&"weights"], [0.5, -0.25, 1.0 / 3.0] as Array[float])

func test_a_parsed_graph_still_has_to_pass_validation() -> void:
	# Parsing only checks the text is well formed; whether the type exists is a
	# separate question, answered by the validator.
	var text := "format 1\nname \"Bad\"\n\nnode boom rocket_launcher\n"
	var result := BrainFormat.parse(text)
	assert_true(result.ok(), "text itself is fine")
	var errors := BrainValidator.validate(result.graph, NodeRegistry.create_default())
	assert_eq(errors.size(), 1)
	assert_true(errors[0].contains("unknown type"), errors[0])

func test_comments_and_blank_lines_are_ignored() -> void:
	var text := "# my brain\nformat 1\n\n# the starting number\nnode one constant\n    value = 2.0\n"
	var result := BrainFormat.parse(text)
	assert_true(result.ok(), "  ".join(result.errors))
	assert_almost_eq(result.graph.instances[&"one"].config[&"value"], 2.0)

func test_broken_files_report_the_line_and_do_not_crash() -> void:
	var text := "format 1\nnode one constant\n    value = banana\nwire one.out acc.add\nnonsense here\n"
	var result := BrainFormat.parse(text)
	assert_eq(result.errors.size(), 3)
	assert_true(result.errors[0].contains("line 3"), result.errors[0])
	assert_true(result.errors[1].contains("line 4"), result.errors[1])
	assert_true(result.errors[2].contains("line 5"), result.errors[2])

func test_a_newer_format_version_is_refused() -> void:
	var result := BrainFormat.parse("format 99\n")
	assert_eq(result.errors.size(), 1)
	assert_true(result.errors[0].contains("only reads"), result.errors[0])

func test_parsed_brain_actually_runs() -> void:
	# The whole point: text in, working brain out.
	var text := BrainFormat.serialize(_counter_graph())
	var graph := BrainFormat.parse(text).graph
	var e := BrainEvaluator.create(graph, NodeRegistry.create_default())
	e.tick(SensorSnapshot.blank())
	e.tick(SensorSnapshot.blank())
	e.tick(SensorSnapshot.blank())
	assert_almost_eq(e.output_of(&"acc", &"out"), 2.0, 1e-6)

func test_canvas_positions_survive_a_save() -> void:
	# Layout is not part of the brain's behaviour, but losing it every reload
	# would make the editor useless.
	var g := BrainGraph.new()
	g.add_node(&"c", &"constant", { &"value": 1.0 }, Vector2(120.0, -40.5))
	var back := BrainFormat.parse(BrainFormat.serialize(g))
	assert_true(back.ok(), "  ".join(back.errors))
	assert_almost_eq(back.graph.instances[&"c"].position.x, 120.0)
	assert_almost_eq(back.graph.instances[&"c"].position.y, -40.5)

func test_an_old_file_without_positions_still_loads() -> void:
	var result := BrainFormat.parse("format 1\nnode c constant\n    value = 1.0\n")
	assert_true(result.ok(), "  ".join(result.errors))
	assert_eq(result.graph.instances[&"c"].position, Vector2.ZERO)

# ------------------------------------------------------------------ trays

## Trays are editor furniture, but they live in the brain file for the same
## reason node positions do: it is where the author's layout is kept.
func _trayed_graph() -> BrainGraph:
	var g := _counter_graph()
	var tray := g.add_tray(&"counting", "The counting bit", Vector2(40, 60), Vector2(420, 300))
	tray.colour = 4
	return g

func test_a_tray_round_trips() -> void:
	var result := BrainFormat.parse(BrainFormat.serialize(_trayed_graph()))
	assert_true(result.ok(), "  ".join(result.errors))
	assert_eq(result.graph.trays.size(), 1)
	var tray := result.graph.trays[0]
	assert_eq(tray.id, &"counting")
	assert_eq(tray.title, "The counting bit")
	assert_almost_eq(tray.position.x, 40.0)
	assert_almost_eq(tray.size.y, 300.0)
	assert_eq(tray.colour, 4)
	assert_eq(result.graph.instances.size(), 2, "and the nodes are still there")

func test_a_tray_does_not_disturb_the_nodes_around_it() -> void:
	# A tray block sits between nodes in the file, so the parser has to stop
	# treating the tray's indented lines as settings for the node above it.
	var text := "format 1\nname \"X\"\nnode one constant\n    value = 3.0\n" \
		+ "tray t \"Group\"\n    at 10 20\n    size 200 150\nnode two constant\n    value = 4.0\n"
	var result := BrainFormat.parse(text)
	assert_true(result.ok(), "  ".join(result.errors))
	assert_almost_eq(result.graph.instances[&"one"].config[&"value"], 3.0)
	assert_almost_eq(result.graph.instances[&"two"].config[&"value"], 4.0)
	assert_eq(result.graph.trays[0].title, "Group")
	assert_false(result.graph.instances[&"one"].config.has(&"size"),
		"the tray's own lines must not leak into the node before it")

func test_a_broken_tray_is_reported() -> void:
	var result := BrainFormat.parse("format 1\ntray t \"G\"\n    at 10\n")
	assert_false(result.ok(), "a tray with half a position is not silently accepted")

func test_a_node_left_at_the_origin_stays_there() -> void:
	# The origin used to be indistinguishable from "never placed", so a node
	# parked exactly there was shuffled somewhere else on the next load.
	var g := BrainGraph.new()
	var node := g.add_node(&"c", &"constant")
	node.position = Vector2.ZERO
	node.placed = true

	var text := BrainFormat.serialize(g)
	assert_true(text.contains("at "), "a placed node writes where it is, origin or not")
	var back := BrainFormat.parse(text)
	assert_true(back.ok(), "  ".join(back.errors))
	assert_eq(back.graph.instances[&"c"].position, Vector2.ZERO)
	assert_true(back.graph.instances[&"c"].placed, "and it comes back placed")

func test_a_hand_written_node_with_no_position_is_not_placed() -> void:
	# Which is what lets the editor lay it out rather than stacking it at 0,0.
	var result := BrainFormat.parse("format 1\nnode c constant\n    value = 1.0\n")
	assert_true(result.ok(), "  ".join(result.errors))
	assert_false(result.graph.instances[&"c"].placed)
