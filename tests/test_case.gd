extends RefCounted
class_name TestCase
## Minimal assertion base for headless tests. No external addon dependency:
## the whole suite must run under `godot --headless --script res://tests/run_tests.gd`.

var failures: Array[String] = []
var assertions: int = 0

func assert_true(value: bool, message: String = "") -> void:
	assertions += 1
	if not value:
		_fail("expected true", message)

func assert_false(value: bool, message: String = "") -> void:
	assertions += 1
	if value:
		_fail("expected false", message)

func assert_eq(actual: Variant, expected: Variant, message: String = "") -> void:
	assertions += 1
	if actual != expected:
		_fail("expected %s, got %s" % [expected, actual], message)

func assert_almost_eq(actual: float, expected: float, epsilon: float = 1e-6, message: String = "") -> void:
	assertions += 1
	if absf(actual - expected) > epsilon:
		_fail("expected %f +/- %f, got %f" % [expected, epsilon, actual], message)

func _fail(detail: String, message: String) -> void:
	failures.append(detail if message.is_empty() else "%s: %s" % [message, detail])
