class_name ConjunctionStore
extends RefCounted
## Close approaches found by tools/find_conjunctions.py.

var events: Array = []
var method: String = ""
var caveat: String = ""
var built_utc: String = ""
var co_orbital_excluded: int = 0

func load_from(path: String) -> Error:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		# Optional data: the demo runs without it, that chapter is just skipped.
		return ERR_FILE_NOT_FOUND
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("ConjunctionStore: %s is not valid JSON." % path)
		return ERR_FILE_CORRUPT
	var d: Dictionary = parsed
	events = d.get("events", [])
	method = d.get("method", "")
	caveat = d.get("caveat", "")
	built_utc = d.get("built_utc", "")
	co_orbital_excluded = int(d.get("co_orbital_excluded", 0))
	return OK

func has_tracks() -> bool:
	for e in events:
		if e.has("track") and not e["track"].is_empty():
			return true
	return false

## First event with a fine track and at least this relative speed. A fast,
## cross-operator approach tells the SDA story better than a slow one between
## two satellites of the same constellation.
func best_event(min_rel_kms: float = 4.0, prefer_cross_operator: bool = true) -> int:
	var fallback := -1
	for i in events.size():
		var e: Dictionary = events[i]
		if not e.has("track") or e["track"].is_empty():
			continue
		if float(e.get("relative_speed_kms", 0.0)) < min_rel_kms:
			continue
		if fallback < 0:
			fallback = i
		if not prefer_cross_operator:
			return i
		# Same-constellation pairs share a name stem; a different stem means
		# two different operators, which is the more interesting case.
		var a := String(e.get("a_name", "")).split("-")[0]
		var b := String(e.get("b_name", "")).split("-")[0]
		if a != b:
			return i
	return fallback
