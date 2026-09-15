shader_type spatial;
// Camera-facing ribbons for recent aircraft tracks.
//
// One MultiMesh instance per aircraft. The instance transform carries the
// segment rather than a rotation: the translation is where the trail starts and
// the basis X column is the vector to where the aircraft is now. The vertex
// shader sweeps along that and offsets perpendicular to both the segment and
// the view direction, so the ribbon always faces the viewer whatever angle the
// globe is turned to.
//
// A ribbon rather than a line primitive because 1-pixel lines shimmer as they
// move, and in stereo the two eyes disagree about which pixels are lit -- that
// reads as retinal rivalry rather than as depth.
render_mode blend_add, unshaded, cull_disabled, depth_draw_never, shadows_disabled;

uniform vec4 trail_color : source_color = vec4(0.72, 0.45, 1.0, 1.0);
uniform float width_pixels : hint_range(0.5, 6.0) = 2.2;
uniform float brightness : hint_range(0.0, 3.0) = 1.15;

varying float v_along;

void vertex() {
	// QuadMesh spans -0.5..0.5; remap to 0 (tail) .. 1 (aircraft).
	float t = VERTEX.x + 0.5;
	v_along = t;

	vec3 start = MODEL_MATRIX[3].xyz;
	vec3 seg = MODEL_MATRIX[0].xyz;
	vec3 p = start + seg * t;

	vec3 eye = INV_VIEW_MATRIX[3].xyz;
	vec3 to_eye = eye - p;
	float depth = max(length(to_eye), 0.0001);
	vec3 dir = length(seg) > 1e-9 ? normalize(seg) : vec3(0.0, 1.0, 0.0);
	vec3 side = cross(dir, to_eye / depth);
	float side_len = length(side);
	// Degenerate when the segment points straight at the viewer; any
	// perpendicular will do, and the ribbon is edge-on anyway.
	side = side_len > 1e-6 ? side / side_len : vec3(0.0, 1.0, 0.0);

	// Constant width in pixels, so trails neither vanish when zoomed out nor
	// turn into slabs when zoomed in.
	float px_per_world = PROJECTION_MATRIX[0][0] * VIEWPORT_SIZE.x * 0.5 / depth;
	float half_width = (width_pixels / max(px_per_world, 0.0001)) * 0.5;

	p += side * half_width * VERTEX.y * 2.0;
	POSITION = PROJECTION_MATRIX * (VIEW_MATRIX * vec4(p, 1.0));
}

void fragment() {
	// Fade toward the tail: the track is a history, and it should read as one.
	// Square-rooted rather than squared -- the squared falloff put most of the
	// trail's length below the visible threshold at the default framing, so the
	// tracks only appeared once you had already zoomed in.
	float a = sqrt(v_along);
	ALBEDO = trail_color.rgb * brightness * a;
	ALPHA = trail_color.a * a;
}
