class_name CableLayer
extends Control
## Paints the strands of every cable on the canvas.
##
## GraphEdit will only ever draw one polyline of one thickness per connection, so
## four strands over a thinner rail cannot come out of it. What it does draw is
## the rail, hairline thin; this layer paints over it — a single core for an
## ordinary wire, the four-strand loom for a bundle.
##
## It lives inside GraphEdit's own connection layer, which is what puts it in the
## right place at every zoom and scroll without doing any of that arithmetic:
## a child Control inherits its parent's transform, and that parent is already
## the surface the wires are drawn on.

var canvas: BrainCanvas

## Seconds since the layer appeared, which is what the flow along a cable is
## drawn against. Kept here rather than read from the engine clock so the whole
## canvas animates in step.
var clock := 0.0

static func build(for_canvas: BrainCanvas) -> CableLayer:
	var layer := CableLayer.new()
	layer.canvas = for_canvas
	layer.name = "Cables"
	layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.set_process(true)
	return layer

## Nodes move, so the cables are repainted every frame. Each one is a few dozen
## points; the cost of this is nothing next to the cost of getting it wrong by
## caching and forgetting to invalidate.
func _process(delta: float) -> void:
	clock += delta
	queue_redraw()

func _draw() -> void:
	for strand: Dictionary in strands():
		var points: PackedVector2Array = strand["points"]
		draw_polyline_colors(points, _flow_along(points, strand["colour"]),
			strand["width"], true)

## One colour per point, so the band can travel along the line. Distance is
## measured along the cable itself rather than across the screen, so the band
## keeps its shape round a curve.
func _flow_along(points: PackedVector2Array, base: Color) -> PackedColorArray:
	var colours := PackedColorArray()
	var travelled := 0.0
	for i in points.size():
		if i > 0:
			travelled += points[i].distance_to(points[i - 1])
		colours.append(CableStyle.flowing(base, travelled, clock))
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
		var to_port: int = wire["to_port"]
		# The view's own ports, not the type's: a node whose shape depends on its
		# config has no fixed list, and reading the empty one hid every cable
		# leaving a Ray node.
		if from_port >= from_view.output_ports.size():
			continue
		var kind: int = from_view.output_ports[from_port].kind

		# The same coordinates GraphEdit hands to _get_connection_line: a node
		# reports its ports unscaled, and the connection surface is drawn zoomed.
		var from := (from_view.position_offset
			+ from_view.get_output_port_position(from_port)) * canvas.zoom
		var to := (to_view.position_offset
			+ to_view.get_input_port_position(to_port)) * canvas.zoom

		var spine := canvas.spine(from, to)
		var colours := CableStyle.strand_colours(kind)
		var width := CableStyle.strand_width(kind)
		# Where a cable runs is scaled one for one — it has to land on its socket.
		# How thick it is drawn is not; see CableStyle.zoom_scale.
		var thickness := CableStyle.zoom_scale(canvas.zoom)
		var index := 0
		for offset: float in CableStyle.offsets(kind):
			out.append({
				"points": BrainCanvas.offset_curve(spine, offset * thickness),
				"colour": colours[index],
				"width": width * thickness,
			})
			index += 1
	return out
