extends TestCase
## The reference brains are a deliberate ladder (spec 2.10): each one should beat
## the one below it. These tests hold that ladder in place, which also means they
## catch the day the sim stops rewarding the thing it is supposed to reward.

func _load(path: String) -> BrainGraph:
	var result := BrainFormat.parse(FileAccess.get_file_as_string(path))
	assert_true(result.ok(), "  ".join(result.errors))
	return result.graph

func _race(path: String, laps: int = 2) -> RaceSession:
	var registry := NodeRegistry.create_default()
	var graph := _load(path)
	assert_eq(BrainValidator.validate(graph, registry).size(), 0, "%s must be valid" % path)
	var session := RaceSession.create(graph, registry, Track.grand_prix())
	session.run_until_lap(laps, 8000)
	return session

func test_both_reference_brains_are_valid() -> void:
	var registry := NodeRegistry.create_default()
	for path: String in ["res://brains/follower.brain", "res://brains/braker.brain"]:
		assert_eq(BrainValidator.validate(_load(path), registry).size(), 0, path)

func test_the_follower_gets_round_the_real_circuit() -> void:
	var session := _race("res://brains/follower.brain")
	assert_eq(session.car.lap, 2, "the naive brain must still finish, just slowly")

func test_the_braker_is_quicker_than_the_follower() -> void:
	var follower := _race("res://brains/follower.brain")
	var braker := _race("res://brains/braker.brain")
	assert_true(braker.ticks < follower.ticks,
		"braker %d ticks vs follower %d — braking must pay" % [braker.ticks, follower.ticks])

func test_the_braker_finishes_undamaged() -> void:
	var session := _race("res://brains/braker.brain")
	assert_almost_eq(session.car.damage, 0.0, 0.001, "a clean racer does not touch barriers")
	assert_eq(session.wall_hits, 0)

func test_flat_out_is_fast_but_wrecks_the_car() -> void:
	# The tension the whole design needs: speed has to cost something, or there
	# is no decision to make and no reason to build a cleverer brain.
	var registry := NodeRegistry.create_default()
	var graph := _load("res://brains/follower.brain")
	graph.instances[&"cruise"].config[&"value"] = 1.0
	var session := RaceSession.create(graph, registry, Track.grand_prix())
	session.run_until_lap(2, 8000)
	assert_true(session.car.damage > 0.3,
		"flat out with no braking should hurt, got %.0f%%" % [session.car.damage * 100.0])

func test_the_braker_beats_flat_out_on_time_as_well() -> void:
	var registry := NodeRegistry.create_default()
	var reckless := _load("res://brains/follower.brain")
	reckless.instances[&"cruise"].config[&"value"] = 1.0
	var flat_out := RaceSession.create(reckless, registry, Track.grand_prix())
	flat_out.run_until_lap(2, 8000)

	var braker := _race("res://brains/braker.brain")
	assert_true(braker.ticks < flat_out.ticks,
		"thinking must beat flooring it: %d vs %d" % [braker.ticks, flat_out.ticks])
