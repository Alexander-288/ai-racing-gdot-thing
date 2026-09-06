class_name EditorTheme
extends RefCounted
## Every colour and every box the brain editor draws, in one file.
##
## Built in code rather than saved as a .tres, for the same reason the rest of
## the editor is: a resource file is invisible in a diff and easy to leave stale.
## Nothing here knows what a node *is* — it only knows how things should look.

# ---------------------------------------------------------------- the palette

const BG          := Color("0f1013")  # the canvas, behind everything
const PANEL       := Color("16171c")  # the sidebar
const PANEL_EDGE  := Color("262931")  # the hairline between panel and canvas
const FIELD       := Color("0d0e12")  # sunken things: text boxes, spinners
const NODE_BODY   := Color("24262c")
const NODE_TITLE  := Color("2b2e35")  # a shade up from the body, not a slab of colour
const NODE_EDGE   := Color("32353e")
const HOVER       := Color("2b2f38")
const TEXT        := Color("c8cdd8")
const TEXT_DIM    := Color("6f7688")
const VALUE       := Color("9ed2a6")  # numbers you can edit read green, as in the reference
const ACCENT      := Color("7aa2ff")  # selection, focus, activity
const TRAY_TITLE  := Color("8892a8")

## Eight tray colours, and no more: a fixed list keeps a canvas full of trays
## looking like one drawing rather than a paint sample book. Index 0 is the
## plain one, so a tray you never touch stays neutral.
const TRAY_COLOURS := [
	Color("7f8798"),  # slate
	Color("5aa9f8"),  # blue
	Color("5fd0b0"),  # teal
	Color("86dc9a"),  # green
	Color("e0c064"),  # amber
	Color("e89060"),  # orange
	Color("e58fb0"),  # pink
	Color("b48ce0"),  # violet
]
const TRAY_COLOUR_NAMES := ["Slate", "Blue", "Teal", "Green", "Amber", "Orange", "Pink", "Violet"]

static func tray_colour(index: int) -> Color:
	return TRAY_COLOURS[clampi(index, 0, TRAY_COLOURS.size() - 1)]
const GOOD        := Color("8fdc8f")
const BAD         := Color("ff9c8f")

## Corner radius used by every rounded box, so nothing drifts out of family.
const RADIUS := 6

## How many texels every hand-drawn icon holds per pixel it is shown at.
##
## GraphEdit zooms by scaling its children, not by redrawing them, so a texture
## with one texel per pixel has nothing left to show when magnified except its
## own texels. The spare resolution here is what it magnifies into instead — four
## covers the whole zoom range (BrainEditor sets zoom_max to 3).
const SUPERSAMPLE := 4

## How wide the soft edge of a stylebox is, in the box's own units.
##
## Same problem, other half: Godot's default of one unit is one pixel at life
## size but a three-pixel gradient at zoom 3, which is what made the node boxes
## read as fuzzy rather than as magnified. Half a unit still looks clean at life
## size and stays a hairline when zoomed.
const EDGE_SOFTNESS := 0.5

## A tint per role. Used as title *text*, and as a whisper of colour behind the
## title bar — a node should be identifiable without shouting.
const ROLE_COLOURS := {
	NodeType.Role.PURE: Color("9fb2d8"),
	NodeType.Role.SENSOR: Color("6fd6a8"),
	NodeType.Role.MEMORY: Color("e0b464"),
	NodeType.Role.OUTPUT: Color("e58fb0"),
}

## Socket colours by port kind, so a wrong connection looks wrong before you try
## it. These are also the colours a cable is drawn in, so a socket and the wire
## leaving it can never drift apart.
##
## The violet is the one that matters: it marks everything a network runs on, and
## it is the only kind drawn as a loom rather than a single core (CableStyle).
const KIND_COLOURS := {
	Port.Kind.FLOAT: Color("6fb4f0"),   # blue — one number
	Port.Kind.BOOL: Color("e8b06a"),    # amber — a yes or a no
	Port.Kind.VECTOR: Color("7b6ae8"),  # violet — eight numbers at once
}

static func role_colour(role: int) -> Color:
	return ROLE_COLOURS.get(role, TEXT)

## Bakes a hand-drawn image into a texture that reports a smaller size than it
## actually holds. Everything laying the editor out sees the small size, so no
## layout changes; the canvas has the extra texels to draw from when you zoom in,
## and the mipmaps stop them shimmering when you zoom out.
static func _baked(img: Image, logical: Vector2i) -> ImageTexture:
	img.generate_mipmaps()
	var tex := ImageTexture.create_from_image(img)
	tex.set_size_override(logical)
	return tex

## Every node in a graph asks for a dot, but there are only as many answers as
## there are role colours — and at SUPERSAMPLE the drawing loop is sixteen times
## the work it used to be. So the answers are kept.
static var _dots: Dictionary = {}

## A small filled circle, drawn rather than imported so the editor still needs no
## art files. The soft edge is one texel wide, which after the downscale to its
## shown size is all the antialiasing a circle this small needs.
static func dot(colour: Color, size: int = 10) -> ImageTexture:
	var key := "%s@%d" % [colour.to_html(true), size]
	if _dots.has(key):
		return _dots[key]

	var pixels := size * SUPERSAMPLE
	var img := Image.create(pixels, pixels, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var r := pixels * 0.5
	for y in pixels:
		for x in pixels:
			var edge := r - Vector2(x + 0.5 - r, y + 0.5 - r).length()
			if edge > 0.0:
				img.set_pixel(x, y, Color(colour, minf(edge, 1.0)))

	var tex := _baked(img, Vector2i(size, size))
	_dots[key] = tex
	return tex

## A socket. Not a dot: a small rounded rectangle, so a port reads as a connector
## you plug into rather than a full stop. Godot tints this icon with the slot's
## colour, so it is drawn white — and the brightness falling off towards the
## bottom survives that tinting as a shade across the connector.
## GraphNode will only take a Texture2D here, so unlike the dot this one cannot
## be swapped for something drawn live — which is exactly what _baked is for.
static func connector(width: int = 14, height: int = 8, radius: float = 3.0) -> ImageTexture:
	var w := width * SUPERSAMPLE
	var h := height * SUPERSAMPLE
	var r := radius * SUPERSAMPLE
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var half := Vector2(w, h) * 0.5
	for y in h:
		for x in w:
			# Distance to a rounded rectangle: measure to the inner box, then
			# subtract the corner radius. Negative is inside.
			var from_middle := (Vector2(x + 0.5, y + 0.5) - half).abs()
			var corner := from_middle - (half - Vector2(r, r))
			var distance := Vector2(maxf(corner.x, 0.0), maxf(corner.y, 0.0)).length() - r
			var alpha := clampf(-distance, 0.0, 1.0)
			if alpha > 0.0:
				var shade := lerpf(1.0, 0.68, y / maxf(h - 1.0, 1.0))
				img.set_pixel(x, y, Color(shade, shade, shade, alpha))
	return _baked(img, Vector2i(width, height))

# ---------------------------------------------------------------- the pieces

## One flat box. Every stylebox below is this function with different arguments,
## which is what keeps the look consistent instead of hand-tuned per widget.
static func box(fill: Color, radius: int = RADIUS, edge: Color = Color(0, 0, 0, 0),
		edge_width: int = 0, margin: int = 0) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = fill
	s.set_corner_radius_all(radius)
	s.anti_aliasing_size = EDGE_SOFTNESS
	if edge_width > 0:
		s.set_border_width_all(edge_width)
		s.border_color = edge
	if margin > 0:
		s.set_content_margin_all(margin)
	return s

## A node is two styleboxes that have to look like one shape: the title bar on
## top and the body below. So the title rounds only its top corners and skips its
## bottom border, the body does the mirror image, and the seam between them
## disappears. Rounding all four corners on either half is what leaves a notch.
static func top_box(fill: Color, edge: Color, edge_width: int = 1) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = fill
	s.anti_aliasing_size = EDGE_SOFTNESS
	s.corner_radius_top_left = RADIUS
	s.corner_radius_top_right = RADIUS
	s.border_color = edge
	s.border_width_top = edge_width
	s.border_width_left = edge_width
	s.border_width_right = edge_width
	s.content_margin_left = 9
	s.content_margin_right = 9
	s.content_margin_top = 5
	s.content_margin_bottom = 5
	# Godot lays the title bar and the body out as two separate rectangles, and at
	# any zoom that does not land on whole pixels a hairline of canvas can show
	# through between them. Growing the title a pixel in each direction — which
	# expand margins do without changing the layout — closes that sliver.
	s.expand_margin_top = 1
	s.expand_margin_bottom = 1
	return s

static func bottom_box(fill: Color, edge: Color, edge_width: int = 1) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = fill
	s.anti_aliasing_size = EDGE_SOFTNESS
	s.corner_radius_bottom_left = RADIUS
	s.corner_radius_bottom_right = RADIUS
	s.border_color = edge
	s.border_width_left = edge_width
	s.border_width_right = edge_width
	s.border_width_bottom = edge_width
	s.set_content_margin_all(7)
	# A soft drop shadow lifts the node off the canvas the way the reference does.
	# It is offset downwards so almost none of it lands on the seam up top.
	s.shadow_color = Color(0, 0, 0, 0.45)
	s.shadow_size = 6
	s.shadow_offset = Vector2(0, 3)
	return s

## A tray sits behind everything, so it is mostly transparent: enough tint to
## read as one area, not enough to change the colour of the nodes standing on it.
static func tray_box(colour_index: int, selected: bool) -> StyleBoxFlat:
	var tint := tray_colour(colour_index)
	return box(Color(tint, 0.08), RADIUS * 2,
		ACCENT if selected else Color(tint, 0.35), 2 if selected else 1)

## The little six-dot grip that a tray is dragged by. Drawn, like everything else
## in this editor, so there is still no art folder to keep in step with the code.
static func grip(colour: Color) -> ImageTexture:
	var img := Image.create(9 * SUPERSAMPLE, 14 * SUPERSAMPLE, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for row in 3:
		for column in 2:
			# The dots are 2x2 at the size this is shown at, so they are drawn as
			# rectangles now rather than as four named pixels.
			img.fill_rect(Rect2i((1 + column * 5) * SUPERSAMPLE, (2 + row * 4) * SUPERSAMPLE,
				2 * SUPERSAMPLE, 2 * SUPERSAMPLE), colour)
	return _baked(img, Vector2i(9, 14))

static func empty(margin: int = 0) -> StyleBoxEmpty:
	var s := StyleBoxEmpty.new()
	s.set_content_margin_all(margin)
	return s

# ---------------------------------------------------------------- the theme

static func build() -> Theme:
	var t := Theme.new()
	t.default_font_size = 12
	_canvas(t)
	_nodes(t)
	_sidebar(t)
	_fields(t)
	_scrollbars(t)
	return t

## The GraphEdit itself: a near-black sheet with a grid you can only just see.
static func _canvas(t: Theme) -> void:
	t.set_stylebox("panel", "GraphEdit", box(BG, 0))
	t.set_color("grid_major", "GraphEdit", Color(1, 1, 1, 0.16))
	t.set_color("grid_minor", "GraphEdit", Color(1, 1, 1, 0.07))
	t.set_color("selection_fill", "GraphEdit", Color(ACCENT, 0.12))
	t.set_color("selection_stroke", "GraphEdit", Color(ACCENT, 0.55))
	t.set_color("activity", "GraphEdit", ACCENT)

	# The minimap is its own little theme type, and left unstyled it is the one
	# pale rectangle in an otherwise dark editor.
	t.set_stylebox("panel", "GraphEditMinimap", box(Color(0, 0, 0, 0.35), 4, PANEL_EDGE, 1))
	t.set_stylebox("node", "GraphEditMinimap", box(NODE_EDGE, 2))
	t.set_stylebox("camera", "GraphEditMinimap", box(Color(0, 0, 0, 0), 2, ACCENT, 1))

## A node box. The two halves are described above; what is set here is the pair
## for resting and the pair for selected, which differ only in their edge.
static func _nodes(t: Theme) -> void:
	t.set_stylebox("panel", "GraphNode", bottom_box(NODE_BODY, NODE_EDGE))
	t.set_stylebox("panel_selected", "GraphNode", bottom_box(NODE_BODY, ACCENT, 2))
	t.set_stylebox("panel_focus", "GraphNode", bottom_box(NODE_BODY, ACCENT, 2))
	t.set_stylebox("slot", "GraphNode", empty(1))
	t.set_constant("separation", "GraphNode", 1)
	t.set_color("resizer_color", "GraphNode", TEXT_DIM)
	# Sockets are connectors, not dots — see EditorTheme.connector.
	t.set_icon("port", "GraphNode", connector())

## The sidebar, and the two button shapes living in it. Type variations mean a
## palette button and a Save button can look different without either of them
## carrying its own styling code.
static func _sidebar(t: Theme) -> void:
	var side := box(PANEL, 0)
	side.border_width_right = 1
	side.border_color = PANEL_EDGE
	side.set_content_margin_all(10)
	t.set_type_variation("Sidebar", "PanelContainer")
	t.set_stylebox("panel", "Sidebar", side)

	t.set_color("font_color", "Label", TEXT)

	# Category headings: small, quiet, and clearly not clickable.
	t.set_type_variation("CategoryLabel", "Label")
	t.set_color("font_color", "CategoryLabel", TEXT_DIM)
	t.set_font_size("font_size", "CategoryLabel", 10)

	# A node title: the role colour, as text rather than as a filled bar.
	t.set_type_variation("NodeTitle", "Label")
	t.set_font_size("font_size", "NodeTitle", 13)

	# A palette entry reads as a list row, so it lights up rather than sits raised.
	t.set_type_variation("PaletteButton", "Button")
	t.set_stylebox("normal", "PaletteButton", empty(5))
	t.set_stylebox("hover", "PaletteButton", box(HOVER, 4, Color(0, 0, 0, 0), 0, 5))
	t.set_stylebox("pressed", "PaletteButton", box(Color(ACCENT, 0.18), 4, Color(0, 0, 0, 0), 0, 5))
	t.set_stylebox("focus", "PaletteButton", empty(5))
	t.set_color("font_color", "PaletteButton", TEXT)
	t.set_color("font_hover_color", "PaletteButton", Color.WHITE)

	# Actions (Test Drive, Save, Load) are real buttons: raised, with an edge.
	t.set_stylebox("normal", "Button", box(NODE_BODY, 4, NODE_EDGE, 1, 7))
	t.set_stylebox("hover", "Button", box(HOVER, 4, ACCENT.darkened(0.4), 1, 7))
	t.set_stylebox("pressed", "Button", box(Color(ACCENT, 0.22), 4, ACCENT, 1, 7))
	t.set_stylebox("focus", "Button", empty(7))
	t.set_color("font_color", "Button", TEXT)
	t.set_color("font_hover_color", "Button", Color.WHITE)

	t.set_color("separator", "HSeparator", PANEL_EDGE)
	t.set_stylebox("normal", "RichTextLabel", empty(2))
	t.set_color("default_color", "RichTextLabel", TEXT)

	t.set_stylebox("split_bar_background", "HSplitContainer", box(PANEL_EDGE, 0))
	t.set_constant("separation", "HSplitContainer", 1)

## Anything you type or spin into. Sunken, and the number itself is green — in a
## node full of grey labels, the green is what says "this part is yours".
static func _fields(t: Theme) -> void:
	t.set_stylebox("normal", "LineEdit", box(FIELD, 4, NODE_EDGE, 1, 4))
	t.set_stylebox("focus", "LineEdit", box(FIELD, 4, ACCENT, 1, 4))
	t.set_stylebox("read_only", "LineEdit", box(FIELD, 4, NODE_EDGE, 1, 4))
	t.set_color("font_color", "LineEdit", VALUE)
	t.set_color("caret_color", "LineEdit", ACCENT)
	t.set_color("selection_color", "LineEdit", Color(ACCENT, 0.3))

## Thin, dim, and out of the way until you are actually using them.
static func _scrollbars(t: Theme) -> void:
	for bar: String in ["VScrollBar", "HScrollBar"]:
		# The margin is what gives a scrollbar its width: the box is the whole bar,
		# and the padding inside it is the gap either side of the grabber.
		t.set_stylebox("scroll", bar, box(Color(0, 0, 0, 0.25), 3, Color(0, 0, 0, 0), 0, 2))
		t.set_stylebox("grabber", bar, box(Color(1, 1, 1, 0.20), 3, Color(0, 0, 0, 0), 0, 2))
		t.set_stylebox("grabber_highlight", bar, box(Color(1, 1, 1, 0.32), 3, Color(0, 0, 0, 0), 0, 2))
		t.set_stylebox("grabber_pressed", bar, box(ACCENT, 3, Color(0, 0, 0, 0), 0, 2))
