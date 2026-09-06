class_name GridDialog
extends Control
## Sets up a race: who is on the grid, what each of them is driving, and where.
##
## A field used to be a number, which only ever let you race copies of one brain
## against itself. This is the thing that lets a brain race something that is not
## itself — which is the only way to find out whether it can overtake, defend, or
## survive contact with a driver that behaves differently.

signal start_requested(entries: Array, seed: int)
signal cancelled

const MAX_CARS := 14
## The open brain, whatever it happens to be right now. Kept as a path that is
## deliberately not a path, so the roster does not go stale when you edit.
const OPEN_BRAIN := ""

var registry: NodeRegistry
var open_graph: BrainGraph
var open_name: String = "this brain"
var seed: int = 0

## One entry per car: the file it drives, in grid order. Empty means the brain
## currently open in the editor.
var roster: Array[String] = []

var _available: Array[String] = []
var _rows: VBoxContainer
var _summary: RichTextLabel

static func open(for_registry: NodeRegistry, editor_graph: BrainGraph,
		editor_name: String, current_seed: int, current_roster: Array[String]) -> GridDialog:
	var dialog := GridDialog.new()
	dialog.registry = for_registry
	dialog.open_graph = editor_graph
	dialog.open_name = editor_name if editor_name != "" else "this brain"
	dialog.seed = current_seed
	# Copied entry by entry: duplicate() hands back an untyped Array, which will
	# not go into a typed one.
	var start: Array[String] = []
	for path: String in current_roster:
		start.append(path)
	if start.is_empty():
		start.append(OPEN_BRAIN)
	dialog.roster = start
	dialog.set_anchors_preset(Control.PRESET_FULL_RECT)
	return dialog

func _ready() -> void:
	_available = discover_brains()
	_build()
	_refresh()
	modulate.a = 0.0
	var fade := create_tween()
	fade.tween_property(self, "modulate:a", 1.0, 0.12)

## Every brain file the editor can offer without a file browser: the ones that
## ship with the game, and the ones you have saved.
static func discover_brains() -> Array[String]:
	var found: Array[String] = []
	for folder: String in ["res://brains", "user://brains"]:
		var dir := DirAccess.open(folder)
		if dir == null:
			continue
		var names := dir.get_files()
		names.sort()  # so the list is the same every time it is opened
		for file: String in names:
			if file.ends_with(".brain"):
				found.append("%s/%s" % [folder, file])
	return found

# ---------------------------------------------------------------- the window

func _build() -> void:
	# Swallows clicks, which is what makes it modal: nothing behind it can be
	# touched while the grid is being set up.
	mouse_filter = Control.MOUSE_FILTER_STOP
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.55)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(shade)

	var centre := CenterContainer.new()
	centre.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(centre)

	var frame := PanelContainer.new()
	frame.theme_type_variation = &"Sidebar"
	frame.custom_minimum_size = Vector2(520, 460)
	centre.add_child(frame)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	frame.add_child(column)

	var heading := Label.new()
	heading.text = "Grid"
	column.add_child(heading)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)

	_rows = VBoxContainer.new()
	_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rows.add_theme_constant_override("separation", 4)
	scroll.add_child(_rows)

	_summary = RichTextLabel.new()
	_summary.bbcode_enabled = true
	_summary.scroll_active = false
	_summary.custom_minimum_size.y = 46
	column.add_child(_summary)

	column.add_child(_footer())

func _footer() -> HBoxContainer:
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 6)

	bar.add_child(_button("Add car", add_car))
	bar.add_child(_button("Fill grid", func() -> void:
		while roster.size() < MAX_CARS:
			roster.append(roster[roster.size() - 1])
		_refresh()))

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(spacer)

	var track := OptionButton.new()
	for i in Circuit.count():
		track.add_item(Circuit.label_for(i), i)
	for s in range(1, 6):
		var id := Circuit.GENERATED_BASE + s
		track.add_item(Circuit.label_for(id), id)
	track.select(maxi(track.get_item_index(seed), 0))
	track.item_selected.connect(func(i: int) -> void: seed = track.get_item_id(i))
	bar.add_child(track)

	bar.add_child(_button("Cancel", func() -> void: cancelled.emit()))
	bar.add_child(_button("Start", func() -> void: start_requested.emit(roster, seed)))
	return bar

## One car: where it starts, what it drives, and a way to take it off the grid.
func _car_row(index: int) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)

	var place := Label.new()
	place.text = "P%d" % (index + 1)
	place.theme_type_variation = &"CategoryLabel"
	place.custom_minimum_size.x = 34
	row.add_child(place)

	var picker := OptionButton.new()
	picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	picker.add_item(open_name, 0)
	for i in _available.size():
		picker.add_item(_available[i].get_file().get_basename(), i + 1)
	picker.select(_available.find(roster[index]) + 1)
	picker.item_selected.connect(func(chosen: int) -> void:
		roster[index] = OPEN_BRAIN if chosen == 0 else _available[chosen - 1]
		_refresh())
	row.add_child(picker)

	var remove := _button("x", func() -> void:
		roster.remove_at(index)
		_refresh())
	remove.custom_minimum_size.x = 28
	remove.disabled = roster.size() <= 1  # a race needs somebody in it
	remove.tooltip_text = "Take this car off the grid"
	row.add_child(remove)

	return row

func add_car() -> void:
	if roster.size() >= MAX_CARS:
		return
	roster.append(roster[roster.size() - 1])  # same as the car before it, as a starting point
	_refresh()

func _refresh() -> void:
	for child: Node in _rows.get_children():
		_rows.remove_child(child)
		child.queue_free()
	for i in roster.size():
		_rows.add_child(_car_row(i))
	_summary.text = _describe()

## Says what is wrong before the race rather than after it. A brain that will not
## load is rejected here with a reason, which is the same promise the race manager
## makes on ingest (spec 3.3).
func _describe() -> String:
	var problems: PackedStringArray = []
	for i in roster.size():
		var graph := graph_for(roster[i])
		if graph == null:
			problems.append("P%d: %s will not load" % [i + 1, roster[i].get_file()])
			continue
		var errors := BrainValidator.validate(graph, registry)
		if not errors.is_empty():
			problems.append("P%d: %s" % [i + 1, errors[0]])

	if problems.is_empty():
		return "[color=#8fdc8f]%d car%s, ready[/color]" % [roster.size(), "" if roster.size() == 1 else "s"]
	return "[color=#ff9c8f]%s[/color]" % "\n".join(problems)

## The graph one roster entry refers to, or null if it cannot be read. The open
## brain is copied like any other, because each car needs its own node state —
## two cars sharing one graph would share one accumulator.
func graph_for(path: String) -> BrainGraph:
	if path == OPEN_BRAIN:
		return BrainFormat.parse(BrainFormat.serialize(open_graph)).graph
	if not FileAccess.file_exists(path):
		return null
	var result := BrainFormat.parse(FileAccess.get_file_as_string(path))
	return result.graph if result.ok() else null

## Every car's graph, in grid order. Empty if any of them is unusable, so a race
## never starts half-built.
func build_field() -> Array:
	var field: Array = []
	for path: String in roster:
		var graph := graph_for(path)
		if graph == null or not BrainValidator.validate(graph, registry).is_empty():
			return []
		field.append(graph)
	return field

func _button(text: String, action: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.pressed.connect(action)
	return b
