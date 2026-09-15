shader_type spatial;
// Streamlines through the 250 hPa wind field.
//
// Same camera-facing ribbon construction as the flight trails: the instance
// transform carries the segment (translation = tail, basis X = vector to head)
// rather than a rotation, and the ribbon is offset perpendicular to both the
// segment and the view direction so it faces the viewer from any angle.
//
// Coloured by SPEED rather than a flat colour, because speed is the whole point
// of a jet stream map -- a streamline that only shows direction throws away the
// quantity a flight planner actually cares about.
render_mode blend_add, unshaded, cull_disabled, depth_draw_never, shadows_disabled;

uniform float width_pixels : hint_range(0.5, 8.0) = 2.4;
uniform float brightness : hint_range(0.0, 3.0) = 1.0;
// Segment length, in world units, corresponding to SPEED_FULL_SCALE_MS. Set by
// main.gd from the trail interval and the rig scale.
//
// Pinned to a fixed speed rather than the field's own peak, for the same reason
// the TEC scale is fixed: auto-scaling redefines what a colour means between
// fetches, so a calm day and a stormy one look identical and the viewer cannot
// compare them. 65 m/s puts the ramp's thresholds on meanings a forecaster
// would recognise -- a jet stream is conventionally 30 m/s and up.
uniform float speed_full_scale = 0.35;

varying float v_along;
varying float v_speed;

// Monotonic in lightness, so the ordering survives greyscale and colour-blind
// viewing: deep violet (calm) through magenta and orange to near-white.
//
// The stops sit at meaningful speeds against a 65 m/s full scale, not at even
// fractions: ~15 m/s where flow becomes organised, 30 m/s where a jet stream is
// conventionally declared, and 50 m/s where a core is worth routing around.
// That is why most of the field reads violet-magenta and only the cores go
// bright -- the colour is saying something, not just filling the ramp.
vec3 speed_ramp(float t) {
	vec3 c = mix(vec3(0.20, 0.09, 0.42), vec3(0.58, 0.18, 0.78),
		smoothstep(0.0, 0.23, t));                       // to ~15 m/s
	c = mix(c, vec3(1.00, 0.38, 0.52), smoothstep(0.20, 0.46, t));  // to ~30
	c = mix(c, vec3(1.00, 0.72, 0.30), smoothstep(0.44, 0.77, t));  // to ~50
	c = mix(c, vec3(1.00, 0.99, 0.94), smoothstep(0.74, 1.0, t));   // core
	return c;
}

void vertex() {
	float t = VERTEX.x + 0.5;            // 0 at the tail, 1 at the particle
	v_along = t;

	vec3 start = MODEL_MATRIX[3].xyz;
	vec3 seg = MODEL_MATRIX[0].xyz;
	v_speed = clamp(length(seg) / max(speed_full_scale, 1e-6), 0.0, 1.0);

	vec3 p = start + seg * t;
	vec3 eye = INV_VIEW_MATRIX[3].xyz;
	vec3 to_eye = eye - p;
	float depth = max(length(to_eye), 0.0001);
	vec3 dir = length(seg) > 1e-9 ? normalize(seg) : vec3(0.0, 1.0, 0.0);
	vec3 side = cross(dir, to_eye / depth);
	float side_len = length(side);
	side = side_len > 1e-6 ? side / side_len : vec3(0.0, 1.0, 0.0);

	// Constant pixel width, as everywhere else: sub-pixel geometry shimmers,
	// and in stereo the two eyes disagree about which pixels are lit.
	float px_per_world = PROJECTION_MATRIX[0][0] * VIEWPORT_SIZE.x * 0.5 / depth;
	float half_width = (width_pixels / max(px_per_world, 0.0001)) * 0.5;

	p += side * half_width * VERTEX.y * 2.0;
	POSITION = PROJECTION_MATRIX * (VIEW_MATRIX * vec4(p, 1.0));
}

void fragment() {
	// Taper to nothing at the tail so streamlines read as having direction.
	float a = v_along * v_along;
	ALBEDO = speed_ramp(v_speed) * brightness * a;
	ALPHA = a;
}
