extends SceneTree
func run(name: String) -> void:
	var registry := NodeRegistry.create_default()
	var text := FileAccess.get_file_as_string("res://brains/%s.brain" % name)
	var field: Array = []
	for i in 14:
		field.append(BrainFormat.parse(text).graph)
	var s := RaceSession.create_field(field, registry, Track.grand_prix())
	for i in 2400:
		s.tick()
	var damage := 0.0
	var contacts := 0
	var laps := 0
	for e: RaceSession.Entry in s.entries:
		damage += e.car.damage
		contacts += e.contacts
		laps += e.car.lap
	print("%-9s avg damage %3.0f%%   contacts %4d   laps %3d" % [name, damage / 14.0 * 100.0, contacts, laps])

func _initialize() -> void:
	print("14 copies of each, 40 seconds:")
	for name: String in ["braker", "racer", "ace"]:
		run(name)

	# And a mixed grid, which is what the dialog now makes possible.
	var registry := NodeRegistry.create_default()
	var field: Array = []
	var names: Array[String] = []
	for i in 12:
		var pick: String = ["ace", "racer", "braker"][i % 3]
		names.append(pick)
		field.append(BrainFormat.parse(FileAccess.get_file_as_string("res://brains/%s.brain" % pick)).graph)
	var s := RaceSession.create_field(field, registry, Track.grand_prix())
	for i in 2400:
		s.tick()
	print("mixed grid, finishing order:")
	for e: RaceSession.Entry in s.standings():
		var idx := s.entries.find(e)
		print("  P%-2d %-8s lap %d  %3.0f%% dmg" % [e.car.position_in_field, names[idx], e.car.lap, e.car.damage * 100.0])
	quit(0)
