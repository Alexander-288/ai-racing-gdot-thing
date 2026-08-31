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

func _canvas(editor: BrainEditor) -> BrainCanvas:
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

	var field := _find_spinbox(_views(editor)[0])
	assert_true(field != null, "constant has a setting, so it needs a field")
	assert_almost_eq(field.value, 4.0, 1e-6, "shows the saved value")
	_close(editor)

## Settings sit in the left column beside the sockets, so how deeply a field is
## nested is a layout decision the test should not care about.
func _find_spinbox(node: Node) -> SpinBox:
	for child: Node in node.get_children():
		if child is SpinBox:
			return child as SpinBox
		var deeper := _find_spinbox(child)
		if deeper != null:
			return deeper
	return null

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

# ------------------------------------------------------------------ trays

func _tray_views(editor: BrainEditor) -> Array:
	var out: Array = []
	for child: Node in _canvas(editor).get_children():
		if child is TrayView:
			out.append(child)
	return out

func test_a_tray_is_drawn_behind_the_nodes() -> void:
	# Order among GraphEdit's children is draw order, so this is what "under" means.
	var editor := _open()
	editor.graph.add_node(&"c", &"constant")
	editor.graph.add_tray(&"t", "Group", Vector2.ZERO, Vector2(400, 300))
	editor._rebuild_canvas()

	var children := _canvas(editor).get_children()
	var tray_at := children.find(_tray_views(editor)[0])
	var node_at := children.find(_views(editor)[0])
	assert_true(tray_at < node_at, "the tray must be drawn first, so it ends up underneath")
	_close(editor)

func test_dragging_a_tray_carries_the_nodes_standing_on_it() -> void:
	var editor := _open()
	editor.graph.add_node(&"on_it", &"constant", {}, Vector2(60, 60))
	editor.graph.add_node(&"beside_it", &"constant", {}, Vector2(900, 900))
	editor.graph.add_tray(&"t", "Group", Vector2(20, 20), Vector2(400, 300))
	editor._rebuild_canvas()

	editor._on_move_begin(false)
	var tray: TrayView = _tray_views(editor)[0]
	tray.position_offset += Vector2(100, 50)  # as a grip drag would
	editor._on_moved()

	assert_eq(editor.graph.instances[&"on_it"].position, Vector2(160, 110), "picked up")
	assert_eq(editor.graph.instances[&"beside_it"].position, Vector2(900, 900), "left alone")
	assert_eq(editor.graph.trays[0].position, Vector2(120, 70), "and the tray itself moved")
	_close(editor)

func test_a_node_the_user_is_dragging_is_not_carried_as_well() -> void:
	# Otherwise GraphEdit moves it once and the tray moves it again, and it
	# travels twice as far as the mouse did.
	var editor := _open()
	editor.graph.add_node(&"c", &"constant", {}, Vector2(60, 60))
	editor.graph.add_tray(&"t", "Group", Vector2(20, 20), Vector2(400, 300))
	editor._rebuild_canvas()

	var node: NodeView = _views(editor)[0]
	node.selected = true
	editor._on_move_begin(true)  # GraphEdit is dragging the selection
	var tray: TrayView = _tray_views(editor)[0]
	tray.position_offset += Vector2(100, 0)
	editor._on_moved()

	assert_eq(editor.graph.instances[&"c"].position, Vector2(60, 60), "moved by the drag, not by us")
	_close(editor)

func test_deleting_a_tray_leaves_the_nodes_on_it() -> void:
	var editor := _open()
	editor.graph.add_node(&"c", &"constant", {}, Vector2(60, 60))
	editor.graph.add_tray(&"t", "Group", Vector2(20, 20), Vector2(400, 300))
	editor._rebuild_canvas()

	editor._on_delete([&"t"] as Array[StringName])

	assert_eq(editor.graph.trays.size(), 0)
	assert_eq(editor.graph.instances.size(), 1, "a tray owns nothing it sits behind")
	_close(editor)

func test_the_palette_offers_a_tray() -> void:
	var editor := _open()
	editor._add_tray()
	assert_eq(editor.graph.trays.size(), 1)
	assert_eq(_tray_views(editor).size(), 1, "and it is drawn")
	_close(editor)

func test_a_tray_moves_only_by_its_grip() -> void:
	# Dragging a panel this big by its face would shove the layout around on
	# every stray drag, so GraphEdit is told not to drag trays at all.
	var editor := _open()
	editor.graph.add_tray(&"t", "Group")
	editor._rebuild_canvas()
	assert_false((_tray_views(editor)[0] as TrayView).draggable)
	_close(editor)

func test_the_grip_drag_follows_the_mouse_through_the_zoom() -> void:
	# position_offset is in canvas units and the mouse moves in screen pixels, so
	# a tray dragged at half zoom must travel twice as far as the pointer did.
	var editor := _open()
	editor.graph.add_tray(&"t", "Group", Vector2(100, 100))
	editor._rebuild_canvas()
	_canvas(editor).zoom = 0.5

	var tray: TrayView = _tray_views(editor)[0]
	tray.begin_drag_at(Vector2(500, 500))
	tray.drag_to(Vector2(560, 500))

	assert_eq(tray.position_offset, Vector2(220, 100))
	_close(editor)

func test_a_tray_colour_is_remembered() -> void:
	var editor := _open()
	editor.graph.add_tray(&"t", "Group")
	editor._rebuild_canvas()
	editor._on_tray_colour_changed(&"t", 3)
	assert_eq(editor.graph.get_tray(&"t").colour, 3)
	_close(editor)

func test_a_clicked_tray_does_not_climb_on_top_of_its_nodes() -> void:
	# GraphEdit raises whatever you click to the front. For a tray that would
	# park a full-size panel over the nodes standing on it: they vanish behind it
	# and it eats every click meant for them.
	var editor := _open()
	editor.graph.add_node(&"c", &"constant")
	editor.graph.add_tray(&"t", "Group")
	editor._rebuild_canvas()

	var canvas := _canvas(editor)
	var tray: TrayView = _tray_views(editor)[0]
	canvas.move_child(tray, -1)  # exactly what a click does
	editor._sink_trays()

	var children := canvas.get_children()
	assert_true(children.find(tray) < children.find(_views(editor)[0]),
		"the tray must sink back underneath")
	_close(editor)

func test_every_tray_keeps_its_own_order_when_sunk() -> void:
	var editor := _open()
	editor.graph.add_tray(&"first", "One")
	editor.graph.add_tray(&"second", "Two")
	editor.graph.add_node(&"c", &"constant")
	editor._rebuild_canvas()

	var canvas := _canvas(editor)
	canvas.move_child(editor._trays[&"first"], -1)
	editor._sink_trays()

	var children := canvas.get_children()
	assert_eq(children.find(editor._trays[&"first"]), 0)
	assert_eq(children.find(editor._trays[&"second"]), 1)
	_close(editor)

# ------------------------------------------------------------------ harnesses

## A bundle is one wire carrying eight numbers. It is drawn as three strands so
## it reads as a loom rather than a single core — but it is still one connection.
func _line_from(editor: BrainEditor, node_id: StringName, slot: int) -> PackedVector2Array:
	var view: NodeView = editor._views[node_id]
	var port := view.position_offset + view.get_output_port_position(slot)
	return _canvas(editor)._get_connection_line(port, port + Vector2(300, 80))

func test_a_bundle_wire_is_drawn_as_a_harness() -> void:
	var editor := _open()
	editor.graph.add_node(&"ring", &"ray_ring")   # its outputs are bundles
	editor.graph.add_node(&"k", &"constant")      # its output is one number
	editor._rebuild_canvas()

	var plain := _line_from(editor, &"k", 0)
	var bundle := _line_from(editor, &"ring", 0)

	assert_eq(plain.size(), BrainCanvas.SAMPLES, "a plain wire is one strand")
	assert_eq(bundle.size(), BrainCanvas.SAMPLES * BrainCanvas.STRANDS,
		"a bundle is a harness of strands")
	_close(editor)

func test_a_harness_starts_and_ends_where_the_wire_does() -> void:
	# The strands are offset sideways, so the harness must still begin and end
	# close enough to the sockets that it does not look unplugged.
	var editor := _open()
	editor.graph.add_node(&"ring", &"ray_ring")
	editor._rebuild_canvas()

	var view: NodeView = editor._views[&"ring"]
	var from := view.position_offset + view.get_output_port_position(0)
	var to := from + Vector2(300, 80)
	var harness := _canvas(editor)._get_connection_line(from, to)

	assert_true(harness[0].distance_to(from) <= BrainCanvas.STRAND_GAP * 2.0)
	assert_true(harness[harness.size() - 1].distance_to(to) <= BrainCanvas.STRAND_GAP * 2.0)
	_close(editor)

func test_a_harness_survives_zooming() -> void:
	# GraphEdit hands out port positions already multiplied by the zoom, while a
	# node reports its own unscaled. Miss that conversion and every bundle
	# quietly goes back to being a single line the moment you zoom.
	var editor := _open()
	editor.graph.add_node(&"ring", &"ray_ring")
	editor._rebuild_canvas()

	var canvas := _canvas(editor)
	canvas.zoom = 0.5
	var view: NodeView = editor._views[&"ring"]
	var port := (view.position_offset + view.get_output_port_position(0)) * canvas.zoom
	var line := canvas._get_connection_line(port, port + Vector2(200, 60))

	assert_eq(line.size(), BrainCanvas.SAMPLES * BrainCanvas.STRANDS)
	_close(editor)

# ------------------------------------------------------------------ file actions

const SCRATCH := "user://test_brains"

func _scratch(name: String) -> String:
	DirAccess.make_dir_recursive_absolute(SCRATCH)
	return "%s/%s" % [SCRATCH, name]

func test_a_new_editor_starts_with_no_file() -> void:
	var editor := _open()
	assert_eq(editor._current_path, "")
	assert_false(editor._unsaved, "an empty brain has nothing to lose yet")
	_close(editor)

func test_editing_marks_the_brain_unsaved() -> void:
	var editor := _open()
	editor._add_node(&"constant")
	assert_true(editor._unsaved, "adding a node is a change")
	_close(editor)

func test_saving_clears_the_unsaved_mark_and_remembers_the_file() -> void:
	var editor := _open()
	editor._add_node(&"constant")
	var path := _scratch("remembered.brain")
	assert_true(editor.save_to(path))

	assert_false(editor._unsaved)
	assert_eq(editor._current_path, path, "Save now writes straight back here")
	assert_true(FileAccess.file_exists(path))
	_close(editor)

func test_a_saved_brain_loads_back_the_same() -> void:
	var editor := _open()
	editor.graph.add_node(&"c", &"constant", { &"value": 4.25 })
	var path := _scratch("roundtrip.brain")
	editor.save_to(path)

	var reopened := _open()
	reopened.load_file(path)
	assert_eq(reopened.graph.instances.size(), 1)
	assert_almost_eq(reopened.graph.instances[&"c"].config[&"value"], 4.25)
	assert_eq(reopened._current_path, path)
	assert_false(reopened._unsaved)
	_close(editor)
	_close(reopened)

func test_the_extension_is_added_if_you_leave_it_off() -> void:
	var editor := _open()
	editor.save_to(_scratch("no_extension"))
	assert_true(editor._current_path.ends_with(".brain"), editor._current_path)
	assert_true(FileAccess.file_exists(editor._current_path))
	_close(editor)

func test_saving_a_copy_leaves_you_editing_the_original() -> void:
	# The difference between Save As and Save a Copy: one moves you to the new
	# file, the other does not.
	var editor := _open()
	var original := _scratch("original.brain")
	editor.save_to(original)
	editor._add_node(&"constant")

	editor.save_to(_scratch("a_copy.brain"), false)
	assert_eq(editor._current_path, original, "still editing the original")
	assert_true(editor._unsaved, "and it still has unsaved changes")
	_close(editor)

func test_a_new_brain_forgets_the_old_one() -> void:
	var editor := _open()
	editor.save_to(_scratch("before_new.brain"))
	editor._add_node(&"add")
	editor.new_brain()

	assert_eq(editor.graph.instances.size(), 0)
	assert_eq(editor._current_path, "", "a new brain has no file yet")
	assert_false(editor._unsaved)
	_close(editor)

func test_saving_somewhere_impossible_reports_rather_than_pretends() -> void:
	var editor := _open()
	assert_false(editor.save_to("user://nope/nowhere/at/all/x.brain"))
	assert_eq(editor._current_path, "", "a failed save must not claim the file")
	_close(editor)
