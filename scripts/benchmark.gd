class_name Benchmark
extends Node
## Frame-time sampling, and a direct measurement of the satellite update cost.
##
##   Godot --path . -- --benchmark 6 [--chapter N]
##
## The number that decides Phase A vs Phase B is not total FPS -- it is how much
## of the frame SatelliteField.update_positions() eats, because that is the part
## a GPU vertex-shader path would remove.

var seconds: float = 6.0
var field: SatelliteField

var _frames: PackedFloat32Array = PackedFloat32Array()
var _update_us: PackedFloat32Array = PackedFloat32Array()
var _elapsed: float = 0.0
var _warmup: int = 20

func _ready() -> void:
	# Without this the result is just the refresh rate, not the cost.
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0

static func from_command_line() -> Benchmark:
	var args := OS.get_cmdline_user_args()
	var i := args.find("--benchmark")
	if i < 0:
		return null
	var b := Benchmark.new()
	if i + 1 < args.size():
		b.seconds = float(args[i + 1])
	return b

func _process(delta: float) -> void:
	# Skip the first frames: shader compilation and the initial SubViewport
	# renders are one-off costs that would otherwise dominate the average.
	if _warmup > 0:
		_warmup -= 1
		return

	_frames.append(delta * 1000.0)
	if field != null:
		# Read what the real update already cost this frame. Calling
		# update_positions() here instead would double the work per frame.
		_update_us.append(float(field.last_update_usec))

	_elapsed += delta
	if _elapsed >= seconds:
		_report()
		get_tree().quit()

static func _percentile(a: PackedFloat32Array, p: float) -> float:
	if a.is_empty():
		return 0.0
	var sorted := a.duplicate()
	sorted.sort()
	return sorted[clampi(int(p * sorted.size()), 0, sorted.size() - 1)]

func _report() -> void:
	var vp := get_viewport()
	var size := vp.get_visible_rect().size
	var n: int = 0 if field == null else field.active.size()
	var mean := 0.0
	for f in _frames:
		mean += f
	mean /= maxf(_frames.size(), 1.0)

	print("\n--- BENCHMARK ---")
	print("  window            %d x %d (%.1f Mpix/frame)"
		% [size.x, size.y, size.x * size.y / 1e6])
	print("  visible objects   %d" % n)
	print("  frames sampled    %d over %.1f s" % [_frames.size(), _elapsed])
	print("  frame time        mean %.2f ms  p50 %.2f  p95 %.2f  p99 %.2f"
		% [mean, _percentile(_frames, 0.50), _percentile(_frames, 0.95),
			_percentile(_frames, 0.99)])
	print("  implied FPS       mean %.1f  p95 %.1f"
		% [1000.0 / maxf(mean, 0.001), 1000.0 / maxf(_percentile(_frames, 0.95), 0.001)])
	if not _update_us.is_empty():
		var um := 0.0
		for u in _update_us:
			um += u
		um /= _update_us.size()
		print("  update_positions  mean %.2f ms  p95 %.2f ms  (%.0f%% of mean frame)"
			% [um / 1000.0, _percentile(_update_us, 0.95) / 1000.0,
				100.0 * (um / 1000.0) / maxf(mean, 0.001)])
	print("-----------------")
