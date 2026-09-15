shader_type spatial;
// Rim glow on a slightly enlarged inverted sphere.
//
// Drawn with front faces culled so we see the inside of the shell, additively,
// with no depth write. depth_draw_never matters in stereo: an additive shell
// that writes depth would occlude satellites between the globe and the viewer
// in one eye before the other and read as flicker rather than as haze.
render_mode blend_add, unshaded, cull_front, depth_draw_never, shadows_disabled;

uniform vec3 rim_color : source_color = vec3(0.32, 0.60, 1.0);
uniform vec3 sun_direction = vec3(1.0, 0.0, 0.0);
uniform float rim_power : hint_range(0.5, 8.0) = 2.6;
uniform float intensity : hint_range(0.0, 3.0) = 0.85;

varying vec3 v_normal_world;

void vertex() {
	v_normal_world = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 n = normalize(v_normal_world);
	// NORMAL points inward on a cull_front shell, so the grazing angle is where
	// the view direction is most perpendicular to it.
	float rim = pow(1.0 - abs(dot(normalize(VIEW), normalize(NORMAL))), rim_power);
	// Only the sunlit limb glows.
	float lit = smoothstep(-0.35, 0.25, dot(n, normalize(sun_direction)));
	ALBEDO = rim_color * rim * intensity * lit;
	ALPHA = 1.0;
}
