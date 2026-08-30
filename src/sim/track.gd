class_name Track
extends RefCounted
## A track, seen from above: a centre line and a width. Flat 2D for Phase 1 —
## the brain only ever gets egocentric readings, so adding height later changes
## the sim and none of the brain code.

var centre_line: PackedVector2Array = PackedVector2Array()
var half_width: float = 8.0

## Checkpoints are the centre line points. They give route, not racing line
## (spec 2.5): placed one per real feature, never densely, or a brain could just
## follow them and the rays would be decoration.
var checkpoints: PackedVector2Array = PackedVector2Array()

## A simple closed oval for testing and early development. Not a race track —
## it exists so a brain can be run at all.
static func oval(radius_x: float = 60.0, radius_y: float = 38.0, corners: int = 16) -> Track:
	var t := Track.new()
	for i in corners:
		var angle := TAU * float(i) / float(corners)
		t.centre_line.append(Vector2(sin(angle) * radius_x, cos(angle) * radius_y))
	t.checkpoints = t.centre_line
	return t

func checkpoint_count() -> int:
	return checkpoints.size()

func checkpoint_at(index: int) -> Vector2:
	return checkpoints[index % checkpoints.size()]

## Where a car starts: on the first checkpoint, pointing at the second.
func start_position() -> Vector2:
	return checkpoint_at(0)

func start_heading() -> float:
	var forward := checkpoint_at(1) - checkpoint_at(0)
	return atan2(forward.x, forward.y)

func is_on_track(point: Vector2) -> bool:
	return distance_to_centre(point) <= half_width

## Shortest distance from a point to the centre line, checked against every
## segment. Fine at this scale; if tracks get long this wants a spatial index.
func distance_to_centre(point: Vector2) -> float:
	var best := INF
	var count := centre_line.size()
	for i in count:
		var a := centre_line[i]
		var b := centre_line[(i + 1) % count]  # wraps, because the track is a loop
		best = minf(best, _distance_to_segment(point, a, b))
	return best

## How far a ray travels before it crosses the track edge. Works from either side:
## a car that has run wide is still entitled to see where the track is. Walks
## forward in fixed steps and then bisects, which is exact enough and — being
## fixed steps — gives the same answer every run, which matters more (spec 2.4).
func ray_distance(origin: Vector2, direction: Vector2, max_range: float) -> float:
	const STEPS := 32
	var started_on := is_on_track(origin)
	var step := max_range / float(STEPS)
	var previous := 0.0
	for i in range(1, STEPS + 1):
		var travelled := step * float(i)
		if is_on_track(origin + direction * travelled) != started_on:
			return _bisect_edge(origin, direction, previous, travelled, started_on)
		previous = travelled
	return max_range  # never crossed an edge within range

## Narrows down where the edge sits, between a point on the near side and one past it.
func _bisect_edge(origin: Vector2, direction: Vector2, near: float, far: float, started_on: bool) -> float:
	for i in 12:  # fixed count, so the cost and the answer are both predictable
		var middle := (near + far) * 0.5
		if is_on_track(origin + direction * middle) == started_on:
			near = middle
		else:
			far = middle
	return near

static func _distance_to_segment(point: Vector2, a: Vector2, b: Vector2) -> float:
	var span := b - a
	var length_squared := span.length_squared()
	if length_squared == 0.0:
		return point.distance_to(a)
	# How far along the segment the closest point sits, kept inside its ends.
	var along := clampf((point - a).dot(span) / length_squared, 0.0, 1.0)
	return point.distance_to(a + span * along)
