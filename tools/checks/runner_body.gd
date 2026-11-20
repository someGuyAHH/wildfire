extends SceneTree
# Every character wears the runner (RunnerBody), and it plays a clip that fits what the character
# is doing: tallies (state -> clip) over a few seconds of a bot match. Headless.
#   MAPI=2 timeout 120 godot --headless --fixed-fps 120 -s res://tools/checks/runner_body.gd
const _FITS := {
	0: [&"Idle", &"Jog_Fwd", &"Sprint", &"Jump_Land", &"Slide_Exit", &"Hit_Knockback", &"Jump_Start", &"NinjaJump_Start"],
	1: [&"Jump", &"Jump_Start", &"NinjaJump_Start", &"Hit_Knockback", &"Jump_Land", &"Slide_Exit"],
	2: [&"Slide_Start", &"Slide"],
	3: [&"Dash"],
	4: [&"Slam"],
	5: [], # frozen: whatever it was doing, held
}
var _main: Node


func _initialize() -> void:
	_main = (load("res://scn/main/main.tscn") as PackedScene).instantiate()
	root.add_child(_main)
	_run.call_deferred()


func _run() -> void:
	await create_timer(0.5).timeout
	_main.call(&"_start_match", 0, 7, 1, int(OS.get_environment("MAPI")) if OS.get_environment("MAPI") != "" else 2)
	for i: int in 10: await physics_frame # the title screen's bots are gone by now
	var bodies := root.find_children("Body", "Node3D", true, false).filter(func(n: Node) -> bool: return n is RunnerBody and is_instance_valid(n))
	print("characters wearing the runner: %d" % bodies.size())
	var tally := {}
	var bad := 0
	var samples := 0
	for f: int in 120 * 12:
		await physics_frame
		if f < 120 * 4 or f % 6 != 0: continue # past the countdown; ~20 samples a second
		for b: RunnerBody in bodies:
			if not is_instance_valid(b): continue
			var st: int = b.character.get_state()
			var clip: StringName = b._anim.current_animation
			var key := "%s -> %s" % [Character.STATE_NAMES[st], clip]
			tally[key] = tally.get(key, 0) + 1
			samples += 1
			if st != 5 and clip not in _FITS[st]: bad += 1
	var keys := tally.keys()
	keys.sort()
	for k: String in keys: print("  %-34s %d" % [k, tally[k]])
	print("runner body: %d of %d samples off (%s)" % [bad, samples, "OK" if bad * 50 < samples and bodies.size() > 0 else "CHECK"])
	quit()
