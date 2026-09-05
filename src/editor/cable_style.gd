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

## The plain wire: a single core, no wider than it needs to be.
const PLAIN_WIDTH := 2.4

## The loom, for bundles only.
const STRANDS := 4
const STRAND_WIDTH := 1.4
const GAP := 4.6            # between strand centres
const BACKING_WIDTH := 1.0  # the rail beneath them, drawn by GraphEdit itself

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
