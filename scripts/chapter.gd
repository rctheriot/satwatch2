class_name Chapter
extends Resource
## One beat of the presentation: a camera pose plus a content state.
##
## Chapters are presets over a single shared data spine, which is why adding one
## costs almost nothing.

@export var title: String = ""
@export var subtitle: String = ""

@export_group("Content")
## Empty means every regime.
@export var regimes: Array[String] = []
## Objects whose name contains this are highlighted, everything else dimmed.
@export var highlight_name: String = ""
## Objects whose international designator starts with this are highlighted --
## how you isolate the debris cloud from a single breakup event.
@export var highlight_intl_prefix: String = ""
@export var content_scale: float = 1.45
@export var altitude_exaggeration: float = 2.0
## Point size in world units. Wide views need smaller points: the size that
## reads as a crisp shell at the LEO framing becomes a solid additive disc once
## 20k LEO objects are packed around a small globe.
@export var point_size: float = 0.0035

@export_group("Camera")
@export var azimuth: float = 0.0
@export var elevation: float = 0.2
## Distance from the eye to the content origin, in metres. 0 derives a distance
## that keeps the outermost visible object comfortably clear of the viewer.
@export var camera_distance: float = 0.0

## Index into ConjunctionStore.events. -1 means this is not a conjunction
## chapter; >= 0 shows the magnified encounter inset and jumps the clock to TCA.
@export var conjunction_index: int = -1

@export_group("Time")
@export var rate_index: int = 3
@export var transition_seconds: float = 2.5
