extends TestCase
## The grid: who is racing, what each of them drives, and refusing to start a
## race that cannot be run.

func _open() -> GridDialog:
	var graph := BrainFormat.parse(FileAccess.get_file_as_string("res://brains/racer.brain")).graph
	var dialog := GridDialog.open(NodeRegistry.create_default(), graph, "Open Brain", 0,
		[] as Array[String])
	Engine.get_main_loop().root.add_child(dialog)
	return dialog

func _close(dialog: GridDialog) -> void:
	Engine.get_main_loop().root.remove_child(dialog)
	dialog.free()

func test_it_starts_with_the_open_brain_on_its_own() -> void:
	var dialog := _open()
	assert_eq(dialog.roster.size(), 1)
	assert_eq(dialog.roster[0], GridDialog.OPEN_BRAIN, "the car you have is the one you are editing")
	_close(dialog)

func test_it_finds_the_brains_that_ship_with_the_game() -> void:
	var found := GridDialog.discover_brains()
	assert_true(found.size() >= 3, "the reference brains should be offered, got %d" % found.size())
	var names := ""
	for path: String in found:
		names += path
	assert_true(names.contains("racer"), names)

func test_adding_a_car_puts_another_on_the_grid() -> void:
	var dialog := _open()
	dialog.add_car()
	dialog.add_car()
	assert_eq(dialog.roster.size(), 3)
	_close(dialog)

func test_the_grid_has_a_ceiling() -> void:
	var dialog := _open()
	for i in 40:
		dialog.add_car()
	assert_eq(dialog.roster.size(), GridDialog.MAX_CARS)
	_close(dialog)

func test_each_car_can_drive_something_different() -> void:
	var dialog := _open()
	dialog.add_car()
	dialog.roster[1] = "res://brains/follower.brain"
	var field := dialog.build_field()
	assert_eq(field.size(), 2)
	assert_eq((field[1] as BrainGraph).name, "Reference: Checkpoint Follower",
		"the second car drives what it was given, not a copy of the first")
	_close(dialog)

func test_every_car_gets_its_own_copy_of_the_brain() -> void:
	# Two cars sharing one graph would share one accumulator, so one car's memory
	# would be the other's too.
	var dialog := _open()
	dialog.add_car()
	var field := dialog.build_field()
	assert_false(field[0] == field[1], "the same graph object must not be raced twice")
	_close(dialog)

func test_the_open_brain_is_read_as_it_is_now() -> void:
	var dialog := _open()
	dialog.open_graph.add_node(&"late_addition", &"constant", { &"value": 3.0 })
	var field := dialog.build_field()
	assert_true((field[0] as BrainGraph).instances.has(&"late_addition"),
		"the roster refers to the open brain, not to a snapshot of it")
	_close(dialog)

func test_a_brain_that_will_not_load_stops_the_race() -> void:
	var dialog := _open()
	dialog.add_car()
	dialog.roster[1] = "res://brains/there_is_no_such_brain.brain"
	assert_eq(dialog.build_field().size(), 0, "a race never starts half built")
	assert_true(dialog._describe().contains("will not load"), dialog._describe())
	_close(dialog)

func test_an_invalid_brain_is_reported_before_the_race_not_during_it() -> void:
	var dialog := _open()
	dialog.open_graph.add_node(&"a", &"add")
	dialog.open_graph.add_node(&"b", &"add")
	dialog.open_graph.connect_ports(&"a", &"out", &"b", &"a")
	dialog.open_graph.connect_ports(&"b", &"out", &"a", &"a")  # a cycle with no memory in it
	assert_true(dialog._describe().contains("cycle"), dialog._describe())
	assert_eq(dialog.build_field().size(), 0)
	_close(dialog)

func test_a_healthy_grid_says_so() -> void:
	var dialog := _open()
	dialog.add_car()
	assert_true(dialog._describe().contains("2 cars"), dialog._describe())
	_close(dialog)

func test_filling_the_grid_and_racing_it() -> void:
	var dialog := _open()
	for i in 5:
		dialog.add_car()
	var field := dialog.build_field()
	var session := RaceSession.create_field(field, NodeRegistry.create_default(), Track.proving_circuit())
	for i in 120:
		session.tick()
	for e: RaceSession.Entry in session.entries:
		assert_true(e.car.speed > 0.0, "every car the grid built should be driving")
	_close(dialog)
