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
const BOTTOM_TOP_EDGE := -0.21  ## Bottom panels are top-aligned here.

var left: WorldPanel
var right: WorldPanel
var time_bar: WorldPanel
var provenance: WorldPanel

var _chapter_title: Label
var _chapter_sub: Label
var _legend_rows: Dictionary = {}
var _detail_rows: Dictionary = {}
var _detail_name: Label
var _time_label: Label
var _rate_label: Label
var _exaggeration_label: Label
var _comfort_label: Label
var _comfort_warned := false

func build(catalog: CatalogStore) -> void:
	var top := Vector2(1.52, 1.05)
	left = _make_panel(top, Vector3(-PANEL_X, TOP_Y, PANEL_Z), _build_left(catalog))
	right = _make_panel(top, Vector3(PANEL_X, TOP_Y, PANEL_Z), _build_right())

	var time_size := Vector2(1.52, 0.30)
	time_bar = _make_panel(time_size,
		Vector3(-PANEL_X, BOTTOM_TOP_EDGE - time_size.y * 0.5, PANEL_Z),
		_build_time_bar())

	var prov_size := Vector2(1.52, 0.68)
	provenance = _make_panel(prov_size,
		Vector3(PANEL_X, BOTTOM_TOP_EDGE - prov_size.y * 0.5, PANEL_Z),
		_build_provenance(catalog))

	# Only the clock changes every frame. At 15.5 Mpix/frame the fill saved by
	# not re-rendering three static SubViewports is worth claiming.
	for panel in [left, right, provenance]:
		panel.set_update_always(false)

func _make_panel(size: Vector2, pos: Vector3, content: Control) -> WorldPanel:
	var p := WorldPanel.new()
	add_child(p)
	p.build(size, content)
	p.position = pos
	return p

func _column() -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 14)
	return v

func _build_left(catalog: CatalogStore) -> Control:
	var bg := PanelTheme.backdrop()
	var col := _column()
	bg.add_child(col)

	_chapter_title = PanelTheme.heading("")
	_chapter_sub = PanelTheme.label("", 26, PanelTheme.DIM)
	_chapter_sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(_chapter_title)
	col.add_child(_chapter_sub)
	col.add_child(PanelTheme.rule())
	col.add_child(PanelTheme.label("CATALOG", 24, PanelTheme.DIM))

	for regime in ["LEO", "MEO", "GEO", "HEO"]:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 16)

		var swatch := ColorRect.new()
		swatch.color = PanelTheme.REGIME_COLORS[regime]
		swatch.custom_minimum_size = Vector2(22, 22)
		swatch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(swatch)

		row.add_child(PanelTheme.label(regime, 30))
		var spacer := Control.new()
		spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(spacer)

		var count := PanelTheme.label(
			str(int(catalog.regime_counts.get(regime, 0))), 30, PanelTheme.ACCENT)
		row.add_child(count)
		_legend_rows[regime] = row
		col.add_child(row)

	col.add_child(PanelTheme.rule())
	var total: int = catalog.objects.size()
	col.add_child(PanelTheme.label("%d TRACKED OBJECTS" % total, 28))
	_comfort_label = PanelTheme.label("", 22, PanelTheme.WARN)
	col.add_child(_comfort_label)
	return bg

func _build_right() -> Control:
	var bg := PanelTheme.backdrop()
	var col := _column()
	bg.add_child(col)

	col.add_child(PanelTheme.label("SELECTED OBJECT", 24, PanelTheme.DIM))
	_detail_name = PanelTheme.heading("— none —")
	_detail_name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(_detail_name)
	col.add_child(PanelTheme.rule())

	for key in ["NORAD ID", "INTL DES", "REGIME", "PERIGEE", "APOGEE",
			"INCLINATION", "PERIOD", "TLE EPOCH"]:
		var row := HBoxContainer.new()
		row.add_child(PanelTheme.label(key, 24, PanelTheme.DIM))
		var spacer := Control.new()
		spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(spacer)
		var val := PanelTheme.label("—", 26)
		row.add_child(val)
		_detail_rows[key] = val
		col.add_child(row)
	return bg

func _build_time_bar() -> Control:
	var bg := PanelTheme.backdrop()
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 30)
	bg.add_child(row)
	_time_label = PanelTheme.label("", 40)
	row.add_child(_time_label)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)
	_rate_label = PanelTheme.label("", 40, PanelTheme.ACCENT)
	row.add_child(_rate_label)
	return bg

func _build_provenance(catalog: CatalogStore) -> Control:
	# Non-negotiable for this audience. Overstating fidelity to people who work
	# this problem daily costs more credibility than the demo can buy back.
	var bg := PanelTheme.backdrop()
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	bg.add_child(col)

	var spread := catalog.epoch_spread_days()
	col.add_child(_wrapped(
		"SOURCE %s · BUILT %s · ELEMENT EPOCH SPREAD %.1f days"
			% [catalog.source, catalog.built_utc.left(19), spread], PanelTheme.DIM))
	col.add_child(_wrapped(
		"%s, %s frame. Error grows to kilometres per day in LEO. "
		% [catalog.propagator, catalog.frame]
		+ "Not an operational conjunction product.", PanelTheme.WARN))
	_exaggeration_label = _wrapped("", PanelTheme.WARN)
	col.add_child(_exaggeration_label)
	return bg

func _wrapped(text: String, color: Color) -> Label:
	var l := PanelTheme.label(text, 22, color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l


func set_chapter(c: Chapter, idx: int, total: int) -> void:
	_chapter_title.text = c.title
	_chapter_sub.text = "%s   (%d/%d)" % [c.subtitle, idx + 1, total]
	left.set_update_always(false)   # UPDATE_ONCE: re-render exactly one frame.

func set_exaggeration(k: float) -> void:
	# Whenever the geometry is not true, say so on screen.
	_exaggeration_label.text = "" if is_equal_approx(k, 1.0) \
		else "ALTITUDE EXAGGERATED x%.1f — orbital radii are not to scale." % k
	provenance.set_update_always(false)

## Nearest visible content, in metres from the eye. Free navigation is allowed
## to fly inside the shell, so rather than blocking the camera we say when the
## view has gone past comfortable fusion -- the presenter can then decide.
func set_comfort(nearest_m: float) -> void:
	var warn := nearest_m < CameraDirector.MIN_CONTENT_DISTANCE
	if warn == _comfort_warned:
		return
	_comfort_warned = warn
	_comfort_label.text = "" if not warn else \
		"CLOSE VIEW — %.0f mm parallax, past comfortable fusion" \
			% CameraDirector.parallax_mm(maxf(nearest_m, 0.05))
	left.set_update_always(false)


func set_time(utc: String, rate: String) -> void:
	_time_label.text = utc
	_rate_label.text = rate

func set_selection(obj: Variant) -> void:
	right.set_update_always(false)
	if obj == null:
		_detail_name.text = "— none —"
		for v in _detail_rows.values():
			v.text = "—"
		return
	_detail_name.text = String(obj.get("name", "UNKNOWN"))
	_detail_rows["NORAD ID"].text = str(obj.get("norad_id", 0))
	_detail_rows["INTL DES"].text = String(obj.get("intl_des", "—"))
	_detail_rows["REGIME"].text = String(obj.get("regime", "—"))
	_detail_rows["PERIGEE"].text = "%.0f km" % float(obj.get("perigee_km", 0.0))
	_detail_rows["APOGEE"].text = "%.0f km" % float(obj.get("apogee_km", 0.0))
	_detail_rows["INCLINATION"].text = "%.2f°" % float(obj.get("inclination_deg", 0.0))
	_detail_rows["PERIOD"].text = "%.1f min" % float(obj.get("period_min", 0.0))
	_detail_rows["TLE EPOCH"].text = String(obj.get("epoch", "—")).left(19)
