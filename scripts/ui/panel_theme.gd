class_name PanelTheme
extends RefCounted
## Shared look for the world-space panels. Built in code so there is one source
## of truth and no .tres to drift.

const BG := Color(0.03, 0.05, 0.09, 0.82)
const EDGE := Color(0.30, 0.62, 0.95, 0.55)
const TEXT := Color(0.88, 0.94, 1.00)
const DIM := Color(0.55, 0.66, 0.78)
const ACCENT := Color(0.42, 0.80, 1.00)
const WARN := Color(1.00, 0.72, 0.35)

const REGIME_COLORS := {
	"LEO": Color(0.36, 0.78, 1.00),
	"MEO": Color(0.55, 1.00, 0.62),
	"GEO": Color(1.00, 0.78, 0.31),
	"HEO": Color(1.00, 0.45, 0.55),
}

static func backdrop() -> PanelContainer:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = BG
	sb.border_color = EDGE
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(10)
	sb.set_content_margin_all(28)
	p.add_theme_stylebox_override("panel", sb)
	return p

static func label(text: String, size: int, color: Color = TEXT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	# Stereo legibility: thin light-on-dark text shimmers between the eyes
	# unless it carries a little weight of its own.
	l.add_theme_constant_override("outline_size", 4)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.75))
	return l

static func heading(text: String) -> Label:
	return label(text, 46, ACCENT)

static func rule() -> HSeparator:
	var s := HSeparator.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = EDGE
	sb.content_margin_top = 1
	s.add_theme_stylebox_override("separator", sb)
	return s
