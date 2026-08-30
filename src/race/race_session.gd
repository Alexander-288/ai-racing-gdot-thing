class_name RaceSession
extends RefCounted
## One car, one track, one brain, stepped tick by tick. The smallest thing that
## can answer the Phase 1 question: does a hand-built brain complete a clean lap?
##
## No Godot nodes here on purpose, so a whole race runs headless in a test.

var track: Track
var car: Car
var evaluator: BrainEvaluator
var ticks: int = 0
var wall_hits: int = 0  # ticks spent against a barrier, i.e. was the lap clean

static func create(graph: BrainGraph, registry: NodeRegistry, track: Track) -> RaceSession:
	var s := RaceSession.new()
	s.track = track
	s.car = Car.at_start(track)
	s.evaluator = BrainEvaluator.create(graph, registry)
	return s

## The per-tick data flow from spec 3.2, in the one place it is allowed to live:
## sense, think, act, step. Same order for every car, every tick.
func tick() -> void:
	var snapshot := SensorBuilder.build(car, track)
	var controls := evaluator.tick(snapshot)
	car.step(controls, track)
	if car.touching_wall:
		wall_hits += 1
	ticks += 1

## Runs until the car finishes the given lap, or gives up. Returns whether it
## made it, so a test can say "this brain drives" rather than "it did not crash".
func run_until_lap(target_lap: int, tick_limit: int = 5000) -> bool:
	while ticks < tick_limit:
		tick()
		if car.lap >= target_lap:
			return true
	return false
