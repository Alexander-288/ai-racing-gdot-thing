class_name SensorBuilder
## Turns a car's situation into the snapshot its brain is allowed to see.
## This is the only place the sim talks to the brain, and it is where the
## "no world position" rule is actually enforced (spec 2.5).

const RAY_RANGE := 60.0          # how far a ray can see, in metres
const CHECKPOINTS_VISIBLE := 4   # how far ahead a brain may look

## Directions for the 6 aimable rays, as angles from straight ahead. Fixed here
## for now; these become per-brain configuration once the editor exists.
const AIMED_ANGLES: Array[float] = [-0.35, -0.15, 0.0, 0.15, 0.35, PI]

## Where every ray points, as angles from straight ahead. One list, used both to
## cast the rays and to draw them, so the picture can never disagree with what
## the brain was actually told.
static func ray_angles() -> Array[float]:
	var angles: Array[float] = []
	# The 8-ray ring: fixed, evenly spaced, identical for every car so the
	# competition measures thinking rather than provisioning (spec 2.5).
	for i in SensorSnapshot.RING_RAYS:
		angles.append(TAU * float(i) / float(SensorSnapshot.RING_RAYS))
	angles.append_array(AIMED_ANGLES)
	return angles

## `others` is the whole field including this car; `self_index` says which one is
## us, so a car never senses itself. Pass an empty field for a solo run.
static func build(car: Car, track: Track, others: Array = [], self_index: int = -1) -> SensorSnapshot:
	var s := SensorSnapshot.new()

	# The ring and the aimable set overlap: straight ahead and straight behind are
	# in both. Casting either twice would cost a seventh of all ray work for two
	# numbers we already have, so identical directions are cast once and shared.
	var already_cast: Dictionary = {}
	var origin_distance := track.distance_to_centre(car.position)
	for angle: float in ray_angles():
		var key := snappedf(angle, 0.0001)
		if not already_cast.has(key):
			already_cast[key] = _cast(car, track, angle, others, self_index, origin_distance)
		var hit: Dictionary = already_cast[key]
		s.ray_distance.append(hit[&"distance"])
		s.ray_hit_track.append(hit[&"track"])
		s.ray_hit_car.append(hit[&"car"])
		s.ray_hit_object.append(false)  # nothing but cars and barriers exists yet

	s.speed = car.speed
	s.forward_speed = car.speed  # no sideways slide in the Phase 1 car model
	s.lateral_speed = 0.0
	s.angular_velocity = car.angular_velocity
	# With walls there is no "off track" any more; what a brain needs to know is
	# whether it is currently scraping one.
	s.on_track = not car.touching_wall
	s.damage = car.damage
	# Always available for now. Zones and the one-second rule need slipstream,
	# which is deferred — until then the grip penalty is the only thing policing it.
	s.drs_available = true
	s.lap = car.lap
	s.position_in_field = car.position_in_field

	for i in CHECKPOINTS_VISIBLE:
		var target := track.checkpoint_at(car.next_checkpoint + i)
		s.checkpoints.append(_into_car_frame(car, target))

	_fill_radar(s, car, others, self_index)
	return s

## Radar: up to four slots, each pointed at one rival by a rule rather than by
## name (spec 2.5). Relative position, heading and velocity — never an absolute
## anything, same as the rest of the snapshot.
##
## Every rival is put into the car's own frame once, and all five rules then read
## that. Doing the transform per rule instead meant doing it five times over.
static func _fill_radar(s: SensorSnapshot, car: Car, others: Array, self_index: int) -> void:
	var seen: Array = []
	for i in others.size():
		if i == self_index:
			continue
		var them: Car = others[i]
		var offset := _into_car_frame(car, them.position)
		seen.append({ &"car": them, &"offset": offset, &"gap": offset.length() })
	if seen.is_empty():
		return

	for mode: StringName in SensorSnapshot.RADAR_MODES:
		var best: Dictionary = {}
		var best_score := INF
		for candidate: Dictionary in seen:
			var score := _score(mode, candidate)
			if score < best_score:
				best_score = score
				best = candidate
		if best_score == INF:
			continue

		var them: Car = best[&"car"]
		var contact := SensorSnapshot.RadarContact.new()
		contact.found = true
		contact.offset = best[&"offset"]
		contact.relative_heading = wrapf(them.heading - car.heading, -PI, PI)
		# Their velocity as we see it: what the gap is doing, not what they are doing.
		contact.relative_velocity = _direction_in_car_frame(car,
			them.forward() * them.speed - car.forward() * car.speed)
		s.radar[mode] = contact

## Lower is a better match. INF means this rival does not qualify for the slot.
static func _score(mode: StringName, candidate: Dictionary) -> float:
	var gap: float = candidate[&"gap"]
	var ahead: float = (candidate[&"offset"] as Vector2).y
	var them: Car = candidate[&"car"]
	match mode:
		&"closest":
			return gap
		&"ahead":
			return gap if ahead > 0.0 else INF
		&"behind":
			return gap if ahead < 0.0 else INF
		&"leader":
			return float(them.position_in_field)
		&"slowest_nearby":
			# Nearby first, then slow: a crawling car half a lap away is not a hazard.
			return them.speed if gap < SensorSnapshot.NEARBY else INF
		_:
			return INF

## Casts one ray and reports what it found, without touching the snapshot — so
## the answer can be reused by a second ray pointing the same way.
static func _cast(car: Car, track: Track, angle_from_nose: float,
		others: Array, self_index: int, origin_distance: float) -> Dictionary:
	var direction := car.forward().rotated(-angle_from_nose)
	var wall := track.ray_distance(car.position, direction, RAY_RANGE, origin_distance)
	var rival := _nearest_car_along(car, direction, others, self_index)

	# Whatever the ray reaches first is what it reports. A car in front of a wall
	# hides the wall, which is exactly what a ray should do.
	var hit := minf(wall, rival)
	return {
		&"distance": hit / RAY_RANGE,
		&"track": hit < RAY_RANGE and wall <= rival,
		&"car": hit < RAY_RANGE and rival < wall,
	}

## How far along the ray the nearest rival sits, treating each car as a circle.
static func _nearest_car_along(car: Car, direction: Vector2, others: Array, self_index: int) -> float:
	var nearest := RAY_RANGE
	for i in others.size():
		if i == self_index:
			continue
		var them: Car = others[i]
		var to_them := them.position - car.position
		var along := to_them.dot(direction)
		if along <= 0.0 or along > nearest:
			continue  # behind us, or further than something we already found
		var sideways := absf(to_them.cross(direction))
		if sideways > Car.RADIUS:
			continue  # the ray passes it by
		# Back up to where the ray first touches the circle, not its centre.
		nearest = maxf(along - sqrt(maxf(Car.RADIUS * Car.RADIUS - sideways * sideways, 0.0)), 0.0)
	return nearest

## A direction seen from the car: x to its right, y out of its nose.
static func _direction_in_car_frame(car: Car, world: Vector2) -> Vector2:
	return Vector2(world.dot(car.right()), world.dot(car.forward()))

## World point to the car's own frame: x to its right, y out of its nose.
## Absolute positions stop here and never reach the brain.
static func _into_car_frame(car: Car, world_point: Vector2) -> Vector2:
	var offset := world_point - car.position
	return Vector2(offset.dot(car.right()), offset.dot(car.forward()))
