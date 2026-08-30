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

static func build(car: Car, track: Track) -> SensorSnapshot:
	var s := SensorSnapshot.new()

	for angle: float in ray_angles():
		_add_ray(s, car, track, angle)

	s.speed = car.speed
	s.forward_speed = car.speed  # no sideways slide in the Phase 1 car model
	s.lateral_speed = 0.0
	s.angular_velocity = car.angular_velocity
	# With walls there is no "off track" any more; what a brain needs to know is
	# whether it is currently scraping one.
	s.on_track = not car.touching_wall
	s.damage = car.damage
	s.lap = car.lap

	for i in CHECKPOINTS_VISIBLE:
		var target := track.checkpoint_at(car.next_checkpoint + i)
		s.checkpoints.append(_into_car_frame(car, target))

	return s

## Casts one ray and records what it found. Distance is normalised to 0..1 so a
## brain never has to know the range, and so rays stay comparable between tracks.
static func _add_ray(s: SensorSnapshot, car: Car, track: Track, angle_from_nose: float) -> void:
	var direction := car.forward().rotated(-angle_from_nose)
	var hit := track.ray_distance(car.position, direction, RAY_RANGE)
	s.ray_distance.append(hit / RAY_RANGE)
	s.ray_hit_track.append(hit < RAY_RANGE)
	s.ray_hit_car.append(false)    # no opponents until Phase 3
	s.ray_hit_object.append(false)

## World point to the car's own frame: x to its right, y out of its nose.
## Absolute positions stop here and never reach the brain.
static func _into_car_frame(car: Car, world_point: Vector2) -> Vector2:
	var offset := world_point - car.position
	return Vector2(offset.dot(car.right()), offset.dot(car.forward()))
