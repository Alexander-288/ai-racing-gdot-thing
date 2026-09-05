class_name CableStyle
extends RefCounted
## How a wire looks, in one table.
##
## Godot has no stylesheet — a wire's colour is an argument handed to the node
## that owns the socket, and its shape is a method on the canvas. So this file
## stands in for one: everything about the look of a cable is declared here, and
## CableLayer and NodeView both read it rather than deciding anything themselves.
##
## Change these numbers and every wire in the editor changes with them.

## A cable is a loom of strands over a thin backing rail, not a single core.
const STRANDS := 4
const STRAND_WIDTH := 1.4   # each strand
const BACKING_WIDTH := 1.0  # the rail beneath them, drawn by GraphEdit itself

const GAP := 3.4            # between strand centres on an ordinary wire
const BUNDLE_GAP := 4.8     # a bundle carries eight numbers; its loom is fatter

## How much each strand differs from its cable's base colour: lighter at the top
## of the loom, darker at the bottom, as if one light were falling across it.
## Small numbers on purpose — the strands should read as one cable in slightly
## different tones, not as four unrelated wires.
const TONES := [0.18, 0.06, -0.06, -0.16]

## Strands closer together than about twice their width stop reading as separate
## lines and start moiring into a braid, which is why the gaps are what they are.

static func gap(kind: int) -> float:
	return BUNDLE_GAP if kind == Port.Kind.VECTOR else GAP

## The colour of each strand, top to bottom.
static func strand_colours(kind: int) -> Array[Color]:
	var base: Color = EditorTheme.KIND_COLOURS.get(kind, EditorTheme.TEXT)
	var out: Array[Color] = []
	for tone: float in TONES:
		out.append(base.lightened(tone) if tone > 0.0 else base.darkened(-tone))
	return out

## How far each strand sits from the centre of the cable, in the same order.
static func offsets(kind: int) -> Array[float]:
	var spread := gap(kind)
	var out: Array[float] = []
	for i in STRANDS:
		out.append((i - (STRANDS - 1) * 0.5) * spread)
	return out
