shader_type sky;
// Procedural starfield.
//
// A sky sits at infinity, so it carries zero disparity and fuses effortlessly --
// it gives the eyes a stable backdrop to reference the orbital shells against.
//
// Stars are placed in CELL-LOCAL space: quantise the view direction into a grid,
// pick one candidate position inside the cell, and measure distance to it in the
// cell's own fractional coordinates. Comparing against a normalised cell centre
// instead (the obvious-looking version) warps wildly with direction and smears
// stars into large facets rather than points.
//
// Deliberately dim: at 15.5 Mpix a bright field competes with the satellites,
// which are the actual subject.

uniform float density : hint_range(8.0, 400.0) = 140.0;
uniform float brightness : hint_range(0.0, 2.0) = 0.85;
uniform float coverage : hint_range(0.0, 0.2) = 0.045;
uniform float star_size : hint_range(0.02, 0.5) = 0.13;
uniform vec3 space_tint : source_color = vec3(0.008, 0.011, 0.022);
// Inverse of the content rig's rotation. Sampling through it pins the stars to
// the inertial frame, so orbiting the globe sweeps the starfield past exactly as
// moving the camera would. Without it the stars sit fixed while the Earth turns,
// which is the giveaway that the content is rotating rather than the viewer.
uniform mat3 frame_inverse = mat3(1.0);

float hash13(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.yzx + 33.33);
	return fract((p.x + p.y) * p.z);
}

void sky() {
	vec3 p = (frame_inverse * EYEDIR) * density;
	vec3 cell = floor(p);
	vec3 f = p - cell;

	vec3 color = space_tint;

	// Only a small fraction of cells hold a star, so the field scatters rather
	// than showing the grid.
	float occupied = hash13(cell);
	if (occupied < coverage) {
		vec3 star = vec3(hash13(cell + 17.0), hash13(cell + 41.0), hash13(cell + 83.0));
		// Keep stars off the cell boundary so they never clip against a neighbour.
		star = 0.2 + 0.6 * star;
		float d = length(f - star);
		float mag = occupied / max(coverage, 0.0001);
		float intensity = smoothstep(star_size, 0.0, d) * (0.25 + 0.75 * mag * mag);
		// Real fields are not uniformly white.
		vec3 tint = mix(vec3(0.72, 0.81, 1.0), vec3(1.0, 0.94, 0.84), hash13(cell + 7.0));
		color += tint * intensity * brightness;
	}
	COLOR = color;
}
