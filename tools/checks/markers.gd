extends SceneTree
# Role markers: every character has exactly one, the Torch's is orange, glowing and through
# walls, the others use their own colour and are depth tested, roles update on a tag, no name
# tag nodes are left, the pyramid's faces point outward, and aiming at someone finds them.
var _main: Node
var _fails := 0


func _ok(cond: bool, what: String) -> void:
	print("%s  %s" % ["ok  " if cond else "FAIL", what])
	if not cond: _fails += 1


func _initialize() -> void:
	_main = (load("res://scn/main/main.tscn") as PackedScene).instantiate()
	root.add_child(_main)
	_run.call_deferred()


func _markers(c: Character) -> Array[RoleMarker]:
	var out: Array[RoleMarker] = []
	for n: Node in c.get_children():
		if n is RoleMarker: out.append(n)
	return out


func _count_tags(n: Node) -> int:
	var k := 0
	if n is Label3D and n.name == "NameTag": k += 1
	for ch: Node in n.get_children(): k += _count_tags(ch)
	return k


func _run() -> void:
	await create_timer(1.0).timeout
	_main.call(&"_start_match", 0, 3, 1, 0)
	var tm: TagManager = _main.tag_manager
	while tm.get_phase() != TagManager.PHASE_PLAYING: await physics_frame
	var player: Character = _main.get(&"_player")
	player.get_node(^"Input").process_mode = Node.PROCESS_MODE_DISABLED
	var all := tm.get_participants()
	print("characters: %d" % all.size())
	var one := true
	for c: Character in all: one = one and _markers(c).size() == 1
	_ok(one, "each character has exactly one marker")
	_ok(_count_tags(_main) == 0, "no NameTag nodes anywhere")
	var xray := load("res://assets/gdshaders/role_marker_xray.gdshader") as Shader
	var solid := load("res://assets/gdshaders/role_marker.gdshader") as Shader
	var torches := all.filter(func(c: Character) -> bool: return tm.is_torch(c))
	_ok(torches.size() >= 1, "there is a Torch (%d)" % torches.size())
	for c: Character in all:
		var m := c.marker
		var mat := m.material_override as ShaderMaterial
		if tm.is_torch(c):
			var col := m.get_color()
			_ok(m.is_torch() and mat.shader == xray, "Torch marker is through-wall")
			_ok(col.r > 0.9 and col.g < 0.4 and col.b < 0.3, "Torch marker is fire orange/red %s" % col)
			_ok(float(m.get_instance_shader_parameter(&"glow")) > 0.0, "Torch marker glows")
		else:
			_ok(not m.is_torch() and mat.shader == solid, "%s marker is depth tested" % c.display_name)
			_ok(m.get_color().is_equal_approx(c.base_tint), "%s marker uses its own colour" % c.display_name)
	var bots: Array = all.filter(func(c: Character) -> bool: return c != player)
	_ok(bots.size() >= 2 and bots.map(func(c: Character) -> Color: return c.base_tint).size() == bots.size(), "bots present")
	# marker is shared: same mesh and materials everywhere
	_ok(all[0].marker.mesh == all[1].marker.mesh, "mesh is shared")
	# a tag moves the Torch role
	tm.call(&"_clear_torches")
	var a: Character = bots[0]
	var b: Character = bots[1]
	tm.call(&"_add_torch", a)
	await process_frame
	_ok(a.marker.is_torch() and a.marker.get_color().r > 0.9, "after _add_torch the marker is the Torch's")
	tm.call(&"_remove_torch", a)
	tm.call(&"_add_torch", b)
	await process_frame
	_ok(not a.marker.is_torch() and a.marker.get_color().is_equal_approx(a.base_tint), "old Torch back to its own colour")
	_ok(b.marker.is_torch() and (b.marker.material_override as ShaderMaterial).shader == xray, "new Torch is through-wall")
	# first person hides your own marker, third person shows it
	_ok(not player.marker.visible, "own marker hidden in first person")
	var stg = root.get_node(^"STG")
	stg.set_value(stg.THIRD_PERSON, 1.0)
	await process_frame
	_ok(player.marker.visible, "own marker shown in third person")
	stg.set_value(stg.THIRD_PERSON, 0.0)
	await process_frame
	_ok(not player.marker.visible, "own marker hidden again in first person")
	# mesh winding: three lid normals point up, nine side normals point down-and-out (an inverted
	# pyramid's sides face down; inside-out ones would face up). Vertices come back reordered.
	var probe := RoleMarker.new()
	var arr := probe.mesh.surface_get_arrays(0)
	probe.free()
	var n: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
	var up := 0
	var down := 0
	for nn: Vector3 in n:
		if nn.y > 0.9: up += 1
		elif nn.y < -0.3: down += 1
	_ok(up == 3 and down == 9, "mesh normals point outward (lid %d up, sides %d down)" % [up, down])
	# constant on-screen size: scale grows with distance, within the clamp
	var cam := root.get_viewport().get_camera_3d()
	_ok(cam != null, "a camera is current")
	if cam:
		await create_timer(0.6).timeout # let the pop settle
		var s0 := a.marker.scale.x
		var d0 := cam.global_position.distance_to(a.marker.global_position)
		a.global_position += (a.global_position - cam.global_position).normalized() * (d0 * 0.5)
		await process_frame
		await process_frame
		var s1 := a.marker.scale.x
		print("marker scale %.3f at %.1f m, %.3f after moving 50%% farther" % [s0, d0, s1])
		_ok(s1 > s0 * 1.2 or s0 >= 6.0 * a.marker.config.size * 0.99, "marker grows with distance")
	# aiming: a bot straight ahead of the view is found, one far off to the side is not
	var hud: Node = _main.get(&"_hud")
	if cam and hud:
		b.freeze(100.0)
		b.velocity = Vector3.ZERO
		var fwd := -cam.global_basis.z
		b.global_position = cam.global_position + fwd * 10.0 - Vector3.UP * 1.0
		await physics_frame
		var found: Character = hud.call(&"_aimed_at", cam)
		_ok(found == b, "aimed-at bot is found (%s)" % (found.display_name if found else "nobody"))
		for i: int in 3: await process_frame
		var lbl: Label = hud.get(&"_aim_label")
		_ok(lbl.visible and lbl.text.contains(b.display_name), "aim label shows the name: '%s'" % lbl.text)
		b.global_position = cam.global_position + cam.global_basis.x * 10.0 - Vector3.UP * 1.0
		await physics_frame
		_ok(hud.call(&"_aimed_at", cam) == null, "a bot off to the side is not aimed at")
		await create_timer(1.6).timeout
		_ok(not lbl.visible, "name fades out after looking away")
	print("done: %d failures" % _fails)
	quit(1 if _fails else 0)
