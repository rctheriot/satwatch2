shader_type spatial;
// Auroral oval from the NOAA SWPC OVATION model.
//
// Drawn as a shell ABOVE the surface rather than painted on it. That is both
// more truthful -- the emission really is at ~100-250 km -- and better on a
// stereo wall, because the shell carries its own disparity and reads as a
// luminous curtain standing off the limb instead of a decal on the globe.
//
// The texture is in GEOGRAPHIC coordinates, so this mesh is a child of the
// Earth and inherits its GMST rotation. Sun direction stays inertial and is
// compared against the world normal, because the night-side test is a physical
// one and must not rotate with the Earth.
render_mode blend_add, unshaded, cull_disabled, depth_draw_never, shadows_disabled;

uniform sampler2D aurora_texture : hint_default_black, filter_linear;
uniform vec3 sun_direction = vec3(1.0, 0.0, 0.0);
// Emission altitude in Earth radii (~120 km), scaled by the same exaggeration
// the satellite field uses so the two layers stay consistent with each other.
uniform float altitude_re = 0.0188;
uniform float altitude_exaggeration = 2.0;
uniform float intensity : hint_range(0.0, 4.0) = 1.5;
uniform vec3 low_color : source_color = vec3(0.22, 1.0, 0.55);   // 557.7 nm
uniform vec3 high_color : source_color = vec3(1.0, 0.25, 0.42);  // 630.0 nm
uniform float terminator_softness : hint_range(0.01, 0.6) = 0.22;

varying vec3 v_normal_world;
varying vec3 v_normal_local;

void vertex() {
	vec3 n = normalize(VERTEX);
	v_normal_local = n;
	VERTEX = n * (1.0 + altitude_re * altitude_exaggeration);
	v_normal_world = normalize((MODEL_MATRIX * vec4(n, 0.0)).xyz);
	NORMAL = n;
}

// Same derivation as earth.gdshader's geo_uv, so the oval lands on the same
// ground the imagery shows.
vec2 geo_uv(vec3 n) {
	float lon = atan(-n.z, n.x);
	float lat = asin(clamp(n.y, -1.0, 1.0));
	return vec2(fract(lon / (2.0 * PI) + 0.5), 0.5 - lat / PI);
}

void fragment() {
	float prob = texture(aurora_texture, geo_uv(normalize(v_normal_local))).r;
	if (prob < 0.004) discard;

	// Only on the night side -- aurora is invisible against a sunlit surface.
	float cos_sun = dot(normalize(v_normal_world), normalize(sun_direction));
	float night = 1.0 - smoothstep(-terminator_softness, terminator_softness, cos_sun);
	if (night < 0.004) discard;

	// Limb brightening: seen edge-on the line of sight crosses far more of the
	// emitting layer, which is why the oval reads as a curtain from orbit.
	float grazing = 1.0 - abs(dot(normalize(VIEW), normalize(NORMAL)));
	float limb = 1.0 + 2.2 * pow(grazing, 3.0);

	// Strong aurora develops red tops above the green; ramping colour with
	// intensity reproduces that without needing a second shell.
	vec3 c = mix(low_color, high_color, smoothstep(0.45, 0.95, prob));
	ALBEDO = c * prob * night * limb * intensity;
	ALPHA = 1.0;
}
