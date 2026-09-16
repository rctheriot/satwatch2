shader_type spatial;
// Thin cloud shell just above the Earth surface. Same day/night logic as
// earth.gdshader (recomputed here rather than shared, since this is the only
// other place it's needed) so the terminator on the clouds lines up exactly
// with the terminator on the ground beneath them.
//
// UNSHADED for the same reason as earth.gdshader: the sun term is computed by
// hand from sun_direction, and letting the engine light this too would double
// it and crush the terminator.
render_mode cull_back, unshaded, blend_mix;

uniform sampler2D cloud_texture : source_color, filter_linear_mipmap, hint_default_black;

uniform vec3 sun_direction = vec3(1.0, 0.0, 0.0);
uniform float terminator_softness : hint_range(0.005, 0.5) = 0.14;
// Real cloud tops are near-white in daylight and, absent moonlight, close to
// black on the night side -- they read as an absence of city lights below
// rather than as their own visible shape.
uniform float day_brightness : hint_range(0.0, 2.0) = 1.0;
uniform float night_brightness : hint_range(0.0, 0.3) = 0.03;
uniform float opacity : hint_range(0.0, 1.0) = 0.55;
// Longitude slip relative to the ground, in radians, set from main.gd as
// clock.gmst() * a small fraction. Driving it from the SAME clock that spins
// the globe (rather than the engine's real wall-clock TIME) matters: this
// mesh is a child of EarthMesh and already co-rotates with the ground
// perfectly, so TIME-based drift only reads as motion when sim time runs
// near real-time. Any time acceleration -- which most chapters use -- made
// the globe spin far faster than that real-time drift, so the clouds looked
// welded to the continents instead of sliding across them.
uniform float drift_angle = 0.0;
uniform float longitude_offset_deg : hint_range(-180.0, 180.0) = 0.0;

varying vec3 v_normal_world;
varying vec3 v_normal_local;

void vertex() {
	v_normal_world = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	v_normal_local = normalize(NORMAL);
}

// Same derivation as earth.gdshader's geo_uv() -- must match exactly so cloud
// features track the same ground they were photographed over.
vec2 geo_uv(vec3 n) {
	float lon = atan(-n.z, n.x) + radians(longitude_offset_deg);
	float lat = asin(clamp(n.y, -1.0, 1.0));
	return vec2(fract(lon / (2.0 * PI) + 0.5), 0.5 - lat / PI);
}

void fragment() {
	vec3 n = normalize(v_normal_world);
	float cos_sun = dot(n, normalize(sun_direction));
	float day = smoothstep(-terminator_softness, terminator_softness, cos_sun);

	vec2 uv = geo_uv(normalize(v_normal_local));
	uv.x = fract(uv.x + drift_angle / (2.0 * PI));
	float density = texture(cloud_texture, uv).r;

	float brightness = mix(night_brightness, day_brightness, day);
	ALBEDO = vec3(density * brightness);
	ALPHA = density * opacity;
}
