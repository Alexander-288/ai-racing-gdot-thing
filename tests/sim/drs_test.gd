extends TestCase
## DRS: the wing lies down. Much less drag, much less grip.
##
## There are no activation zones and no one-second rule yet — those need
## slipstream. For now the tradeoff polices itself, because a brain that opens it
## in a corner puts the car in the wall.

func _controls(throttle: float, drs: bool, steering: float = 0.0) -> CarControls:
	var c := CarControls.new()
	c.throttle = throttle
	c.steering = steering
	c.drs = drs
	return c

## Terminal speed on an open expanse: a wide, gentle circle the car cannot reach
## the edge of. On a real circuit it would be in a barrier long before it settled.
func _open_ground() -> Track:
	var t := Track.oval(600.0, 600.0, 48)
	t.half_width = 400.0
	t.build_index()
	return t

## Ten seconds is long enough to be within a whisker of terminal speed, and short
## enough that a car driving dead straight has not yet wandered to the edge of
## the circle and started grinding along it.
func _settle(drs: bool, ticks: int = 600) -> Car:
	var track := _open_ground()
	var car := Car.at_start(track)
	for i in ticks:
		car.step(_controls(1.0, drs), track)
	return car

func test_drs_raises_the_top_speed() -> void:
	var closed := _settle(false)
	var open := _settle(true)
	assert_true(open.speed > closed.speed * 1.2,
		"open should be much faster: %.1f vs %.1f" % [open.speed, closed.speed])

func test_drs_costs_cornering_grip() -> void:
	# Same speed, same steering input, and the one with the wing down turns less.
	var track := _open_ground()
	var closed := Car.at_start(track)
	var open := Car.at_start(track)
	closed.speed = 40.0
	open.speed = 40.0

	var before := closed.heading
	for i in 30:
		closed.step(_controls(0.0, false, 1.0), track)
		open.step(_controls(0.0, true, 1.0), track)

	var closed_turn := absf(wrapf(closed.heading - before, -PI, PI))
	var open_turn := absf(wrapf(open.heading - before, -PI, PI))
	assert_true(open_turn < closed_turn,
		"open turned %.3f rad, closed turned %.3f" % [open_turn, closed_turn])

func test_the_car_reports_whether_it_is_open() -> void:
	var track := Track.grand_prix()
	var car := Car.at_start(track)
	car.step(_controls(1.0, true), track)
	assert_true(car.drs_open)
	car.step(_controls(1.0, false), track)
	assert_false(car.drs_open)

func test_a_brain_can_open_it() -> void:
	# End to end: a graph decides, and the car does it.
	# DRS wants a yes or no, so it is wired from something that answers one.
	var g := BrainGraph.new()
	g.add_node(&"me", &"self_state")
	g.add_node(&"drs", &"out_drs")
	g.connect_ports(&"me", &"drs_available", &"drs", &"value")

	var session := RaceSession.create(g, NodeRegistry.create_default(), Track.grand_prix())
	session.tick()
	assert_true(session.car.drs_open, "the brain asked for it, the car opened it")

func test_a_brain_can_tell_whether_it_is_allowed() -> void:
	var g := BrainGraph.new()
	g.add_node(&"me", &"self_state")
	var session := RaceSession.create(g, NodeRegistry.create_default(), Track.grand_prix())
	session.tick()
	# Always available for now, but the wire exists so the rule can tighten later
	# without every brain needing rewiring.
	assert_almost_eq(session.evaluator.output_of(&"me", &"drs_available"), 1.0)

func test_holding_it_open_through_the_corners_wrecks_the_car() -> void:
	# The whole point: it has to be a decision, not free speed.
	var registry := NodeRegistry.create_default()

	var reckless := BrainFormat.parse(FileAccess.get_file_as_string("res://brains/racer.brain")).graph
	reckless.add_node(&"me2", &"self_state")
	reckless.add_node(&"wing", &"out_drs")
	reckless.connect_ports(&"me2", &"drs_available", &"wing", &"value")
	var errors := BrainValidator.validate(reckless, registry)
	assert_eq(errors.size(), 0, "  ".join(errors))

	var with_drs := RaceSession.create(reckless, registry, Track.grand_prix())
	with_drs.run_until_lap(1, 6000)

	var normal_graph := BrainFormat.parse(FileAccess.get_file_as_string("res://brains/racer.brain")).graph
	var without := RaceSession.create(normal_graph, registry, Track.grand_prix())
	without.run_until_lap(1, 6000)

	assert_almost_eq(without.car.damage, 0.0, 0.001, "the racer is clean without it")
	assert_true(with_drs.car.damage > 0.0,
		"leaving it open everywhere should hurt, got %.0f%%" % [with_drs.car.damage * 100.0])
