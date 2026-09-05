class_name NodeView
extends GraphNode
## The box you see on the canvas for one node. Built entirely from the NodeType,
## so a new node type appears in the editor without any editor code being written
## (spec 3.1). This file should never mention a specific node by name.
##
## Colours and boxes come from EditorTheme; what is decided here is only which
## of them a given node gets.

signal config_changed(node_id: StringName, key: StringName, value: Variant)
## Grow and shrink change how many sockets the node has, so the editor has to
## rebuild it rather than just store a number.
signal shape_changed(node_id: StringName, segments: int)

## Wide enough that a title and a socket label never fight for the same pixels.
const MIN_WIDTH := 176

## How much room a socket label gets before the row starts stretching.
const LABEL_WIDTH := 62

var node_id: StringName
var type: NodeType

## The sockets this box actually ended up with. A node's shape can depend on its
## config, so the editor reads these rather than working them out a second time
## and risking a different answer.
var input_ports: Array[Port] = []
var output_ports: Array[Port] = []

static func build(instance: BrainGraph.Instance, node_type: NodeType) -> NodeView:
	var view := NodeView.new()
	view.node_id = instance.id
	view.type = node_type
	view.name = String(instance.id)
	view.title = ""  # the title bar is built by hand below, so it can be coloured
	view.position_offset = instance.position
	view.resizable = false
	view.custom_minimum_size.x = MIN_WIDTH

	# Title and body are two styleboxes pretending to be one shape, so they have
	# to agree about the edge as well as the fill — including when selected.
	view.add_theme_stylebox_override("titlebar",
		EditorTheme.top_box(EditorTheme.NODE_TITLE, EditorTheme.NODE_EDGE))
	view.add_theme_stylebox_override("titlebar_selected",
		EditorTheme.top_box(EditorTheme.NODE_TITLE.lightened(0.06), EditorTheme.ACCENT, 2))

	view._build_titlebar(instance)
	view._build_body(instance)
	return view

## The title bar carries three things: a dot in the node's role colour, the type
## name in that same colour, and the instance id pushed to the right — the id
## matters when you are reading an error message, and not at all the rest of the
## time. The colour lives in the text, not in a filled bar behind it.
func _build_titlebar(instance: BrainGraph.Instance) -> void:
	var bar := get_titlebar_hbox()
	var tint := EditorTheme.role_colour(type.role)

	# GraphNode's own title label is already in that box, and even emptied it
	# still expands and shoves everything below to the right. Hiding it is what
	# lets the dot start at the left edge where the reference puts it.
	if bar.get_child_count() > 0:
		(bar.get_child(0) as Control).visible = false

	var icon := TextureRect.new()
	icon.texture = EditorTheme.dot(tint, 9)
	icon.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	bar.add_child(icon)

	var name_label := Label.new()
	name_label.text = type.display_name
	name_label.theme_type_variation = &"NodeTitle"
	name_label.add_theme_color_override("font_color", tint)
	bar.add_child(name_label)

	var id_label := Label.new()
	id_label.text = String(instance.id)
	id_label.theme_type_variation = &"CategoryLabel"
	id_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	id_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	bar.add_child(id_label)

## The body is two columns: what goes in down the left, what comes out down the
## right. A node's settings continue the left column underneath its inputs, so a
## sensor's selector sits at the top left of the box next to the readings it
## selects — rather than in a full-width block below everything, which is where
## it ended up when settings were their own separate section.
##
## Rows are laid out by an HBoxContainer, so the two columns can never overlap:
## the widest cell in each column decides how wide the node is.
func _build_body(instance: BrainGraph.Instance) -> void:
	# A node's sockets can depend on how it is configured, so everything below
	# asks the type what shape it is in rather than reading a fixed list.
	var inputs := type.inputs_for(instance.config)
	var outputs := type.outputs_for(instance.config)
	input_ports = inputs
	output_ports = outputs

	var left: Array[Control] = []
	for port: Port in inputs:
		left.append(_socket_label(port.display_name, HORIZONTAL_ALIGNMENT_LEFT))
	for field: ConfigField in type.fields_for(instance.config):
		left.append(_setting_cell(instance, field))

	for i in maxi(left.size(), outputs.size()):
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		row.add_child(left[i] if i < left.size() else _blank())
		row.add_child(_socket_label(
			outputs[i].display_name if i < outputs.size() else "",
			HORIZONTAL_ALIGNMENT_RIGHT))
		add_child(row)

		# Slot numbers are row numbers, and the editor turns them back into port
		# names by index — so input i and output i must stay on row i. Settings
		# take the rows below the inputs, where no input port can be looking.
		set_slot(i,
			i < inputs.size(), _kind_of(inputs, i), _colour_of(inputs, i),
			i < outputs.size(), _kind_of(outputs, i), _colour_of(outputs, i))

	if type.can_grow():
		add_child(_grow_row(instance))

## The footer on a node that can grow: one button to add a segment, one to take
## the last one away. Greyed out at the ends rather than hidden, so the node does
## not change height as you reach a limit.
func _grow_row(instance: BrainGraph.Instance) -> HBoxContainer:
	var segments := int(instance.config.get(type.grow_key, type.grow_min))
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 8)

	var fewer := _grow_button("-", segments > type.grow_min,
		func() -> void: shape_changed.emit(node_id, segments - 1))
	fewer.tooltip_text = "Remove the last ray"
	row.add_child(fewer)

	var count := Label.new()
	count.text = "%d" % segments
	count.theme_type_variation = &"CategoryLabel"
	row.add_child(count)

	var more := _grow_button("+", segments < type.grow_max,
		func() -> void: shape_changed.emit(node_id, segments + 1))
	more.tooltip_text = "Add another ray"
	row.add_child(more)

	return row

static func _grow_button(text: String, enabled: bool, action: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(26, 20)
	b.disabled = not enabled
	if enabled:
		b.pressed.connect(action)
	return b

static func _socket_label(text: String, align: int) -> Label:
	var label := Label.new()
	label.text = text
	label.custom_minimum_size.x = LABEL_WIDTH
	label.horizontal_alignment = align
	if align == HORIZONTAL_ALIGNMENT_RIGHT:
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return label

## Holds the left column open on rows that have run out of inputs and settings,
## so the outputs below stay in line with the ones above.
static func _blank() -> Control:
	var gap := Control.new()
	gap.custom_minimum_size.x = LABEL_WIDTH
	return gap

## One setting: a dimmed name and a green number. That is the whole visual
## grammar of a node — grey is what it is, green is what you chose.
func _setting_cell(instance: BrainGraph.Instance, field: ConfigField) -> HBoxContainer:
	var cell := HBoxContainer.new()
	cell.add_theme_constant_override("separation", 6)

	var label := Label.new()
	label.text = field.label
	label.theme_type_variation = &"CategoryLabel"
	cell.add_child(label)

	var stored: Variant = instance.config.get(field.key, type.config_defaults.get(field.key, 0.0))
	cell.add_child(_choice_widget(field, stored) if field.kind == ConfigField.Kind.CHOICE
		else _number_widget(field, stored))
	return cell

## A setting whose value is one of a handful of names gets a dropdown. It writes
## the name itself, so the brain file says arc = "cone" rather than arc = 1.
func _choice_widget(field: ConfigField, stored: Variant) -> OptionButton:
	var picker := OptionButton.new()
	picker.custom_minimum_size.x = 76
	for i in field.choices.size():
		picker.add_item(field.choices[i], i)
		if field.choices[i] == str(stored):
			picker.select(i)
	# Changing which set of rays this is can change how many there are to pick
	# from, so the node is rebuilt rather than just updated.
	picker.item_selected.connect(func(i: int) -> void:
		config_changed.emit(node_id, field.key, field.choices[i]))
	return picker

func _number_widget(field: ConfigField, stored: Variant) -> SpinBox:
	var spin := SpinBox.new()
	spin.min_value = field.minimum
	spin.max_value = field.maximum
	spin.allow_greater = is_inf(field.maximum)
	spin.allow_lesser = is_inf(field.minimum)
	spin.step = field.step
	spin.custom_minimum_size.x = 76
	spin.value = float(stored)
	spin.value_changed.connect(func(v: float) -> void: config_changed.emit(node_id, field.key, v))
	return spin

## GraphEdit refuses a connection when the slot types differ, so a bool going into
## a float needs the same number on both. The validator still has the final say.
static func _kind_of(ports: Array[Port], i: int) -> int:
	if i >= ports.size():
		return 0
	return 0 if ports[i].kind != Port.Kind.VECTOR else 1

static func _colour_of(ports: Array[Port], i: int) -> Color:
	if i >= ports.size():
		return Color.WHITE
	return EditorTheme.KIND_COLOURS.get(ports[i].kind, Color.WHITE)
