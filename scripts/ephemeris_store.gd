class_name EphemerisStore
extends RefCounted
## Loads data/ephemeris.bin and interpolates positions at arbitrary sim time.
##
## Layout (little-endian), written by tools/build_ephemeris.py:
##   magic "SATE" | u32 version | u32 n_objects | u32 n_samples
##   f64 epoch_unix | f32 step_seconds | f32 reserved          == 32 bytes
##   then n_samples blocks of n_objects * 3 float32, TEME in Earth radii,
##   already mapped to Godot axes.
##
## Sample-major matters: the two slabs bracketing any instant are contiguous,
## so interpolation is two sequential reads rather than a strided gather.

const MAGIC := "SATE"
const SUPPORTED_VERSION := 2
const HEADER_SIZE := 32

var n_objects: int = 0
var n_samples: int = 0
var epoch_unix: float = 0.0
var step_seconds: float = 30.0
var positions: PackedFloat32Array    ## n_samples * n_objects * 3

var _loaded: bool = false

func is_loaded() -> bool:
	return _loaded

func span_seconds() -> float:
	return float(n_samples) * step_seconds

func load_from(path: String) -> Error:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("EphemerisStore: cannot open %s (%s). Run tools/build_ephemeris.py."
			% [path, error_string(FileAccess.get_open_error())])
		return ERR_FILE_NOT_FOUND

	var header := f.get_buffer(HEADER_SIZE)
	if header.size() < HEADER_SIZE:
		push_error("EphemerisStore: %s is truncated." % path)
		return ERR_FILE_CORRUPT
	if header.slice(0, 4).get_string_from_ascii() != MAGIC:
		push_error("EphemerisStore: %s is not an ephemeris file." % path)
		return ERR_FILE_UNRECOGNIZED

	var version := header.decode_u32(4)
	if version != SUPPORTED_VERSION:
		push_error("EphemerisStore: %s is version %d, expected %d. Rebuild it."
			% [path, version, SUPPORTED_VERSION])
		return ERR_INVALID_DATA

	n_objects = header.decode_u32(8)
	n_samples = header.decode_u32(12)
	epoch_unix = header.decode_double(16)
	step_seconds = header.decode_float(24)

	var expected := n_objects * n_samples * 3 * 4
	var body := f.get_buffer(expected)
	f.close()
	if body.size() != expected:
		push_error("EphemerisStore: %s has %d bytes of data, expected %d."
			% [path, body.size(), expected])
		return ERR_FILE_CORRUPT

	# Bulk conversion -- one engine call. This is why positions are float32
	# rather than int16; GDScript has no bulk int16 decode.
	positions = body.to_float32_array()
	_loaded = true
	print("EphemerisStore: %d objects, %d samples, %.1f h span, %.1f MB"
		% [n_objects, n_samples, span_seconds() / 3600.0, expected / 1e6])
	return OK

## Fractional sample index for a sim time, wrapped into the span.
func sample_cursor(unix_seconds: float) -> float:
	if n_samples <= 0:
		return 0.0
	return fposmod((unix_seconds - epoch_unix) / step_seconds, float(n_samples))

func position_at(object_index: int, unix_seconds: float) -> Vector3:
	if not _loaded or object_index < 0 or object_index >= n_objects:
		return Vector3.ZERO
	var cursor := sample_cursor(unix_seconds)
	var i0 := int(cursor)
	var i1 := (i0 + 1) % n_samples
	var t := cursor - float(i0)
	var a := i0 * n_objects * 3 + object_index * 3
	var b := i1 * n_objects * 3 + object_index * 3
	return Vector3(
		lerpf(positions[a], positions[b], t),
		lerpf(positions[a + 1], positions[b + 1], t),
		lerpf(positions[a + 2], positions[b + 2], t))
