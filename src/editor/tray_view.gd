class_name TrayView
extends GraphElement
## A tray: a big resizable panel that sits *behind* the nodes and groups them by
## eye. It has no sockets, no settings and no part in evaluation — dropping every
## tray from a brain file would change nothing about how the car drives.
##
## GraphElement rather than GraphNode, because GraphNode is the one that draws a
## title bar and slots. A tray wants neither: just a body, a name in its top-left
## corner, and a corner you can drag.
##
## A tray is deliberately NOT draggable in GraphEdit's sense. Dragging a panel
## this big by its face would mean every stray drag across the canvas shoves your
## layout around, so moving one is the grip's job and nothing else's.

signal title_changed(tray_id: StringName, title: String)
signal tray_resized(tray_id: StringName, new_size: Vector2)
signal colour_changed(tray_id: StringName, colour: int)
signal drag_started(tray_id: StringName)
signal drag_ended(tray_id: StringName)

## Small enough to tuck a couple of nodes into, large enough that a stray drag
## cannot shrink one into a speck you then have to hunt for.
const MIN_SIZE := Vector2(160, 120)
const PAD := 8.0
const TITLE_HEIGHT := 22.0
const GRIP_SIZE := 18.0
const SWATCH_SIZE := 18.0

## How close to the bottom-right corner counts as "on the resizer" for the sake
## of the mouse cursor. GraphElement's own hit test uses its resizer icon size.
const CORNER_REACH := 18.0

var tray_id: StringName
var colour: int = 0

var _title_field: LineEdit
var _grip: TextureRect
var _swatch: TextureRect
var _menu: PopupMenu

var _drag_from := Vector2.ZERO      # mouse position when the grip was grabbed
var _drag_origin := Vector2.ZERO    # where the tray was at that moment
var _dragging := false

static func build(tray: BrainGraph.Tray) -> TrayView:
	var view := TrayView.new()
	view.tray_id = tray.id
	view.name = String(tray.id)
	view.colour = tray.colour
	view.position_offset = tray.position
	view.size = tray.size.max(MIN_SIZE)
	view.resizable = true
	view.selectable = true
	view.draggable = false  # the grip moves it; the body does nothing

	view._build_grip()
	view._build_title(tray.title)
	view._build_swatch()

	view.resize_request.connect(view._on_resize_request)
	# The panel is drawn by hand, so it has to be told when the look changes.
	view.node_selected.connect(view.queue_redraw)
	view.node_deselected.connect(view.queue_redraw)
	return view

## The one part of a tray you can move it by. Its cursor is the grab hand, so
## the difference between "this drags" and "this does nothing" is visible before
## you press anything.
func _build_grip() -> void:
	_grip = TextureRect.new()
	_grip.texture = EditorTheme.grip(EditorTheme.TRAY_TITLE)
	_grip.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	_grip.mouse_default_cursor_shape = Control.CURSOR_DRAG
	_grip.gui_input.connect(_on_grip_input)
	add_child(_grip)

## The title is an editable field rather than a label, so naming a tray is one
## click. Flat, so until you click it, it reads as plain text on the panel.
func _build_title(text: String) -> void:
	_title_field = LineEdit.new()
	_title_field.text = text
	_title_field.placeholder_text = "Tray"
	_title_field.flat = true
	_title_field.add_theme_color_override("font_color", EditorTheme.TRAY_TITLE)
	_title_field.add_theme_color_override("font_placeholder_color", EditorTheme.TEXT_DIM)
	_title_field.add_theme_font_size_override("font_size", 14)
	_title_field.text_changed.connect(func(t: String) -> void: title_changed.emit(tray_id, t))
	add_child(_title_field)

## Eight colours, chosen for you. A free colour picker on a background panel is
## a way to make a canvas look like a paint sample; a short list keeps a brain
## full of trays looking like one drawing.
func _build_swatch() -> void:
	_menu = PopupMenu.new()
	for i in EditorTheme.TRAY_COLOURS.size():
		_menu.add_icon_item(EditorTheme.dot(EditorTheme.tray_colour(i), 12),
			EditorTheme.TRAY_COLOUR_NAMES[i], i)
	_menu.id_pressed.connect(_on_colour_picked)
	add_child(_menu)

	_swatch = TextureRect.new()
	_swatch.texture = EditorTheme.dot(EditorTheme.tray_colour(colour), 12)
	_swatch.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	_swatch.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_swatch.tooltip_text = "Colour"
	_swatch.gui_input.connect(_on_swatch_input)
	add_child(_swatch)

## GraphElement is a Container, so where its children go is this method's job.
## Grip, title, swatch — one row along the top, and nothing else laid out at all.
func _notification(what: int) -> void:
	if what != NOTIFICATION_SORT_CHILDREN or _title_field == null:
		return
	var top := PAD * 0.75
	fit_child_in_rect(_grip, Rect2(PAD, top + 2.0, GRIP_SIZE, GRIP_SIZE))
	fit_child_in_rect(_swatch,
		Rect2(size.x - PAD - SWATCH_SIZE, top + 2.0, SWATCH_SIZE, SWATCH_SIZE))
	var title_left := PAD + GRIP_SIZE + 6.0
	var title_width := maxf(size.x - title_left - SWATCH_SIZE - PAD * 2.0, 0.0)
	fit_child_in_rect(_title_field, Rect2(title_left, top, title_width, TITLE_HEIGHT))

## Without this a Container reports no minimum, and the resizer would happily
## fold the tray down to nothing.
func _get_minimum_size() -> Vector2:
	return MIN_SIZE

# ---------------------------------------------------------------- moving it

func _on_grip_input(event: InputEvent) -> void:
	var button := event as InputEventMouseButton
	if button != null and button.button_index == MOUSE_BUTTON_LEFT:
		if button.pressed:
			_dragging = true
			_drag_from = _mouse()
			_drag_origin = position_offset
			selected = true
			drag_started.emit(tray_id)
		elif _dragging:
			_dragging = false
			drag_ended.emit(tray_id)
		accept_event()
	elif _dragging and event is InputEventMouseMotion:
		drag_to(_mouse())
		accept_event()

## Split out from the input handler so the arithmetic can be tested without
## pretending to be a mouse. Zoom divides because position_offset is in canvas
## units while the mouse moves in screen pixels.
func drag_to(mouse: Vector2) -> void:
	position_offset = _drag_origin + (mouse - _drag_from) / _canvas_zoom()

func begin_drag_at(mouse: Vector2) -> void:
	_dragging = true
	_drag_from = mouse
	_drag_origin = position_offset
	drag_started.emit(tray_id)

func _mouse() -> Vector2:
	return get_viewport().get_mouse_position()

func _canvas_zoom() -> float:
	var canvas := get_parent() as GraphEdit
	return canvas.zoom if canvas != null else 1.0

# ---------------------------------------------------------------- the rest

## The cursor is the only hint that a corner does something, so it is worth
## keeping honest: diagonal resize over the resizer, plain arrow everywhere else.
func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var corner := size - (event as InputEventMouseMotion).position
		var on_corner := corner.x < CORNER_REACH and corner.y < CORNER_REACH
		mouse_default_cursor_shape = Control.CURSOR_FDIAGSIZE if on_corner else Control.CURSOR_ARROW

func _on_swatch_input(event: InputEvent) -> void:
	var button := event as InputEventMouseButton
	if button != null and button.pressed and button.button_index == MOUSE_BUTTON_LEFT:
		_menu.popup(Rect2i(Vector2i(_swatch.global_position) + Vector2i(0, int(SWATCH_SIZE)),
			Vector2i.ZERO))
		accept_event()

func _on_colour_picked(id: int) -> void:
	colour = id
	_swatch.texture = EditorTheme.dot(EditorTheme.tray_colour(colour), 12)
	queue_redraw()
	colour_changed.emit(tray_id, colour)

func _on_resize_request(new_size: Vector2) -> void:
	size = new_size.max(MIN_SIZE)
	queue_redraw()
	tray_resized.emit(tray_id, size)

func _draw() -> void:
	draw_style_box(EditorTheme.tray_box(colour, selected), Rect2(Vector2.ZERO, size))

## The rectangle this tray covers, in canvas coordinates — which is what decides
## whether a node counts as sitting on it.
func canvas_rect() -> Rect2:
	return Rect2(position_offset, size)
