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
const TURN_RATE := 2.0       # radians per second at full lock
const GRIP_SPEED := 12.0     # below this the car turns lazily, like a real one
const OFF_TRACK_DRAG := 6.0  # running wide costs you time

# Heading is an angle where 0 points along +Y. Forward is (sin, cos), so the
# car's own frame matches the snapshot's: x is right, y is forward.
var position: Vector2 = Vector2.ZERO
var heading: float = 0.0
var speed: float = 0.0
var angular_velocity: float = 0.0

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
	var push := controls.throttle * ENGINE
	var slow := controls.brake * BRAKING + DRAG * speed
	if not track.is_on_track(position):
		slow += OFF_TRACK_DRAG
	speed = clampf(speed + (push - slow) * TICK, 0.0, MAX_SPEED)

	# A stationary car cannot steer, and a slow one steers weakly.
	var grip := clampf(speed / GRIP_SPEED, 0.0, 1.0)
	angular_velocity = controls.steering * TURN_RATE * grip
	heading = wrapf(heading + angular_velocity * TICK, -PI, PI)

	position += forward() * speed * TICK
	_update_progress(track)

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
