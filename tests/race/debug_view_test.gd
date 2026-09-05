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
