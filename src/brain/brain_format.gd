class_name BrainFormat
## Reads and writes the brain file format (spec 2.3): verbose, readable, and
## hand-editable. Never minified — a brain file is meant to be diffed and patched.
## It is also the import path for weights trained outside the engine.
##
## Example:
##
##   format 1
##   name "Counter"
##
##   node one constant
##       value = 1.0
##
##   node acc accumulator
##
##   wire one.out -> acc.add

const FORMAT_VERSION := 1

## What parse() gives back. Errors are collected, never thrown: a broken brain
## file must be rejected with a reason, not crash the race manager (spec 3.3).
class ParseResult extends RefCounted:
	var graph: BrainGraph = null
	var errors: PackedStringArray = []

	func ok() -> bool:
		return errors.is_empty()

# ---------------------------------------------------------------- writing

static func serialize(graph: BrainGraph) -> String:
	var out: PackedStringArray = []
	out.append("format %d" % FORMAT_VERSION)
	out.append("name %s" % _quote(graph.name))
	out.append("")

	# Trays first, because that is the order they are drawn in: background, then
	# the nodes standing on it.
	for tray: BrainGraph.Tray in graph.trays:
		out.append("tray %s %s" % [tray.id, _quote(tray.title)])
		out.append("    at %s %s" % [_write_float(tray.position.x), _write_float(tray.position.y)])
		out.append("    size %s %s" % [_write_float(tray.size.x), _write_float(tray.size.y)])
		if tray.colour != 0:  # 0 is the plain one, and not worth a line
			out.append("    colour %d" % tray.colour)
		out.append("")

	for inst: BrainGraph.Instance in graph.instances.values():
		out.append("node %s %s" % [inst.id, inst.type_id])
		# Where it sits on the canvas. Layout only — the runtime ignores it.
		if inst.position != Vector2.ZERO:
			out.append("    at %s %s" % [_write_float(inst.position.x), _write_float(inst.position.y)])
		# Sorted so the same graph always writes byte-identical text.
		var keys: Array = inst.config.keys()
		keys.sort()
		for key: StringName in keys:
			out.append("    %s = %s" % [key, _write_value(inst.config[key])])
		out.append("")

	for w: BrainGraph.Wire in graph.wires:
		out.append("wire %s.%s -> %s.%s" % [w.from_node, w.from_port, w.to_node, w.to_port])

	return "\n".join(out) + "\n"

## Floats are written the short way when that survives a reload, and at full
## precision when it does not. Plain str() drops digits — 1.0/3.0 comes back
## different — which would quietly corrupt imported network weights.
static func _write_float(v: float) -> String:
	var short := str(v)
	return short if short.to_float() == v else String.num(v, 17)

static func _write_value(v: Variant) -> String:
	match typeof(v):
		TYPE_BOOL:
			return "true" if v else "false"
		TYPE_STRING, TYPE_STRING_NAME:
			return _quote(str(v))
		TYPE_ARRAY, TYPE_PACKED_FLOAT64_ARRAY, TYPE_PACKED_FLOAT32_ARRAY:
			var parts: PackedStringArray = []
			for item: float in v:
				parts.append(_write_float(item))
			return "[%s]" % ", ".join(parts)
		_:
			return _write_float(float(v))

static func _quote(s: String) -> String:
	return "\"%s\"" % s.replace("\\", "\\\\").replace("\"", "\\\"")

# ---------------------------------------------------------------- reading

static func parse(text: String) -> ParseResult:
	var result := ParseResult.new()
	result.graph = BrainGraph.new()
	var current: BrainGraph.Instance = null
	var current_tray: BrainGraph.Tray = null
	var line_no := 0

	for raw_line: String in text.split("\n"):
		line_no += 1
		var line := raw_line.strip_edges()
		if line.is_empty() or line.begins_with("#"):  # whole-line comments only
			continue

		# Indentation is what marks a config line, so it belongs to the node above.
		var indented := raw_line.begins_with(" ") or raw_line.begins_with("\t")
		if indented:
			if current != null:
				_read_config(line, current, line_no, result)
			elif current_tray != null:
				_read_tray_setting(line, current_tray, line_no, result)
			else:
				result.errors.append("line %d: setting outside any node" % line_no)
			continue

		current = null
		current_tray = null
		var parts := line.split(" ", false)
		match parts[0]:
			"format":
				_read_format(parts, line_no, result)
			"name":
				result.graph.name = _read_string(line.substr(4).strip_edges(), line_no, result)
			"node":
				current = _read_node(parts, line_no, result)
			"tray":
				current_tray = _read_tray(line, parts, line_no, result)
			"wire":
				_read_wire(line, line_no, result)
			_:
				result.errors.append("line %d: don't understand '%s'" % [line_no, parts[0]])

	return result

static func _read_format(parts: PackedStringArray, line_no: int, result: ParseResult) -> void:
	if parts.size() != 2 or not parts[1].is_valid_int():
		result.errors.append("line %d: expected 'format <number>'" % line_no)
	elif parts[1].to_int() > FORMAT_VERSION:
		result.errors.append("line %d: file is format %s, this build only reads %d"
			% [line_no, parts[1], FORMAT_VERSION])

static func _read_node(parts: PackedStringArray, line_no: int, result: ParseResult) -> BrainGraph.Instance:
	if parts.size() != 3:
		result.errors.append("line %d: expected 'node <id> <type>'" % line_no)
		return null
	var id := StringName(parts[1])
	if result.graph.instances.has(id):
		result.errors.append("line %d: there is already a node called '%s'" % [line_no, id])
		return null
	return result.graph.add_node(id, StringName(parts[2]))

## A tray is layout, so a file with a broken one is still a runnable brain — but
## it is reported like anything else rather than silently dropped.
static func _read_tray(line: String, parts: PackedStringArray, line_no: int,
		result: ParseResult) -> BrainGraph.Tray:
	if parts.size() < 2:
		result.errors.append("line %d: expected 'tray <id> \"<title>\"'" % line_no)
		return null
	var id := StringName(parts[1])
	if result.graph.has_tray(id):
		result.errors.append("line %d: there is already a tray called '%s'" % [line_no, id])
		return null
	# Everything past the id is the title, because a title may contain spaces.
	# Measured from the end of the keyword rather than by searching for the id:
	# a tray called "t" would otherwise match the "t" in "tray" itself.
	var title := line.substr(4).strip_edges().substr(parts[1].length()).strip_edges()
	return result.graph.add_tray(id, "" if title.is_empty() else _read_string(title, line_no, result))

static func _read_tray_setting(line: String, tray: BrainGraph.Tray, line_no: int,
		result: ParseResult) -> void:
	if line.begins_with("at "):
		tray.position = _read_pair(line.substr(3), "at", line_no, result)
	elif line.begins_with("size "):
		tray.size = _read_pair(line.substr(5), "size", line_no, result)
	elif line.begins_with("colour "):
		var raw := line.substr(7).strip_edges()
		if raw.is_valid_int():
			tray.colour = raw.to_int()
		else:
			result.errors.append("line %d: expected 'colour <number>'" % line_no)
	else:
		result.errors.append("line %d: a tray has only 'at', 'size' and 'colour'" % line_no)

static func _read_pair(raw: String, keyword: String, line_no: int, result: ParseResult) -> Vector2:
	var parts := raw.split(" ", false)
	if parts.size() != 2:
		result.errors.append("line %d: expected '%s <x> <y>'" % [line_no, keyword])
		return Vector2.ZERO
	return Vector2(_read_float(parts[0], line_no, result), _read_float(parts[1], line_no, result))

static func _read_wire(line: String, line_no: int, result: ParseResult) -> void:
	var sides := line.substr(4).split("->")
	if sides.size() != 2:
		result.errors.append("line %d: expected 'wire node.port -> node.port'" % line_no)
		return
	var from := sides[0].strip_edges().split(".")
	var to := sides[1].strip_edges().split(".")
	if from.size() != 2 or to.size() != 2:
		result.errors.append("line %d: each end of a wire needs one dot, as node.port" % line_no)
		return
	result.graph.connect_ports(StringName(from[0]), StringName(from[1]), StringName(to[0]), StringName(to[1]))

static func _read_config(line: String, node: BrainGraph.Instance, line_no: int, result: ParseResult) -> void:
	# "at x y" is editor layout rather than a setting, so it is read separately.
	if line.begins_with("at "):
		var coords := line.substr(3).split(" ", false)
		if coords.size() != 2:
			result.errors.append("line %d: expected 'at <x> <y>'" % line_no)
		else:
			node.position = Vector2(_read_float(coords[0], line_no, result),
				_read_float(coords[1], line_no, result))
		return

	var split_at := line.find("=")
	if split_at == -1:
		result.errors.append("line %d: expected 'setting = value'" % line_no)
		return
	var key := line.substr(0, split_at).strip_edges()
	var value: Variant = _read_value(line.substr(split_at + 1).strip_edges(), line_no, result)
	node.config[StringName(key)] = value

static func _read_value(raw: String, line_no: int, result: ParseResult) -> Variant:
	if raw == "true":
		return true
	if raw == "false":
		return false
	if raw.begins_with("\""):
		return _read_string(raw, line_no, result)
	if raw.begins_with("[") and raw.ends_with("]"):
		var numbers: Array[float] = []
		var body := raw.substr(1, raw.length() - 2).strip_edges()
		if not body.is_empty():
			for item: String in body.split(","):
				numbers.append(_read_float(item.strip_edges(), line_no, result))
		return numbers
	return _read_float(raw, line_no, result)

static func _read_float(raw: String, line_no: int, result: ParseResult) -> float:
	if not raw.is_valid_float():
		result.errors.append("line %d: '%s' is not a number" % [line_no, raw])
		return 0.0
	return raw.to_float()

static func _read_string(raw: String, line_no: int, result: ParseResult) -> String:
	if raw.length() < 2 or not raw.begins_with("\"") or not raw.ends_with("\""):
		result.errors.append("line %d: text must be in quotes" % line_no)
		return ""
	return raw.substr(1, raw.length() - 2).replace("\\\"", "\"").replace("\\\\", "\\")
