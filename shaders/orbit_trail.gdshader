shader_type spatial;
// Camera-facing ribbons tracing one full orbital period per object.
//
// Same construction as flight_trail.gdshader and wind_trail.gdshader: one
// MultiMesh instance per SEGMENT (not per object), the instance transform
// carries the segment itself -- translation is the segment's start, the
// basis X column is the vector to its end -- and the vertex shader sweeps
// along that and offsets perpendicular to both the segment and the view
// direction, so every ribbon faces the viewer regardless of how the globe is
// turned. A ribbon rather than a 1px line for the same reason as those two:
// hairline geometry shimmers and disagrees between stereo eyes.
//
// No fade-to-tail here, unlike a history trail -- this is a closed loop with
// no head or tail, just dimmer than the satellite dots so it reads as a
// guide rather than competing with them.
//
// ALPHA blend, not additive: hundreds of ellipses share a perigee region by
// definition (every HEO path passes near Earth), so additive summed that
// crowd to a blown-out white disc and buried the shape it was meant to show.
// Alpha blend still shows the crowding -- it just saturates at the trail
// colour instead of past it, which keeps individual loops legible at the
// edges where they are not overlapping.
render_mode blend_mix, unshaded, cull_disabled, depth_draw_never, shadows_disabled;

uniform vec4 trail_color : source_color = vec4(0.55, 0.68, 0.95, 0.16);
uniform float width_pixels : hint_range(0.5, 6.0) = 1.4;
uniform float brightness : hint_range(0.0, 3.0) = 1.0;

void vertex() {
	float t = VERTEX.x + 0.5;      // 0 at segment start, 1 at segment end

	vec3 start = MODEL_MATRIX[3].xyz;
	vec3 seg = MODEL_MATRIX[0].xyz;
	vec3 p = start + seg * t;

	vec3 eye = INV_VIEW_MATRIX[3].xyz;
	vec3 to_eye = eye - p;
	float depth = max(length(to_eye), 0.0001);
	vec3 dir = length(seg) > 1e-9 ? normalize(seg) : vec3(0.0, 1.0, 0.0);
	vec3 side = cross(dir, to_eye / depth);
	float side_len = length(side);
	side = side_len > 1e-6 ? side / side_len : vec3(0.0, 1.0, 0.0);

	// Constant width in pixels, as everywhere else this technique is used.
	float px_per_world = PROJECTION_MATRIX[0][0] * VIEWPORT_SIZE.x * 0.5 / depth;
	float half_width = (width_pixels / max(px_per_world, 0.0001)) * 0.5;

	p += side * half_width * VERTEX.y * 2.0;
	POSITION = PROJECTION_MATRIX * (VIEW_MATRIX * vec4(p, 1.0));
}

void fragment() {
	ALBEDO = trail_color.rgb * brightness;
	ALPHA = trail_color.a;
}
