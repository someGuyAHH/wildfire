extends SceneTree
# Inferno: walk the player into the Nave of Ash's hidden doorway, then back out. Where do you
# come out, facing which way, at what speed?
var _main: Node


func _initialize() -> void:
	_main = (load("res://scn/main/main.tscn") as PackedScene).instantiate()
	root.add_child(_main)
	_run.call_deferred()


func _walk(c: Character, from: Vector3, dir: Vector3, frames: int) -> void:
	c.teleport(from)
	for i in frames:
		c.intent.wish_dir = dir
		await physics_frame
	c.intent.wish_dir = Vector3.ZERO


func _run() -> void:
	await create_timer(1.0).timeout
	_main.call(&"_start_match", 0, 1, 1, 3)
	var map := _main.get(&"_map") as GameMap
	var tm: TagManager = _main.tag_manager
	while tm.get_phase() != TagManager.PHASE_PLAYING: await physics_frame
	var player: Character = _main.get(&"_player")
	player.get_node(^"Input").process_mode = Node.PROCESS_MODE_DISABLED # the test drives it
	var door := map.find_child("VaultDoor", true, false) as Node3D
	var exit := map.find_child("VaultExit", true, false) as Node3D
	var into := -door.global_basis.z
	var rig := player.get_node(^"CameraRig")
	var yaw0: float = rig.get(&"_yaw")
	await _walk(player, door.global_position + door.global_basis.z * 6.0, into, 90)
	var in_room := exit.global_transform.affine_inverse() * player.global_position
	print("walked in: now at %s (exit-local %s), speed %.1f, safe %s, view turned %.0f deg" % [player.global_position.snapped(Vector3.ONE * 0.1), in_room.snapped(Vector3.ONE * 0.1), player.velocity.length(), map.is_safe(player.global_position), rad_to_deg(float(rig.get(&"_yaw")) - yaw0)])
	await create_timer(1.0).timeout
	print("1 s later: at %s (no lava respawn: %s)" % [player.global_position.snapped(Vector3.ONE * 0.1), player.global_position.y < -20.0])
	await _walk(player, exit.global_position + exit.global_basis.z * 5.0, -exit.global_basis.z, 90)
	var back := door.global_transform.affine_inverse() * player.global_position
	print("walked out: now at %s (door-local %s)" % [player.global_position.snapped(Vector3.ONE * 0.1), back.snapped(Vector3.ONE * 0.1)])
	quit()
