class_name Port
extends RefCounted
## One socket on a node — either an input or an output.

enum Kind { FLOAT, BOOL, VECTOR }

## How many numbers a bundle carries. Fixed, so a wire's width is never in doubt
## and no node has to grow or shrink its sockets. Eight because that is the ray
## ring, which is the reason bundles exist at all (spec 2.8).
const VECTOR_WIDTH := 8

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

## A bundle coming in. Defaults to empty, which the receiver reads as all zeros —
## the same promise as any other unwired input, just wider.
static func make_vector_input(p_id: StringName, p_name: String) -> Port:
	return make_input(p_id, p_name, [] as Array[float], Kind.VECTOR)

static func make_vector_output(p_id: StringName, p_name: String,
		p_min: float = -INF, p_max: float = INF) -> Port:
	return make_output(p_id, p_name, p_min, p_max, Kind.VECTOR)

## Makes an output port. min/max are the range the evaluator clamps results into.
static func make_output(p_id: StringName, p_name: String, p_min: float = -INF, p_max: float = INF, p_kind: Kind = Kind.FLOAT) -> Port:
	var p := Port.new()
	p.id = p_id
	p.display_name = p_name
	p.min_value = p_min
	p.max_value = p_max
	p.kind = p_kind
	return p
