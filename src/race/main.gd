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

	var session := RaceSession.create(loaded.graph, registry, Track.grand_prix())
	var finished := session.run_until_lap(3)

	print('brain "%s"' % loaded.graph.name)
	print("laps: %d, ticks: %d (%.1fs), wall contact: %d ticks, damage: %.0f%%"
		% [session.car.lap, session.ticks, session.ticks * Car.TICK, session.wall_hits,
			session.car.damage * 100.0])
	if not finished:
		print("did not finish — it is a naive brain, that is allowed")
