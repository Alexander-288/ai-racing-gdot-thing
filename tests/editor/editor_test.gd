extends TestCase
## The editor is UI, but the parts worth testing are not: that it is genuinely
## driven by the registry, and that what it draws matches the graph underneath.

func _open() -> BrainEditor:
	var editor := BrainEditor.new()
	Engine.get_main_loop().root.add_child(editor)  # so _ready runs and builds the UI
	return editor

func _close(editor: BrainEditor) -> void:
	Engine.get_main_loop().root.remove_child(editor)
	editor.free()

func _canvas(editor: BrainEditor) -> GraphEdit:
	return editor._canvas

func _views(editor: BrainEditor) -> Array:
	var out: Array = []
	for child: Node in _canvas(editor).get_children():
		if child is NodeView:
			out.append(child)
	return out

# ------------------------------------------------------------------ the palette

func test_the_palette_offers_every_registered_node_type() -> void:
	# If this ever needs updating by hand, the editor has stopped being data-driven.
	var editor := _open()
	var offered: Array[String] = []
	for child: Node in editor._palette.get_children():
		if child is Button:
			offered.append((child as Button).text.strip_edges())

	for type: NodeType in editor.registry.all():
		assert_true(offered.has(type.display_name),
			"%s is registered but not in the palette" % type.display_name)
	_close(editor)

# ------------------------------------------------------------------ drawing

func test_a_node_is_drawn_with_a_slot_per_port() -> void:
	var editor := _open()
	editor.graph.add_node(&"t", &"threshold")
	editor._rebuild_canvas()

	var views := _views(editor)
	assert_eq(views.size(), 1)
	var view: NodeView = views[0]
	# Threshold has two inputs and one output, so two rows: both used on the left.
	assert_eq(view.get_child_count(), 2)
	assert_true(view.is_slot_enabled_left(0))
	assert_true(view.is_slot_enabled_left(1))
	assert_true(view.is_slot_enabled_right(0))
	assert_false(view.is_slot_enabled_right(1))
	_close(editor)

func test_a_setting_becomes_a_widget() -> void:
	var editor := _open()
	editor.graph.add_node(&"c", &"constant", { &"value": 4.0 })
	editor._rebuild_canvas()

	var found := false
	for row: Node in _views(editor)[0].get_children():
		for cell: Node in row.get_children():
			if cell is SpinBox:
				found = true
				assert_almost_eq((cell as SpinBox).value, 4.0, 1e-6, "shows the saved value")
	assert_true(found, "constant has a setting, so it needs a field")
	_close(editor)

func test_editing_a_setting_updates_the_graph() -> void:
	var editor := _open()
	editor.graph.add_node(&"c", &"constant", { &"value": 1.0 })
	editor._rebuild_canvas()
	editor._on_config_changed(&"c", &"value", 7.5)
	assert_almost_eq(editor.graph.instances[&"c"].config[&"value"], 7.5)
	_close(editor)

# ------------------------------------------------------------------ wiring

func test_connecting_two_boxes_adds_a_wire_by_port_name() -> void:
	var editor := _open()
	editor.graph.add_node(&"c", &"constant")
	editor.graph.add_node(&"t", &"threshold")
	editor._rebuild_canvas()
	editor._on_connect(&"c", 0, &"t", 0)  # slot numbers in, port names out

	assert_eq(editor.graph.wires.size(), 1)
	assert_eq(editor.graph.wires[0].from_port, &"out")
	assert_eq(editor.graph.wires[0].to_port, &"value")
	assert_eq(_canvas(editor).get_connection_list().size(), 1, "and it is drawn")
	_close(editor)

func test_a_second_wire_into_one_socket_replaces_the_first() -> void:
	# Two values arriving at one input would mean whichever ran last silently won.
	var editor := _open()
	editor.graph.add_node(&"a", &"constant")
	editor.graph.add_node(&"b", &"constant")
	editor.graph.add_node(&"t", &"threshold")
	editor._rebuild_canvas()
	editor._on_connect(&"a", 0, &"t", 0)
	editor._on_connect(&"b", 0, &"t", 0)

	assert_eq(editor.graph.wires.size(), 1)
	assert_eq(editor.graph.wires[0].from_node, &"b", "the newer wire wins")
	_close(editor)

func test_deleting_a_node_takes_its_wires_with_it() -> void:
	var editor := _open()
	editor.graph.add_node(&"c", &"constant")
	editor.graph.add_node(&"t", &"threshold")
	editor._rebuild_canvas()
	editor._on_connect(&"c", 0, &"t", 0)
	editor._on_delete([&"c"] as Array[StringName])

	assert_eq(editor.graph.instances.size(), 1)
	assert_eq(editor.graph.wires.size(), 0, "no wire may point at a node that is gone")
	_close(editor)

# ------------------------------------------------------------------ problems

func test_problems_are_shown_while_you_work() -> void:
	var editor := _open()
	editor.graph.add_node(&"a", &"add")
	editor.graph.add_node(&"b", &"add")
	editor.graph.connect_ports(&"a", &"out", &"b", &"a")
	editor.graph.connect_ports(&"b", &"out", &"a", &"a")
	editor._revalidate()
	assert_true(editor._problems.text.contains("cycle"), editor._problems.text)
	_close(editor)

func test_a_good_graph_says_so() -> void:
	var editor := _open()
	editor.graph.add_node(&"c", &"constant")
	editor._revalidate()
	assert_true(editor._problems.text.contains("valid"), editor._problems.text)
	_close(editor)

# ------------------------------------------------------------------ files

func test_it_opens_the_reference_brain_and_draws_all_of_it() -> void:
	var editor := _open()
	editor.load_file("res://brains/follower.brain")

	assert_eq(editor.graph.instances.size(), 6)
	assert_eq(_views(editor).size(), 6, "every node got a box")
	assert_eq(_canvas(editor).get_connection_list().size(), 4, "every wire got drawn")
	assert_true(editor._problems.text.contains("valid"))
	_close(editor)

func test_a_broken_file_is_reported_not_opened() -> void:
	var editor := _open()
	var before := editor.graph
	editor.load_file("res://brains/does_not_exist.brain")
	assert_true(editor.graph == before, "a failed load must not wipe your work")
	_close(editor)
