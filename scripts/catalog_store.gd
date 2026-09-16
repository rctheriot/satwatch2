class_name CatalogStore
extends RefCounted
## Per-object metadata written alongside the ephemeris by build_ephemeris.py.
## Index i here is index i in EphemerisStore.positions -- the builder writes both
## from the same filtered array, so they must never be sorted independently.

var objects: Array = []
var source: String = ""
var built_utc: String = ""
var propagator: String = ""
var frame: String = ""
var epoch_unix: float = 0.0
var regime_counts: Dictionary = {}
## Sub-satellite point of a known object at epoch, computed by the builder with
## its own GMST implementation. tests/verify_frames.gd checks the engine against
## it -- stored rather than hardcoded so it survives every rebuild.
var registration_reference: Dictionary = {}

func load_from(path: String) -> Error:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("CatalogStore: cannot open %s. Run tools/build_ephemeris.py." % path)
		return ERR_FILE_NOT_FOUND
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("CatalogStore: %s is not valid catalog JSON." % path)
		return ERR_FILE_CORRUPT

	var d: Dictionary = parsed
	objects = d.get("objects", [])
	source = d.get("source", "unknown")
	built_utc = d.get("built_utc", "")
	propagator = d.get("propagator", "SGP4")
	frame = d.get("frame", "TEME")
	epoch_unix = d.get("epoch_unix", 0.0)
	regime_counts = d.get("regime_counts", {})
	var ref: Variant = d.get("registration_reference", null)
	registration_reference = ref if typeof(ref) == TYPE_DICTIONARY else {}
	return OK

func indices_where(key: String, value: Variant) -> PackedInt32Array:
	var out := PackedInt32Array()
	for i in objects.size():
		if objects[i].get(key, null) == value:
			out.append(i)
	return out

func indices_matching_name(fragment: String) -> PackedInt32Array:
	var out := PackedInt32Array()
	var needle := fragment.to_upper()
	for i in objects.size():
		if String(objects[i].get("name", "")).to_upper().contains(needle):
			out.append(i)
	return out

## All objects from one launch / breakup event. Debris from a single event
## shares the launch's international designator prefix (e.g. "1982-092" for
## Cosmos 1408), which is how a breakup cloud is isolated from the catalog.
func indices_with_intl_prefix(prefix: String) -> PackedInt32Array:
	var out := PackedInt32Array()
	for i in objects.size():
		if String(objects[i].get("intl_des", "")).begins_with(prefix):
			out.append(i)
	return out
