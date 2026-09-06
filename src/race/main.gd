extends Node3D
## Temporary entry point: loads the reference brain and drives it round the test
## oval, printing what happened. There is nothing to look at yet — rendering is
## Phase 6, deliberately last, because it is the fun part and would otherwise eat
## the time the risky parts need.

const BRAIN_PATH := "res://brains/braker.brain"

func _ready() -> void:
	print("Formula AI: Grand Prix — Godot %s" % Engine.get_version_info().string)

	var loaded := BrainFormat.parse(FileAccess.get_file_as_string(BRAIN_PATH))
	if not loaded.ok():
		for problem: String in loaded.errors:
			printerr("brain file: %s" % problem)
		return

	var registry := NodeRegistry.create_default()
	var errors := BrainValidator.validate(loaded.graph, registry)
	if not errors.is_empty():
		for problem: String in errors:
			printerr("invalid brain: %s" % problem)
		return

	# A full grid of the same brain — the race manager does not care that they
	# are all the same one, which is what makes self-play free later.
	var field: Array = []
	for i in 14:
		field.append(BrainFormat.parse(FileAccess.get_file_as_string(BRAIN_PATH)).graph)
	var session := RaceSession.create_field(field, registry, Circuit.track_for(0))
	var finished := session.run_until_lap(3, 24000)

	print('brain "%s"' % loaded.graph.name)
	print("%d cars, %d ticks (%.1fs)" % [session.entries.size(), session.ticks, session.ticks * Car.TICK])
	for e: RaceSession.Entry in session.standings():
		print("  P%-2d  lap %d  %5.1f m/s  damage %3.0f%%  walls %4d  contacts %3d"
			% [e.car.position_in_field, e.car.lap, e.car.speed, e.car.damage * 100.0,
				e.wall_hits, e.contacts])
	if not finished:
		print("did not finish — it is a naive brain, that is allowed")
