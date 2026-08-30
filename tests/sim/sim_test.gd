extends TestCase
## The sim core: track geometry, car physics, and what a brain gets to see.

# ------------------------------------------------------------------ track

func test_the_centre_line_is_on_track_and_the_far_side_is_not() -> void:
	var t := Track.oval()
	assert_true(t.is_on_track(t.checkpoint_at(0)))
	assert_false(t.is_on_track(Vector2(500.0, 500.0)))

func test_a_ray_pointing_off_the_track_finds_the_edge() -> void:
	var t := Track.oval()
	t.half_width = 8.0
	# Checkpoint 0 sits at the top of the oval where the track runs left to right,
	# so straight up is across it and the edge is one half-width away.
	var distance := t.ray_distance(t.checkpoint_at(0), Vector2(0.0, 1.0), 60.0)
	assert_almost_eq(distance, 8.0, 0.1, "the edge is half a track width away")

func test_a_ray_that_hits_nothing_reports_full_range() -> void:
	var t := Track.oval()
	# From far outside, pointing further away: it never crosses an edge at all.
	var distance := t.ray_distance(Vector2(500.0, 500.0), Vector2(1.0, 0.0), 60.0)
	assert_almost_eq(distance, 60.0, 1e-6)

# ------------------------------------------------------------------ car

func _straight_line(throttle: float, brake: float = 0.0) -> CarControls:
	var c := CarControls.new()
	c.throttle = throttle
	c.brake = brake
	return c

func test_throttle_makes_the_car_move() -> void:
	var t := Track.oval()
	var car := Car.at_start(t)
	for i in 60:
		car.step(_straight_line(1.0), t)
	assert_true(car.speed > 5.0, "a second of full throttle should be moving, got %f" % car.speed)

func test_speed_settles_instead_of_growing_forever() -> void:
	var t := Track.oval()
	var car := Car.at_start(t)
	for i in 3000:
		car.step(_straight_line(1.0), t)
	assert_true(car.speed <= Car.MAX_SPEED, "drag and the cap hold it, got %f" % car.speed)

func test_brakes_stop_the_car_and_it_does_not_reverse() -> void:
	var t := Track.oval()
	var car := Car.at_start(t)
	for i in 120:
		car.step(_straight_line(1.0), t)
	for i in 600:
		car.step(_straight_line(0.0, 1.0), t)
	assert_almost_eq(car.speed, 0.0, 1e-6, "no reverse gear in Phase 1")

func test_a_stationary_car_cannot_steer() -> void:
	var t := Track.oval()
	var car := Car.at_start(t)
	var heading_before := car.heading
	var c := CarControls.new()
	c.steering = 1.0
	for i in 60:
		car.step(c, t)
	assert_almost_eq(car.heading, heading_before, 1e-6, "no speed, no turning")

# ------------------------------------------------------------------ what the brain sees

func test_the_snapshot_never_leaks_where_the_car_is() -> void:
	# The rule that makes brains generalise: no absolute position, anywhere.
	var t := Track.oval()
	var car := Car.at_start(t)
	var snapshot := SensorBuilder.build(car, t)
	for name: String in ["position", "world_position", "x", "y", "coordinates"]:
		assert_false(snapshot.get(name) != null, "snapshot must not expose '%s'" % name)

func test_a_car_in_the_middle_of_the_track_sees_walls_to_both_sides() -> void:
	var t := Track.oval()
	var car := Car.at_start(t)
	var snapshot := SensorBuilder.build(car, t)
	# Ring rays 2 and 6 point right and left (quarter turns off the nose).
	assert_true(snapshot.ray_hit_track[2], "should see the right-hand edge")
	assert_true(snapshot.ray_hit_track[6], "should see the left-hand edge")
	assert_true(snapshot.ray_distance[2] < 1.0)

func test_the_same_situation_moved_elsewhere_reads_identically() -> void:
	# Egocentric means a car cannot tell where on the oval it is from its senses.
	var t := Track.oval(60.0, 60.0, 24)  # a circle, so every point is alike
	var a := Car.at_start(t)
	var b := Car.at_start(t)
	b.position = t.checkpoint_at(6)
	b.heading = atan2((t.checkpoint_at(7) - t.checkpoint_at(6)).x, (t.checkpoint_at(7) - t.checkpoint_at(6)).y)

	var sa := SensorBuilder.build(a, t)
	var sb := SensorBuilder.build(b, t)
	for i in SensorSnapshot.RAY_COUNT:
		assert_almost_eq(sa.ray_distance[i], sb.ray_distance[i], 1e-6,
			"ray %d differs, so the car could work out where it is" % i)

func test_checkpoints_arrive_in_the_cars_own_frame() -> void:
	var t := Track.oval()
	var car := Car.at_start(t)
	var snapshot := SensorBuilder.build(car, t)
	assert_eq(snapshot.checkpoints.size(), SensorBuilder.CHECKPOINTS_VISIBLE)
	assert_true(snapshot.checkpoints[0].y > 0.0, "the next checkpoint is ahead, not behind")

func test_a_ray_works_from_off_the_track_too() -> void:
	# Cars run wide. A car that has left the track still needs to see its way back.
	var t := Track.oval()
	var outside := t.checkpoint_at(0) + Vector2(0.0, 12.0)  # just past the edge
	assert_false(t.is_on_track(outside))
	var distance := t.ray_distance(outside, Vector2(0.0, -1.0), 60.0)
	assert_almost_eq(distance, 4.0, 0.2, "the track starts a few metres back")
