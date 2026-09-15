class_name WorldPanel
extends MeshInstance3D
## A 2D Control rendered into world space.
##
## This is not a stylistic choice. StereoWallDisplay composites the two eye
## viewports into CanvasLayer 100 as two TextureRects side by side, so anything
## drawn on a CanvasLayer above it lands on ONE EYE'S HALF of the output window
## -- it appears once, in the wrong place, with no stereo depth. Every piece of
## UI in this project is therefore a textured quad in the 3D world.
##
## Panels sit at or just BEHIND the wall plane (positive parallax). Content in
## front of the wall must not touch a frame edge, and a panel near the edge of a
## 3:1 wall is exactly where that window violation would happen.

## Per-eye pixel density: 4800 px across the 6.047 m wall.
const PIXELS_PER_METRE := 794.0

var viewport: SubViewport
var root: Control

func build(size_metres: Vector2, content: Control) -> void:
	viewport = SubViewport.new()
	viewport.size = Vector2i(roundi(size_metres.x * PIXELS_PER_METRE),
		roundi(size_metres.y * PIXELS_PER_METRE))
	viewport.transparent_bg = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	# Panels never take input: in stereo mode get_viewport() picking does not
	# work anyway, so selection goes through the 3D reticle instead.
	viewport.gui_disable_input = true
	add_child(viewport)

	root = content
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	viewport.add_child(root)

	var quad := QuadMesh.new()
	quad.size = size_metres
	mesh = quad

	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_texture = viewport.get_texture()
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	# Always drawn over the scene. These panels are fixed to the physical wall,
	# but they are real geometry 2.45 m in front of the viewer, so zooming the
	# content in far enough pushed the globe through them and the UI vanished
	# into the Earth. Depth-testing wall-fixed UI against world content is the
	# wrong relationship: it is a window frame, not an object in the scene.
	mat.no_depth_test = true
	mat.render_priority = 8
	material_override = mat

func set_update_always(always: bool) -> void:
	# Panels that only change on chapter transitions do not need to re-render
	# every frame; at 15.5 Mpix/frame the saved fill is worth having.
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS if always \
		else SubViewport.UPDATE_ONCE
