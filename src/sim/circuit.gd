class_name Circuit
extends RefCounted
## The named circuits, traced from the real ones.
##
## Each is a handful of waypoints down the middle of the road, in roughly the
## proportions of the real place. They are approximations drawn from the shape of
## each circuit rather than surveyed data — what they are faithful to is the
## sequence of features, which is what a driver actually meets: Monza's two long
## straights either side of the Lesmos, Monaco's hairpin between two downhill
## rights, the climb out of Eau Rouge onto the Kemmel straight.
##
## The waypoints are deliberately sparse. A Catmull-Rom spline through them is
## what becomes the centre line, so a corner's radius comes out of how the points
## are spaced rather than from anything written down — which is also what makes
## the outlines below editable by eye.
##
## Scale is not real. This car tops out at 55 m/s against an F1 car's ninety, so
## a real 5.8 km lap would take three minutes. Every circuit is scaled to a
## length that puts its lap near the real one in *time* rather than in distance —
## under three kilometres — keeping their order, so Spa is still the long one and
## Monaco is still the short one.

## How finely the centre line is sampled. The same as every other track — the
## spline, the resampling and this all live on Track, so a circuit drawn by hand
## and one rolled from a seed are built by identical code.
const SPACING := Track.SPACING

## Track ids at or above this are not circuits at all but seeds for the
## generator, so one picker can offer both without needing two kinds of number.
const GENERATED_BASE := 100

## One circuit: what it is called, how long it should come out, how wide the road
## is, and the shape itself.
class Spec extends RefCounted:
	var id: StringName
	var name: String
	var length: float      # centre-line metres the outline is scaled to
	var half_width: float  # kerb to kerb is twice this
	var outline: PackedVector2Array

	func _init(p_id: StringName, p_name: String, p_length: float,
			p_half_width: float, p_outline: PackedVector2Array) -> void:
		id = p_id
		name = p_name
		length = p_length
		half_width = p_half_width
		outline = p_outline

# ---------------------------------------------------------------- the circuits

static func all() -> Array[Spec]:
	return [_monza(), _spa(), _silverstone(), _interlagos(), _monaco()]

static func spec_at(index: int) -> Spec:
	var list := all()
	return list[clampi(index, 0, list.size() - 1)]

static func count() -> int:
	return all().size()

## The track a picker id means. Below GENERATED_BASE it is one of the circuits;
## at or above it, a seed for the generator — the held-out tracks a brain has
## never seen.
static func track_for(id: int) -> Track:
	if id >= GENERATED_BASE:
		return Track.generated(id - GENERATED_BASE)
	return build(spec_at(id))

## The name a picker id means, so the editor and the grid dialog can agree
## without either of them holding a list of its own.
static func label_for(id: int) -> String:
	if id >= GENERATED_BASE:
		return "seed %d" % (id - GENERATED_BASE)
	return spec_at(id).name

static func build(spec: Spec) -> Track:
	var t := Track.new()
	t.half_width = spec.half_width
	t.centre_line = Track.resample_closed(
		Track.scaled_to_length(Track.spline_through(spec.outline), spec.length), SPACING)
	t.finish()
	return t

# ------------------------------------------------------------------ the shapes

## Monza. Two enormous straights, three chicanes put there to slow the cars down,
## and the Parabolica sweeping all the way back onto the pit straight. The
## chicanes are the only tight corners on it; the rest is taken flat or nearly.
static func _monza() -> Spec:
	return Spec.new(&"monza", "Monza", 2830.0, 7.0, PackedVector2Array([
		Vector2(0, 0), Vector2(0, 350), Vector2(0, 700), Vector2(0, 990),
		Vector2(25, 1075), Vector2(62, 1098), Vector2(88, 1132),
		Vector2(110, 1230), Vector2(170, 1330), Vector2(250, 1420),
		Vector2(345, 1495), Vector2(450, 1550),
		Vector2(488, 1588), Vector2(528, 1578), Vector2(566, 1608),
		Vector2(605, 1650), Vector2(660, 1655),
		Vector2(710, 1630), Vector2(735, 1585),
		Vector2(740, 1480), Vector2(730, 1330), Vector2(710, 1180),
		Vector2(690, 1060),
		Vector2(662, 1002), Vector2(692, 950), Vector2(732, 928),
		Vector2(715, 880),
		Vector2(690, 760), Vector2(660, 620), Vector2(630, 490),
		Vector2(605, 380),
		Vector2(580, 290), Vector2(535, 205), Vector2(465, 140),
		Vector2(375, 90), Vector2(275, 55), Vector2(170, 35), Vector2(80, 20),
	]))

## Spa. The longest of them, and the one with the most road between corners: up
## out of the dip at Eau Rouge, the whole length of the Kemmel, then a long way
## round through Pouhon and Blanchimont before the Bus Stop drops you back onto
## the pit straight.
static func _spa() -> Spec:
	return Spec.new(&"spa", "Spa", 3000.0, 7.5, PackedVector2Array([
		Vector2(0, 0), Vector2(60, 120), Vector2(120, 240),
		Vector2(150, 320), Vector2(120, 380), Vector2(150, 440),
		Vector2(215, 520), Vector2(290, 610), Vector2(370, 700),
		Vector2(450, 790), Vector2(530, 880),
		Vector2(590, 950), Vector2(640, 985), Vector2(700, 975),
		Vector2(745, 935), Vector2(760, 880), Vector2(735, 830),
		Vector2(760, 760), Vector2(820, 700), Vector2(880, 630),
		Vector2(910, 550), Vector2(890, 470), Vector2(830, 420),
		Vector2(790, 360), Vector2(810, 300), Vector2(860, 260),
		Vector2(900, 200), Vector2(880, 140), Vector2(820, 105),
		Vector2(730, 90), Vector2(630, 85), Vector2(530, 75),
		Vector2(430, 55), Vector2(330, 30), Vector2(240, 5),
		Vector2(170, -25), Vector2(140, -60), Vector2(95, -55),
		Vector2(50, -35),
	]))

## Silverstone. Fast and open. Maggotts and Becketts is the part that matters: a
## run of direction changes taken at enormous speed, where a brain that brakes in
## a straight line and turns afterwards loses whole seconds.
static func _silverstone() -> Spec:
	# The waist is the thing to get right: the Wellington straight runs west and
	# the old pit straight runs east a little way alongside it, joined by the long
	# left of Luffield at one end and Copse at the other. Everything else hangs off
	# that as two lobes — Becketts and the Hangar straight to the north, Abbey and
	# the Loop to the south.
	return Spec.new(&"silverstone", "Silverstone", 2850.0, 7.5, PackedVector2Array([
		Vector2(250, 0), Vector2(140, 10), Vector2(30, 15), Vector2(-80, 15),
		Vector2(-180, 10),
		Vector2(-255, 5), Vector2(-310, 25), Vector2(-320, 60),
		Vector2(-290, 88), Vector2(-225, 95),
		Vector2(-120, 100), Vector2(-10, 105), Vector2(100, 110), Vector2(200, 115),
		Vector2(290, 135), Vector2(340, 185),
		Vector2(375, 250), Vector2(430, 300), Vector2(470, 360), Vector2(530, 400),
		Vector2(600, 420), Vector2(660, 390),
		Vector2(700, 335), Vector2(700, 270),
		Vector2(665, 215), Vector2(605, 185),
		Vector2(545, 150), Vector2(510, 90), Vector2(490, 20), Vector2(475, -60),
		Vector2(450, -135), Vector2(400, -195),
		Vector2(335, -230), Vector2(275, -230),
		Vector2(225, -200), Vector2(225, -150),
		Vector2(265, -110), Vector2(300, -65), Vector2(300, -20),
	]))

## Interlagos. Anticlockwise, tight and busy through the middle, with a long
## climb back up to the line that makes the last corner matter more than any
## other on the lap.
static func _interlagos() -> Spec:
	# Same idea: the Reta Oposta runs out west and the long climb of the Subida
	# comes back alongside it, with the infield lobe hung off the far end. The
	# climb wraps round the outside of the Senna S rather than inside it, which is
	# the one liberty taken with the real place - inside, the two would be on top
	# of each other at this scale.
	return Spec.new(&"interlagos", "Interlagos", 2630.0, 7.0, PackedVector2Array([
		Vector2(0, 0), Vector2(-60, 70), Vector2(-115, 145),
		Vector2(-155, 215), Vector2(-225, 240), Vector2(-290, 210),
		Vector2(-320, 150),
		Vector2(-400, 120), Vector2(-500, 100), Vector2(-600, 85), Vector2(-700, 75),
		Vector2(-790, 80), Vector2(-855, 120),
		Vector2(-885, 185), Vector2(-865, 250),
		Vector2(-810, 290), Vector2(-745, 295),
		Vector2(-690, 265), Vector2(-660, 210),
		Vector2(-610, 180), Vector2(-570, 215),
		Vector2(-520, 235), Vector2(-460, 230),
		Vector2(-400, 210), Vector2(-350, 245),
		Vector2(-280, 275), Vector2(-190, 285), Vector2(-105, 275),
		Vector2(-30, 250), Vector2(40, 200), Vector2(80, 130),
		Vector2(85, 50), Vector2(60, -20), Vector2(25, -25),
	]))

## Monaco. The short one, and the slowest: a street circuit that never lets go.
## The hairpin is the tightest corner in the game by some way — a brain that
## cannot slow down for it does not get round at all.
static func _monaco() -> Spec:
	return Spec.new(&"monaco", "Monaco", 2500.0, 5.5, PackedVector2Array([
		Vector2(0, 0), Vector2(40, 90), Vector2(75, 175),
		Vector2(120, 235), Vector2(180, 250),
		Vector2(255, 300), Vector2(330, 355),
		Vector2(375, 400), Vector2(390, 455),
		Vector2(430, 495), Vector2(490, 500), Vector2(540, 470),
		Vector2(570, 425), Vector2(575, 380),
		Vector2(560, 345), Vector2(528, 338), Vector2(515, 368),
		Vector2(480, 385), Vector2(440, 372), Vector2(420, 335),
		Vector2(410, 285), Vector2(420, 230), Vector2(450, 185),
		Vector2(490, 150), Vector2(470, 115), Vector2(500, 90),
		Vector2(455, 55), Vector2(400, 40), Vector2(360, 60),
		Vector2(320, 90), Vector2(280, 80), Vector2(265, 40),
		Vector2(230, 15), Vector2(190, 20), Vector2(185, 55),
		Vector2(150, 70), Vector2(115, 55), Vector2(105, 20),
		Vector2(60, 5),
	]))
