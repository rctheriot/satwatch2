class_name SimClock
extends Node
## Owns simulation time for the whole demo.
##
## Everything time-dependent reads from here: satellite interpolation, Earth
## rotation (GMST), and the solar terminator. Nothing else keeps its own clock.

signal time_changed(unix_seconds: float)

## Seconds of simulation time per second of wall-clock time.
const RATE_STEPS: Array[float] = [0.0, 1.0, 10.0, 60.0, 300.0, 1800.0]

@export var rate_index: int = 2
@export var paused: bool = false

var epoch_unix: float = 0.0      ## First ephemeris sample.
var span_seconds: float = 0.0    ## Total ephemeris span; time wraps within it.
var now_unix: float = 0.0

func _ready() -> void:
	set_process(true)

func configure(p_epoch_unix: float, p_span_seconds: float) -> void:
	epoch_unix = p_epoch_unix
	span_seconds = p_span_seconds
	now_unix = p_epoch_unix
	time_changed.emit(now_unix)

func _process(delta: float) -> void:
	if paused or span_seconds <= 0.0:
		return
	var rate := RATE_STEPS[clampi(rate_index, 0, RATE_STEPS.size() - 1)]
	if rate == 0.0:
		return
	# Wrap inside the precomputed span rather than clamping, so an unattended
	# loop runs forever without walking off the end of the buffer.
	now_unix = epoch_unix + fposmod(now_unix + delta * rate - epoch_unix, span_seconds)
	time_changed.emit(now_unix)

## 0 at the start of the propagated window, approaching 1 at the end, where the
## clock wraps and every position jumps back to its starting point. Exposed so
## the HUD can show the viewer where they are in that loop, rather than the
## jump just looking like a glitch.
func loop_progress() -> float:
	if span_seconds <= 0.0:
		return 0.0
	return fposmod(now_unix - epoch_unix, span_seconds) / span_seconds

func rate() -> float:
	return 0.0 if paused else RATE_STEPS[clampi(rate_index, 0, RATE_STEPS.size() - 1)]

func rate_label() -> String:
	if paused:
		return "PAUSED"
	var r := rate()
	if r == 0.0: return "STOPPED"
	if r < 60.0: return "%dx realtime" % int(r)
	return "%d min/sec" % int(r / 60.0)

func step_rate(dir: int) -> void:
	rate_index = clampi(rate_index + dir, 0, RATE_STEPS.size() - 1)

func utc_string() -> String:
	var d := Time.get_datetime_dict_from_unix_time(int(now_unix))
	return "%04d-%02d-%02d %02d:%02d:%02dZ" % [d.year, d.month, d.day, d.hour, d.minute, d.second]

## Julian Date (UT1 ~= UTC at our fidelity).
func julian_date() -> float:
	return now_unix / 86400.0 + 2440587.5

## Greenwich Mean Sidereal Time in radians, IAU-82.
## Mirrors gmst_rad() in tools/build_ephemeris.py -- keep the two in step.
func gmst() -> float:
	var t := (julian_date() - 2451545.0) / 36525.0
	var sec := 67310.54841 \
		+ (876600.0 * 3600.0 + 8640184.812866) * t \
		+ 0.093104 * t * t \
		- 6.2e-6 * t * t * t
	return fposmod(deg_to_rad(fposmod(sec, 86400.0) / 240.0), TAU)

## Unit vector toward the Sun in the same TEME-ish frame the satellites use,
## mapped to Godot axes. Low-precision solar position -- good to ~0.01 deg,
## far beyond what a terminator needs.
func sun_direction() -> Vector3:
	var n := julian_date() - 2451545.0
	var mean_long := deg_to_rad(fposmod(280.460 + 0.9856474 * n, 360.0))
	var mean_anom := deg_to_rad(fposmod(357.528 + 0.9856003 * n, 360.0))
	var ecl_long := mean_long + deg_to_rad(1.915 * sin(mean_anom) + 0.020 * sin(2.0 * mean_anom))
	var obliquity := deg_to_rad(23.439 - 0.0000004 * n)
	# ECI -> Godot: (x, z, -y). Same mapping as teme_to_godot() in the builder.
	var x := cos(ecl_long)
	var y := cos(obliquity) * sin(ecl_long)
	var z := sin(obliquity) * sin(ecl_long)
	return Vector3(x, z, -y).normalized()
