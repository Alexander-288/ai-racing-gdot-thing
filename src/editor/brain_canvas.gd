class_name BrainCanvas
extends GraphEdit
## The canvas the brain is drawn on. It exists for one reason: a bundle is one
## wire carrying eight numbers, and it should look like it.
##
## GraphEdit draws every connection itself and asks this one question along the
## way — what shape is the line? So a bundle answers with a harness: three
## strands running side by side, gathered at both ends. It is still one
## connection to GraphEdit, one wire in the graph, and one thing to click.

## Godot hands us only the two endpoints, never which ports they belong to, so a
## bundle is recognised by its start: every VECTOR output on the canvas is a
## candidate, and a line beginning at one of them is a harness.
const SNAP := 12.0

const STRANDS := 3
const STRAND_GAP := 3.0    # pixels between neighbouring strands
const SAMPLES := 24        # points per strand; enough that a curve reads smooth
const MIN_CURVE := 24.0    # so a very short wire still leaves its socket sideways

var _cached_ports: Array[Vector2] = []
var _cached_frame: int = -1

## GraphEdit calls this for every connection it draws, including the one you are
## dragging out of a socket.
func _get_connection_line(from: Vector2, to: Vector2) -> PackedVector2Array:
	var spine := _bezier(from, to)
	return _harness(spine) if _is_bundle(from) else spine

## The ordinary S-curve: out of the socket sideways, into the next one sideways.
## Written out here rather than borrowed from GraphEdit, because a script cannot
## call the engine's own version of a virtual it has overridden.
func _bezier(from: Vector2, to: Vector2) -> PackedVector2Array:
	var reach := maxf(absf(to.x - from.x) * connection_lines_curvature, MIN_CURVE)
	var control_a := from + Vector2(reach, 0.0)
	var control_b := to - Vector2(reach, 0.0)
	var points := PackedVector2Array()
	for i in SAMPLES:
		points.append(from.bezier_interpolate(control_a, control_b, to,
			i / (SAMPLES - 1.0)))
	return points

## Three strands from one spine. The middle one runs backwards so the whole
## harness is a single unbroken polyline — which is what GraphEdit draws — and
## the short hops where it doubles back sit at the sockets, reading as the collar
## that gathers a real loom of cables.
func _harness(spine: PackedVector2Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for strand in STRANDS:
		var offset := (strand - (STRANDS - 1) * 0.5) * STRAND_GAP
		var points := _offset(spine, offset)
		if strand % 2 == 1:
			points.reverse()
		out.append_array(points)
	return out

## Slides a curve sideways along its own normal, so the strands stay parallel
## through the bends instead of crossing on the inside of a corner.
static func _offset(spine: PackedVector2Array, distance: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in spine.size():
		var ahead: Vector2 = spine[mini(i + 1, spine.size() - 1)]
		var behind: Vector2 = spine[maxi(i - 1, 0)]
		var along := (ahead - behind).normalized()
		out.append(spine[i] + Vector2(-along.y, along.x) * distance)
	return out

func _is_bundle(from: Vector2) -> bool:
	# GraphEdit hands out port positions already multiplied by the zoom, while a
	# node reports its own ports unscaled — so one of the two has to be converted
	# before they can be compared. (The minimap draws its connections through this
	# same method at its own scale; those simply never match, and a bundle in a
	# thumbnail has no business being a harness anyway.)
	var canvas_point := from / zoom
	for port: Vector2 in _bundle_ports():
		if canvas_point.distance_to(port) < SNAP:
			return true
	return false

## Recomputed once per frame rather than kept up to date by the editor: port
## positions move whenever a node is dragged, and a harness that turned back into
## a plain line halfway through a drag would look broken.
func _bundle_ports() -> Array[Vector2]:
	var frame := Engine.get_process_frames()
	if frame == _cached_frame:
		return _cached_ports
	_cached_frame = frame
	_cached_ports = []
	for child: Node in get_children():
		var view := child as NodeView
		if view == null:
			continue
		for i in view.type.outputs.size():
			if view.type.outputs[i].kind == Port.Kind.VECTOR:
				_cached_ports.append(view.position_offset + view.get_output_port_position(i))
	return _cached_ports
