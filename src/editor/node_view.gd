class_name NodeView
extends GraphNode
## The box you see on the canvas for one node. Built entirely from the NodeType,
## so a new node type appears in the editor without any editor code being written
## (spec 3.1). This file should never mention a specific node by name.
##
## Colours and boxes come from EditorTheme; what is decided here is only which
## of them a given node gets.

signal config_changed(node_id: StringName, key: StringName, value: Variant)

## Wide enough that a title and a socket label never fight for the same pixels.
const MIN_WIDTH := 176

## How much room a socket label gets before the row starts stretching.
const LABEL_WIDTH := 62

var node_id: StringName
var type: NodeType

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
	var left: Array[Control] = []
	for port: Port in type.inputs:
		left.append(_socket_label(port.display_name, HORIZONTAL_ALIGNMENT_LEFT))
	for key: StringName in type.config_defaults:
		left.append(_setting_cell(instance, key))

	for i in maxi(left.size(), type.outputs.size()):
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		row.add_child(left[i] if i < left.size() else _blank())
		row.add_child(_socket_label(
			type.outputs[i].display_name if i < type.outputs.size() else "",
			HORIZONTAL_ALIGNMENT_RIGHT))
		add_child(row)

		# Slot numbers are row numbers, and the editor turns them back into port
		# names by index — so input i and output i must stay on row i. Settings
		# take the rows below the inputs, where no input port can be looking.
		set_slot(i,
			i < type.inputs.size(), _kind_of(type.inputs, i), _colour_of(type.inputs, i),
			i < type.outputs.size(), _kind_of(type.outputs, i), _colour_of(type.outputs, i))

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
func _setting_cell(instance: BrainGraph.Instance, key: StringName) -> HBoxContainer:
	var cell := HBoxContainer.new()
	cell.add_theme_constant_override("separation", 6)

	var label := Label.new()
	label.text = String(key)
	label.theme_type_variation = &"CategoryLabel"
	cell.add_child(label)

	var field := SpinBox.new()
	field.allow_greater = true
	field.allow_lesser = true
	field.step = 0.01
	field.custom_minimum_size.x = 76
	field.value = float(instance.config.get(key, type.config_defaults[key]))
	field.value_changed.connect(func(v: float) -> void: config_changed.emit(node_id, key, v))
	cell.add_child(field)

	return cell

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
