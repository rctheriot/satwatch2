class_name TecStore
extends RefCounted
## Ionospheric total electron content, from tools/fetch_tec.py.
##
## TEC is the electron count in a column through the ionosphere, in TECU. It is
## the direct cause of GNSS ranging error: a signal crossing a dense ionosphere
## arrives late and the receiver reports the wrong distance. High and, more to
## the point, sharply VARYING TEC is why GPS accuracy degrades during solar
## activity -- which makes it the operational consequence of the same
## disturbance the auroral oval shows the visible signature of.

var loaded := false
var observation_utc := ""
var source := ""
var full_scale_tecu: float = 120.0
var min_tecu: float = 0.0
var max_tecu: float = 0.0
var mean_tecu: float = 0.0

func load_from(path: String) -> bool:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return false                    # Optional layer.
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("TecStore: %s is not valid JSON." % path)
		return false
	var d: Dictionary = parsed
	observation_utc = String(d.get("observation_utc", ""))
	source = String(d.get("source", ""))
	full_scale_tecu = float(d.get("full_scale_tecu", 120.0))
	min_tecu = float(d.get("min_tecu", 0.0))
	max_tecu = float(d.get("max_tecu", 0.0))
	mean_tecu = float(d.get("mean_tecu", 0.0))
	loaded = true
	return true

func summary() -> String:
	if not loaded:
		return ""
	return "IONOSPHERE  %.0f–%.0f TECU (mean %.0f) · %s" % [
		min_tecu, max_tecu, mean_tecu, observation_utc.left(16)]
