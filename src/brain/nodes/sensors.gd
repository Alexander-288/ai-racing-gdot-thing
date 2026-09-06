class_name SensorNodes
## The brain's senses. All of these are sources: they have no inputs, and their
## numbers are ready before any maths runs on a tick.

## Rays. One node can carry one reading or eight — the editor grows it a segment
## at a time, and each segment picks its own ray.
##
## A ray is named by which set it belongs to and which one of that set: the ring
## of eight that looks all the way round, or the cone of six that looks forward.
## That beats a single flat number, because "cone 2" means something to a person
## reading a brain file and "ray 10" does not.
##
## Separate boolean sockets rather than a magic number for the hit type, so the
## telemetry overlay stays readable and the editor stays memorable (spec 2.5).
static func ray() -> NodeType:
	var t := NodeType.new()
	t.id = &"ray"
	t.display_name = "Ray"
	t.category = "Sensors"
	t.role = NodeType.Role.SENSOR

	# What the + and - on the node change.
	t.grow_key = &"segments"
	t.grow_min = 1
	t.grow_max = 8

	# Only the first segment's settings are defaults; the rest are written by the
	# editor as segments are added, and read with a fallback if they are missing.
	t.config_defaults = { &"segments": 1.0, &"arc": "ring", &"index": 0.0 }

	t.shape_for = func(cfg: Dictionary) -> Dictionary:
		var outputs: Array[Port] = []
		var fields: Array[ConfigField] = []
		for i in _segment_count(cfg):
			var tail := _segment_suffix(i)
			var shown := _segment_label(i)
			outputs.append(Port.make_output(StringName("distance" + tail), "Distance" + shown, 0.0, 1.0))
			outputs.append(Port.make_output(StringName("hit_track" + tail), "Track" + shown, 0.0, 1.0, Port.Kind.BOOL))
			outputs.append(Port.make_output(StringName("hit_car" + tail), "Car" + shown, 0.0, 1.0, Port.Kind.BOOL))
			outputs.append(Port.make_output(StringName("hit_object" + tail), "Object" + shown, 0.0, 1.0, Port.Kind.BOOL))

			# The index only goes as far as the chosen set has rays, so a cone
			# cannot be asked for a seventh ray it does not have.
			var arc := _segment_arc(cfg, i)
			# Each segment owns four socket rows, so its two settings sit against
			# the first two of them. Without this the settings run down the left
			# in one block and a later segment's arc ends up beside an earlier
			# segment's sockets.
			var first_row := i * 4
			fields.append(ConfigField.choice(StringName("arc" + tail), "arc" + shown,
				["ring", "cone"]).beside(first_row))
			fields.append(ConfigField.number(StringName("index" + tail), "ray" + shown,
				0.0, float(SensorSnapshot.rays_in(arc) - 1), 1.0).beside(first_row + 1))
		return { &"inputs": [] as Array[Port], &"outputs": outputs, &"fields": fields }

	t.sense = func(snapshot: SensorSnapshot, cfg: Dictionary) -> Dictionary:
		var out: Dictionary = {}
		for i in _segment_count(cfg):
			var tail := _segment_suffix(i)
			var index := int(cfg.get(StringName("index" + tail), 0))
			var reading := snapshot.ray_at(SensorSnapshot.flat_ray(_segment_arc(cfg, i), index))
			out[StringName("distance" + tail)] = reading[&"distance"]
			out[StringName("hit_track" + tail)] = 1.0 if reading[&"hit_track"] else 0.0
			out[StringName("hit_car" + tail)] = 1.0 if reading[&"hit_car"] else 0.0
			out[StringName("hit_object" + tail)] = 1.0 if reading[&"hit_object"] else 0.0
		return out

	return t

## Segment 0 keeps the plain names, so a one-ray node reads exactly as it always
## did and brain files written before the node could grow still load.
static func _segment_suffix(i: int) -> String:
	return "" if i == 0 else "_%d" % i

static func _segment_label(i: int) -> String:
	return "" if i == 0 else " %d" % (i + 1)

static func _segment_count(cfg: Dictionary) -> int:
	return clampi(int(cfg.get(&"segments", 1)), 1, 8)

static func _segment_arc(cfg: Dictionary, i: int) -> StringName:
	var named := StringName(str(cfg.get(StringName("arc" + _segment_suffix(i)), "ring")))
	return named if SensorSnapshot.RAY_SETS.has(named) else &"ring"

## The whole eight-ray ring as two bundles instead of eight separate Ray nodes
## and the wires to go with them (spec 2.8). Same numbers, one wire.
##
## This is the node that makes bundles worth having: it is also exactly the shape
## a Dense Layer wants as its input.
static func ray_ring() -> NodeType:
	var t := NodeType.new()
	t.id = &"ray_ring"
	t.display_name = "Ray Ring"
	t.category = "Sensors"
	t.role = NodeType.Role.SENSOR

	t.outputs = [
		Port.make_vector_output(&"distances", "Distances", 0.0, 1.0),
		Port.make_vector_output(&"hits", "Hit Track", 0.0, 1.0),
	]

	t.sense = func(snapshot: SensorSnapshot, _cfg: Dictionary) -> Dictionary:
		var distances: Array[float] = []
		var hits: Array[float] = []
		for i in SensorSnapshot.RING_RAYS:
			var r := snapshot.ray_at(i)
			distances.append(r[&"distance"])
			hits.append(1.0 if r[&"hit_track"] else 0.0)
		return { &"distances": distances, &"hits": hits }

	return t

## How the car is currently moving. One box, because these are always wanted together.
static func self_state() -> NodeType:
	var t := NodeType.new()
	t.id = &"self_state"
	t.display_name = "Self State"
	t.category = "Sensors"
	t.role = NodeType.Role.SENSOR

	t.outputs = [
		Port.make_output(&"speed", "Speed"),
		Port.make_output(&"forward_speed", "Forward Speed"),
		Port.make_output(&"lateral_speed", "Lateral Speed"),  # sideways: the feel of a slide
		Port.make_output(&"angular_velocity", "Turn Rate"),
		Port.make_output(&"on_track", "On Track", 0.0, 1.0, Port.Kind.BOOL),
		Port.make_output(&"damage", "Damage", 0.0, 1.0),
		Port.make_output(&"drs_available", "DRS Ready", 0.0, 1.0, Port.Kind.BOOL),
		Port.make_output(&"position", "Position"),
	]

	t.sense = func(snapshot: SensorSnapshot, _cfg: Dictionary) -> Dictionary:
		return {
			&"speed": snapshot.speed,
			&"forward_speed": snapshot.forward_speed,
			&"lateral_speed": snapshot.lateral_speed,
			&"angular_velocity": snapshot.angular_velocity,
			&"on_track": 1.0 if snapshot.on_track else 0.0,
			&"damage": snapshot.damage,
			&"drs_available": 1.0 if snapshot.drs_available else 0.0,
			&"position": float(snapshot.position_in_field),
		}

	return t

## Where the next bit of route is, relative to the nose of the car.
## Angle is usually what a brain steers on; the raw x/y are there for the rest.
static func checkpoint() -> NodeType:
	var t := NodeType.new()
	t.id = &"checkpoint"
	t.display_name = "Checkpoint"
	t.category = "Sensors"
	t.role = NodeType.Role.SENSOR

	t.config_defaults = { &"index": 0.0 }  # 0 is the next one, 1 the one after
	t.outputs = [
		Port.make_output(&"angle", "Angle", -PI, PI),  # negative left, positive right
		Port.make_output(&"distance", "Distance"),
		Port.make_output(&"right", "Right"),
		Port.make_output(&"forward", "Forward"),
	]

	t.sense = func(snapshot: SensorSnapshot, cfg: Dictionary) -> Dictionary:
		var v := snapshot.checkpoint_at(int(cfg[&"index"]))
		return {
			&"angle": atan2(v.x, v.y),  # x over y: measured from straight ahead
			&"distance": v.length(),
			&"right": v.x,
			&"forward": v.y,
		}

	return t

## One radar slot: a dropdown says which rival it watches, and it reports where
## that car is relative to us (spec 2.5). Four of these is the whole budget.
##
## Everything here is relative. A brain can learn "someone is close on my left",
## never "someone is at these coordinates".
static func radar() -> NodeType:
	var t := NodeType.new()
	t.id = &"radar"
	t.display_name = "Radar"
	t.category = "Sensors"
	t.role = NodeType.Role.SENSOR
	t.budget_class = &"radar"

	# Which rival to watch. Stored as text so a brain file says "ahead" rather
	# than a magic number nobody can read.
	t.config_defaults = { &"target": "closest" }
	# A dropdown of the rules, so a brain file names one rather than numbering it.
	var modes: Array[String] = []
	for mode: StringName in SensorSnapshot.RADAR_MODES:
		modes.append(String(mode))
	t.config_fields = [ConfigField.choice(&"target", "watch", modes)]
	t.outputs = [
		Port.make_output(&"found", "Found", 0.0, 1.0, Port.Kind.BOOL),
		Port.make_output(&"right", "Right"),
		Port.make_output(&"forward", "Forward"),
		Port.make_output(&"distance", "Distance"),
		Port.make_output(&"closing", "Closing"),          # how fast the gap shrinks
		Port.make_output(&"relative_heading", "Heading", -PI, PI),
	]

	t.sense = func(snapshot: SensorSnapshot, cfg: Dictionary) -> Dictionary:
		var contact := snapshot.radar_at(StringName(str(cfg[&"target"])))
		return {
			&"found": 1.0 if contact.found else 0.0,
			&"right": contact.offset.x,
			&"forward": contact.offset.y,
			&"distance": contact.distance(),
			# Negative closing means the gap is opening up.
			&"closing": -contact.relative_velocity.y,
			&"relative_heading": contact.relative_heading,
		}

	return t
