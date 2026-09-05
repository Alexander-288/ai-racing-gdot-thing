class_name RaceSession
extends RefCounted
## A field of cars on a track, stepped tick by tick.
##
## No Godot nodes here on purpose, so a whole race runs headless in a test — and
## so the same code drives a fourteen-car Grand Prix and a one-car test drive.

## One car in the field: its brain, its machine, and what it did last tick.
class Entry extends RefCounted:
	var name: String = ""
	var car: Car
	var evaluator: BrainEvaluator
	var snapshot: SensorSnapshot
	var controls: CarControls = CarControls.new()
	var wall_hits: int = 0
	var contacts: int = 0  # times it has hit another car

var track: Track
var entries: Array[Entry] = []
var ticks: int = 0

## Which car the single-car accessors below refer to. A debug view watches one
## car at a time; a headless test usually only has one.
var focus: int = 0

# Conveniences, so anything that only cares about one car does not have to reach
# through the field to find it.
var car: Car:
	get:
		return entries[focus].car

var evaluator: BrainEvaluator:
	get:
		return entries[focus].evaluator

var snapshot: SensorSnapshot:
	get:
		return entries[focus].snapshot

var controls: CarControls:
	get:
		return entries[focus].controls

var wall_hits: int:
	get:
		return entries[focus].wall_hits
	set(value):
		entries[focus].wall_hits = value

static func create(graph: BrainGraph, registry: NodeRegistry, track: Track) -> RaceSession:
	return create_field([graph], registry, track)

## A grid. The race manager does not care whether these are fourteen different
## brains or fourteen copies of one, which is what makes self-play free.
static func create_field(graphs: Array, registry: NodeRegistry, track: Track) -> RaceSession:
	var s := RaceSession.new()
	s.track = track
	for i in graphs.size():
		var graph: BrainGraph = graphs[i]
		var e := Entry.new()
		e.name = graph.name if graph.name != "" else "Car %d" % (i + 1)
		e.car = Car.at_grid_slot(track, i, graphs.size())
		e.evaluator = BrainEvaluator.create(graph, registry)
		e.snapshot = SensorBuilder.build(e.car, track, [], -1)
		s.entries.append(e)
	s._update_standings()
	return s

## The per-tick data flow from spec 3.2, in the one place it is allowed to live.
##
## Each stage runs for every car before the next stage begins. That is not
## tidiness — sensing car by car while earlier cars had already moved would hand
## the later ones a tick of fresher information, and the grid order would quietly
## become an advantage.
func tick() -> void:
	var cars: Array[Car] = []
	for e: Entry in entries:
		cars.append(e.car)

	for i in entries.size():
		entries[i].snapshot = SensorBuilder.build(entries[i].car, track, cars, i)

	for e: Entry in entries:
		e.controls = e.evaluator.tick(e.snapshot)

	for e: Entry in entries:
		e.car.step(e.controls, track)

	_resolve_contacts()

	for e: Entry in entries:
		if e.car.touching_wall:
			e.wall_hits += 1

	_update_standings()
	ticks += 1

## Puts everyone back on the grid with their memory wiped. Brains spawn clean
## every race, so nothing carries over from the last run (spec 2.5).
func restart() -> void:
	for i in entries.size():
		entries[i].car = Car.at_grid_slot(track, i, entries.size())
		entries[i].evaluator.reset()
		entries[i].wall_hits = 0
		entries[i].contacts = 0
		entries[i].snapshot = SensorBuilder.build(entries[i].car, track, [], -1)
	ticks = 0
	_update_standings()

## Runs until the focused car finishes the given lap, or gives up. Returns
## whether it made it, so a test can say "this brain drives" rather than "it did
## not crash".
func run_until_lap(target_lap: int, tick_limit: int = 5000) -> bool:
	while ticks < tick_limit:
		tick()
		if car.lap >= target_lap:
			return true
	return false

## The field in running order, leader first.
func standings() -> Array[Entry]:
	var order: Array[Entry] = entries.duplicate()
	order.sort_custom(func(a: Entry, b: Entry) -> bool:
		return a.car.position_in_field < b.car.position_in_field)
	return order

# ---------------------------------------------------------------- internals

## Running order is how many checkpoints you have passed, then how close you are
## to the next one. Grid index breaks a dead heat, so the order is never left to
## chance — two cars level on the same tick must still sort the same way twice.
func _update_standings() -> void:
	var order: Array[int] = []
	for i in entries.size():
		order.append(i)

	var progress: Array[float] = []
	for e: Entry in entries:
		progress.append(e.car.position.distance_to(track.checkpoint_at(e.car.next_checkpoint)))

	order.sort_custom(func(a: int, b: int) -> bool:
		var passed_a := entries[a].car.checkpoints_passed
		var passed_b := entries[b].car.checkpoints_passed
		if passed_a != passed_b:
			return passed_a > passed_b
		if not is_equal_approx(progress[a], progress[b]):
			return progress[a] < progress[b]
		return a < b)

	for place in order.size():
		entries[order[place]].car.position_in_field = place + 1

## Cars that ended the tick inside each other are pushed apart and both pay for
## it. Pairs are visited in a fixed order so the same crash resolves the same way
## every run.
func _resolve_contacts() -> void:
	for i in entries.size():
		for j in range(i + 1, entries.size()):
			if entries[i].car.collide_with(entries[j].car):
				entries[i].contacts += 1
				entries[j].contacts += 1
