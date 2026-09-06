extends TestCase
## The ace: the top of the reference ladder, and the best a brain gets here
## without a network in it.

func _registry() -> NodeRegistry:
	return NodeRegistry.create_default()

func _load(name: String) -> BrainGraph:
	var result := BrainFormat.parse(FileAccess.get_file_as_string("res://brains/%s.brain" % name))
	assert_true(result.ok(), "  ".join(result.errors))
	return result.graph

func _race(name: String, seed: int, laps: int = 2) -> RaceSession:
	var track: Track = Track.grand_prix() if seed == 0 else Track.generated(seed)
	var session := RaceSession.create(_load(name), _registry(), track)
	session.run_until_lap(laps, 8000)
	return session

func test_it_is_a_legal_brain() -> void:
	var errors := BrainValidator.validate(_load("ace"), _registry())
	assert_eq(errors.size(), 0, "  ".join(errors))

func test_it_stays_inside_the_budgets() -> void:
	# It uses memory and radar heavily, so it is the brain most likely to run out.
	var graph := _load("ace")
	var accumulators := 0
	var radars := 0
	for inst: BrainGraph.Instance in graph.instances.values():
		if inst.type_id == &"accumulator":
			accumulators += 1
		elif inst.type_id == &"radar":
			radars += 1
	assert_true(accumulators <= 8, "%d accumulators" % accumulators)
	assert_true(radars <= 4, "%d radars" % radars)
	assert_true(accumulators >= 2, "it should be using memory, not just allowed to")

func test_it_beats_the_racer_on_its_own_circuit() -> void:
	var ace := _race("ace", 0)
	var racer := _race("racer", 0)
	assert_true(ace.ticks < racer.ticks,
		"ace %d ticks vs racer %d" % [ace.ticks, racer.ticks])

func test_it_finishes_clean() -> void:
	var session := _race("ace", 0)
	assert_almost_eq(session.car.damage, 0.0, 0.001, "fast is no good if it arrives broken")
	assert_eq(session.wall_hits, 0)

func test_it_beats_the_racer_on_tracks_it_has_never_seen() -> void:
	# The property that actually matters (spec 2.9). Being quicker at home is
	# what the braker managed, and it is not the same thing.
	for seed in [1, 3]:
		var ace := _race("ace", seed)
		var racer := _race("racer", seed)
		assert_true(ace.ticks < racer.ticks,
			"seed %d: ace %d vs racer %d" % [seed, ace.ticks, racer.ticks])
		assert_almost_eq(ace.car.damage, 0.0, 0.02, "seed %d left it damaged" % seed)

func test_the_wheel_is_smoothed_rather_than_snapped() -> void:
	# The steering runs through an accumulator, so it cannot jump from lock to
	# lock in one tick. Without that the car judders and the telemetry is noise.
	var session := RaceSession.create(_load("ace"), _registry(), Track.grand_prix())
	var previous := 0.0
	var biggest_jump := 0.0
	for i in 600:
		session.tick()
		var now := session.controls.steering
		if i > 10:
			biggest_jump = maxf(biggest_jump, absf(now - previous))
		previous = now
	assert_true(biggest_jump < 0.5,
		"steering moved %.2f in one tick, which is a snap not a turn" % biggest_jump)

func test_drs_latches_instead_of_chattering() -> void:
	# A bare threshold flickers on and off while the input sits near it. The
	# latch is what stops the wing strobing down a straight.
	var session := RaceSession.create(_load("ace"), _registry(), Track.grand_prix())
	var flips := 0
	var was := false
	var opened := 0
	for i in 1200:
		session.tick()
		var now := session.controls.drs
		if i > 0 and now != was:
			flips += 1
		if now:
			opened += 1
		was = now
	assert_true(opened > 0, "it should be using DRS at all")
	assert_true(flips < 40, "the wing changed state %d times in a lap" % flips)

func test_the_whole_ladder_still_climbs() -> void:
	# Each reference brain should beat the one below it on the circuit they were
	# all built against.
	var follower := _race("follower", 0).ticks
	var braker := _race("braker", 0).ticks
	var racer := _race("racer", 0).ticks
	var ace := _race("ace", 0).ticks
	assert_true(braker < follower, "braker %d vs follower %d" % [braker, follower])
	assert_true(ace < racer, "ace %d vs racer %d" % [ace, racer])
	assert_true(ace < braker, "ace %d vs braker %d" % [ace, braker])
