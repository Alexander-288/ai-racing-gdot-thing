extends TestCase
## The Phase 1 success condition, as a test: one hand-built brain, read from its
## file, completes a clean lap. Everything else in the project exists to make
## this sentence true and then keep it true.

const FOLLOWER := "res://brains/follower.brain"

func _load_follower() -> BrainGraph:
	var result := BrainFormat.parse(FileAccess.get_file_as_string(FOLLOWER))
	assert_true(result.ok(), "  ".join(result.errors))
	return result.graph

func _session() -> RaceSession:
	return RaceSession.create(_load_follower(), NodeRegistry.create_default(), Track.oval())

func test_the_reference_brain_file_is_valid() -> void:
	var errors := BrainValidator.validate(_load_follower(), NodeRegistry.create_default())
	assert_eq(errors.size(), 0, "  ".join(errors))

func test_it_completes_a_lap() -> void:
	var session := _session()
	assert_true(session.run_until_lap(1), "did not finish in %d ticks" % session.ticks)
	assert_eq(session.car.checkpoints_passed, 16, "every checkpoint, in order")

func test_the_lap_is_clean() -> void:
	var session := _session()
	session.run_until_lap(1)
	assert_eq(session.left_track_count, 0, "ran wide on %d ticks" % session.left_track_count)

func test_it_keeps_going_for_several_laps() -> void:
	# A brain that survives one lap by luck usually falls apart on the next.
	var session := _session()
	assert_true(session.run_until_lap(3, 6000), "only reached lap %d" % session.car.lap)
	assert_eq(session.left_track_count, 0)

func test_the_same_brain_and_track_give_the_identical_lap_twice() -> void:
	# The determinism regression in miniature (spec 3.4). If this ever fails,
	# something has started depending on frame rate.
	var first := _session()
	var second := _session()
	first.run_until_lap(1)
	second.run_until_lap(1)
	assert_eq(first.ticks, second.ticks)
	assert_almost_eq(first.car.position.x, second.car.position.x, 0.0, "exactly, not nearly")
	assert_almost_eq(first.car.position.y, second.car.position.y, 0.0)
	assert_almost_eq(first.car.heading, second.car.heading, 0.0)

func test_a_brain_that_does_nothing_goes_nowhere() -> void:
	# The negative case, so the lap test above is proving something.
	var empty := BrainGraph.new()
	empty.add_node(&"steer", &"out_steering")
	var session := RaceSession.create(empty, NodeRegistry.create_default(), Track.oval())
	assert_false(session.run_until_lap(1, 1200), "no throttle, no lap")
	assert_almost_eq(session.car.speed, 0.0, 1e-6)
