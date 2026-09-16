class_name Hud
extends Node3D
## Builds and updates every world-space panel.
##
## Layout for the 6.047 m x 2.042 m wall (y spans 0.62 to 2.66 about head height
## 1.64). The globe owns the middle; the 3:1 aspect leaves ~1.8 m of usable wall
## in each side gutter, so EVERY panel lives in a gutter. Nothing is centred --
## a centre-bottom bar would be drawn in front of the globe and read as an
## object floating inside it.
##
## Panels sit at z = -2.45 m, just BEHIND the wall plane at 2.282 m, so they
## carry mild positive parallax and never risk a window violation at the edges.
##
## Satellites nearer than 2.45 m correctly draw in front of a panel and farther
## ones are correctly occluded by it -- the panels are opaque and write depth,
## and the additive point shader depth-TESTS even though it does not depth-WRITE.
## That reads as consistent depth rather than as UI being overdrawn.

## All panel coordinates are HEAD-RELATIVE: main.gd sets this node's global
## transform from the camera pivot every frame, so the panels stay fixed on the
## physical wall while the camera flies. The pivot sits at eye height, so y = 0
## here is eye level, and -z is straight ahead.
const PANEL_Z := -2.45
const PANEL_X := 2.22
const TOP_Y := 0.41             ## Eye-relative; 2.05 m above the floor.

## Left and right are now both full-height gutter panels: left carries the
## catalog key, the live clock, and the control scheme; right carries the
## chapter title and explanation. Same height keeps their tops AND bottoms
## aligned, which reads as one layout rather than two unrelated boxes.
const PANEL_HEIGHT := 1.80

## Spelled out for a general audience. The chapter titles already say these in
## full the first time; this is the one place they are looked up afterward.
const REGIME_NAMES := {
	"LEO": "Low Earth Orbit",
	"MEO": "Medium Earth Orbit",
	"GEO": "Geostationary Orbit",
	"HEO": "Highly Elliptical Orbit",
}

## Second column: action, then the physical control. The last row is shared
## between both schemes rather than duplicated in each list below.
const KEYBOARD_CONTROLS := [
	["Drag mouse", "Orbit the globe"],
	["Scroll wheel, or W / S", "Zoom in and out"],
	["Left / Right arrows", "Change chapter"],
	["Space", "Pause or resume time"],
	["[ and ]", "Slow down or speed up time"],
	["F", "Toggle free-fly mode"],
	["T", "Toggle orbit paths"],
	["M", "Mute / unmute music"],
	["R", "Reset the view"],
	["Esc", "Quit"],
]
const GAMEPAD_CONTROLS := [
	["Right stick", "Orbit the globe"],
	["Left stick", "Zoom in and out"],
	["D-pad left / right", "Change chapter"],
	["A button", "Pause or resume time"],
	["Shoulder buttons", "Slow down or speed up time"],
	["Y button", "Toggle free-fly mode"],
	["B button", "Toggle orbit paths"],
	["Back button", "Mute / unmute music"],
]
const SWITCH_ROW := ["H, or X button", "Switch these instructions"]

var left: WorldPanel
var right: WorldPanel

var _chapter_title: Label
var _chapter_sub: Label
var _explanation: Label
var _legend_col: VBoxContainer
var _site_rows: VBoxContainer
var _time_label: Label
var _rate_label: Label
var _loop_caption: Label
var _loop_bar: ProgressBar
var _controls_heading: Label
var _controls_col: VBoxContainer
var _site_signature := ""
var _gamepad_controls := false

func build(catalog: CatalogStore) -> void:
	var size := Vector2(1.52, PANEL_HEIGHT)
	var y := TOP_Y - (PANEL_HEIGHT - 1.05) * 0.5
	left = _make_panel(size, Vector3(-PANEL_X, y, PANEL_Z), _build_left(catalog))
	right = _make_panel(size, Vector3(PANEL_X, y, PANEL_Z), _build_right())

	# The right panel changes only on a chapter transition, so it renders once
	# and stops. The left panel now carries the live clock and loop bar, so it
	# has to keep rendering every frame -- seeing the last digit of a UTC clock
	# holding still would be a worse tell than the fill cost of redrawing it.
	right.set_update_always(false)

func _make_panel(size: Vector2, pos: Vector3, content: Control) -> WorldPanel:
	var p := WorldPanel.new()
	add_child(p)
	p.build(size, content)
	p.position = pos
	return p

func _column(separation: int = 14) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", separation)
	return v

func _swatch_row(color: Color, text: String, label_size: int,
		value: String = "") -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)

	var sw := ColorRect.new()
	sw.color = color
	sw.custom_minimum_size = Vector2(22, 22)
	sw.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(sw)

	row.add_child(PanelTheme.label(text, label_size))

	if not value.is_empty():
		var spacer := Control.new()
		spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(spacer)
		row.add_child(PanelTheme.label(value, label_size, PanelTheme.ACCENT))
	return row

func _text_row(left_text: String, right_text: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	row.add_child(PanelTheme.label(left_text, 20, PanelTheme.ACCENT))
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)
	var r := PanelTheme.label(right_text, 20)
	r.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	r.custom_minimum_size = Vector2(560, 0)
	r.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(r)
	return row

## Catalog key, live clock, and controls: everything that does not depend on
## which chapter is showing.
func _build_left(catalog: CatalogStore) -> Control:
	var bg := PanelTheme.backdrop()
	var col := _column()
	bg.add_child(col)

	col.add_child(PanelTheme.label("SATELLITE CATALOG", 24, PanelTheme.DIM))
	for regime in ["LEO", "MEO", "GEO", "HEO"]:
		col.add_child(_swatch_row(PanelTheme.REGIME_COLORS[regime],
			REGIME_NAMES[regime], 26,
			str(int(catalog.regime_counts.get(regime, 0)))))
	col.add_child(PanelTheme.label(
		"%s tracked objects total" % _comma(catalog.objects.size()), 22,
		PanelTheme.DIM))

	col.add_child(PanelTheme.rule())
	var time_row := HBoxContainer.new()
	time_row.add_theme_constant_override("separation", 30)
	col.add_child(time_row)
	_time_label = PanelTheme.label("", 32)
	time_row.add_child(_time_label)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	time_row.add_child(spacer)
	_rate_label = PanelTheme.label("", 32, PanelTheme.ACCENT)
	time_row.add_child(_rate_label)

	_loop_caption = PanelTheme.label("", 20, PanelTheme.DIM)
	col.add_child(_loop_caption)

	_loop_bar = ProgressBar.new()
	_loop_bar.min_value = 0.0
	_loop_bar.max_value = 1.0
	_loop_bar.show_percentage = false
	_loop_bar.custom_minimum_size = Vector2(0, 14)
	var track := StyleBoxFlat.new()
	track.bg_color = Color(1, 1, 1, 0.12)
	track.set_corner_radius_all(4)
	var fill := StyleBoxFlat.new()
	fill.bg_color = PanelTheme.ACCENT
	fill.set_corner_radius_all(4)
	_loop_bar.add_theme_stylebox_override("background", track)
	_loop_bar.add_theme_stylebox_override("fill", fill)
	col.add_child(_loop_bar)

	col.add_child(PanelTheme.rule())
	_controls_heading = PanelTheme.label("", 24, PanelTheme.DIM)
	col.add_child(_controls_heading)
	_controls_col = _column(6)
	col.add_child(_controls_col)
	_render_controls()
	return bg

func _build_right() -> Control:
	var bg := PanelTheme.backdrop()
	var col := _column(10)
	bg.add_child(col)

	_chapter_title = PanelTheme.heading("")
	_chapter_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_chapter_sub = PanelTheme.label("", 24, PanelTheme.DIM)
	_chapter_sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(_chapter_title)
	col.add_child(_chapter_sub)
	col.add_child(PanelTheme.rule())

	_explanation = PanelTheme.label("", 30)
	_explanation.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(_explanation)

	_legend_col = _column(6)
	col.add_child(_legend_col)

	# Per-site visibility, shown only during the surveillance chapter. There is
	# no object-detail readout any more: picking one satellite out of 14,745 was
	# never the point, and the reticle was competing with the content.
	_site_rows = VBoxContainer.new()
	_site_rows.add_theme_constant_override("separation", 4)
	_site_rows.visible = false
	col.add_child(_site_rows)
	return bg

## Rebuilds the control list for whichever scheme is currently selected.
## Called once at startup and again each time the viewer switches schemes --
## see toggle_controls_scheme().
func _render_controls() -> void:
	_controls_heading.text = ("CONTROLS: GAMEPAD" if _gamepad_controls
		else "CONTROLS: KEYBOARD AND MOUSE")
	for child in _controls_col.get_children():
		child.queue_free()
	var rows: Array = GAMEPAD_CONTROLS if _gamepad_controls else KEYBOARD_CONTROLS
	for r in rows:
		_controls_col.add_child(_text_row(r[0], r[1]))
	_controls_col.add_child(_text_row(SWITCH_ROW[0], SWITCH_ROW[1]))

## Bound to H / gamepad X in main.gd. There is no pointer in stereo mode (see
## WorldPanel), so this cannot be a clickable button -- it is a real control
## in the same sense chapter_next/prev are, just one that changes what the
## panel says rather than what the globe shows.
func toggle_controls_scheme() -> void:
	_gamepad_controls = not _gamepad_controls
	_render_controls()

static func _comma(n: int) -> String:
	var s := str(n)
	var out := ""
	var count := 0
	for i in range(s.length() - 1, -1, -1):
		out = s[i] + out
		count += 1
		if count % 3 == 0 and i != 0:
			out = "," + out
	return out

## Live per-site visibility. The panel re-renders only when the numbers change,
## since it is a SubViewport and redrawing it every frame at this pixel count is
## fill we do not need to spend.
func set_site_rows(rows: Array, total: int) -> void:
	var signature := "%d|" % total
	for r in rows:
		signature += "%s:%d:%d|" % [r["name"], r["count"], 1 if r["active"] else 0]
	if signature == _site_signature:
		return
	_site_signature = signature

	for c in _site_rows.get_children():
		c.queue_free()
	_site_rows.add_child(PanelTheme.label(
		"%s objects in view of the network" % _comma(total), 22, PanelTheme.ACCENT))
	for r in rows:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		var swatch := ColorRect.new()
		swatch.color = (PanelTheme.ACCENT if r["kind"] == GroundSites.Kind.RADAR
			else PanelTheme.WARN)
		if not r["active"]:
			swatch.color = Color(0.3, 0.33, 0.38)
		swatch.custom_minimum_size = Vector2(14, 14)
		swatch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(swatch)
		var dim: bool = not r["active"]
		row.add_child(PanelTheme.label(String(r["name"]), 20,
			PanelTheme.DIM if dim else PanelTheme.TEXT))
		var spacer := Control.new()
		spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(spacer)
		# "in the dark" is the honest reason an optical site shows nothing.
		row.add_child(PanelTheme.label(
			"in the dark" if dim else str(r["count"]), 20,
			PanelTheme.DIM if dim else PanelTheme.ACCENT))
		_site_rows.add_child(row)
	right.set_update_always(false)

func set_chapter(c: Chapter, idx: int, total: int) -> void:
	_chapter_title.text = c.title
	_chapter_sub.text = "%s   (%d of %d)" % [c.subtitle, idx + 1, total]
	_explanation.text = c.explanation

	for child in _legend_col.get_children():
		child.queue_free()
	for row in c.legend:
		_legend_col.add_child(_swatch_row(row["color"], row["label"], 22))

	_site_rows.visible = c.show_sensors
	right.set_update_always(false)   # UPDATE_ONCE: re-render exactly one frame.

func set_time(utc: String, rate: String, loop_progress: float,
		loop_hours: float) -> void:
	_time_label.text = utc
	_rate_label.text = rate
	_loop_caption.text = "Snapshot of orbital motion, %s hours, repeating on a loop" \
		% _trim_zero(loop_hours)
	_loop_bar.value = loop_progress

static func _trim_zero(x: float) -> String:
	return "%.0f" % x if is_equal_approx(x, roundf(x)) else "%.1f" % x
