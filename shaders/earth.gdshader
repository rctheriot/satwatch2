shader_type spatial;
// Day/night Earth with a real terminator.
//
// The mesh is yawed by GMST(t) from SimClock so that satellites -- which stay in
// TEME, SGP4's native frame -- pass over the correct ground. Rotating the globe
// instead of converting every satellite to ECEF is both cheaper and more
// accurate: it sidesteps nutation and polar motion (sub-km, invisible here).
//
// UNSHADED is deliberate. This shader already computes the sun term itself, so
// letting the engine's lighting multiply the result again darkens the lit side
// toward black and destroys the terminator. Everything below -- diffuse falloff,
// the ocean highlight, the rim -- is computed here from sun_direction so there
// is exactly one source of truth for where the sun is.
render_mode cull_back, unshaded;

uniform sampler2D day_texture : source_color, filter_linear_mipmap, hint_default_white;
uniform sampler2D night_texture : source_color, filter_linear_mipmap, hint_default_black;
uniform sampler2D ocean_mask : hint_default_black, filter_linear_mipmap;

uniform vec3 sun_direction = vec3(1.0, 0.0, 0.0);
uniform float day_gain : hint_range(0.0, 3.0) = 1.15;
uniform float night_gain : hint_range(0.0, 4.0) = 1.35;
uniform float terminator_softness : hint_range(0.005, 0.5) = 0.10;
// Minimum brightness on the LIT hemisphere at grazing sun angle, as a
// fraction of full Lambertian. Not a night-side term -- the night side gets
// none of this, on purpose (see fragment()).
uniform float ambient_floor : hint_range(0.0, 0.3) = 0.02;
uniform float ocean_specular : hint_range(0.0, 2.0) = 0.6;
// Calibration only. The UV mapping below is derived, not guessed, so this
// should stay 0; it exists so a texture that is not exactly centred on the
// prime meridian can be nudged without touching code.
uniform float longitude_offset_deg : hint_range(-180.0, 180.0) = 0.0;

// Atmospheric limb haze, keyed to VIEW angle rather than sun angle -- this is
// the cue that actually reads as "sphere" rather than "lit disc". The sun
// terminator only shows curvature along one axis; grazing-view haze shows it
// all the way around the silhouette regardless of where the sun is, which is
// closer to why a real photo of Earth looks round even in full daylight.
uniform vec3 haze_color : source_color = vec3(0.55, 0.68, 0.88);
uniform float haze_intensity : hint_range(0.0, 1.0) = 0.3;
uniform float haze_power : hint_range(1.0, 8.0) = 4.5;

varying vec3 v_normal_world;
varying vec3 v_normal_local;
varying vec3 v_world_pos;

void vertex() {
	v_normal_world = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	v_normal_local = normalize(NORMAL);
	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

// Equirectangular UV derived from the MESH-LOCAL normal.
//
// SphereMesh's own UV origin is an engine convention, not a documented
// geographic one, so trusting it puts every continent at a constant unknown
// longitude offset -- which still looks completely plausible, because the globe
// is round and the terminator is in the right shape, just over the wrong ocean.
// Deriving UV here instead pins the mapping to a frame we control:
//
//   ECEF +X (lat 0, lon 0)    -> local (1, 0, 0)
//   ECEF +Z (north pole)      -> local (0, 1, 0)
//   ECEF +Y (lat 0, lon 90E)  -> local (0, 0, -1)
//
// which is the same (x, z, -y) mapping the ephemeris builder applies to TEME,
// so satellites and ground agree by construction. The mesh is then yawed by
// GMST(t), which carries local +X to right ascension GMST -- exactly the
// definition of Greenwich sidereal time.
vec2 geo_uv(vec3 n) {
	float lon = atan(-n.z, n.x) + radians(longitude_offset_deg);
	float lat = asin(clamp(n.y, -1.0, 1.0));
	return vec2(fract(lon / (2.0 * PI) + 0.5), 0.5 - lat / PI);
}

void fragment() {
	vec3 n = normalize(v_normal_world);
	vec3 l = normalize(sun_direction);
	float cos_sun = dot(n, l);

	// Softened terminator: the real one is blurred by atmospheric scattering
	// over roughly a degree of arc, and a hard step reads as a CG artefact.
	float day = smoothstep(-terminator_softness, terminator_softness, cos_sun);
	// Lambert falloff across the lit hemisphere, so the subsolar point is
	// brightest and the limb falls off rather than being uniformly flat.
	float lambert = max(cos_sun, 0.0);

	vec2 uv = geo_uv(normalize(v_normal_local));
	vec3 day_c = texture(day_texture, uv).rgb * day_gain;
	vec3 night_c = texture(night_texture, uv).rgb * night_gain;

	// Real Earth falls off close to true Lambertian toward the limb -- the
	// old 0.25 floor here kept the whole day side near-uniformly bright and
	// was most of why the globe read as flat/ambient-lit.
	vec3 lit = day_c * (ambient_floor + (1.0 - ambient_floor) * lambert);
	// City lights fade in through the terminator and never show on the lit side.
	// Nothing is added on the night side beyond night_c: any day-texture bleed
	// there reads as the "whole earth ambiently lit" look this replaces.
	vec3 color = mix(night_c, lit, day);

	vec3 view = normalize(v_world_pos - CAMERA_POSITION_WORLD);

	// Ocean highlight. Falls back to matte everywhere when no mask is supplied
	// (hint_default_black), which is the current state -- see assets/README.md.
	float ocean = texture(ocean_mask, uv).r;
	if (ocean > 0.001 && day > 0.0) {
		vec3 refl = reflect(l, n);
		float spec = pow(max(dot(normalize(refl), view), 0.0), 48.0);
		color += vec3(spec * ocean * ocean_specular * day);
	}

	// Limb haze -- see the uniform comment above for why this is keyed to
	// view angle, not sun angle. Near-zero on the night limb on purpose: the
	// dark side is supposed to read as genuinely dark, and even a small
	// blend here showed up as the whole silhouette looking faintly lit
	// rather than just the day side.
	float fresnel = pow(1.0 - clamp(abs(dot(n, view)), 0.0, 1.0), haze_power);
	color = mix(color, haze_color, fresnel * haze_intensity * mix(0.02, 1.0, day));

	ALBEDO = color;
}
