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

# DRS: the wing lies down. Far less drag, so a much higher top speed — and far
# less downforce, so much less grip to corner on. No activation zones and no
# one-second rule yet; those arrive with slipstream. For now the tradeoff polices
# itself, because opening it in a corner puts you in the wall.
const DRS_DRAG := 0.45           # share of normal drag while it is open
const DRS_GRIP := 0.55           # share of normal cornering grip while it is open

const RADIUS := 1.6              # cars are circles to the sim; close enough at this scale
const CONTACT_BITE := 0.35       # speed lost in a square hit on another car
const CONTACT_DAMAGE := 0.008    # contact hurts, but less than a barrier does

# Heading is an angle where 0 points along +Y. Forward is (sin, cos), so the
# car's own frame matches the snapshot's: x is right, y is forward.
var position: Vector2 = Vector2.ZERO
var heading: float = 0.0
var speed: float = 0.0
var angular_velocity: float = 0.0

var drs_open: bool = false
var damage: float = 0.0       # 0 is fresh, 1 is wrecked
var touching_wall: bool = false

var position_in_field: int = 1

var lap: int = 0
var next_checkpoint: int = 1  # starts on checkpoint 0, so it is heading for 1
var checkpoints_passed: int = 0

static func at_start(track: Track) -> Car:
	var c := Car.new()
	c.position = track.start_position()
	c.heading = track.start_heading()
	return c

## Lines this car up on the grid rather than on the start line itself, which is
## what a field of more than one needs.
static func at_grid_slot(track: Track, index: int, count: int) -> Car:
	var slot := track.grid_slot(index, count)
	var c := Car.new()
	c.position = slot[&"position"]
	c.heading = slot[&"heading"]
	return c

## Pushes two overlapping cars apart and charges both for it. Returns whether
## they were actually touching.
##
## Contact is legal and a valid strategy (spec 2.1), so this is deliberately
## survivable: a nudge costs a little speed, a square hit costs a lot. Both cars
## pay, so punting a rival off is never free.
func collide_with(other: Car) -> bool:
	var between := other.position - position
	var gap := between.length()
	if gap >= RADIUS * 2.0 or gap <= 0.0001:
		return false

	var push := between / gap
	var overlap := RADIUS * 2.0 - gap
	position -= push * overlap * 0.5
	other.position += push * overlap * 0.5

	# How hard depends on how much each car was driving into the other.
	var into := maxf(forward().dot(push), 0.0)
	var other_into := maxf(other.forward().dot(-push), 0.0)
	var closing := speed * into + other.speed * other_into

	damage = minf(damage + closing * CONTACT_DAMAGE * into, 1.0)
	other.damage = minf(other.damage + closing * CONTACT_DAMAGE * other_into, 1.0)
	speed = maxf(speed * (1.0 - into * CONTACT_BITE), 0.0)
	other.speed = maxf(other.speed * (1.0 - other_into * CONTACT_BITE), 0.0)
	return true

func forward() -> Vector2:
	return Vector2(sin(heading), cos(heading))

func right() -> Vector2:
	return Vector2(cos(heading), -sin(heading))

## Advances one physics tick. Order matters and never changes: speed, then
## heading, then position, then progress round the track.
func step(controls: CarControls, track: Track) -> void:
	# Damage costs engine, braking and grip alike (spec 2.2).
	var health := 1.0 - damage * DAMAGE_COST

	drs_open = controls.drs

	var push := controls.throttle * ENGINE * health
	var drag := DRAG * (DRS_DRAG if drs_open else 1.0)
	var slow := controls.brake * BRAKING * health + drag * speed
	# Less drag means a higher top speed, not a bigger engine.
	var ceiling := MAX_SPEED * health * (1.0 / DRS_DRAG if drs_open else 1.0)
	speed = clampf(speed + (push - slow) * TICK, 0.0, minf(ceiling, MAX_SPEED * 1.6))

	# Two different limits, and the slower one wins.
	#
	# At low speed the car is limited by steering lock, and a stationary car
	# cannot turn at all. At high speed it is limited by grip: holding a corner
	# needs sideways force, that force is speed x turn rate, and the tyres can
	# only supply so much. So turn radius grows with the SQUARE of speed, which
	# is what makes braking for a corner a real decision instead of a formality.
	var steering_limit := TURN_RATE * clampf(speed / GRIP_SPEED, 0.0, 1.0)
	var lateral := MAX_LATERAL * (DRS_GRIP if drs_open else 1.0)
	var grip_limit := lateral / maxf(speed, 0.5)
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
