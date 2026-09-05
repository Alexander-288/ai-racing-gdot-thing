class_name BrainEditor
extends Control
## The brain editor. Reads and writes the brain file format, and never evaluates
## anything (spec 3). Its palette, its boxes and its sockets all come from the
## node registry, so new node types need no editor code at all.

const SAVE_DIR := "user://brains"

var registry: NodeRegistry
var graph: BrainGraph

var _canvas: BrainCanvas
var _palette: VBoxContainer
var _problems: RichTextLabel
var _views: Dictionary = {}   # node id -> NodeView
var _trays: Dictionary = {}   # tray id -> TrayView
## While a drag is running: per tray, which nodes it picked up and where it was
## last frame. Empty at every other moment.
var _carried: Dictionary = {}

## Where Save writes. Empty until the brain has been given a file, at which point
## Save overwrites it and only Save As asks again.
var _current_path: String = ""
var _unsaved := false
var _file_label: Label

func _ready() -> void:
	registry = NodeRegistry.create_default()
	graph = BrainGraph.new()
	graph.name = "New Brain"
	_build_ui()
	_rebuild_canvas()
	_revalidate()

# ---------------------------------------------------------------- the window

func _build_ui() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	# Set once, on the root: every child control inherits it, including the node
	# boxes the canvas builds later.
	theme = EditorTheme.build()

	var split := HSplitContainer.new()
	split.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(split)

	var frame := PanelContainer.new()
	frame.theme_type_variation = &"Sidebar"
	frame.custom_minimum_size.x = 200
	split.add_child(frame)

	var side := VBoxContainer.new()
	side.add_theme_constant_override("separation", 6)
	frame.add_child(side)

	# The palette outgrew the window once the registry passed twenty types, so it
	# scrolls. The scroll container is what expands; the list inside it grows to
	# whatever height it needs.
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	side.add_child(scroll)

	# The palette is a loop over the registry, never a hand-written list.
	_palette = VBoxContainer.new()
	_palette.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_palette.add_theme_constant_override("separation", 2)
	scroll.add_child(_palette)
	_build_palette()

	side.add_child(HSeparator.new())

	_file_label = Label.new()
	_file_label.clip_text = true
	side.add_child(_file_label)

	side.add_child(_button("Test Drive", _on_test_drive))
	side.add_child(_button("New Brain", _on_new))
	side.add_child(_build_save_row())
	side.add_child(_button("Load", _on_load))

	_problems = RichTextLabel.new()
	_problems.custom_minimum_size.y = 110
	_problems.bbcode_enabled = true
	side.add_child(_problems)

	var right := VBoxContainer.new()
	split.add_child(right)

	_canvas = BrainCanvas.new()
	_canvas.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_canvas.right_disconnects = true
	# Dotted grid and fat, lazy curves — the two things that make a node canvas
	# read as wiring rather than as a flowchart.
	_canvas.grid_pattern = GraphEdit.GRID_PATTERN_DOTS
	_canvas.connection_lines_curvature = 0.65
	# GraphEdit draws one line per wire, and that line is the backing rail: the
	# four strands over it are painted by CableLayer.
	_canvas.connection_lines_thickness = CableStyle.BACKING_WIDTH
	_canvas.connection_lines_antialiased = true
	# The sockets and dots are drawn at one texel per pixel, so magnifying far
	# past life size only magnifies their pixels. This is where that stops.
	_canvas.zoom_max = 1.5
	# The minimap earns its place on a big brain, but only as a quiet corner of
	# the canvas rather than a bright grey slab sitting on top of it.
	_canvas.minimap_size = Vector2(140, 90)
	_canvas.minimap_opacity = 0.5
	_canvas.connection_request.connect(_on_connect)
	_canvas.disconnection_request.connect(_on_disconnect)
	_canvas.delete_nodes_request.connect(_on_delete)
	# GraphEdit only ever drags nodes now, so it always wants the selection left
	# out — see _on_move_begin.
	_canvas.begin_node_move.connect(_on_move_begin.bind(true))
	_canvas.end_node_move.connect(_on_moved)
	right.add_child(_canvas)

## Preferred reading order first, then anything else the registry knows about.
## The second half is what stops a new category quietly vanishing from the palette.
const CATEGORY_ORDER := ["Sensors", "Math", "Bundles", "Memory", "Outputs"]

func _palette_categories() -> Array[String]:
	var ordered: Array[String] = []
	for wanted: String in CATEGORY_ORDER:
		if registry.categories().has(wanted):
			ordered.append(wanted)
	for extra: String in registry.categories():
		if not ordered.has(extra):
			ordered.append(extra)
	return ordered

func _build_palette() -> void:
	for category: String in _palette_categories():
		var types := registry.by_category(category)
		if types.is_empty():
			continue
		var heading := Label.new()
		heading.text = category.to_upper()
		heading.theme_type_variation = &"CategoryLabel"
		_palette.add_child(heading)
		for type: NodeType in types:
			var entry := _button(type.display_name, func() -> void: _add_node(type.id))
			entry.theme_type_variation = &"PaletteButton"
			entry.alignment = HORIZONTAL_ALIGNMENT_LEFT
			# A dot in the node's own role colour, so the palette and the canvas
			# agree about what a sensor looks like before you have placed one.
			entry.icon = EditorTheme.dot(EditorTheme.role_colour(type.role), 9)
			_palette.add_child(entry)

	# The one hand-written palette entry, because a tray is not a node type and
	# has no business in the registry: it computes nothing.
	var heading := Label.new()
	heading.text = "LAYOUT"
	heading.theme_type_variation = &"CategoryLabel"
	_palette.add_child(heading)
	var tray_entry := _button("Tray", _add_tray)
	tray_entry.theme_type_variation = &"PaletteButton"
	tray_entry.alignment = HORIZONTAL_ALIGNMENT_LEFT
	tray_entry.icon = EditorTheme.dot(EditorTheme.TRAY_TITLE, 9)
	_palette.add_child(tray_entry)

## Save is one click; the arrow beside it opens the less common choices. Keeping
## Save As behind a dropdown means the common action stays a single button, and
## the rare one is still one gesture away.
func _build_save_row() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 2)

	var save := _button("Save", _on_save)
	save.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(save)

	var more := MenuButton.new()
	more.text = "▾"  # a small down arrow
	more.tooltip_text = "More save options"
	more.flat = false
	var menu := more.get_popup()
	menu.add_item("Save As...", 0)
	menu.add_item("Save a Copy...", 1)
	menu.id_pressed.connect(func(id: int) -> void:
		if id == 0:
			_ask_for_path(true)
		else:
			_ask_for_path(false))  # a copy leaves the open file where it was
	row.add_child(more)

	return row

func _button(text: String, action: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.pressed.connect(action)
	return b

# ---------------------------------------------------------------- editing

## Node ids must be unique and stable, because they are what a save file refers to.
func _unique_id(type_id: StringName) -> StringName:
	var n := 1
	while graph.instances.has(StringName("%s_%d" % [type_id, n])):
		n += 1
	return StringName("%s_%d" % [type_id, n])

func _add_node(type_id: StringName) -> void:
	var where := (_canvas.scroll_offset + Vector2(220, 160)) / _canvas.zoom
	graph.add_node(_unique_id(type_id), type_id, {}, where)
	_rebuild_canvas()
	_mark_unsaved()
	_revalidate()

func _unique_tray_id() -> StringName:
	var n := 1
	while graph.has_tray(StringName("tray_%d" % n)):
		n += 1
	return StringName("tray_%d" % n)

func _add_tray() -> void:
	var where := (_canvas.scroll_offset + Vector2(160, 120)) / _canvas.zoom
	graph.add_tray(_unique_tray_id(), "", where)
	_rebuild_canvas()

func _on_delete(names: Array[StringName]) -> void:
	for view_name: StringName in names:
		if graph.has_tray(view_name):
			graph.remove_tray(view_name)
		else:
			graph.remove_node(view_name)
	_rebuild_canvas()
	_mark_unsaved()
	_revalidate()

func _on_connect(from_view: StringName, from_slot: int, to_view: StringName, to_slot: int) -> void:
	var from_port := _port_id(from_view, from_slot, true)
	var to_port := _port_id(to_view, to_slot, false)

	# One wire per input socket: a second one would silently overwrite the first.
	for w: BrainGraph.Wire in graph.wires.duplicate():
		if w.to_node == to_view and w.to_port == to_port:
			graph.disconnect_ports(w.from_node, w.from_port, w.to_node, w.to_port)

	graph.connect_ports(from_view, from_port, to_view, to_port)
	_sync_connections()
	_mark_unsaved()
	_revalidate()

func _on_disconnect(from_view: StringName, from_slot: int, to_view: StringName, to_slot: int) -> void:
	graph.disconnect_ports(from_view, _port_id(from_view, from_slot, true),
		to_view, _port_id(to_view, to_slot, false))
	_sync_connections()
	_mark_unsaved()
	_revalidate()

## A tray picks up whatever is standing on it. The set is worked out once, when
## the drag starts, so a node cannot join or leave a tray halfway through one.
##
## skip_selected is the difference between the two ways a tray can move. When
## GraphEdit drags a selection that happens to include a tray, it is already
## moving the selected nodes, and carrying them too would send them twice as far.
## When the tray moves by its own grip, GraphEdit is not moving anything, so
## everything standing on the tray comes along.
func _on_move_begin(skip_selected: bool) -> void:
	_carried.clear()
	for tray_id: StringName in _trays:
		var tray: TrayView = _trays[tray_id]
		var riding: Array[StringName] = []
		for node_id: StringName in _views:
			var view: NodeView = _views[node_id]
			if skip_selected and view.selected:
				continue
			if tray.canvas_rect().has_point(view.position_offset + view.size * 0.5):
				riding.append(node_id)
		_carried[tray_id] = { "anchor": tray.position_offset, "riding": riding }

## Called every time a tray shifts during a drag, which is why it works from the
## step since last frame rather than from where the drag began.
func _on_tray_moved(tray_id: StringName) -> void:
	if not _carried.has(tray_id):
		return
	var state: Dictionary = _carried[tray_id]
	var tray: TrayView = _trays[tray_id]
	var step: Vector2 = tray.position_offset - (state["anchor"] as Vector2)
	state["anchor"] = tray.position_offset
	for node_id: StringName in state["riding"]:
		var view: NodeView = _views[node_id]
		view.position_offset += step

func _on_tray_title_changed(tray_id: StringName, title: String) -> void:
	graph.get_tray(tray_id).title = title

func _on_tray_colour_changed(tray_id: StringName, colour: int) -> void:
	graph.get_tray(tray_id).colour = colour

func _on_tray_resized(tray_id: StringName, new_size: Vector2) -> void:
	graph.get_tray(tray_id).size = new_size

func _on_moved() -> void:
	_carried.clear()
	for id: StringName in _views:
		var view: NodeView = _views[id]
		graph.instances[id].position = view.position_offset
	for tray_id: StringName in _trays:
		graph.get_tray(tray_id).position = (_trays[tray_id] as TrayView).position_offset
	_mark_unsaved()

func _on_config_changed(node_id: StringName, key: StringName, value: Variant) -> void:
	var instance: BrainGraph.Instance = graph.instances[node_id]
	instance.config[key] = value
	_mark_unsaved()

	# A dropdown can change what the rest of the node looks like — picking the
	# cone leaves fewer rays to choose from — so those rebuild the box. A number
	# does not, and rebuilding on every keystroke would take the field's focus away.
	if _is_choice(instance, key):
		_prune_wires(node_id)
		_rebuild_canvas()
	_revalidate()

func _is_choice(instance: BrainGraph.Instance, key: StringName) -> bool:
	var type := registry.get_type(instance.type_id)
	if type == null:
		return false
	for field: ConfigField in type.fields_for(instance.config):
		if field.key == key:
			return field.kind == ConfigField.Kind.CHOICE
	return false

## Growing or shrinking a node changes how many sockets it has, so any wire left
## pointing at a socket that is gone has to go with it.
func _on_shape_changed(node_id: StringName, segments: int) -> void:
	var instance: BrainGraph.Instance = graph.instances[node_id]
	var type := registry.get_type(instance.type_id)
	if type == null:
		return
	instance.config[type.grow_key] = float(clampi(segments, type.grow_min, type.grow_max))
	_prune_wires(node_id)
	_mark_unsaved()
	_rebuild_canvas()
	_revalidate()

## Drops every wire that refers to a socket this node no longer has. Leaving one
## behind would be a wire the validator rejects and the canvas cannot draw.
func _prune_wires(node_id: StringName) -> void:
	var instance: BrainGraph.Instance = graph.instances[node_id]
	var type := registry.get_type(instance.type_id)
	if type == null:
		return
	var outputs := _port_ids(type.outputs_for(instance.config))
	var inputs := _port_ids(type.inputs_for(instance.config))

	for w: BrainGraph.Wire in graph.wires.duplicate():
		var gone := (w.from_node == node_id and not outputs.has(w.from_port)) 			or (w.to_node == node_id and not inputs.has(w.to_port))
		if gone:
			graph.disconnect_ports(w.from_node, w.from_port, w.to_node, w.to_port)

static func _port_ids(ports: Array[Port]) -> Array[StringName]:
	var ids: Array[StringName] = []
	for p: Port in ports:
		ids.append(p.id)
	return ids

# ---------------------------------------------------------------- drawing it

func _rebuild_canvas() -> void:
	_canvas.clear_connections()
	for view: Node in _canvas.get_children():
		if view is NodeView or view is TrayView:
			view.queue_free()
			_canvas.remove_child(view)
	_views.clear()
	_trays.clear()
	_carried.clear()

	_auto_layout()

	# Trays go in first: GraphEdit draws its children in order, so anything added
	# afterwards stands on top of them.
	for tray: BrainGraph.Tray in graph.trays:
		var tray_view := TrayView.build(tray)
		tray_view.title_changed.connect(_on_tray_title_changed)
		tray_view.tray_resized.connect(_on_tray_resized)
		tray_view.position_offset_changed.connect(_on_tray_moved.bind(tray.id))
		tray_view.colour_changed.connect(_on_tray_colour_changed)
		# A tray moves by its grip, which GraphEdit knows nothing about, so the
		# start and end of that drag are announced by the tray itself.
		tray_view.drag_started.connect(func(_id: StringName) -> void: _on_move_begin(false))
		tray_view.drag_ended.connect(func(_id: StringName) -> void: _on_moved())
		# Clicking any element makes GraphEdit raise it to the front. For a panel
		# the size of a tray that means it lands on top of every node it was
		# holding, hiding them and swallowing their clicks — so a tray asked to
		# rise is put straight back down. Deferred, because it has to run after
		# GraphEdit has done the raising.
		tray_view.raise_request.connect(_sink_trays, CONNECT_DEFERRED)
		_canvas.add_child(tray_view)
		_trays[tray.id] = tray_view

	for inst: BrainGraph.Instance in graph.instances.values():
		var type := registry.get_type(inst.type_id)
		if type == null:
			continue  # unknown types are reported by the validator, not drawn
		var view := NodeView.build(inst, type)
		view.config_changed.connect(_on_config_changed)
		view.shape_changed.connect(_on_shape_changed)
		_canvas.add_child(view)
		_views[inst.id] = view

	_sync_connections()

## Trays live at the bottom of the canvas's child list, because that list is the
## draw order and the pick order both: last child drawn on top, last child asked
## first whether the mouse hit it. Everything that keeps a tray underneath the
## nodes comes down to this one ordering.
func _sink_trays() -> void:
	var index := 0
	for tray: BrainGraph.Tray in graph.trays:
		if _trays.has(tray.id):
			_canvas.move_child(_trays[tray.id], index)
			index += 1

## Hand-written brain files carry no positions, so every box would land on the
## same spot. Anything still at the origin gets placed by how far downstream it
## is: senses on the left, controls on the right, flow reading left to right.
func _auto_layout() -> void:
	var unplaced: Array[StringName] = []
	for inst: BrainGraph.Instance in graph.instances.values():
		if inst.position == Vector2.ZERO:
			unplaced.append(inst.id)
	if unplaced.is_empty():
		return

	var depth: Dictionary = {}
	for id: StringName in graph.instances.keys():
		depth[id] = 0
	# Sorted order means every upstream node is settled before the ones it feeds.
	for id: StringName in BrainValidator.sort_nodes(graph, registry):
		for w: BrainGraph.Wire in graph.wires:
			if w.to_node == id and depth.has(w.from_node):
				depth[id] = maxi(int(depth[id]), int(depth[w.from_node]) + 1)

	var used_rows: Dictionary = {}
	for id: StringName in unplaced:
		var column: int = int(depth[id])
		var row: int = int(used_rows.get(column, 0))
		used_rows[column] = row + 1
		graph.instances[id].position = Vector2(60 + column * 280, 40 + row * 240)

## Wires are stored by port name but drawn by slot number, so this is where the
## two representations meet.
func _sync_connections() -> void:
	_canvas.clear_connections()
	for w: BrainGraph.Wire in graph.wires:
		if not _views.has(w.from_node) or not _views.has(w.to_node):
			continue
		var from_view: NodeView = _views[w.from_node]
		var to_view: NodeView = _views[w.to_node]
		var from_slot := _slot_of(from_view.output_ports, w.from_port)
		var to_slot := _slot_of(to_view.input_ports, w.to_port)
		if from_slot >= 0 and to_slot >= 0:
			_canvas.connect_node(w.from_node, from_slot, w.to_node, to_slot)

## GraphEdit talks in slot numbers; the graph stores port names. This is the
## translation, and it is typed explicitly because a Dictionary lookup is untyped.
func _port_id(view_name: StringName, slot: int, is_output: bool) -> StringName:
	var view: NodeView = _views[view_name]
	var ports: Array[Port] = view.output_ports if is_output else view.input_ports
	return ports[slot].id

static func _slot_of(ports: Array[Port], port_id: StringName) -> int:
	for i in ports.size():
		if ports[i].id == port_id:
			return i
	return -1

## Problems are shown as you work, not on save (spec 3.3, the editor layer).
func _revalidate() -> void:
	var errors := BrainValidator.validate(graph, registry)
	if errors.is_empty():
		_problems.text = "[color=#8fdc8f]%d nodes, %d wires — valid[/color]" % [
			graph.instances.size(), graph.wires.size()]
		return
	var lines: PackedStringArray = ["[color=#ff9c8f]%d problem(s)[/color]" % errors.size()]
	for e: String in errors:
		lines.append("• " + e)
	_problems.text = "\n".join(lines)

## Build, watch, tweak — the loop this whole project rests on. The editor still
## does not evaluate anything itself: it hands the graph to a race session and
## gets out of the way.
func _on_test_drive() -> void:
	var errors := BrainValidator.validate(graph, registry)
	if not errors.is_empty():
		_revalidate()
		return  # a brain with problems is not worth watching drive

	var view := DebugView.open(graph, registry, Track.grand_prix())
	view.closed.connect(func() -> void:
		remove_child(view)
		view.queue_free())
	add_child(view)

# ---------------------------------------------------------------- files

## True once the graph differs from what is on disk. Every edit calls this, so
## New and Load can warn before throwing work away.
func _mark_unsaved() -> void:
	_unsaved = true
	_update_file_label()

func _update_file_label() -> void:
	if _file_label == null:
		return
	var where := _current_path.get_file() if _current_path != "" else "unsaved"
	_file_label.text = "%s%s" % [where, "  *" if _unsaved else ""]
	_file_label.tooltip_text = _current_path

## Starts a blank brain. Asks first if there is unsaved work, because silently
## discarding it is the same mistake as loading over it.
func _on_new() -> void:
	if not _unsaved:
		new_brain()
		return
	var confirm := ConfirmationDialog.new()
	confirm.dialog_text = "Discard unsaved changes to this brain?"
	confirm.title = "New Brain"
	confirm.confirmed.connect(new_brain)
	add_child(confirm)
	confirm.popup_centered()

func new_brain() -> void:
	graph = BrainGraph.new()
	graph.name = "New Brain"
	_current_path = ""
	_unsaved = false
	_rebuild_canvas()
	_revalidate()
	_update_file_label()

## Save writes straight back to the open file. A brain that has never been saved
## has nowhere to write, so the first Save behaves as Save As.
func _on_save() -> void:
	if _current_path == "":
		_ask_for_path(true)
		return
	save_to(_current_path, true)

## remember: true for Save As (the file becomes the open one), false for Save a
## Copy (write it out and carry on editing where you were).
func _ask_for_path(remember: bool) -> void:
	DirAccess.make_dir_recursive_absolute(SAVE_DIR)
	var dialog := FileDialog.new()
	dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	dialog.access = FileDialog.ACCESS_FILESYSTEM
	dialog.add_filter("*.brain", "Brain files")
	dialog.current_dir = ProjectSettings.globalize_path(SAVE_DIR)
	dialog.current_file = "%s.brain" % graph.name.to_snake_case()
	dialog.size = Vector2i(700, 480)
	dialog.file_selected.connect(func(path: String) -> void: save_to(path, remember))
	add_child(dialog)
	dialog.popup_centered()

## Writes the brain out. Returns whether it got there, so a test can tell the
## difference between saved and merely attempted.
func save_to(path: String, remember: bool = true) -> bool:
	if not path.ends_with(".brain"):
		path += ".brain"

	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		_problems.text = "[color=#ff9c8f]could not write %s[/color]" % path
		return false
	f.store_string(BrainFormat.serialize(graph))
	f.close()

	if remember:
		# The file is the brain's identity, so the name follows it. Otherwise a
		# brain saved as "quick_test" would still call itself "New Brain".
		_current_path = path
		graph.name = path.get_file().get_basename().capitalize()
		_unsaved = false
	_problems.text = "[color=#8fdc8f]saved to %s[/color]" % path
	_update_file_label()
	return true

func _on_load() -> void:
	var dialog := FileDialog.new()
	dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	dialog.access = FileDialog.ACCESS_FILESYSTEM
	dialog.add_filter("*.brain", "Brain files")
	dialog.size = Vector2i(700, 480)
	dialog.file_selected.connect(load_file)
	add_child(dialog)
	dialog.popup_centered()

## Loading is deliberately the same path the race manager uses: parse, then
## validate, then show what is wrong rather than assuming the file is good.
func load_file(path: String) -> void:
	# A missing file reads as empty text, which parses as a perfectly valid brain
	# with no nodes — so without this check, a bad path silently wipes your work.
	if not FileAccess.file_exists(path):
		_problems.text = "[color=#ff9c8f]cannot open %s[/color]" % path
		return

	var result := BrainFormat.parse(FileAccess.get_file_as_string(path))
	if not result.ok():
		_problems.text = "[color=#ff9c8f]%s[/color]" % "
".join(result.errors)
		return
	graph = result.graph
	_current_path = path
	_unsaved = false
	_rebuild_canvas()
	_revalidate()
	_update_file_label()
