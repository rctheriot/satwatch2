class_name FrameCapture
extends Node
## Renders for a few frames, writes a PNG, and quits.
##
## Used from the command line as:
##   Godot --path . -- --capture out.png [--frames N] [--chapter N]
##
## Worth having beyond development: it is also how the wall's stereo output gets
## checked without a person standing in front of it.

var path: String = ""
var frames: int = 30
var chapter: int = -1

static func from_command_line() -> FrameCapture:
	var args := OS.get_cmdline_user_args()
	var i := args.find("--capture")
	if i < 0 or i + 1 >= args.size():
		return null
	var fc := FrameCapture.new()
	fc.path = args[i + 1]
	var f := args.find("--frames")
	if f >= 0 and f + 1 < args.size():
		fc.frames = int(args[f + 1])
	var c := args.find("--chapter")
	if c >= 0 and c + 1 < args.size():
		fc.chapter = int(args[c + 1])
	return fc

func run(tree: SceneTree) -> void:
	# Let the SubViewport panels and the MultiMesh buffer settle before grabbing.
	for i in frames:
		await tree.process_frame
	var img := tree.root.get_texture().get_image()
	var err := img.save_png(path)
	if err != OK:
		push_error("FrameCapture: could not write %s (%s)" % [path, error_string(err)])
	else:
		print("FrameCapture: wrote %s (%dx%d)" % [path, img.get_width(), img.get_height()])
	tree.quit()
