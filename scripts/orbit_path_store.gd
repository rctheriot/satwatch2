class_name OrbitPathStore
extends RefCounted
## Loads data/orbit_paths.bin: one closed loop per object, in the SAME index
## order as EphemerisStore/CatalogStore (both come from the same filtered
## object list in tools/build_ephemeris.py -- see build_orbit_paths() there).
##
## Layout (little-endian), written by tools/build_ephemeris.py:
##   magic "OPTH" | u32 version | u32 n_objects | u32 points_per_path
##   then n_objects blocks of points_per_path * 3 float32, Godot axes,
##   Earth radii, unexaggerated -- object-major, since a path is drawn whole
##   rather than interpolated at a time cursor like the position ephemeris.
##
## Each object's loop covers its OWN orbital period, not a shared window, so a
## 12-hour HEO object gets a full ellipse from the same file a 90-minute LEO
## object gets a full circle from. See build_orbit_paths()'s docstring for why
## that is a separate file rather than a longer shared ephemeris window.

const MAGIC := "OPTH"
const SUPPORTED_VERSION := 1
const HEADER_SIZE := 16

var n_objects: int = 0
var points_per_path: int = 0
var positions: PackedFloat32Array    ## n_objects * points_per_path * 3

var _loaded: bool = false

func is_loaded() -> bool:
	return _loaded

func load_from(path: String) -> Error:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return ERR_FILE_NOT_FOUND

	var header := f.get_buffer(HEADER_SIZE)
	if header.size() < HEADER_SIZE \
			or header.slice(0, 4).get_string_from_ascii() != MAGIC:
		push_error("OrbitPathStore: %s is not an orbit-paths file." % path)
		return ERR_FILE_UNRECOGNIZED

	var version := header.decode_u32(4)
	if version != SUPPORTED_VERSION:
		push_error("OrbitPathStore: %s is version %d, expected %d. Rebuild it."
			% [path, version, SUPPORTED_VERSION])
		return ERR_INVALID_DATA

	n_objects = header.decode_u32(8)
	points_per_path = header.decode_u32(12)

	var expected := n_objects * points_per_path * 3 * 4
	var body := f.get_buffer(expected)
	f.close()
	if body.size() != expected:
		push_error("OrbitPathStore: %s has %d bytes of data, expected %d."
			% [path, body.size(), expected])
		return ERR_FILE_CORRUPT

	positions = body.to_float32_array()
	_loaded = true
	print("OrbitPathStore: %d objects, %d points/path, %.1f MB"
		% [n_objects, points_per_path, expected / 1e6])
	return OK
