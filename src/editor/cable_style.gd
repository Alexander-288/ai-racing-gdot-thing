class_name CableStyle
extends RefCounted
## How a wire looks, in one table.
##
## Godot has no stylesheet — a wire's colour is an argument handed to the node
## that owns the socket, and its shape is a method on the canvas. So this file
## stands in for one: everything about the look of a cable is declared here, and
## CableLayer reads it rather than deciding anything itself.
##
## There are two kinds of cable. An ordinary wire carries one number and is drawn
## as one core in its port's colour. A bundle carries eight, and is the wire a
## network is actually built out of — so it gets the loom: four violet strands in
## slightly different tones over a thin backing rail.

## The plain wire: a single core. Heavy enough to read as a cable rather than as
## a pen stroke — a node canvas is mostly wire, so the wire is the drawing.
const PLAIN_WIDTH := 3.4

## The loom, for bundles only.
const STRANDS := 4
const STRAND_WIDTH := 2.2
const GAP := 5.2            # between strand centres
## GraphEdit draws its own line per connection, at a hairline width that never
## scales with zoom. Under a loom it showed through the gap down the middle as a
## stray thread, and on a magnified canvas it stayed stubbornly one pixel while
## everything round it grew. Nothing is lost by switching it off: every cable you
## see is drawn by CableLayer, which also picks up the drag preview GraphEdit
## used to draw with this.
const BACKING_WIDTH := 0.0

## How wide the whole loom is at rest, outer edge to outer edge. A bundle socket
## is built from this, so the plug is always at least as big as the thing that
## plugs into it — see EditorTheme.bundle_port.
static func loom_span() -> float:
	return (STRANDS - 1) * GAP + STRAND_WIDTH

## How much each strand differs from its cable's base colour: lighter at the top
## of the loom, darker at the bottom, as if one light were falling across it.
## Small numbers on purpose — the strands should read as one cable in slightly
## different tones, not as four unrelated wires.
##
## The gap is what keeps them readable: strands closer together than about twice
## their width stop looking like separate lines and start moiring into a braid.
const TONES := [0.18, 0.06, -0.06, -0.16]

## A slow bright band travelling along every cable, so the canvas reads as
## something running rather than something drawn.
##
## Deliberately faint. A wire that pulses hard turns a graph into a fairground,
## and the point of the animation is only to suggest direction — which end feeds
## which — at a glance.
const FLOW_SPEED := 55.0     # pixels a second, at zoom 1
const FLOW_LENGTH := 190.0   # how far apart the bands are
const FLOW_LIFT := 0.30      # how much brighter the crest is than the trough

## How much thicker a cable gets as you zoom in.
##
## One, meaning a cable scales exactly as the nodes do. Zooming is then a
## magnifying glass over one drawing: a wire keeps the same proportion to the box
## it plugs into at every zoom, so nothing appears to change size — which is the
## point. A number below one would make cables shrink relative to the nodes as
## you zoom in, and the canvas would read as a different drawing at each zoom.
##
## Strand spacing is scaled by the same number, so the loom keeps its proportions
## rather than merging into a braid or splaying into four separate wires.
const WIDTH_RESPONSE := 1.0

static func zoom_scale(zoom: float) -> float:
	return pow(zoom, WIDTH_RESPONSE)

## The tint of one point along a cable, given how far along it sits and how long
## the animation has been running.
static func flowing(base: Color, distance: float, clock: float) -> Color:
	# A raised cosine: mostly trough, with a short crest passing through.
	var phase := (distance - clock * FLOW_SPEED) / FLOW_LENGTH
	var wave := pow((cos(phase * TAU) + 1.0) * 0.5, 3.0)
	return base.lightened(wave * FLOW_LIFT)

## Only a bundle gets the loom. Every other wire is one line, as it was.
static func is_loom(kind: int) -> bool:
	return kind == Port.Kind.VECTOR

static func strand_width(kind: int) -> float:
	return STRAND_WIDTH if is_loom(kind) else PLAIN_WIDTH

## The colour of each strand, top to bottom. A plain wire has exactly one.
static func strand_colours(kind: int) -> Array[Color]:
	var base: Color = EditorTheme.KIND_COLOURS.get(kind, EditorTheme.TEXT)
	if not is_loom(kind):
		return [base] as Array[Color]
	var out: Array[Color] = []
	for tone: float in TONES:
		out.append(base.lightened(tone) if tone > 0.0 else base.darkened(-tone))
	return out

## How far each strand sits from the centre of the cable, in the same order.
static func offsets(kind: int) -> Array[float]:
	if not is_loom(kind):
		return [0.0] as Array[float]
	var out: Array[float] = []
	for i in STRANDS:
		out.append((i - (STRANDS - 1) * 0.5) * GAP)
	return out
