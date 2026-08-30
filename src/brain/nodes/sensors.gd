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
	]

	t.sense = func(snapshot: SensorSnapshot, _cfg: Dictionary) -> Dictionary:
		return {
			&"speed": snapshot.speed,
			&"forward_speed": snapshot.forward_speed,
			&"lateral_speed": snapshot.lateral_speed,
			&"angular_velocity": snapshot.angular_velocity,
			&"on_track": 1.0 if snapshot.on_track else 0.0,
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
