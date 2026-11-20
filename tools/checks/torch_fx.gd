extends SceneTree
# The Torch's fire: its flames sit on the runner's back unit (behind and at shoulder height, moving
# with the body), it leaves scorch marks while running, it stops when the fire goes out, and
# catching fire spawns a TagFlash. Headless (particles don't draw, but their nodes and decals do).
#   timeout 120 godot --headless --fixed-fps 120 -s res://tools/checks/torch_fx.gd
var _main: Node


func _initialize() -> void:
	_main = (load("res://scn/main/main.tscn") as PackedScene).instantiate()
	root.add_child(_main)
	_run.call_deferred()


func _run() -> void:
	await create_timer(0.5).timeout
	_main.call(&"_start_match", 0, 3, 1, 1)
	_main.call(&"toggle_cheat", &"alone")
	_main.call(&"toggle_cheat", &"no_tag")
	for i: int in 300: await physics_frame
	var p := _main.get(&"_player") as Character
	var flashes_before := root.find_children("*", "Node3D", true, false).filter(func(n: Node) -> bool: return n is TagFlash).size()
	p.set_burning(false)
	p.set_burning(true)
	await process_frame
	var flashes := root.find_children("*", "Node3D", true, false).filter(func(n: Node) -> bool: return n is TagFlash).size() - flashes_before
	var fx := p.find_children("*", "Node3D", true, false).filter(func(n: Node) -> bool: return n is TorchFX)[0] as TorchFX
	for i: int in 10: await process_frame
	var local := p.global_transform.affine_inverse() * fx.global_position
	var fwd := p.visual.global_basis * Vector3.FORWARD
	var behind := (fx.global_position - p.global_position).dot(fwd) < -0.05
	print("fire at %s from the character's feet (behind: %s), %d flash(es)" % [local.snappedf(0.01), behind, flashes])
	# run in a straight line for 2 s
	var marks_seen := 0
	for i: int in 240:
		p.velocity.x = 9.0
		await physics_frame
	for d: Node in fx.find_children("*", "Decal", true, false): if (d as Decal).visible: marks_seen += 1
	print("scorch marks after a 2 s run: %d" % marks_seen)
	p.set_burning(false)
	await process_frame
	var flames_on := (fx.get_node(^"Flames") as CPUParticles3D).emitting
	var ok := local.y > 1.1 and local.y < 1.6 and behind and flashes == 1 and marks_seen >= 8 and not flames_on
	print("torch fx: %s" % ("OK" if ok else "CHECK"))
	quit()
