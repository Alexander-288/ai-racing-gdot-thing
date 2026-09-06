extends TestCase
## The named circuits. Most of what can go wrong with a hand-drawn track is
## geometric and silent: a shape that folds through its own corridor, or a corner
## the spline pinched into something no car could take. Both were true of two of
## these while they were being drawn, and neither shows up as an error — the race
## just quietly stops making sense.

func _registry() -> NodeRegistry:
	return NodeRegistry.create_default()

func _load(name: String) -> BrainGraph:
	var result := BrainFormat.parse(FileAccess.get_file_as_string("res://brains/%s.brain" % name))
	assert_true(result.ok(), "  ".join(result.errors))
	return result.graph

## The closest two bits of road come to each other, ignoring each point's own
## neighbourhood. Below the width of the road means the track overlaps itself.
## Coarse on purpose: every fourth point is enough to catch a fold, and the exact
## check is a quarter of a million distances per circuit.
func _closest_approach(track: Track) -> float:
	var pts := track.centre_line
	var n := pts.size()
	var best := INF
	var i := 0
	while i < n:
		var j := 0
		while j < n:
			if mini(absi(i - j), n - absi(i - j)) > 24:
				best = minf(best, pts[i].distance_to(pts[j]))
			j += 4
		i += 4
	return best

func test_every_circuit_comes_out_the_length_it_asks_for() -> void:
	for spec: Circuit.Spec in Circuit.all():
		var track := Circuit.build(spec)
		var length := track.centre_line.size() * Circuit.SPACING
		assert_true(absf(length - spec.length) < spec.length * 0.02,
			"%s came out %.0f m, wanted %.0f" % [spec.name, length, spec.length])

func test_no_circuit_runs_through_itself() -> void:
	# The failure this catches is a track that crosses or doubles back onto its
	# own road. A car on one of those is on two parts of the lap at once, and the
	# lap counter and the barrier both start lying.
	for spec: Circuit.Spec in Circuit.all():
		var track := Circuit.build(spec)
		var gap := _closest_approach(track)
		assert_true(gap > track.half_width * 2.0,
			"%s folds onto itself: %.1f m apart where the road is %.1f wide"
				% [spec.name, gap, track.half_width * 2.0])

func test_every_corner_can_actually_be_taken() -> void:
	# A car holds a corner of radius r up to sqrt(MAX_LATERAL * r). Below about
	# six metres that speed is slower than the car can usefully go, and the corner
	# stops being a corner and becomes a wall.
	for spec: Circuit.Spec in Circuit.all():
		var track := Circuit.build(spec)
		var tightest := track.tightest_corner()
		assert_true(tightest >= 6.0,
			"%s has a %.1f m corner, which is not a corner" % [spec.name, tightest])

func test_every_circuit_is_route_marked() -> void:
	for spec: Circuit.Spec in Circuit.all():
		var track := Circuit.build(spec)
		assert_true(track.checkpoints.size() >= 12,
			"%s has only %d checkpoints" % [spec.name, track.checkpoints.size()])

func test_the_circuits_keep_their_order_of_length() -> void:
	# Scaled to lap time rather than to distance, but Spa is still the long one
	# and Monaco still the short one — that ordering is most of what makes them
	# feel like the places they are named after.
	var by_id: Dictionary = {}
	for spec: Circuit.Spec in Circuit.all():
		by_id[spec.id] = spec.length
	assert_true(by_id[&"spa"] > by_id[&"monza"], "Spa is the longest")
	assert_true(by_id[&"monaco"] < by_id[&"interlagos"], "Monaco is the shortest")

func test_a_picker_id_is_a_circuit_or_a_seed() -> void:
	for i in Circuit.count():
		assert_eq(Circuit.label_for(i), Circuit.spec_at(i).name)
		assert_true(Circuit.track_for(i).centre_line.size() > 0)
	var seeded := Circuit.GENERATED_BASE + 3
	assert_eq(Circuit.label_for(seeded), "seed 3")
	assert_true(Circuit.track_for(seeded).centre_line.size() > 0)

func test_a_held_out_track_is_the_same_size_as_a_named_one() -> void:
	# A generated track a quarter the size of the circuits would not be a
	# held-out version of the same problem, just an easier one.
	var generated := Track.generated(4)
	var length := generated.centre_line.size() * Circuit.SPACING
	assert_true(length > 2000.0 and length < 3600.0,
		"a generated track came out %.0f m" % length)

func test_a_reference_brain_gets_round_a_circuit() -> void:
	# The one test here that actually drives. Geometry can pass every check above
	# and still produce a lap nothing can complete.
	var session := RaceSession.create(_load("ace"), _registry(), Circuit.track_for(0))
	var finished := session.run_until_lap(1, 12000)
	assert_true(finished, "the ace did not get round Monza in %d ticks" % session.ticks)
