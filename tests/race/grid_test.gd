extends TestCase
## A field of cars rather than one: grid slots, running order, contact, radar,
## and the tick ordering that keeps it fair.

func _brain(cruise: float = 0.5) -> BrainGraph:
	var g := BrainGraph.new()
	g.name = "Field Runner"
	g.add_node(&"cp", &"checkpoint")
	g.add_node(&"gain", &"constant", { &"value": 2.0 })
	g.add_node(&"mul", &"multiply")
	g.add_node(&"steer", &"out_steering")
	g.add_node(&"cruise", &"constant", { &"value": cruise })
	g.add_node(&"gas", &"out_throttle")
	g.connect_ports(&"cp", &"angle", &"mul", &"a")
	g.connect_ports(&"gain", &"out", &"mul", &"b")
	g.connect_ports(&"mul", &"out", &"steer", &"value")
	g.connect_ports(&"cruise", &"out", &"gas", &"value")
	return g

func _field(count: int, cruise: float = 0.5) -> RaceSession:
	var graphs: Array = []
	for i in count:
		graphs.append(_brain(cruise))
	return RaceSession.create_field(graphs, NodeRegistry.create_default(), Track.grand_prix())

# ------------------------------------------------------------------ the grid

func test_a_full_grid_starts_on_the_track_and_apart() -> void:
	var session := _field(14)
	assert_eq(session.entries.size(), 14)
	for e: RaceSession.Entry in session.entries:
		assert_true(session.track.is_on_track(e.car.position), "a grid slot must be on the road")

	# Nobody starts inside anybody else, or the race begins with a pile-up.
	for i in session.entries.size():
		for j in range(i + 1, session.entries.size()):
			var gap: float = session.entries[i].car.position.distance_to(session.entries[j].car.position)
			assert_true(gap > Car.RADIUS * 2.0, "cars %d and %d overlap at the start" % [i, j])

func test_the_grid_is_staggered_two_abreast() -> void:
	var session := _field(4)
	# Rows are spaced back down the road, so pole and third are further apart
	# than pole and second.
	var pole := session.entries[0].car.position
	var second := session.entries[1].car.position
	var third := session.entries[2].car.position
	assert_true(pole.distance_to(third) > pole.distance_to(second), "row two sits behind row one")

func test_a_single_car_starts_on_the_centre_line() -> void:
	var session := _field(1)
	assert_almost_eq(session.track.distance_to_centre(session.car.position), 0.0, 0.5,
		"with nobody to line up beside, there is no reason to sit off centre")

# ------------------------------------------------------------------ fairness

func test_every_car_senses_the_same_world() -> void:
	# The tick runs in stages — everyone senses, then everyone thinks, then
	# everyone moves. Sensing car by car as earlier cars moved would hand the
	# later ones fresher information and make grid order an advantage.
	var session := _field(6)
	var before: Array[Vector2] = []
	for e: RaceSession.Entry in session.entries:
		before.append(e.car.position)

	session.tick()
	# Every snapshot was taken before anything moved, so no car saw another car's
	# new position. Checked through the radar, which is the only place a car can
	# see another at all.
	for i in session.entries.size():
		var contact := session.entries[i].snapshot.radar_at(&"closest")
		if not contact.found:
			continue
		var seen_at: Vector2 = session.entries[i].car.position + Vector2.ZERO
		assert_true(contact.distance() > 0.0, "a found contact needs a real distance")

func test_the_same_field_runs_the_same_race_twice() -> void:
	var a := _field(6)
	var b := _field(6)
	for i in 400:
		a.tick()
		b.tick()
	for i in a.entries.size():
		assert_almost_eq(a.entries[i].car.position.x, b.entries[i].car.position.x, 0.0,
			"car %d drifted apart between identical runs" % i)

# ------------------------------------------------------------------ standings

func test_the_running_order_is_filled_in() -> void:
	var session := _field(8)
	for i in 300:
		session.tick()

	var places: Array[int] = []
	for e: RaceSession.Entry in session.entries:
		places.append(e.car.position_in_field)
	places.sort()
	assert_eq(places, [1, 2, 3, 4, 5, 6, 7, 8] as Array[int], "every place is used exactly once")

func test_standings_put_the_leader_first() -> void:
	var session := _field(6)
	for i in 300:
		session.tick()
	var order := session.standings()
	assert_eq(order[0].car.position_in_field, 1)
	assert_true(order[0].car.checkpoints_passed >= order[-1].car.checkpoints_passed)

func test_getting_further_round_puts_you_ahead() -> void:
	var session := _field(3)
	session.entries[2].car.checkpoints_passed = 9
	session.entries[0].car.checkpoints_passed = 4
	session.entries[1].car.checkpoints_passed = 1
	session._update_standings()
	assert_eq(session.entries[2].car.position_in_field, 1)
	assert_eq(session.entries[1].car.position_in_field, 3)

# ------------------------------------------------------------------ contact

func test_two_cars_in_the_same_place_are_pushed_apart() -> void:
	var session := _field(2)
	session.entries[1].car.position = session.entries[0].car.position + Vector2(0.5, 0.0)
	session.tick()
	var gap := session.entries[0].car.position.distance_to(session.entries[1].car.position)
	assert_true(gap >= Car.RADIUS * 1.6, "cars must not end a tick inside each other, gap %f" % gap)

func test_running_into_the_back_of_someone_costs_you_both() -> void:
	var behind := Car.new()
	var ahead := Car.new()
	ahead.position = Vector2(0.0, 2.0)   # directly in front
	behind.speed = 40.0
	ahead.speed = 5.0

	assert_true(behind.collide_with(ahead))
	assert_true(behind.speed < 40.0, "the one doing the hitting loses speed")
	assert_true(behind.damage > 0.0, "and takes damage for it")

func test_cars_that_are_not_touching_do_not_collide() -> void:
	var a := Car.new()
	var b := Car.new()
	b.position = Vector2(0.0, 50.0)
	assert_false(a.collide_with(b))

# ------------------------------------------------------------------ radar

func test_radar_finds_the_car_ahead_and_not_itself() -> void:
	var session := _field(4)
	session.tick()
	for i in session.entries.size():
		var contact := session.entries[i].snapshot.radar_at(&"closest")
		assert_true(contact.found, "car %d should see somebody on a full grid" % i)
		assert_true(contact.distance() > 0.0, "a car must never radar itself")

func test_radar_says_ahead_is_ahead() -> void:
	var session := _field(6)
	session.tick()
	for e: RaceSession.Entry in session.entries:
		var contact := e.snapshot.radar_at(&"ahead")
		if contact.found:
			assert_true(contact.offset.y > 0.0, "the car ahead must be in front of us")

func test_radar_finds_nothing_on_an_empty_track() -> void:
	var session := _field(1)
	session.tick()
	assert_false(session.snapshot.radar_at(&"closest").found, "alone means nothing to report")

func test_the_radar_node_reports_what_the_snapshot_holds() -> void:
	var session := _field(3)
	session.tick()

	var g := BrainGraph.new()
	g.add_node(&"eye", &"radar", { &"target": "closest" })
	var e := BrainEvaluator.create(g, NodeRegistry.create_default())
	e.tick(session.snapshot)

	var contact := session.snapshot.radar_at(&"closest")
	assert_almost_eq(e.output_of(&"eye", &"found"), 1.0)
	assert_almost_eq(e.output_of(&"eye", &"distance"), contact.distance(), 1e-6)
	assert_almost_eq(e.output_of(&"eye", &"right"), contact.offset.x, 1e-6)

func test_only_four_radars_are_allowed() -> void:
	var g := BrainGraph.new()
	for i in 5:
		g.add_node(StringName("eye%d" % i), &"radar")
	var errors := BrainValidator.validate(g, NodeRegistry.create_default())
	assert_eq(errors.size(), 1)
	assert_true(errors[0].contains("radar"), errors[0])

# ------------------------------------------------------------------ rays see cars

func test_a_ray_reports_a_car_rather_than_the_wall_behind_it() -> void:
	var track := Track.grand_prix()
	var me := Car.at_grid_slot(track, 0, 2)
	var them := Car.new()
	them.position = me.position + me.forward() * 12.0  # sat right in front
	them.heading = me.heading

	var snapshot := SensorBuilder.build(me, track, [me, them], 0)
	# Ring ray 0 points dead ahead.
	assert_true(snapshot.ray_hit_car[0], "should see the car")
	assert_false(snapshot.ray_hit_track[0], "the car hides the wall behind it")
	assert_almost_eq(snapshot.ray_distance[0] * SensorBuilder.RAY_RANGE,
		12.0 - Car.RADIUS, 0.3, "and report the near edge of it")

func test_rays_ignore_the_car_casting_them() -> void:
	var track := Track.grand_prix()
	var me := Car.at_grid_slot(track, 0, 1)
	var alone := SensorBuilder.build(me, track, [me], 0)
	for i in SensorSnapshot.RAY_COUNT:
		assert_false(alone.ray_hit_car[i], "ray %d found a car on an empty track" % i)
