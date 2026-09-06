class_name BrainCanvas
extends GraphEdit
## The canvas the brain is drawn on.
##
## GraphEdit draws one polyline per connection and asks this class one question
## along the way: what shape is the line? The answer is the spine — the single
## curve running down the middle of a cable. GraphEdit paints it thin, as the
## rail beneath the loom, and CableLayer paints the strands on top.
##
## The spine is also what GraphEdit uses to decide whether you clicked a wire, so
## it stays a plain curve however elaborate the cable looks.

## Points per curve. A cable is drawn as a polyline, so this is literally how
## round its bends look: too few and a long S-curve reads as a set of facets.
const SAMPLES := 56
const MIN_CURVE := 24.0    # so a very short wire still leaves its socket sideways

var cables: CableLayer

func _ready() -> void:
	cables = CableLayer.build(self)
	# Inside GraphEdit's own connection surface, so the strands land exactly where
	# the rails do at any zoom, and stay behind the nodes.
	# The cables are a sibling of the nodes, not a child of the connection layer.
	#
	# Parented under the connection layer they came out beneath GraphEdit's own
	# line, which is thin and dark, and on a wide cable that read as a seam
	# splitting the core in two. Raising them with z_index fixed that and broke
	# something worse: z_index is not scoped to the canvas, so lifting the nodes
	# back over the cables lifted them over the minimap, the toolbar, the dialogs
	# and the test-drive view as well.
	#
	# Child order is the canvas's own layering — it is already how trays are kept
	# underneath (BrainEditor._sink_trays) — so the cables just take their place
	# in it: after the connection layer, before any node. Everything keeps the
	# z_index it was born with, and nothing escapes the canvas.
	add_child(cables)
	var surface := get_node_or_null(^"_connection_layer")
	if surface != null:
		move_child(cables, surface.get_index() + 1)
	# GraphEdit no longer draws the wire you are dragging, so the layer has to be
	# told a drag is happening in order to draw it instead.
	connection_drag_started.connect(cables.on_drag_started)
	connection_drag_ended.connect(cables.on_drag_ended)

func _get_connection_line(from: Vector2, to: Vector2) -> PackedVector2Array:
	return spine(from, to)

## The ordinary S-curve: out of the socket sideways, into the next one sideways.
## Written out here rather than borrowed from GraphEdit, because a script cannot
## call the engine's own version of a virtual it has overridden.
func spine(from: Vector2, to: Vector2) -> PackedVector2Array:
	var reach := maxf(absf(to.x - from.x) * connection_lines_curvature, MIN_CURVE)
	var control_a := from + Vector2(reach, 0.0)
	var control_b := to - Vector2(reach, 0.0)
	var points := PackedVector2Array()
	for i in SAMPLES:
		points.append(from.bezier_interpolate(control_a, control_b, to,
			i / (SAMPLES - 1.0)))
	return points

## Slides a curve sideways along its own normal, so strands stay parallel through
## the bends instead of crossing on the inside of a corner.
static func offset_curve(spine_points: PackedVector2Array, distance: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in spine_points.size():
		var ahead: Vector2 = spine_points[mini(i + 1, spine_points.size() - 1)]
		var behind: Vector2 = spine_points[maxi(i - 1, 0)]
		var along := (ahead - behind).normalized()
		out.append(spine_points[i] + Vector2(-along.y, along.x) * distance)
	return out
