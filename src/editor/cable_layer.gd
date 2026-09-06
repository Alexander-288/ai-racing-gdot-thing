class_name CableLayer
extends Node2D
## Paints every cable on the canvas — the connected ones, and the one you are
## dragging.
##
## GraphEdit will only ever draw one polyline of one thickness per connection, so
## four strands cannot come out of it. It is told to draw nothing at all
## (CableStyle.BACKING_WIDTH), and everything you see on the canvas is drawn
## here: a single core for an ordinary wire, the four-strand loom for a bundle.
##
## It sits in GraphEdit's own child list, between the connection layer and the
## nodes, so the ordinary draw order puts it over GraphEdit's line and under
## every box — see BrainCanvas._ready for why that is done with child order
## rather than with z_index. The cost of not being parented to the connection
## layer is that the scroll offset has to be applied here instead of inherited,
## which is one line in _process.
##
## It is a Node2D rather than a Control on purpose. Godot culls a canvas item
## against its own rect, and a Control keeps that rect equal to its own bounds —
## which are empty here, because this layer is only ever a surface to paint on
## and is never laid out. Anything drawn far from that empty rect was culled, so
## the cables vanished as soon as you zoomed in or scrolled off the first screen,
## leaving only the hairline GraphEdit used to draw. A Node2D sets no rect of its
## own, so Godot culls it against what it actually draws, which is right at every
## zoom and every scroll position.

var canvas: BrainCanvas

## Seconds since the layer appeared, which is what the flow along a cable is
## drawn against. Kept here rather than read from the engine clock so the whole
## canvas animates in step.
var clock := 0.0

## The wire currently being dragged out of a socket, if any. GraphEdit draws that
## preview with the same hairline it draws connections with, so switching that
## off means drawing the preview here too — otherwise pulling a new cable out of
## a socket shows nothing at all.
var _dragging := false
var _drag_node: StringName
var _drag_port := 0
var _drag_from_output := true

static func build(for_canvas: BrainCanvas) -> CableLayer:
	var layer := CableLayer.new()
	layer.canvas = for_canvas
	layer.name = "Cables"
	layer.set_process(true)
	return layer

## Nodes move, so the cables are repainted every frame. Each one is a few dozen
## points; the cost of this is nothing next to the cost of getting it wrong by
## caching and forgetting to invalidate.
func _process(delta: float) -> void:
	clock += delta
	# What the connection layer would have given us for free. Zoom is already in
	# the coordinates each cable is built from; this is only the scroll.
	position = -canvas.scroll_offset
	queue_redraw()

func _draw() -> void:
	for strand: Dictionary in strands():
		var points: PackedVector2Array = strand["points"]
		draw_polyline_colors(points,
			_flow_along(points, strand["colour"], strand["colour_to"]),
			strand["width"], true)

# ------------------------------------------------------------- dragging a wire

func on_drag_started(from_node: StringName, from_port: int, is_output: bool) -> void:
	_dragging = true
	_drag_node = from_node
	_drag_port = from_port
	_drag_from_output = is_output

func on_drag_ended() -> void:
	_dragging = false

# ----------------------------------------------------------------- the strands

## One colour per point, which does two jobs at once.
##
## It carries the bright band travelling along the cable, and it carries the
## cable from the colour of the socket it leaves to the colour of the socket it
## arrives at. Most wires start and end on the same kind, so both colours are the
## same and nothing shows. Where they differ — a yes-or-no plugged into something
## that wants a number — the wire fades amber to blue along its length, which
## says the conversion is happening in the wire rather than leaving you to
## notice that the two ends disagree.
##
## Distance is measured along the cable itself rather than across the screen, so
## both the band and the fade keep their shape round a curve.
func _flow_along(points: PackedVector2Array, leaving: Color, arriving: Color) -> PackedColorArray:
	var total := 0.0
	for i in range(1, points.size()):
		total += points[i].distance_to(points[i - 1])

	var colours := PackedColorArray()
	var travelled := 0.0
	for i in points.size():
		if i > 0:
			travelled += points[i].distance_to(points[i - 1])
		var here := leaving if total <= 0.0 else leaving.lerp(arriving, travelled / total)
		colours.append(CableStyle.flowing(here, travelled, clock))
	return colours

## Every strand of every cable, ready to paint. Split out from _draw so the
## geometry can be checked in a test rather than in a screenshot.
func strands() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for wire: Dictionary in canvas.get_connection_list():
		var from_view := canvas.get_node_or_null(NodePath(wire["from_node"])) as NodeView
		var to_view := canvas.get_node_or_null(NodePath(wire["to_node"])) as NodeView
		if from_view == null or to_view == null:
			continue

		var from_port: int = wire["from_port"]
		# The view's own ports, not the type's: a node whose shape depends on its
		# config has no fixed list, and reading the empty one hid every cable
		# leaving a Ray node.
		if from_port >= from_view.output_ports.size():
			continue

		# A cable is coloured by both of its ends, so the socket it arrives at
		# matters as much as the one it leaves. A port list can be shorter than
		# the slot it sits on, so the arriving kind falls back to the leaving one
		# rather than reading past the end.
		var to_port: int = wire["to_port"]
		var from_kind: int = from_view.output_ports[from_port].kind
		var to_kind := from_kind
		if to_port < to_view.input_ports.size():
			to_kind = to_view.input_ports[to_port].kind

		_add_cable(out,
			_socket(from_view, from_port, true),
			_socket(to_view, to_port, false),
			from_kind, to_kind)

	if _dragging:
		_add_drag(out)
	return out

## Where a socket sits on the connection surface. A node reports its ports
## unscaled and the surface is drawn zoomed, so these are the same coordinates
## GraphEdit hands to _get_connection_line.
func _socket(view: NodeView, port: int, is_output: bool) -> Vector2:
	var offset := view.get_output_port_position(port) if is_output else view.get_input_port_position(port)
	return (view.position_offset + offset) * canvas.zoom

## The half-made wire following the pointer. Rebuilt every frame rather than
## remembered, so it stays on its socket if you zoom or scroll mid-drag.
func _add_drag(out: Array[Dictionary]) -> void:
	var view := canvas.get_node_or_null(NodePath(_drag_node)) as NodeView
	if view == null:
		return
	var ports := view.output_ports if _drag_from_output else view.input_ports
	if _drag_port >= ports.size():
		return

	var anchor := _socket(view, _drag_port, _drag_from_output)
	var pointer := get_local_mouse_position()
	# A wire pulled out of an input runs backwards, and the curve leaves each end
	# sideways — so which end is which is what decides its shape.
	# Nothing is plugged in yet, so both ends are the socket you pulled from and
	# the preview is a flat colour.
	var kind: int = ports[_drag_port].kind
	if _drag_from_output:
		_add_cable(out, anchor, pointer, kind, kind)
	else:
		_add_cable(out, pointer, anchor, kind, kind)

## One cable's worth of strands, appended to the list.
##
## Shape comes from the leaving end: a bundle is a loom whatever it plugs into.
## Colour comes from both, so a wire can change kind along its length.
func _add_cable(out: Array[Dictionary], from: Vector2, to: Vector2,
		from_kind: int, to_kind: int) -> void:
	var spine := canvas.spine(from, to)
	var leaving := CableStyle.strand_colours(from_kind)
	var arriving := CableStyle.strand_colours(to_kind)
	var width := CableStyle.strand_width(from_kind)
	# Where a cable runs is scaled one for one — it has to land on its socket.
	# How thick it is drawn is not; see CableStyle.zoom_scale.
	var thickness := CableStyle.zoom_scale(canvas.zoom)
	var index := 0
	for offset: float in CableStyle.offsets(from_kind):
		out.append({
			"points": BrainCanvas.offset_curve(spine, offset * thickness),
			"colour": leaving[index],
			# A loom only ever plugs into a loom, so the tones line up. Anything
			# else has one strand, and this stays inside its list.
			"colour_to": arriving[mini(index, arriving.size() - 1)],
			"width": width * thickness,
		})
		index += 1
