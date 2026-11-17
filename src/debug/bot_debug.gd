extends Node3D

## [DEBUG] F5 overlay: every bot's state over its head (who, what it's doing, which move it's
## on) and its planned path drawn in the world, link segments coloured by kind.
##   orange = the Torch's path, cyan = a runner's; pad magenta, climb green, drop blue,
##   wall-jump yellow, gap jump white; a cross marks where it's headed.

const _LINK_COLORS: Array[Color] = [Color.CYAN, Color.MAGENTA, Color.GREEN, Color(0.3, 0.5, 1.0), Color.YELLOW, Color.WHITE, Color.PURPLE]
const _TORCH := Color(1.0, 0.55, 0.15)

var participants: Array[Character] = []
var tag_manager: TagManager

var _labels: Dictionary[Character, Label3D] = {}
var _mesh := ImmediateMesh.new()


func _ready() -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = _mesh
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.no_depth_test = true
	mi.material_override = mat
	add_child(mi)


func _process(_delta: float) -> void:
	_mesh.clear_surfaces()
	for c: Character in _labels.keys():
		if not is_instance_valid(c) or not c in participants:
			if is_instance_valid(_labels[c]): _labels[c].queue_free()
			_labels.erase(c)
	if not visible: return
	var drew := false
	for c: Character in participants:
		if not is_instance_valid(c): continue
		var brain := c.get_node_or_null(^"Brain")
		if not brain: continue
		var out := tag_manager != null and tag_manager.is_out(c)
		var torch := tag_manager != null and tag_manager.is_torch(c)
		var label: Label3D = _labels.get(c)
		if not label:
			label = Label3D.new()
			label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			label.no_depth_test = true
			label.fixed_size = true
			label.pixel_size = 0.0009
			label.font_size = 26
			label.outline_size = 8
			label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
			add_child(label)
			_labels[c] = label
		label.visible = not out
		if out: continue
		label.global_position = c.global_position + Vector3.UP * 2.4
		label.text = brain.call(&"debug_text")
		label.modulate = _TORCH if torch else Color.WHITE
		var info: Array = brain.call(&"debug_path")
		var pts: PackedVector3Array = info[0]
		var kinds: PackedInt32Array = info[1]
		if pts.size() < 2: continue
		if not drew:
			_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
			drew = true
		for i: int in pts.size() - 1:
			var k := kinds[i - 1] if i >= 1 and i - 1 < kinds.size() else 0
			var col := _LINK_COLORS[k] if k > 0 and k < _LINK_COLORS.size() else (_TORCH if torch else Color.CYAN)
			_line(pts[i] + Vector3.UP * 0.3, pts[i + 1] + Vector3.UP * 0.3, col)
		var g: Vector3 = info[2]
		var gc := _TORCH if torch else Color.CYAN
		_line(g + Vector3(-0.6, 0.3, 0.0), g + Vector3(0.6, 0.3, 0.0), gc)
		_line(g + Vector3(0.0, 0.3, -0.6), g + Vector3(0.0, 0.3, 0.6), gc)
		_line(g, g + Vector3.UP * 1.5, gc)
	if drew: _mesh.surface_end()


func _line(a: Vector3, b: Vector3, col: Color) -> void:
	_mesh.surface_set_color(col)
	_mesh.surface_add_vertex(a)
	_mesh.surface_set_color(col)
	_mesh.surface_add_vertex(b)
