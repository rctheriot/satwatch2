class_name Chapter
extends Resource
## One beat of the presentation. Chapters are camera/filter/time presets over a
## single shared data spine, which is why adding one costs almost nothing.

@export var title: String = ""
@export var subtitle: String = ""
## Empty means every regime.
@export var regimes: Array[String] = []
## Objects whose name contains this are highlighted, everything else dimmed.
@export var highlight_name: String = ""
@export var center_distance: float = 3.0
@export var rig_scale: float = 0.75
@export var yaw: float = 0.0
@export var pitch: float = 0.2
@export var altitude_exaggeration: float = 3.0
## Point size in world units. Wide views need smaller points: the same size that
## reads as a crisp shell at the LEO framing becomes a solid additive disc once
## 20k LEO objects are packed around a 0.6 m globe.
@export var point_size: float = 0.0035
@export var rate_index: int = 3
@export var transition_seconds: float = 2.5
