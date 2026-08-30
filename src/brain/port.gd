class_name Port
extends RefCounted
## One socket on a node — either an input or an output.

enum Kind { FLOAT, BOOL, VECTOR }  # VECTOR is unused until Phase 2 (Dense Layer)

var id: StringName = &""           # stable key; goes in the save file, never rename
var display_name: String = ""      # shown in the editor, safe to rename
var kind: Kind = Kind.FLOAT
var default_value: Variant = null  # inputs only: what an unwired input reads
var min_value: float = -INF        # outputs only: evaluator clamps to this range
var max_value: float = INF

## Makes an input port. Shortcut so declaring a node type stays short.
## The default is required, so an unwired input can never be null at runtime.
static func make_input(p_id: StringName, p_name: String, p_default: Variant, p_kind: Kind = Kind.FLOAT) -> Port:
	var p := Port.new()
	p.id = p_id
	p.display_name = p_name
	p.default_value = p_default
	p.kind = p_kind
	return p

## Makes an output port. min/max are the range the evaluator clamps results into.
static func make_output(p_id: StringName, p_name: String, p_min: float = -INF, p_max: float = INF, p_kind: Kind = Kind.FLOAT) -> Port:
	var p := Port.new()
	p.id = p_id
	p.display_name = p_name
	p.min_value = p_min
	p.max_value = p_max
	p.kind = p_kind
	return p
