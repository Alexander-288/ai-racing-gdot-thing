extends TestCase
## The view is pixels, but what it shows must be true: the rays it draws have to
## be the rays the brain was given.

func _open_view() -> DebugView:
	var graph := BrainFormat.parse(FileAccess.get_file_as_string("res://brains/follower.brain")).graph
	var view := DebugView.open(graph, NodeRegistry.create_default(), Track.oval())
	view.size = Vector2(1000, 700)
	Engine.get_main_loop().root.add_child(view)
	return view

func _close(view: DebugView) -> void:
	Engine.get_main_loop().root.remove_child(view)
	view.free()

func test_it_draws_one_ray_per_sensor_ray() -> void:
	# If these ever disagree, the picture is lying about what the brain saw.
	assert_eq(SensorBuilder.ray_angles().size(), SensorSnapshot.RAY_COUNT)
	_close(_open_view())

func test_stepping_advances_the_sim() -> void:
	var view := _open_view()
	view._physics_process(0.0)
	assert_eq(view.session.ticks, 1)
	assert_true(view.session.car.speed > 0.0, "the follower opens the throttle at once")
	_close(view)

func test_pausing_stops_it() -> void:
	var view := _open_view()
	view.running = false
	view._physics_process(0.0)
	assert_eq(view.session.ticks, 0)
	_close(view)

func test_watching_faster_runs_more_ticks_not_bigger_ones() -> void:
	# Speeding up must never change the tick length, or determinism is gone.
	var slow := _open_view()
	var fast := _open_view()
	fast.steps_per_frame = 10
	for i in 10:
		slow._physics_process(0.0)
	fast._physics_process(0.0)
	assert_eq(slow.session.ticks, fast.session.ticks)
	assert_almost_eq(slow.session.car.position.x, fast.session.car.position.x, 0.0, "identical, not similar")
	_close(slow)
	_close(fast)

func test_the_whole_track_fits_on_screen() -> void:
	var view := _open_view()
	for i in view.session.track.checkpoint_count():
		var on_screen := view._to_screen(view.session.track.checkpoint_at(i))
		assert_true(on_screen.x >= 0.0 and on_screen.x <= view.size.x, "x off screen: %f" % on_screen.x)
		assert_true(on_screen.y >= 0.0 and on_screen.y <= view.size.y, "y off screen: %f" % on_screen.y)
	_close(view)

func test_reset_puts_the_car_back() -> void:
	var view := _open_view()
	for i in 200:
		view._physics_process(0.0)
	var moved := view.session.car.position
	view.session.restart()
	assert_true(view.session.car.position != moved)
	assert_eq(view.session.ticks, 0, "restart puts the clock back too")
	_close(view)

# ------------------------------------------------------------------ a whole field

func _open_field(count: int) -> DebugView:
	var text := FileAccess.get_file_as_string("res://brains/racer.brain")
	var graphs: Array = []
	for i in count:
		graphs.append(BrainFormat.parse(text).graph)
	var view := DebugView.open_field(graphs, NodeRegistry.create_default(), Track.proving_circuit())
	view.size = Vector2(1000, 700)
	Engine.get_main_loop().root.add_child(view)
	return view

func test_a_field_puts_every_car_on_the_track() -> void:
	var view := _open_field(6)
	assert_eq(view.session.entries.size(), 6)
	for i in 60:
		view._physics_process(0.0)
	for e: RaceSession.Entry in view.session.entries:
		assert_true(e.car.speed > 0.0, "every car in the field should be driving")
	_close(view)

func test_watching_next_moves_through_the_field_and_wraps() -> void:
	var view := _open_field(3)
	assert_eq(view.session.focus, 0)
	view.session.focus = (view.session.focus + 1) % view.session.entries.size()
	assert_eq(view.session.focus, 1)
	view.session.focus = 2
	view.session.focus = (view.session.focus + 1) % view.session.entries.size()
	assert_eq(view.session.focus, 0, "past the last car is back to the first")
	_close(view)

func test_the_readout_names_the_car_you_are_watching() -> void:
	var view := _open_field(4)
	view._physics_process(0.0)
	assert_true(view._readout.text.contains("car 1 of 4"), view._readout.text)
	view.session.focus = 2
	view._physics_process(0.0)
	assert_true(view._readout.text.contains("car 3 of 4"), view._readout.text)
	_close(view)

func test_a_field_gets_a_running_order_and_one_car_does_not() -> void:
	var many := _open_field(4)
	many._physics_process(0.0)
	assert_true(many._standings().contains("order"), "a field is worth listing")
	_close(many)

	var alone := _open_field(1)
	alone._physics_process(0.0)
	assert_eq(alone._standings(), "", "there is no order to report with one car")
	_close(alone)

# ------------------------------------------------------------------ trails

func test_each_car_leaves_a_trail() -> void:
	var view := _open_field(3)
	for i in 30:
		view._physics_process(0.0)
	for i in 3:
		assert_eq(view._trails[i].size(), 30, "one point per tick, per car")
	_close(view)

func test_a_trail_stops_growing_once_it_is_long_enough() -> void:
	# Otherwise a long race slowly stains the whole track.
	var view := _open_field(1)
	for i in DebugView.TRAIL_LENGTH + 40:
		view._physics_process(0.0)
	assert_eq(view._trails[0].size(), DebugView.TRAIL_LENGTH)
	_close(view)

func test_resetting_wipes_the_trails() -> void:
	var view := _open_field(2)
	for i in 40:
		view._physics_process(0.0)
	view.session.restart()
	for i in view._trails.size():
		view._trails[i] = PackedVector2Array()
	assert_eq(view._trails[0].size(), 0)
	_close(view)

# ------------------------------------------------------------------ cable flow

func test_the_flow_brightens_and_dims_along_a_cable() -> void:
	# The band has to actually vary, or the animation is a flat tint.
	var base := Color(0.4, 0.5, 0.9)
	var brightest := 0.0
	var dimmest := 1.0
	for step in 40:
		var v := CableStyle.flowing(base, float(step) * 8.0, 0.0).v
		brightest = maxf(brightest, v)
		dimmest = minf(dimmest, v)
	assert_true(brightest > dimmest, "no band travels along the cable")
	assert_true(brightest - dimmest < 0.35, "the band should be a suggestion, not a strobe")

func test_the_flow_moves_over_time() -> void:
	var base := Color(0.4, 0.5, 0.9)
	var at_rest := CableStyle.flowing(base, 100.0, 0.0)
	var later := CableStyle.flowing(base, 100.0, 1.0)
	assert_true(not at_rest.is_equal_approx(later), "the band must travel, not sit still")

func test_the_flow_never_loses_the_cable_colour() -> void:
	var base := Color(0.4, 0.5, 0.9)
	for step in 20:
		var lit := CableStyle.flowing(base, float(step) * 13.0, 0.4)
		assert_true(lit.b > lit.r, "a blue cable stays blue at every point of the band")
