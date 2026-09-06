class_name ConfigField
extends RefCounted
## One setting on a node, and how the editor should let you change it.
##
## The registry has always carried what a node computes; this is the other half
## the spec asks of it (spec 3.1) — the config widgets. Without it the editor can
## only ever draw a number box, which is wrong for a setting whose value is one
## of a fixed handful of names.

enum Kind {
	NUMBER,  # a spinner
	CHOICE,  # a dropdown of named options
}

var key: StringName = &""
var label: String = ""
var kind: Kind = Kind.NUMBER

## Which row of sockets this setting should line up with. -1 lets the editor put
## it wherever it lands, which is right for a node with one or two settings. A
## node that grows needs to say, or a later segment's settings drift away from
## the sockets they control.
var row: int = -1

# NUMBER
var minimum: float = -INF
var maximum: float = INF
var step: float = 0.01

# CHOICE: the values are what gets written to the brain file, so they are words
# rather than numbers — a file should say "ring", not 0.
var choices: Array[String] = []

## Pins this setting to a socket row. Reads as part of the declaration:
##   ConfigField.choice(...).beside(i * 4)
func beside(which_row: int) -> ConfigField:
	row = which_row
	return self

static func number(p_key: StringName, p_label: String,
		p_min: float = -INF, p_max: float = INF, p_step: float = 0.01) -> ConfigField:
	var f := ConfigField.new()
	f.key = p_key
	f.label = p_label
	f.kind = Kind.NUMBER
	f.minimum = p_min
	f.maximum = p_max
	f.step = p_step
	return f

static func choice(p_key: StringName, p_label: String, p_choices: Array[String]) -> ConfigField:
	var f := ConfigField.new()
	f.key = p_key
	f.label = p_label
	f.kind = Kind.CHOICE
	f.choices = p_choices
	return f
