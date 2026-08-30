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
	# Parsing only checks the text is well formed; 'dense' is not a real type yet.
	var text := "format 1\nname \"Bad\"\n\nnode layer dense\n"
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
	e.tick()
	e.tick()
	e.tick()
	assert_almost_eq(e.output_of(&"acc", &"out"), 2.0, 1e-6)
