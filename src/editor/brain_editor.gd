class_name BrainEditor
extends Control
## The brain editor. Reads and writes the brain file format, and never evaluates
## anything (spec 3). Its palette, its boxes and its sockets all come from the
## node registry, so new node types need no editor code at all.

const SAVE_DIR := "user://brains"

var registry: NodeRegistry
var graph: BrainGraph

var _canvas: GraphEdit
var _palette: VBoxContainer
var _problems: RichTextLabel
var _views: Dictionary = {}   # node id -> NodeView

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

	var split := HSplitContainer.new()
	split.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(split)

	var side := VBoxContainer.new()
	side.custom_minimum_size.x = 200
	split.add_child(side)

	var heading := Label.new()
	heading.text = "Nodes"
	side.add_child(heading)

	# The palette is a loop over the registry, never a hand-written list.
	_palette = VBoxContainer.new()
	_palette.size_flags_vertical = Control.SIZE_EXPAND_FILL
	side.add_child(_palette)
	_build_palette()

	side.add_child(HSeparator.new())
	side.add_child(_button("Save", _on_save))
	side.add_child(_button("Load", _on_load))

	_problems = RichTextLabel.new()
	_problems.custom_minimum_size.y = 110
	_problems.bbcode_enabled = true
	side.add_child(_problems)

	var right := VBoxContainer.new()
	split.add_child(right)

	_canvas = GraphEdit.new()
	_canvas.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_canvas.right_disconnects = true
	_canvas.connection_request.connect(_on_connect)
	_canvas.disconnection_request.connect(_on_disconnect)
	_canvas.delete_nodes_request.connect(_on_delete)
	_canvas.end_node_move.connect(_on_moved)
	right.add_child(_canvas)

func _build_palette() -> void:
	for category: String in ["Sensors", "Math", "Memory", "Outputs"]:
		var types := registry.by_category(category)
		if types.is_empty():
			continue
		var heading := Label.new()
		heading.text = category
		_palette.add_child(heading)
		for type: NodeType in types:
			_palette.add_child(_button("  " + type.display_name,
				func() -> void: _add_node(type.id)))

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
	_revalidate()

func _on_delete(names: Array[StringName]) -> void:
	for view_name: StringName in names:
		graph.remove_node(view_name)
	_rebuild_canvas()
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
	_revalidate()

func _on_disconnect(from_view: StringName, from_slot: int, to_view: StringName, to_slot: int) -> void:
	graph.disconnect_ports(from_view, _port_id(from_view, from_slot, true),
		to_view, _port_id(to_view, to_slot, false))
	_sync_connections()
	_revalidate()

func _on_moved() -> void:
	for id: StringName in _views:
		var view: NodeView = _views[id]
		graph.instances[id].position = view.position_offset

func _on_config_changed(node_id: StringName, key: StringName, value: Variant) -> void:
	graph.instances[node_id].config[key] = value
	_revalidate()

# ---------------------------------------------------------------- drawing it

func _rebuild_canvas() -> void:
	_canvas.clear_connections()
	for view: Node in _canvas.get_children():
		if view is NodeView:
			view.queue_free()
			_canvas.remove_child(view)
	_views.clear()

	_auto_layout()

	for inst: BrainGraph.Instance in graph.instances.values():
		var type := registry.get_type(inst.type_id)
		if type == null:
			continue  # unknown types are reported by the validator, not drawn
		var view := NodeView.build(inst, type)
		view.config_changed.connect(_on_config_changed)
		_canvas.add_child(view)
		_views[inst.id] = view

	_sync_connections()

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
		var from_slot := _slot_of(from_view.type.outputs, w.from_port)
		var to_slot := _slot_of(to_view.type.inputs, w.to_port)
		if from_slot >= 0 and to_slot >= 0:
			_canvas.connect_node(w.from_node, from_slot, w.to_node, to_slot)

## GraphEdit talks in slot numbers; the graph stores port names. This is the
## translation, and it is typed explicitly because a Dictionary lookup is untyped.
func _port_id(view_name: StringName, slot: int, is_output: bool) -> StringName:
	var view: NodeView = _views[view_name]
	var ports: Array[Port] = view.type.outputs if is_output else view.type.inputs
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

# ---------------------------------------------------------------- files

func _on_save() -> void:
	DirAccess.make_dir_recursive_absolute(SAVE_DIR)
	var path := "%s/%s.brain" % [SAVE_DIR, graph.name.to_snake_case()]
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		_problems.text = "[color=#ff9c8f]could not write %s[/color]" % path
		return
	f.store_string(BrainFormat.serialize(graph))
	f.close()
	_problems.text = "[color=#8fdc8f]saved to %s[/color]" % ProjectSettings.globalize_path(path)

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
		_problems.text = "[color=#ff9c8f]%s[/color]" % "\n".join(result.errors)
		return
	graph = result.graph
	_rebuild_canvas()
	_revalidate()
