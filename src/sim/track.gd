class_name Track
extends RefCounted
## A track, seen from above: a centre line and a width. Flat 2D for Phase 1 —
## the brain only ever gets egocentric readings, so adding height later changes
## the sim and none of the brain code.

var centre_line: PackedVector2Array = PackedVector2Array()
var half_width: float = 8.0

## Route, not racing line (spec 2.5). Sparse and irregular: one per real feature,
## never evenly spaced and dense, or a brain can just follow them corner to corner
## and the rays become decoration. They are NOT the centre line — the centre line
## is geometry, these are directions.
var checkpoints: PackedVector2Array = PackedVector2Array()

## Segments bucketed by area, so a distance query looks at a handful of segments
## instead of all of them. Ray casting alone asks hundreds of times a tick per car;
## with 14 cars a full scan of a detailed track is the whole frame budget.
##
## The padding is the contract: any segment within REACH of a point is guaranteed
## to be in that point's bucket. So a distance answer is exact up to REACH, and an
## empty bucket means "further away than REACH" — which is a useful fact, not a
## failure. Padding wider than this only makes every bucket slower to search.
const CELL := 8.0
const REACH := 3.0
var _grid: Dictionary = {}

## The centre line again, flattened into plain floats.
##
## Ray casting is most of a tick: fourteen cars, fourteen rays each, a handful of
## steps per ray, and every step measures the distance to every nearby segment.
## At that rate the Vector2 objects and the per-segment method call cost more
## than the arithmetic does, so the hot loop reads these instead.
var _seg_ax := PackedFloat64Array()
var _seg_ay := PackedFloat64Array()
var _seg_dx := PackedFloat64Array()
var _seg_dy := PackedFloat64Array()
var _seg_inv_length_squared := PackedFloat64Array()

## A simple closed oval for testing and early development. Not a race track —
## it exists so a brain can be run at all.
static func oval(radius_x: float = 60.0, radius_y: float = 38.0, corners: int = 16) -> Track:
	var t := Track.new()
	for i in corners:
		var angle := TAU * float(i) / float(corners)
		t.centre_line.append(Vector2(sin(angle) * radius_x, cos(angle) * radius_y))
	t.checkpoints = t.centre_line
	t.build_index()
	return t

## Must be called once after centre_line and half_width are set.
func build_index() -> void:
	_grid.clear()
	var count := centre_line.size()
	_flatten_segments(count)
	var pad := half_width + REACH
	for i in count:
		var a := centre_line[i]
		var b := centre_line[(i + 1) % count]
		var low := Vector2(minf(a.x, b.x), minf(a.y, b.y)) - Vector2.ONE * pad
		var high := Vector2(maxf(a.x, b.x), maxf(a.y, b.y)) + Vector2.ONE * pad
		for cx in range(floori(low.x / CELL), floori(high.x / CELL) + 1):
			for cy in range(floori(low.y / CELL), floori(high.y / CELL) + 1):
				var key := Vector2i(cx, cy)
				if not _grid.has(key):
					_grid[key] = PackedInt32Array()
				var bucket: PackedInt32Array = _grid[key]
				bucket.append(i)
				_grid[key] = bucket

func _flatten_segments(count: int) -> void:
	_seg_ax.resize(count)
	_seg_ay.resize(count)
	_seg_dx.resize(count)
	_seg_dy.resize(count)
	_seg_inv_length_squared.resize(count)
	for i in count:
		var a := centre_line[i]
		var b := centre_line[(i + 1) % count]
		_seg_ax[i] = a.x
		_seg_ay[i] = a.y
		var dx := b.x - a.x
		var dy := b.y - a.y
		_seg_dx[i] = dx
		_seg_dy[i] = dy
		var length_squared := dx * dx + dy * dy
		_seg_inv_length_squared[i] = 0.0 if length_squared == 0.0 else 1.0 / length_squared

func _nearby_segments(point: Vector2) -> PackedInt32Array:
	return _grid.get(Vector2i(floori(point.x / CELL), floori(point.y / CELL)), PackedInt32Array())

func checkpoint_count() -> int:
	return checkpoints.size()

func checkpoint_at(index: int) -> Vector2:
	return checkpoints[index % checkpoints.size()]

## Where a car starts: on the first checkpoint, pointing the way the track runs
## there. Aiming at the next checkpoint would start it crooked now that they are
## far apart and irregular.
func start_position() -> Vector2:
	return checkpoint_at(0)

func start_heading() -> float:
	var here := _nearest_centre_index(checkpoint_at(0))
	var forward := centre_line[(here + 1) % centre_line.size()] - centre_line[here]
	return atan2(forward.x, forward.y)

## Where car `index` of `count` lines up before the start. Two abreast, staggered
## either side of the centre line and spaced back down the road, like a real grid.
func grid_slot(index: int, count: int) -> Dictionary:
	const ROW_GAP := 9.0      # metres between rows
	const FIRST_ROW := 6.0    # how far back pole sits from the line
	const SIDE := 0.45        # how far off centre, as a share of half width

	var row := floori(float(index) / 2.0)
	var walked := _walk_back(_nearest_centre_index(checkpoint_at(0)),
		FIRST_ROW + ROW_GAP * float(row))

	var here: int = walked[&"index"]
	var ahead: Vector2 = centre_line[(here + 1) % centre_line.size()] - centre_line[here]
	var heading := atan2(ahead.x, ahead.y)

	# Odd indexes take the other side of the road, so the grid zig-zags.
	var sideways := Vector2(cos(heading), -sin(heading))
	var offset := (1.0 if index % 2 == 0 else -1.0) * half_width * SIDE
	if count <= 1:
		offset = 0.0

	return { &"position": (walked[&"position"] as Vector2) + sideways * offset, &"heading": heading }

## Steps backwards along the centre line, following the road rather than cutting
## across it. Gives up after one lap so a silly distance cannot loop forever.
func _walk_back(from_index: int, distance: float) -> Dictionary:
	var count := centre_line.size()
	var here := from_index
	var left := distance
	for step in count:
		var previous := (here - 1 + count) % count
		var span: Vector2 = centre_line[here] - centre_line[previous]
		var length := span.length()
		if length >= left:
			return { &"position": centre_line[here] - span.normalized() * left, &"index": previous }
		left -= length
		here = previous
	return { &"position": centre_line[from_index], &"index": from_index }

func _nearest_centre_index(point: Vector2) -> int:
	var best := 0
	var best_distance := INF
	for i in centre_line.size():
		var d := point.distance_squared_to(centre_line[i])
		if d < best_distance:
			best_distance = d
			best = i
	return best

## Nearest point on the centre line, and how far away it is. Used by the barrier
## collision to work out which way is back onto the track.
func closest_point(point: Vector2) -> Vector2:
	var nearby := _nearby_segments(point)
	# Far outside the track the buckets are empty, so fall back to a full scan
	# rather than returning something wrong. Rare, and never in the hot path.
	var search: PackedInt32Array = nearby if not nearby.is_empty() else _all_segments()
	var best := centre_line[0]
	var best_distance := INF
	var count := centre_line.size()
	for i: int in search:
		var a := centre_line[i]
		var b := centre_line[(i + 1) % count]
		var span := b - a
		var length_squared := span.length_squared()
		var along := 0.0 if length_squared == 0.0 else clampf((point - a).dot(span) / length_squared, 0.0, 1.0)
		var candidate := a + span * along
		var d := point.distance_squared_to(candidate)
		if d < best_distance:
			best_distance = d
			best = candidate
	return best

## A real circuit: a long straight, a fast sweeper, a hairpin, and a couple of
## awkward direction changes. Corner radius varies a lot, which is the point —
## on a shape where every corner is the same, one fixed throttle is unbeatable
## and no brain has anything to think about.
##
## The centre line is sampled densely because it is the geometry. The checkpoints
## are chosen separately, at features, and are deliberately few.
static func grand_prix() -> Track:
	var t := Track.new()
	t.half_width = 7.0

	# A closed loop whose radius wanders. The harmonics are what make some
	# corners tight and some sweeping, without the shape ever failing to close.
	const SAMPLES := 180  # 2.5 m of detail on a 9 m wide track is plenty
	for i in SAMPLES:
		var angle := TAU * float(i) / float(SAMPLES)
		# Tuned so the tightest corner is about 16 m: takeable at 32 m/s but not at
		# the 44 m/s the straights reach. That gap is what makes braking a decision
		# rather than a formality.
		var radius := 76.0 + 20.0 * sin(angle * 2.0) + 10.0 * sin(angle * 3.0 + 0.8)
		t.centre_line.append(Vector2(sin(angle) * radius, cos(angle) * radius * 0.74))

	t.checkpoints = t._pick_feature_checkpoints()
	t.build_index()
	return t

## A track from a seed, drawn from the published distribution (spec 2.9): the
## shape family and the ranges are public, the seeds used on race day are not.
## This is what makes a held-out track pool possible — and what stops a brain
## being tuned to one circuit and calling itself general.
static func generated(seed: int) -> Track:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed  # seeded, so a given track is the same track for everyone

	# Retried rather than clamped: some rolls produce a corner tighter than any
	# car could take, and a track nobody can drive tests nothing.
	for attempt in 12:
		var t := Track.new()
		t.half_width = rng.randf_range(7.0, 9.5)
		var sweep := rng.randf_range(14.0, 24.0)
		var kink := rng.randf_range(6.0, 14.0)
		var phase := rng.randf_range(0.0, TAU)
		var squash := rng.randf_range(0.68, 0.95)
		for i in 180:
			var angle := TAU * float(i) / 180.0
			var radius := 76.0 + sweep * sin(angle * 2.0 + phase) + kink * sin(angle * 3.0 + phase * 1.7)
			t.centre_line.append(Vector2(sin(angle) * radius, cos(angle) * radius * squash))
		t.checkpoints = t._pick_feature_checkpoints()
		t.build_index()
		if t.tightest_corner() >= 14.0 and t.checkpoint_count() >= 6:
			return t
	return grand_prix()  # the roll never landed; fall back to the known-good one

## Radius of the tightest corner, in metres. A car can hold a corner of radius r
## only up to sqrt(MAX_LATERAL * r), so this is the number that says whether a
## track is drivable at all.
func tightest_corner() -> float:
	var tightest := INF
	for turn: float in _curvature_profile():
		tightest = minf(tightest, 1.0 / maxf(turn, 0.00001))
	return tightest

## Places checkpoints at features, the way the spec describes them: corner entry,
## apex and exit, plus once down the middle of a long straight. Spacing comes out
## uneven because the track is uneven, which is what stops them adding up to a
## racing line — they say where the route goes, never how to take it.
func _pick_feature_checkpoints() -> PackedVector2Array:
	var curvature := _curvature_profile()
	var count := centre_line.size()
	const CORNER := 0.02   # above this the track is turning meaningfully
	const MIN_GAP := 14.0  # metres; stops entry and apex landing on top of each other

	var wanted: Array[int] = []
	for i in count:
		var here := curvature[i] > CORNER
		var before := curvature[(i - 1 + count) % count] > CORNER
		var after := curvature[(i + 1) % count] > CORNER
		var is_entry := here and not before
		var is_exit := here and not after
		var is_apex := here and curvature[i] >= curvature[(i - 1 + count) % count] 			and curvature[i] >= curvature[(i + 1) % count]
		var is_straight_middle := not here and i % 30 == 0
		if is_entry or is_apex or is_exit or is_straight_middle:
			wanted.append(i)

	var chosen := PackedVector2Array()
	var last := Vector2.INF
	for i: int in wanted:
		if last != Vector2.INF and centre_line[i].distance_to(last) < MIN_GAP:
			continue
		chosen.append(centre_line[i])
		last = centre_line[i]
	return chosen

## How sharply the track turns at each point, as radians of heading change per
## metre. Measured across several samples rather than one: neighbouring points
## are barely a metre apart, so a one-step estimate is mostly sampling noise and
## would invent hairpins that are not there.
func _curvature_profile() -> PackedFloat64Array:
	const SPAN := 3
	var out := PackedFloat64Array()
	var count := centre_line.size()
	for i in count:
		var before: Vector2 = centre_line[i] - centre_line[(i - SPAN + count) % count]
		var after: Vector2 = centre_line[(i + SPAN) % count] - centre_line[i]
		var turn := absf(before.angle_to(after))
		out.append(turn / maxf(after.length(), 0.001))
	return out

func is_on_track(point: Vector2) -> bool:
	return distance_to_centre(point) <= half_width

## Shortest distance from a point to the centre line. Only nearby segments are
## checked; an empty bucket means nothing is within a cell of here, which is
## already further than the track is wide.
func distance_to_centre(point: Vector2) -> float:
	# Deliberately written out in floats rather than as a call per segment: this
	# is the single hottest loop in the sim.
	var best := INF
	var px := point.x
	var py := point.y
	for i: int in _nearby_segments(point):
		var to_start_x := px - _seg_ax[i]
		var to_start_y := py - _seg_ay[i]
		var dx := _seg_dx[i]
		var dy := _seg_dy[i]
		# How far along the segment the nearest point sits, kept between its ends.
		var along := clampf((to_start_x * dx + to_start_y * dy) * _seg_inv_length_squared[i], 0.0, 1.0)
		var off_x := to_start_x - dx * along
		var off_y := to_start_y - dy * along
		var squared := off_x * off_x + off_y * off_y
		if squared < best:
			best = squared
	return best if is_inf(best) else sqrt(best)

## How far a point can move in any direction before it could possibly cross the
## track edge. INF answers mean nothing is within REACH, and since every edge lies
## half a width from a segment, the edge is then at least REACH - half_width away.
func clearance(point: Vector2) -> float:
	var to_centre := distance_to_centre(point)
	if is_inf(to_centre):
		return REACH
	return absf(to_centre - half_width)

## How far a ray travels before it crosses the track edge. Works from either
## side: a car that has run wide is still entitled to see where the track is.
##
## Rather than crawling in fixed steps, each step jumps by however far it is
## currently safe to move — near the middle of the track that is metres at a
## time, and it only slows down as it closes on the edge. Same answer, a fraction
## of the work, and still a fixed step count so it stays predictable.
## `origin_distance` lets a caller hand in the distance it already measured at the
## origin. Every ray a car casts starts from the same point, so measuring it once
## and sharing it saves one query per ray — and there are fourteen of them.
func ray_distance(origin: Vector2, direction: Vector2, max_range: float,
		origin_distance: float = NAN) -> float:
	const STEPS := 24
	const CLOSE_ENOUGH := 0.15
	var first := distance_to_centre(origin) if is_nan(origin_distance) else origin_distance
	var started_on := first <= half_width
	var travelled := 0.0

	for i in STEPS:
		# One distance query answers both questions — which side of the edge we
		# are on, and how far we may safely jump. Asking twice doubled the cost
		# of every ray for nothing.
		var to_centre := first if i == 0 else distance_to_centre(origin + direction * travelled)
		if (to_centre <= half_width) != started_on:
			return travelled  # crossed already; this is the edge to within a step
		var jump := REACH if is_inf(to_centre) else absf(to_centre - half_width)
		if jump < CLOSE_ENOUGH:
			return travelled
		travelled += jump
		if travelled >= max_range:
			return max_range

	return minf(travelled, max_range)

func _all_segments() -> PackedInt32Array:
	var all := PackedInt32Array()
	for i in centre_line.size():
		all.append(i)
	return all

static func _distance_to_segment(point: Vector2, a: Vector2, b: Vector2) -> float:
	var span := b - a
	var length_squared := span.length_squared()
	if length_squared == 0.0:
		return point.distance_to(a)
	# How far along the segment the closest point sits, kept inside its ends.
	var along := clampf((point - a).dot(span) / length_squared, 0.0, 1.0)
	return point.distance_to(a + span * along)
