extends SceneTree
# Every .gdshader under assets/gdshaders parses? (Headless doesn't render, but the dummy renderer
# still runs the shader compiler's parser: errors print as SHADER ERROR with the line.)
#   timeout 60 godot --headless -s res://tools/checks/shaders.gd
const DIR := "res://assets/gdshaders"


func _initialize() -> void:
	var ok := 0
	var bad: PackedStringArray = []
	for f: String in DirAccess.get_files_at(DIR):
		if not f.ends_with(".gdshader"): continue
		var sh := load("%s/%s" % [DIR, f]) as Shader
		# a failed compile leaves no uniforms; a shader with none at all would be flagged too
		if sh and sh.get_shader_uniform_list().size() > 0: ok += 1
		else: bad.append(f)
	print("shaders parsing: %d ok%s" % [ok, (", FAILED: " + ", ".join(bad)) if not bad.is_empty() else ""])
	quit()
