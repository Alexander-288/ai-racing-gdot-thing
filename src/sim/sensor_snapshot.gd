class_name SensorSnapshot
extends RefCounted
## Everything a brain is allowed to know on one tick.
##
## There is deliberately no world position in here (spec 2.5). A brain that cannot
## know where it is has to actually drive, which is what makes it work on a track
## it has never seen. Every value is egocentric: from the car's own point of view.

const RING_RAYS := 8    # fixed ring, evenly spaced, same for every car
const AIMED_RAYS := 6   # player chooses the direction of these
const RAY_COUNT := RING_RAYS + AIMED_RAYS

# One entry per ray. Same budget for everyone, so the contest measures thinking.
var ray_distance: Array[float] = []   # 0..1, where 1 means nothing was hit
var ray_hit_track: Array[bool] = []
var ray_hit_car: Array[bool] = []
var ray_hit_object: Array[bool] = []

# Self state. Speeds are in the car's own frame: forward is where the nose points.
var speed: float = 0.0
var forward_speed: float = 0.0
var lateral_speed: float = 0.0     # sideways drift, so a brain can feel a slide
var angular_velocity: float = 0.0
var on_track: bool = true
var lap: int = 0
var position_in_field: int = 1

# Phase 3 fills these in properly; they are here so node types can already read them.
var damage: float = 0.0
var tyre_grip: float = 1.0
var drs_available: bool = false
var slipstream: float = 0.0

## What one radar slot found. Everything is relative, like the rest of this file:
## a brain learns where a rival is compared to itself, never where either of them
## is on the track.
class RadarContact extends RefCounted:
	var found: bool = false
	var offset: Vector2 = Vector2.ZERO             # x right, y forward
	var relative_heading: float = 0.0              # radians; 0 means pointing the same way
	var relative_velocity: Vector2 = Vector2.ZERO  # how the gap is changing

	func distance() -> float:
		return offset.length()

## The rules a radar slot can be pointed at (spec 2.5). No "random" — no brain
## benefits from an arbitrarily chosen car.
const RADAR_MODES: Array[StringName] = [&"closest", &"ahead", &"behind", &"leader", &"slowest_nearby"]

## How close counts as nearby, for the slots that care.
const NEARBY := 45.0

## Filled slot by slot, keyed by mode. A slot with nothing to report is absent,
## and the node reading it returns "found = 0" rather than a made-up position.
var radar: Dictionary = {}

func radar_at(mode: StringName) -> RadarContact:
	return radar.get(mode, RadarContact.new())

## Direction to each upcoming checkpoint, in the car's own frame.
## x is right, y is forward. Index 0 is the next one.
## Checkpoints give route, not racing line (spec 2.5) — they are placed one per
## corner or straight, never densely, or they would become a centreline to follow.
var checkpoints: Array[Vector2] = []

## A snapshot with every ray empty and the car stationary. Useful as a test
## fixture and as the honest default before the sim has filled anything in.
static func blank() -> SensorSnapshot:
	var s := SensorSnapshot.new()
	for i in RAY_COUNT:
		s.ray_distance.append(1.0)
		s.ray_hit_track.append(false)
		s.ray_hit_car.append(false)
		s.ray_hit_object.append(false)
	return s

## Reads a ray safely. An out-of-range index returns "nothing there" rather than
## crashing, because the index comes from a brain file we do not control.
func ray_at(index: int) -> Dictionary:
	if index < 0 or index >= ray_distance.size():
		return { &"distance": 1.0, &"hit_track": false, &"hit_car": false, &"hit_object": false }
	return {
		&"distance": ray_distance[index],
		&"hit_track": ray_hit_track[index],
		&"hit_car": ray_hit_car[index],
		&"hit_object": ray_hit_object[index],
	}

## Direction to a checkpoint. Out of range gives straight ahead, so a brain
## asking about a checkpoint that does not exist simply keeps going.
func checkpoint_at(index: int) -> Vector2:
	if index < 0 or index >= checkpoints.size():
		return Vector2(0.0, 1.0)
	return checkpoints[index]
