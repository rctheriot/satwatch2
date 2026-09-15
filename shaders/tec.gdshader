shader_type spatial;
// Total electron content, from NOAA SWPC GloTEC.
//
// Drawn on a shell at the F2 peak (~350 km), which is where the electron
// density that dominates the column integral actually sits, and above the
// auroral shell so the two layers stack in their real order.
//
// TEC is geographic, so this mesh is a child of the Earth and inherits the GMST
// rotation; the sun direction stays inertial because the dayside enhancement is
// a physical relationship, not a texture property.
render_mode blend_add, unshaded, cull_disabled, depth_draw_never, shadows_disabled;

uniform sampler2D tec_texture : hint_default_black, filter_linear;
uniform vec3 sun_direction = vec3(1.0, 0.0, 0.0);
uniform float altitude_re = 0.0549;      // ~350 km, the F2 peak
uniform float altitude_exaggeration = 2.0;
uniform float intensity : hint_range(0.0, 3.0) = 0.9;
// Below this fraction of full scale nothing is drawn, so the quiet night-side
// ionosphere does not wash a haze over the whole globe.
uniform float floor_fraction : hint_range(0.0, 0.5) = 0.06;

varying vec3 v_normal_local;

void vertex() {
	vec3 n = normalize(VERTEX);
	v_normal_local = n;
	VERTEX = n * (1.0 + altitude_re * altitude_exaggeration);
	NORMAL = n;
}

vec2 geo_uv(vec3 n) {
	float lon = atan(-n.z, n.x);
	float lat = asin(clamp(n.y, -1.0, 1.0));
	return vec2(fract(lon / (2.0 * PI) + 0.5), 0.5 - lat / PI);
}

// Sequential ramp, deliberately MONOTONIC IN LIGHTNESS: dark blue through cyan
// and yellow to near-white. TEC maps are conventionally blue-to-red, but a ramp
// that only varies in hue collapses for a colour-blind viewer and has no
// meaningful order in greyscale. Rising lightness keeps the ordering readable
// for everyone, while staying close enough to the convention to be familiar.
vec3 tec_ramp(float t) {
	vec3 c = mix(vec3(0.05, 0.10, 0.45), vec3(0.10, 0.55, 0.85),
		smoothstep(0.0, 0.35, t));
	c = mix(c, vec3(0.30, 0.90, 0.70), smoothstep(0.30, 0.58, t));
	c = mix(c, vec3(0.95, 0.90, 0.35), smoothstep(0.55, 0.80, t));
	c = mix(c, vec3(1.00, 0.72, 0.62), smoothstep(0.78, 1.00, t));
	return c;
}

void fragment() {
	float t = texture(tec_texture, geo_uv(normalize(v_normal_local))).r;
	if (t < floor_fraction) discard;

	// Fade at grazing angles rather than brightening: this is a column
	// quantity, and a limb-brightened shell would imply the opposite of what
	// the number means.
	float facing = abs(dot(normalize(VIEW), normalize(NORMAL)));
	float a = smoothstep(0.0, 0.35, facing);

	float scaled = (t - floor_fraction) / max(1.0 - floor_fraction, 0.001);
	ALBEDO = tec_ramp(scaled) * scaled * a * intensity;
	ALPHA = 1.0;
}
