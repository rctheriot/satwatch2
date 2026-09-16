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
const BOTTOM_TOP_EDGE := -0.50  ## Time bar is top-aligned here.

## The left panel is now a static catalog key -- it does not change between
## chapters -- so it stays short. The right panel carries the chapter title
## and the explanation, which is the thing a general audience actually reads,
## so it gets the rest of the gutter's height.
const LEFT_PANEL_HEIGHT := 0.62
const RIGHT_PANEL_HEIGHT := 1.80

## Spelled out for a general audience. The chapter titles already say these in
## full the first time; this is the one place they are looked up afterward.
const REGIME_NAMES := {
	"LEO": "Low Earth Orbit",
	"MEO": "Medium Earth Orbit",
	"GEO": "Geostationary Orbit",
	"HEO": "Highly Elliptical Orbit",
}

var left: WorldPanel
var right: WorldPanel
var time_bar: WorldPanel

var _chapter_title: Label
var _chapter_sub: Label
var _explanation: Label
var _legend_col: VBoxContainer
var _site_rows: VBoxContainer
var _time_label: Label
var _rate_label: Label
var _loop_caption: Label
var _loop_bar: ProgressBar
var _site_signature := ""

func build(catalog: CatalogStore) -> void:
	var side := Vector2(1.52, LEFT_PANEL_HEIGHT)
	var side_y := TOP_Y - (LEFT_PANEL_HEIGHT - 1.05) * 0.5
	left = _make_panel(side, Vector3(-PANEL_X, side_y, PANEL_Z), _build_left(catalog))

	var right_size := Vector2(1.52, RIGHT_PANEL_HEIGHT)
	var right_y := TOP_Y - (RIGHT_PANEL_HEIGHT - 1.05) * 0.5
	right = _make_panel(right_size, Vector3(PANEL_X, right_y, PANEL_Z), _build_right())

	var time_size := Vector2(1.52, 0.34)
	time_bar = _make_panel(time_size,
		Vector3(-PANEL_X, BOTTOM_TOP_EDGE - time_size.y * 0.5, PANEL_Z),
		_build_time_bar())

	# The left panel never changes after this, so it renders once and stops.
	# The right panel changes on every chapter and re-renders itself there.
	left.set_update_always(false)
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

## Static: the catalog totals do not depend on which chapter is showing.
func _build_left(catalog: CatalogStore) -> Control:
	var bg := PanelTheme.backdrop()
	var col := _column()
	bg.add_child(col)

	col.add_child(PanelTheme.label("SATELLITE CATALOG", 24, PanelTheme.DIM))
	for regime in ["LEO", "MEO", "GEO", "HEO"]:
		col.add_child(_swatch_row(PanelTheme.REGIME_COLORS[regime],
			REGIME_NAMES[regime], 26,
			str(int(catalog.regime_counts.get(regime, 0)))))

	col.add_child(PanelTheme.rule())
	var total: int = catalog.objects.size()
	col.add_child(PanelTheme.label("%s tracked objects total" % _comma(total), 26))
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

func _build_time_bar() -> Control:
	var bg := PanelTheme.backdrop()
	var col := _column(6)
	bg.add_child(col)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 30)
	col.add_child(row)
	_time_label = PanelTheme.label("", 36)
	row.add_child(_time_label)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)
	_rate_label = PanelTheme.label("", 36, PanelTheme.ACCENT)
	row.add_child(_rate_label)

	_loop_caption = PanelTheme.label("", 22, PanelTheme.DIM)
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
	return bg

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
