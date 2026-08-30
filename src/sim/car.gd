class_name Car
extends RefCounted
## One car. Deliberately simple for Phase 1: enough to drive a lap and be wrong
## in visible ways, not a tyre model.
##
## Nothing here takes a delta. The tick length is a constant, so the same inputs
## give the same numbers every run — that is the whole determinism lock (spec 2.4),
## and it is far cheaper to keep than to retrofit.

const TICK := 1.0 / 60.0     # must match physics_ticks_per_second in project.godot

const MAX_SPEED := 55.0
const ENGINE := 20.0         # how hard full throttle pushes
const BRAKING := 34.0
const DRAG := 0.45           # slows more the faster you go, so top speed settles
const TURN_RATE := 2.0       # radians per second at full steering lock
const GRIP_SPEED := 12.0     # below this the car turns lazily, like a real one
const MAX_LATERAL := 18.0    # m/s^2 the tyres can hold sideways, about 1.8g
# Hitting a barrier. How hard depends on how squarely you hit it: a glance down
# the wall costs little, a head-on almost stops you and hurts.
const WALL_BITE := 0.85          # share of speed lost in a fully head-on hit
const WALL_SCRAPE := 0.02        # per-tick cost of sliding along a barrier
const DAMAGE_PER_IMPACT := 0.012 # so a 40 m/s head-on costs about half the car
const DAMAGE_COST := 0.6         # at full damage the car keeps 40% of everything

# Heading is an angle where 0 points along +Y. Forward is (sin, cos), so the
# car's own frame matches the snapshot's: x is right, y is forward.
var position: Vector2 = Vector2.ZERO
var heading: float = 0.0
var speed: float = 0.0
var angular_velocity: float = 0.0

var damage: float = 0.0       # 0 is fresh, 1 is wrecked
var touching_wall: bool = false

var lap: int = 0
var next_checkpoint: int = 1  # starts on checkpoint 0, so it is heading for 1
var checkpoints_passed: int = 0

static func at_start(track: Track) -> Car:
	var c := Car.new()
	c.position = track.start_position()
	c.heading = track.start_heading()
	return c

func forward() -> Vector2:
	return Vector2(sin(heading), cos(heading))

func right() -> Vector2:
	return Vector2(cos(heading), -sin(heading))

## Advances one physics tick. Order matters and never changes: speed, then
## heading, then position, then progress round the track.
func step(controls: CarControls, track: Track) -> void:
	# Damage costs engine, braking and grip alike (spec 2.2).
	var health := 1.0 - damage * DAMAGE_COST

	var push := controls.throttle * ENGINE * health
	var slow := controls.brake * BRAKING * health + DRAG * speed
	speed = clampf(speed + (push - slow) * TICK, 0.0, MAX_SPEED * health)

	# Two different limits, and the slower one wins.
	#
	# At low speed the car is limited by steering lock, and a stationary car
	# cannot turn at all. At high speed it is limited by grip: holding a corner
	# needs sideways force, that force is speed x turn rate, and the tyres can
	# only supply so much. So turn radius grows with the SQUARE of speed, which
	# is what makes braking for a corner a real decision instead of a formality.
	var steering_limit := TURN_RATE * clampf(speed / GRIP_SPEED, 0.0, 1.0)
	var grip_limit := MAX_LATERAL / maxf(speed, 0.5)
	angular_velocity = controls.steering * minf(steering_limit, grip_limit) * health
	heading = wrapf(heading + angular_velocity * TICK, -PI, PI)

	position += forward() * speed * TICK
	_hit_barrier(track)
	_update_progress(track)

## The track is walled. You do not drift off into nothing — you hit something,
## and it costs you speed and condition.
func _hit_barrier(track: Track) -> void:
	var was_touching := touching_wall
	var centre := track.closest_point(position)
	var offset := position - centre
	touching_wall = offset.length() > track.half_width
	if not touching_wall:
		return

	var outward := offset / offset.length()
	position = centre + outward * track.half_width  # pinned against the wall

	# How much of the car's motion went into the wall decides how much it hurt.
	# Sliding along a barrier is survivable; arriving square at it is not.
	var into_wall := maxf(forward().dot(outward), 0.0)

	if was_touching:
		# Already against it: scraping, not crashing. Costly but escapable —
		# taking the full impact every tick would make one wall a dead end.
		speed = maxf(speed * (1.0 - WALL_SCRAPE), 0.0)
		return

	damage = minf(damage + speed * into_wall * DAMAGE_PER_IMPACT, 1.0)
	speed = maxf(speed * (1.0 - into_wall * WALL_BITE), 0.0)

## Counts a checkpoint once the car is near it, then rolls over into a new lap.
## Order-only: you cannot skip ahead by cutting the course.
func _update_progress(track: Track) -> void:
	const REACHED := 12.0
	if position.distance_to(track.checkpoint_at(next_checkpoint)) > REACHED:
		return
	checkpoints_passed += 1
	next_checkpoint = (next_checkpoint + 1) % track.checkpoint_count()
	# Checkpoint 0 is the start line, so arriving back at it finishes a lap.
	if next_checkpoint == 1:
		lap += 1
