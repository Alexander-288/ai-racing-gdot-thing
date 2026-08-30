class_name NodeView
extends GraphNode
## The box you see on the canvas for one node. Built entirely from the NodeType,
## so a new node type appears in the editor without any editor code being written
## (spec 3.1). This file should never mention a specific node by name.

signal config_changed(node_id: StringName, key: StringName, value: Variant)

## Slot colours by port kind, so a wrong connection looks wrong before you try it.
const KIND_COLOURS := {
	Port.Kind.FLOAT: Color(0.55, 0.78, 1.0),
	Port.Kind.BOOL: Color(1.0, 0.72, 0.36),
	Port.Kind.VECTOR: Color(0.72, 0.98, 0.6),
}

## A tint per role, so senses, maths, memory and controls are tellable apart at a glance.
const ROLE_COLOURS := {
	NodeType.Role.PURE: Color(0.30, 0.32, 0.38),
	NodeType.Role.SENSOR: Color(0.20, 0.38, 0.34),
	NodeType.Role.MEMORY: Color(0.38, 0.30, 0.20),
	NodeType.Role.OUTPUT: Color(0.38, 0.22, 0.30),
}

var node_id: StringName
var type: NodeType

static func build(instance: BrainGraph.Instance, node_type: NodeType) -> NodeView:
	var view := NodeView.new()
	view.node_id = instance.id
	view.type = node_type
	view.name = String(instance.id)
	view.title = "%s  ·  %s" % [node_type.display_name, instance.id]
	view.position_offset = instance.position
	view.resizable = false

	var style := StyleBoxFlat.new()
	style.bg_color = ROLE_COLOURS.get(node_type.role, Color(0.3, 0.3, 0.3))
	style.set_corner_radius_all(4)
	style.set_content_margin_all(6)
	view.add_theme_stylebox_override("titlebar", style)

	view._build_rows()
	view._build_settings(instance)
	return view

## One row per slot. A row can carry an input on its left, an output on its right,
## or both — which is why the count is whichever list is longer.
func _build_rows() -> void:
	for i in maxi(type.inputs.size(), type.outputs.size()):
		var row := HBoxContainer.new()

		var left := Label.new()
		left.text = type.inputs[i].display_name if i < type.inputs.size() else ""
		left.custom_minimum_size.x = 80
		row.add_child(left)

		var right := Label.new()
		right.text = type.outputs[i].display_name if i < type.outputs.size() else ""
		right.custom_minimum_size.x = 80
		right.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(right)

		add_child(row)

		var has_input := i < type.inputs.size()
		var has_output := i < type.outputs.size()
		set_slot(i,
			has_input, _kind_of(type.inputs, i), _colour_of(type.inputs, i),
			has_output, _kind_of(type.outputs, i), _colour_of(type.outputs, i))

## Settings live below the slots, as ordinary widgets with no connection point.
func _build_settings(instance: BrainGraph.Instance) -> void:
	for key: StringName in type.config_defaults:
		var row := HBoxContainer.new()

		var label := Label.new()
		label.text = String(key)
		label.custom_minimum_size.x = 80
		row.add_child(label)

		var field := SpinBox.new()
		field.allow_greater = true
		field.allow_lesser = true
		field.step = 0.01
		field.value = float(instance.config.get(key, type.config_defaults[key]))
		field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		field.value_changed.connect(func(v: float) -> void: config_changed.emit(node_id, key, v))
		row.add_child(field)

		add_child(row)

## GraphEdit refuses a connection when the slot types differ, so a bool going into
## a float needs the same number on both. The validator still has the final say.
static func _kind_of(ports: Array[Port], i: int) -> int:
	if i >= ports.size():
		return 0
	return 0 if ports[i].kind != Port.Kind.VECTOR else 1

static func _colour_of(ports: Array[Port], i: int) -> Color:
	if i >= ports.size():
		return Color.WHITE
	return KIND_COLOURS.get(ports[i].kind, Color.WHITE)
