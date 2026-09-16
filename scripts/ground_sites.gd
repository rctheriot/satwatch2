class_name GroundSites
extends RefCounted
## Space Surveillance Network sites and the geometry of what they can see.
##
## WHAT IS COMPUTED AND WHAT IS NOT -- the distinction decides what this display
## may honestly claim:
##
##   Geometric visibility IS exact and needs no sensor specifications. Given a
##   site's coordinates and an object's position, whether it sits above the
##   local horizon past an elevation mask is pure geometry. So are the extra
##   constraints on optical sites: the site must be in darkness while the target
##   is still sunlit. Those follow from the sun vector we already have.
##
##   Detection capability is NOT computable. It depends on transmit power,
##   aperture, wavelength and target radar cross-section or albedo, none of
##   which is public for these sensors. Every range here is therefore a NOMINAL
##   figure chosen to represent the class of sensor, labelled as such on screen,
##   and must never be presented as real performance.
##
## Site locations are from open sources; they are not secret. Sensor types and
## roles are likewise publicly documented at this level of detail.

enum Kind { RADAR, OPTICAL }

## name, latitude, longitude, kind, nominal range (km), elevation mask (deg)
const SITES: Array = [
	["Eglin AFB, FL",          30.57,  -86.21, Kind.RADAR,    5500.0,  3.0],
	["Cavalier SFS, ND",       48.72,  -97.90, Kind.RADAR,    3300.0,  2.0],
	["Clear SFS, AK",          64.29, -149.19, Kind.RADAR,    4800.0,  3.0],
	["Pituffik, Greenland",    76.57,  -68.30, Kind.RADAR,    4800.0,  3.0],
	["RAF Fylingdales, UK",    54.36,   -0.67, Kind.RADAR,    4800.0,  3.0],
	["Cobra Dane, Shemya AK",  52.74,  174.09, Kind.RADAR,    3200.0,  3.0],
	["Beale AFB, CA",          39.14, -121.35, Kind.RADAR,    5500.0,  3.0],
	["Cape Cod SFS, MA",       41.75,  -70.54, Kind.RADAR,    5500.0,  3.0],
	["Space Fence, Kwajalein",  9.40,  167.48, Kind.RADAR,    5500.0,  5.0],
	["ALTAIR, Kwajalein",       8.72,  167.73, Kind.RADAR,    4000.0,  5.0],
	["Globus II, Vardo, NO",   70.37,   31.13, Kind.RADAR,    4000.0,  3.0],
]
## The optical (GEODSS) sites this list used to carry -- Socorro NM, Diego
## Garcia, Maui HI, Ascension Island -- were removed from the demo entirely
## rather than filtered at render time: they need a separate darkness
## constraint that read as a confusing "why is this one blank" state to a
## general audience, and the radar coverage alone already carries the chapter.
## Kind.OPTICAL and every branch that handles it are left in place, unused,
## in case that changes.

const RE_KM := 6378.137

## Unit vector to a site in the Earth-fixed frame, on Godot axes.
##
## Uses the same convention as earth.gdshader's geo_uv and the ephemeris
## builder: ECEF +X at (0 lat, 0 lon) maps to Godot (1, 0, 0), the north pole to
## (0, 1, 0), and 90E to (0, 0, -1). Anything else puts every site in the wrong
## hemisphere while still looking like a plausible globe.
static func site_up(lat_deg: float, lon_deg: float) -> Vector3:
	var lat := deg_to_rad(lat_deg)
	var lon := deg_to_rad(lon_deg)
	return Vector3(cos(lat) * cos(lon), sin(lat), -cos(lat) * sin(lon))

## Is a point at `p` (Earth radii, Earth-fixed) at or above `mask_deg` elevation
## as seen from the site at unit vector `up`?
##
## Derivation, with r = |p|, d = p . up, and c = d/r the cosine of the
## geocentric angle between site and object:
##
##     tan(elev) = (c - 1/r) / sqrt(1 - c^2)
##              = ((d - 1)/r) / (sqrt(r^2 - d^2)/r)
##              = (d - 1) / sqrt(r^2 - d^2)
##
## so elev >= mask, given d > 1, is exactly  (d - 1)^2 >= t^2 (r^2 - d^2).
##
## The radius cancels and the square root goes with it. Nothing here needs a
## sqrt or even |p|, which matters: this runs for every object against every
## site, and the earlier form -- two sqrts and a function call per pair -- cost
## about 24 ms a frame and dropped the surveillance chapter to 30 fps.
##
## SensorNetwork inlines this same arithmetic in its hot loop; GDScript call
## overhead alone is significant at 70,000 evaluations per frame. Keep the two
## in step -- tests/verify_sensors.gd checks this one against direct geometry.
static func is_visible(p: Vector3, up: Vector3, tan_mask: float) -> bool:
	var d := p.dot(up)
	if d <= 1.0:
		return false                       # at or below the local horizon
	var e := d - 1.0
	return e * e >= tan_mask * tan_mask * (p.length_squared() - d * d)

## Is an object in sunlight? Cylindrical umbra approximation: behind the Earth
## relative to the sun, and within one Earth radius of the Earth-sun axis.
## Ignores the penumbra, which is a fraction of a degree -- invisible here.
static func is_sunlit(p: Vector3, sun: Vector3) -> bool:
	var along := p.dot(sun)
	if along >= 0.0:
		return true                        # sunward side, always lit
	# Perpendicular distance from the Earth-sun axis, compared squared.
	return p.length_squared() - along * along > 1.0

## Sun elevation at a site, in degrees. Optical sites need real darkness, not
## merely night: astronomical twilight is about -18, and nothing useful happens
## against a bright sky.
static func sun_elevation_deg(up: Vector3, sun: Vector3) -> float:
	return rad_to_deg(asin(clampf(up.dot(sun), -1.0, 1.0)))
