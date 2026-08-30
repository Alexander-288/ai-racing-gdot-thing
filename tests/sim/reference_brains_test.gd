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

# ------------------------------------------------------------------ generalising

## The whole point of the competition (spec 2.9): brains race on tracks they have
## never seen. A brain tuned to one circuit should lose to one that reads the road.

func _race_unseen(path: String, seed: int) -> RaceSession:
	var session := RaceSession.create(_load(path), NodeRegistry.create_default(),
		Track.generated(seed))
	session.run_until_lap(1, 5000)
	return session

func test_generated_tracks_are_drivable_and_repeatable() -> void:
	for seed in [1, 2, 3]:
		var a := Track.generated(seed)
		var b := Track.generated(seed)
		assert_true(a.tightest_corner() >= 14.0, "seed %d has an untakeable corner" % seed)
		assert_eq(a.checkpoints, b.checkpoints, "the same seed must give the same track")

func test_the_racer_finishes_every_unseen_track_undamaged() -> void:
	for seed in [1, 2, 3, 4]:
		var session := _race_unseen("res://brains/racer.brain", seed)
		assert_eq(session.car.lap, 1, "did not finish seed %d" % seed)
		assert_almost_eq(session.car.damage, 0.0, 0.001, "took damage on seed %d" % seed)

func test_reading_the_road_beats_knowing_the_route_on_unseen_tracks() -> void:
	# The braker is quicker on the circuit it was tuned for, and pays for it here.
	# That gap is the reason held-out tracks are the scoring mechanism.
	var braker_damage := 0.0
	var racer_damage := 0.0
	for seed in [1, 3, 5]:
		braker_damage += _race_unseen("res://brains/braker.brain", seed).car.damage
		racer_damage += _race_unseen("res://brains/racer.brain", seed).car.damage
	assert_true(racer_damage < braker_damage,
		"racer %.2f vs braker %.2f damage across unseen tracks" % [racer_damage, braker_damage])
