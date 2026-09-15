class_name Chapter
extends Resource
## One beat of the presentation: a camera pose plus a content state.
##
## Chapters are presets over a single shared data spine, which is why adding one
## costs almost nothing.

@export var title: String = ""
@export var subtitle: String = ""
## A few sentences telling the viewer what they are actually looking at, shown
## on the right panel. A wall of unexplained dots impresses nobody: the point of
## each chapter is the thing it makes visible, and that has to be said.
@export_multiline var explanation: String = ""

@export_group("Content")
## Empty means every regime.
@export var regimes: Array[String] = []
## Objects whose name contains this are highlighted, everything else dimmed.
@export var highlight_name: String = ""
## Objects whose international designator starts with this are highlighted --
## how you isolate the debris cloud from a single breakup event.
@export var highlight_intl_prefix: String = ""
## Colour for highlighted objects. Red reads as debris or hazard against the
## blue LEO population; green suits an operational constellation.
@export var highlight_color: Color = Color(1.0, 0.28, 0.24)
@export var content_scale: float = 1.45
@export var altitude_exaggeration: float = 2.0
## Multiplier on the base screen-space point size. 1.0 everywhere gives uniform
## visibility across chapters; lower it only where a view is genuinely too dense.
@export var point_size: float = 1.0

@export_group("Camera")
@export var azimuth: float = 0.0
@export var elevation: float = 0.2
## Distance from the eye to the content origin, in metres. 0 derives a distance
## that keeps the outermost visible object comfortably clear of the viewer.
@export var camera_distance: float = 0.0

## Show the Space Surveillance Network layer and its per-site visibility panel.
@export var show_sensors: bool = false

@export_group("Time")
## Chapters deliberately do NOT set the clock rate. Having each one impose its
## own speed made the time base jump between demos, which reads as the
## visualisation being inconsistent rather than as a deliberate choice. Rate is
## a global control the presenter sets once, with [ and ].
@export var transition_seconds: float = 2.5
