class_name DebugView
extends Control
## A flat top-down wireframe of a brain driving. Not the graphical suite — that
## is Phase 6 and stays there. This is an instrument: it exists so you can watch
## a brain and see why it did something, which a lap time cannot tell you.
##
## Deliberately throwaway. When the cel-shaded renderer arrives, this is deleted.

signal closed

const RAY_RANGE := SensorBuilder.RAY_RANGE
const MARGIN := 60.0

const BACKDROP := Color(0.09, 0.10, 0.12)
const TRACK_SURFACE := Color(0.15, 0.16, 0.19)
const TRACK_EDGE := Color(0.85, 0.85, 0.9)
const CENTRE_LINE := Color(0.35, 0.35, 0.42)
const CHECKPOINT := Color(0.45, 0.45, 0.55)
const NEXT_CHECKPOINT := Color(1.0, 0.85, 0.3)
const CAR_BODY := Color(0.4, 0.85, 1.0)
const CAR_HURT := Color(1.0, 0.45, 0.4)
## The cars you are not watching: present, readable, and clearly not the subject.
const CAR_OTHER := Color(0.45, 0.48, 0.58)
const CAR_OTHER_HURT := Color(0.62, 0.38, 0.38)
const RAY_CLEAR := Color(0.35, 0.7, 0.45, 0.5)
const RAY_HIT := Color(1.0, 0.45, 0.4, 0.85)

var session: RaceSession
var running := true
var steps_per_frame := 1

var _snapshot: SensorSnapshot
var _controls := CarControls.new()
var _readout: RichTextLabel
var _scale := 1.0
var _origin := Vector2.ZERO

## A few seconds of where each car has been, oldest first. Purely something to
## look at — the sim never reads it — but a line behind a car says more about
## what it just did than a triangle standing still does.
const TRAIL_LENGTH := 90
var _trails: Array[PackedVector2Array] = []

static func open(graph: BrainGraph, registry: NodeRegistry, track: Track) -> DebugView:
	return open_field([graph], registry, track)

static func open_field(graphs: Array, registry: NodeRegistry, track: Track) -> DebugView:
	var view := DebugView.new()
	view.set_anchors_preset(Control.PRESET_FULL_RECT)
	view.session = RaceSession.create_field(graphs, registry, track)
	return view

func _ready() -> void:
	# Fades up over the editor rather than replacing it in one frame.
	modulate.a = 0.0
	var fade := create_tween()
	fade.tween_property(self, "modulate:a", 1.0, 0.18)
	fade.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

	for i in session.entries.size():
		_trails.append(PackedVector2Array())
	_build_controls()
	_fit_track()
	_snapshot = session.snapshot

## The sim steps in _physics_process, never _process, so it advances in fixed
## ticks regardless of frame rate (spec 2.4). Watching faster runs more ticks
## per frame; it never makes a tick bigger.
func _physics_process(_delta: float) -> void:
	if not running:
		return
	# The session owns the tick order. With a field of cars that order decides
	# who senses what, so the view must not step anything itself.
	for i in steps_per_frame:
		session.tick()
		_remember_positions()
	_snapshot = session.snapshot
	_controls = session.controls
	_update_readout()
	queue_redraw()

## Keeps the tail a fixed length, so a car standing still leaves a dot rather
## than slowly staining the track.
func _remember_positions() -> void:
	for i in session.entries.size():
		var trail := _trails[i]
		trail.append(session.entries[i].car.position)
		if trail.size() > TRAIL_LENGTH:
			trail.remove_at(0)
		_trails[i] = trail

# ---------------------------------------------------------------- drawing

func _draw() -> void:
	var track := session.track
	# Opaque: this sits on top of the editor, which must not show through.
	draw_rect(Rect2(Vector2.ZERO, size), BACKDROP)
	draw_polyline(_to_screen_all(_offset_ring(0.0)), CENTRE_LINE, 1.0)
	draw_polyline(_to_screen_all(_offset_ring(track.half_width)), TRACK_EDGE, 2.0)
	draw_polyline(_to_screen_all(_offset_ring(-track.half_width)), TRACK_EDGE, 2.0)

	for i in track.checkpoint_count():
		var is_next := i == session.car.next_checkpoint
		draw_circle(_to_screen(track.checkpoint_at(i)), 4.0 if is_next else 2.5,
			NEXT_CHECKPOINT if is_next else CHECKPOINT)

	_draw_trails()
	_draw_rays()
	for i in session.entries.size():
		if i != session.focus:
			_draw_car(session.entries[i].car, false)
	_draw_car(session.car, true)  # the watched car goes on top

## Each tail fades out towards its oldest end, which is what makes it read as
## motion rather than as a line someone drew on the track.
func _draw_trails() -> void:
	for i in _trails.size():
		var trail := _trails[i]
		if trail.size() < 2:
			continue
		var watched := i == session.focus
		var base := CAR_BODY if watched else CAR_OTHER
		var points := PackedVector2Array()
		var colours := PackedColorArray()
		for step in trail.size():
			points.append(_to_screen(trail[step]))
			var age := float(step) / float(trail.size() - 1)
			colours.append(Color(base.r, base.g, base.b, age * (0.75 if watched else 0.35)))
		draw_polyline_colors(points, colours, 1.5 if watched else 1.0, true)

## Rays are drawn from the same angle list the sensors used, so what you see is
## exactly what the brain was told.
func _draw_rays() -> void:
	var car := session.car
	var angles := SensorBuilder.ray_angles()
	for i in angles.size():
		var direction := car.forward().rotated(-angles[i])
		var length: float = _snapshot.ray_distance[i] * RAY_RANGE
		var hit: bool = _snapshot.ray_hit_track[i]
		draw_line(_to_screen(car.position), _to_screen(car.position + direction * length),
			RAY_HIT if hit else RAY_CLEAR, 1.0)

func _draw_car(car: Car, watched: bool) -> void:
	var nose := car.position + car.forward() * 3.0
	var left := car.position - car.forward() * 1.6 - car.right() * 1.4
	var right := car.position - car.forward() * 1.6 + car.right() * 1.4
	# Reddens as it takes damage, so you can see a car limping without reading numbers.
	var tint := (CAR_BODY if watched else CAR_OTHER).lerp(
		CAR_HURT if watched else CAR_OTHER_HURT, car.damage)
	var shape := PackedVector2Array([_to_screen(nose), _to_screen(left), _to_screen(right)])
	draw_colored_polygon(shape, tint)
	if watched and session.entries.size() > 1:
		# A ring, so the car you are watching is findable in a moving pack.
		draw_arc(_to_screen(car.position), 11.0, 0.0, TAU, 24, tint, 1.5, true)

## The track has width, so its edges are the centre line pushed sideways. Each
## point uses the average direction of the two segments meeting there, which
## keeps the corners joined up instead of leaving gaps.
func _offset_ring(distance: float) -> PackedVector2Array:
	var points := PackedVector2Array()
	var line := session.track.centre_line
	var count := line.size()
	for i in count:
		var before: Vector2 = line[i] - line[(i - 1 + count) % count]
		var after: Vector2 = line[(i + 1) % count] - line[i]
		var direction := (before.normalized() + after.normalized()).normalized()
		points.append(line[i] + Vector2(direction.y, -direction.x) * distance)
	points.append(points[0])  # close the loop
	return points

## Fits the whole track in the window once, so nothing moves but the car.
func _fit_track() -> void:
	var line := session.track.centre_line
	var low := line[0]
	var high := line[0]
	for p: Vector2 in line:
		low = Vector2(minf(low.x, p.x), minf(low.y, p.y))
		high = Vector2(maxf(high.x, p.x), maxf(high.y, p.y))
	low -= Vector2.ONE * session.track.half_width
	high += Vector2.ONE * session.track.half_width

	var span := high - low
	var room := size - Vector2.ONE * MARGIN * 2.0
	_scale = minf(room.x / span.x, room.y / span.y)
	_origin = (low + high) * 0.5

func _to_screen(world: Vector2) -> Vector2:
	# Y is flipped: the sim has y pointing up the track, the screen has it down.
	var centred := (world - _origin) * _scale
	return size * 0.5 + Vector2(centred.x, -centred.y)

func _to_screen_all(points: PackedVector2Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p: Vector2 in points:
		out.append(_to_screen(p))
	return out

# ---------------------------------------------------------------- the panel

func _build_controls() -> void:
	var bar := HBoxContainer.new()
	bar.position = Vector2(12, 12)
	add_child(bar)
	bar.add_child(_button("Pause", func() -> void: running = not running))
	bar.add_child(_button("Step", func() -> void:
		running = false
		var was := steps_per_frame
		steps_per_frame = 1
		running = true
		_physics_process(0.0)
		running = false
		steps_per_frame = was))
	bar.add_child(_button("Reset", func() -> void:
		session.restart()
		for i in _trails.size():
			_trails[i] = PackedVector2Array()))
	bar.add_child(_button("1x", func() -> void: steps_per_frame = 1))
	bar.add_child(_button("5x", func() -> void: steps_per_frame = 5))
	bar.add_child(_button("20x", func() -> void: steps_per_frame = 20))
	bar.add_child(_button("Watch next", func() -> void:
		session.focus = (session.focus + 1) % session.entries.size()
		# A short flash, so it is obvious the readout is talking about someone else.
		_readout.modulate = Color(1.4, 1.4, 1.4)
		create_tween().tween_property(_readout, "modulate", Color.WHITE, 0.25)))
	bar.add_child(_button("Back to editor", func() -> void: closed.emit()))

	_readout = RichTextLabel.new()
	_readout.bbcode_enabled = true
	_readout.position = Vector2(12, 52)
	_readout.scroll_active = false  # it is a readout, not something to scroll
	# Tall enough for the running order as well, or the field below the leader is
	# simply clipped away — which is worse than not listing it at all.
	var height := 260.0 + 14.0 * float(session.entries.size() if session.entries.size() > 1 else 0)
	_readout.custom_minimum_size = Vector2(280, height)
	_readout.size = Vector2(280, height)
	add_child(_readout)

func _button(text: String, action: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.pressed.connect(action)
	return b

## Shows what the brain decided, not just what the car did — that is the whole
## point of watching rather than reading a lap time.
func _update_readout() -> void:
	_readout.text = "\n".join([
		"[b]car %d of %d[/b]    [b]tick[/b] %d    [b]%.1fs[/b]" % [
			session.focus + 1, session.entries.size(), session.ticks, session.ticks * Car.TICK],
		"[b]lap[/b] %d    [b]P%d[/b]" % [session.car.lap, session.car.position_in_field],
		"[b]speed[/b] %.1f m/s" % session.car.speed,
		"",
		"steering %s %+.2f" % [_bar(absf(_controls.steering)), _controls.steering],
		"throttle %s  %.2f" % [_bar(_controls.throttle), _controls.throttle],
		"brake    %s  %.2f" % [_bar(_controls.brake), _controls.brake],
		"drs      %s" % ("on" if _controls.drs else "off"),
		"",
		"wall: %s" % ("clear" if _snapshot.on_track else "[color=#ff8f8f]SCRAPING[/color]"),
		"damage %s  %.0f%%" % [_bar(session.car.damage), session.car.damage * 100.0],
		"contact: %d ticks" % session.wall_hits,
		"",
		_standings(),
	])

## A short table of the field, leader first, with the watched car marked. Only
## worth the room when there is a field to look at.
func _standings() -> String:
	if session.entries.size() < 2:
		return ""
	var lines: PackedStringArray = ["[b]order[/b]"]
	for e: RaceSession.Entry in session.standings():
		var watched := e == session.entries[session.focus]
		lines.append("%s P%-2d  lap %d  %3.0f%% dmg" % [
			">" if watched else " ", e.car.position_in_field, e.car.lap, e.car.damage * 100.0])
	return "
".join(lines)

static func _bar(value: float) -> String:
	var filled := int(roundf(clampf(value, 0.0, 1.0) * 10.0))
	return "[%s%s]" % ["=".repeat(filled), " ".repeat(10 - filled)]
