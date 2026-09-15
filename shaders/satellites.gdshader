shader_type spatial;
// Additive billboarded points for the catalog.
//
// render_mode notes for the wall:
//  - unshaded: these are markers, not lit objects.
//  - cull_disabled + depth_draw_never: additive sprites must not occlude each
//    other or write depth, or the field flickers as instances sort differently
//    between the two eyes -- which reads as retinal rivalry, not as depth.
render_mode blend_add, unshaded, cull_disabled, depth_draw_never, shadows_disabled;

uniform vec4 leo_color : source_color = vec4(0.36, 0.78, 1.00, 1.0);
uniform vec4 meo_color : source_color = vec4(0.55, 1.00, 0.62, 1.0);
uniform vec4 geo_color : source_color = vec4(1.00, 0.78, 0.31, 1.0);
uniform vec4 heo_color : source_color = vec4(1.00, 0.45, 0.55, 1.0);
uniform float brightness : hint_range(0.0, 4.0) = 1.20;
uniform float rig_scale = 1.0;
// How much of the rig's zoom the point size resists. 0 = points shrink with the
// rig and go sub-pixel when we pull back to the GEO view; 1 = points hold a
// constant WORLD size, which at the GEO view makes 20k LEO points merge into a
// solid additive disc that washes the globe out to white. Partial compensation
// keeps them visible without letting them fuse.
uniform float zoom_compensation : hint_range(0.0, 1.0) = 0.55;

varying flat vec4 v_color;

vec4 regime_color(float id) {
	if (id < 0.5) return leo_color;
	if (id < 1.5) return meo_color;
	if (id < 2.5) return geo_color;
	return heo_color;
}

void vertex() {
	float regime = INSTANCE_CUSTOM.x;
	float highlight = INSTANCE_CUSTOM.y;
	float size = INSTANCE_CUSTOM.z;

	v_color = regime_color(regime);
	v_color.a *= highlight;

	// Billboard in view space. Size is in WORLD units, deliberately not screen
	// pixels: a screen-constant sprite carries no disparity cue and fights the
	// stereo depth of the point it marks.
	vec3 center_view = (MODELVIEW_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	float s = size * pow(max(rig_scale, 0.0001), -zoom_compensation);
	POSITION = PROJECTION_MATRIX * vec4(center_view + vec3(VERTEX.xy * s, 0.0), 1.0);
}

void fragment() {
	// Soft round falloff -- a hard-edged quad aliases badly at this pixel count.
	float d = length(UV - vec2(0.5));
	float a = smoothstep(0.5, 0.06, d);
	if (a < 0.004) discard;
	ALBEDO = v_color.rgb * brightness;
	ALPHA = a * v_color.a;
}
