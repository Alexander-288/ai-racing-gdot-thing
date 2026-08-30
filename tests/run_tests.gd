extends SceneTree
## Headless test runner.
##   tools/godot/Godot_v4.7.2-stable_win64_console.exe --headless --script res://tests/run_tests.gd
## Discovers every res://tests/**/*_test.gd, runs each `test_*` method, exits non-zero on failure.

func _init() -> void:
	var files: PackedStringArray = _discover("res://tests")
	files.sort()

	var total_tests: int = 0
	var total_assertions: int = 0
	var failed: Array[String] = []

	for path: String in files:
		var script: GDScript = load(path)
		# A file with a parse error still loads, but reports zero methods — so checking
		# for null is not enough. Without this, a broken test file is silently skipped.
		if script == null or not script.can_instantiate():
			failed.append("%s — did not compile (see parse errors above)" % path.get_file())
			continue
		var found_here: int = 0
		for method: Dictionary in script.get_script_method_list():
			var name: String = method["name"]
			if not name.begins_with("test_"):
				continue
			total_tests += 1
			found_here += 1
			var case: TestCase = script.new()
			case.call(name)
			total_assertions += case.assertions
			# A GDScript runtime error does not stop the run — it just logs and
			# abandons the method. So a test that asserted nothing probably blew up.
			if case.assertions == 0:
				failed.append("%s::%s — asserted nothing (did it error out? see above)"
					% [path.get_file(), name])
			for failure: String in case.failures:
				failed.append("%s::%s — %s" % [path.get_file(), name, failure])
		# Catches the other silent skip: file compiles, but a typo'd method name
		# or a missing `extends TestCase` means nothing in it actually ran.
		if found_here == 0:
			failed.append("%s — contains no test_* methods" % path.get_file())

	print("\n%d tests, %d assertions, %d failures" % [total_tests, total_assertions, failed.size()])
	for line: String in failed:
		printerr("FAIL  " + line)
	quit(0 if failed.is_empty() else 1)

func _discover(dir_path: String) -> PackedStringArray:
	var found: PackedStringArray = []
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return found
	dir.list_dir_begin()
	var entry: String = dir.get_next()
	while entry != "":
		var full: String = dir_path.path_join(entry)
		if dir.current_is_dir():
			found.append_array(_discover(full))
		elif entry.ends_with("_test.gd"):
			found.append(full)
		entry = dir.get_next()
	dir.list_dir_end()
	return found
