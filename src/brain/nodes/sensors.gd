class_name SensorNodes
## The brain's senses. All of these are sources: they have no inputs, and their
## numbers are ready before any maths runs on a tick.

## One ray. Separate boolean sockets rather than a magic number for the hit type,
## so the telemetry overlay stays readable and the editor stays memorable (spec 2.5).
static func ray() -> NodeType:
	var t := NodeType.new()
	t.id = &"ray"
	t.display_name = "Ray"
	t.category = "Sensors"
	t.role = NodeType.Role.SENSOR

	t.config_defaults = { &"index": 0.0 }  # which of the car's rays to read
	t.outputs = [
		Port.make_output(&"distance", "Distance", 0.0, 1.0),
		Port.make_output(&"hit_track", "Hit Track", 0.0, 1.0, Port.Kind.BOOL),
		Port.make_output(&"hit_car", "Hit Car", 0.0, 1.0, Port.Kind.BOOL),
		Port.make_output(&"hit_object", "Hit Object", 0.0, 1.0, Port.Kind.BOOL),
	]

	t.sense = func(snapshot: SensorSnapshot, cfg: Dictionary) -> Dictionary:
		var r := snapshot.ray_at(int(cfg[&"index"]))
		return {
			&"distance": r[&"distance"],
			&"hit_track": 1.0 if r[&"hit_track"] else 0.0,
			&"hit_car": 1.0 if r[&"hit_car"] else 0.0,
			&"hit_object": 1.0 if r[&"hit_object"] else 0.0,
		}

	return t

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
