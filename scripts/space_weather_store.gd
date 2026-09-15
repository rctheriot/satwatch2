class_name SpaceWeatherStore
extends RefCounted
## NOAA SWPC conditions, from tools/fetch_space_weather.py.
##
## Relevant rather than decorative: geomagnetic activity heats and expands the
## thermosphere, raising drag on everything in low LEO. Orbits decay faster and
## predictions degrade -- which is the honest caveat on the whole display, made
## visible.

var loaded := false
var kp_index: float = -1.0
var kp_estimated: float = -1.0
var kp_time_utc := ""
var xray_class := ""
var aurora_observation_utc := ""
var aurora_forecast_utc := ""
var aurora_peak_probability: int = 0
var source := ""
var fetched_utc := ""

func load_from(path: String) -> Error:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return ERR_FILE_NOT_FOUND    # Optional data; the demo runs without it.
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("SpaceWeatherStore: %s is not valid JSON." % path)
		return ERR_FILE_CORRUPT
	var d: Dictionary = parsed
	kp_index = float(d.get("kp_index", -1))
	kp_estimated = float(d.get("kp_estimated", -1))
	kp_time_utc = String(d.get("kp_time_utc", ""))
	xray_class = String(d.get("xray_class", ""))
	aurora_observation_utc = String(d.get("aurora_observation_utc", ""))
	aurora_forecast_utc = String(d.get("aurora_forecast_utc", ""))
	aurora_peak_probability = int(d.get("aurora_peak_probability", 0))
	source = String(d.get("source", ""))
	fetched_utc = String(d.get("fetched_utc", ""))
	loaded = true
	return OK

## NOAA G-scale. Kp 5 is the threshold for a G1 storm; below that is "quiet"
## through "unsettled".
func storm_label() -> String:
	if kp_index < 0.0:
		return "—"
	if kp_index < 4.0:
		return "quiet"
	if kp_index < 5.0:
		return "unsettled"
	return "G%d storm" % clampi(int(kp_index) - 4, 1, 5)

func summary() -> String:
	if not loaded:
		return ""
	return "SPACE WEATHER  Kp %.0f (%s) · X-ray %s · aurora peak %d%%" % [
		kp_index, storm_label(), xray_class, aurora_peak_probability]

## The aurora layer is a forecast from a model, not an observation, and saying
## so costs nothing.
func provenance() -> String:
	if not loaded:
		return ""
	return "%s · aurora forecast for %s" % [source, aurora_forecast_utc]
