extends SceneTree
# The crater's soccer ball: stays in the bowl (rolls about its lowest point a little), a running character kicks it away (and up), it
# doesn't stop the character, and going home puts it back. Headless.
#   timeout 120 godot --headless --fixed-fps 120 -s res://tools/checks/ball.gd
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
	for i: int in 240: await physics_frame
	var ball := root.find_children("SoccerBall", "RigidBody3D", true, false)[0] as SoccerBall
	var home := ball.global_position
	for i: int in 240: await physics_frame
	var rest_moved := ball.global_position.distance_to(home)
	print("ball at rest: moved %.2f m in 2 s, speed %.2f m/s" % [rest_moved, ball.linear_velocity.length()])
	# a runner at 14 m/s straight at it from 8 m out, along the ground
	var p := _main.get(&"_player") as Character
	var start := ball.global_position + Vector3(-8.0, -1.6, 0.0)
	p.teleport(start)
	await physics_frame
	var before := ball.global_position
	var kicked_speed := 0.0
	var runner_speed_after := 0.0
	for i: int in 120:
		p.velocity.x = 14.0
		await physics_frame
		kicked_speed = maxf(kicked_speed, ball.linear_velocity.length())
		if i == 90: runner_speed_after = p.velocity.x
	var travelled := ball.global_position.distance_to(before)
	print("kicked: top speed %.1f m/s, rolled %.1f m; runner still at %.1f m/s through it" % [kicked_speed, travelled, runner_speed_after])
	ball.go_home()
	await physics_frame
	var back := ball.global_position.distance_to(ball._home.origin)
	print("home again: %.2f m off" % back)
	var ok := rest_moved < 3.0 and kicked_speed > 12.0 and travelled > 5.0 and back < 0.05
	print("soccer ball: %s" % ("OK" if ok else "CHECK"))
	quit()
