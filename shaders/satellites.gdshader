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
// Highlighted objects get their own colour rather than just more brightness.
// A debris cloud picked out only by alpha stays the same hue as the 14,745
// objects around it, so finding it means hunting for slightly brighter dots.
// Set per chapter -- red for breakup debris, green for a constellation.
uniform vec4 highlight_color : source_color = vec4(1.00, 0.28, 0.24, 1.0);
uniform float highlight_size_boost : hint_range(1.0, 3.0) = 1.45;
// Colour for everything NOT highlighted, when alpha > 0. Used where the
// un-highlighted state carries meaning of its own rather than being backdrop:
// in the surveillance chapter, red means no ground site can currently see it,
// which is exactly as informative as green meaning one can.
uniform vec4 base_color_override : source_color = vec4(0.0);
uniform float brightness : hint_range(0.0, 4.0) = 1.20;

// Points are sized in SCREEN space, not world space.
//
// They used to carry a world size scaled by pow(content_scale, -k), which was
// tuned when the camera was parked and only the content scaled. Now the camera
// moves too, so the two compound: the LEO chapters (large content scale, close
// camera) came out at 0.70 px against 1.20 px for the full-catalog view, and
// after the sub-pixel alpha compensation they were drawn at 0.17 alpha against
// 0.50 -- three times dimmer, for no reason a viewer could see.
//
// Targeting a pixel size directly makes visibility uniform across chapters by
// construction, and the per-chapter and per-regime multipliers then mean what
// they say instead of fighting the framing.
uniform float point_pixels : hint_range(0.5, 8.0) = 2.8;
// How much true perspective shrink to keep. 0 = flat screen-space sprites,
// which throws away a monocular depth cue that should agree with disparity;
// 1 = full perspective, which is what put the LEO chapters sub-pixel. Partial
// keeps nearer objects visibly larger without losing them.
uniform float depth_cue : hint_range(0.0, 1.0) = 0.30;
// Distance from the eye to the content centre; the size target is honoured
// there and perspective modulates around it. Set per frame by main.gd.
uniform float reference_depth = 4.5;
// Below about a pixel a point lands on a sample or misses it depending on
// sub-pixel position, so the field blinks as it moves -- and the two eyes blink
// INDEPENDENTLY, which is retinal rivalry rather than depth.
uniform float min_pixel_size : hint_range(0.0, 6.0) = 1.6;
// Floor on the fade applied when the minimum size forces a point larger than
// perspective wants. Energy-exact would be much darker, but this is a marker,
// not a photometric simulation, and legibility wins.
uniform float faint_alpha_floor : hint_range(0.0, 1.0) = 0.55;
// Set by main.gd across the ephemeris loop seam, where every object's
// position would otherwise pop to its window-start point in one frame. A
// brief fade through 0 there reads as a cut, not a glitch.
uniform float wrap_fade : hint_range(0.0, 1.0) = 1.0;

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
	float size_mult = INSTANCE_CUSTOM.z;
	float jitter = INSTANCE_CUSTOM.w;

	// Negative marks a highlighted object; see SatelliteField.set_highlight().
	bool is_highlighted = highlight < 0.0;
	vec4 base = base_color_override.a > 0.0
		? base_color_override : regime_color(regime);
	v_color = is_highlighted ? highlight_color : base;
	v_color.a *= abs(highlight);
	if (is_highlighted) {
		size_mult *= highlight_size_boost;
	}

	// Per-object size and brightness variation. See SatelliteField._jitter():
	// this breaks the wallpaper condition, where a dense field of
	// interchangeable points lets each eye pair with the wrong partner.
	// Size and brightness are deliberately CORRELATED -- it reads as a natural
	// magnitude spread and makes each point more distinct than either alone.
	size_mult *= mix(0.72, 1.34, jitter);
	v_color.a *= mix(0.62, 1.30, jitter);

	vec3 center_view = (MODELVIEW_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	float depth = max(-center_view.z, 0.0001);

	// World metres per pixel at this depth. PROJECTION_MATRIX[0][0] is the
	// horizontal NDC-per-view ratio, so world -> pixels is that times half the
	// viewport width, over depth.
	float px_per_world = PROJECTION_MATRIX[0][0] * VIEWPORT_SIZE.x * 0.5 / depth;

	float px_target = point_pixels * size_mult
		* pow(reference_depth / depth, depth_cue);
	float px_draw = max(px_target, min_pixel_size);
	if (px_draw > px_target) {
		v_color.a *= clamp(px_target / px_draw, faint_alpha_floor, 1.0);
	}
	float s = px_draw / max(px_per_world, 0.0001);

	// Billboard in view space.
	POSITION = PROJECTION_MATRIX * vec4(center_view + vec3(VERTEX.xy * s, 0.0), 1.0);
}

void fragment() {
	// Soft round falloff -- a hard-edged quad aliases badly at this pixel count.
	float d = length(UV - vec2(0.5));
	float a = smoothstep(0.5, 0.06, d);
	if (a < 0.004) discard;
	ALBEDO = v_color.rgb * brightness;
	ALPHA = a * v_color.a * wrap_fade;
}
