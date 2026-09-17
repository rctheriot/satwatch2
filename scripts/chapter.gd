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
## Color key rows for the right panel, e.g. [{"color": Color(...), "label":
## "Debris from this event"}]. Only chapters where color carries meaning beyond
## the regime legend need one.
@export var legend: Array[Dictionary] = []

@export_group("Content")
## Empty means every regime.
@export var regimes: Array[String] = []
## When set, shows ONLY objects whose name contains this substring -- the
## whole population, not a subset dimmed within a regime. For isolating a
## named group (GPS) that regimes/highlight_name can't express, since MEO is
## GPS, GLONASS, Galileo and BeiDou all together. Takes priority over
## `regimes` when non-empty; see ChapterDeck.apply().
@export var filter_name: String = ""
## Objects whose name contains this are highlighted, everything else dimmed.
@export var highlight_name: String = ""
## Objects whose international designator starts with this are highlighted --
## how you isolate the debris cloud from a single breakup event.
@export var highlight_intl_prefix: String = ""
## Colour for highlighted objects. Red reads as debris or hazard against the
## blue LEO population; green suits an operational constellation.
@export var highlight_color: Color = Color(1.0, 0.28, 0.24)
## Colour for everything NOT highlighted. Alpha 0 means "use regime colours".
## Set it when not-highlighted is a meaningful state in its own right rather
## than just background -- in the surveillance chapter, out of view is as much
## the point as in view.
@export var base_color: Color = Color(0, 0, 0, 0)
## Brightness of the un-highlighted population. Low when they are context, high
## when they carry meaning.
@export var dim_others: float = 0.28
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
## Show the ionospheric TEC shell.
@export var show_tec: bool = false
## Show advected 250 hPa wind streamlines.
@export var show_winds: bool = false
## Show the auroral oval shell. Only meaningful in the space weather chapter --
## it was previously left visible everywhere its data had loaded.
@export var show_aurora: bool = false
## Hide the satellite field. The jet-stream chapter needs this: satellites
## and 10 km-altitude wind data are so far apart in scale that showing both
## at once would badly misrepresent where either actually is.
@export var show_satellites: bool = true
## Hide the Earth mesh, and with it everything parented to it -- atmosphere,
## clouds, and every optional layer. Only the ISS chapter needs this: it is
## a standalone model inspection, not something shown relative to the globe.
@export var show_earth: bool = true
## Show the free-standing ISS model in place of the globe. Its own chapter
## only.
@export var show_iss: bool = false
## Force the orbit-trail toggle on for this chapter regardless of its current
## state, and restore whatever it was on the way out. See main.gd's
## _on_chapter_changed() -- the toggle itself stays a global, viewer-owned
## control (T / gamepad B); this only borrows it temporarily for a chapter
## where the paths ARE the point, without permanently changing what the
## viewer had it set to.
@export var force_orbit_trails: bool = false

@export_group("Time")
## Chapters deliberately do NOT set the clock rate. Having each one impose its
## own speed made the time base jump between demos, which reads as the
## visualisation being inconsistent rather than as a deliberate choice. Rate is
## a global control the presenter sets once, with [ and ].
@export var transition_seconds: float = 2.5
