extends Node

## The menu background's map swap, as a live cross-fade: the outgoing map and its bots keep
## running and rendering (through their own camera, still orbiting, with their own sky and
## light) on top of the incoming one, fading out. Both maps share one world, so they're kept
## apart for the fade: the outgoing scene is moved to its own render layer (only its camera sees
## it, only its lights light it) and its own collision layer (its bots run on it and nothing
## else). release() puts everything back so the map can be parked as usual.
##   hold(...)        before the swap: take over the outgoing scene (it shows on screen now)
##   adopt_lights(m)  after the incoming map is active: keep its lights off the outgoing scene
##   play(time)       the fade itself (await it)
##   release()        restores the outgoing map's layers; free the bots and park the map after

const OUT_LAYER := 1 << 19 # render + collision layer 20, unused by anything else
const _VIS_MASK := 0xFFFFF # the 20 render layers

var orbit_speed := 0.05
var orbit_radius := 60.0
var orbit_height := 30.0
var orbit_follow := 1.5

var _map: GameMap
var _vp: SubViewport
var _cam: Camera3D
var _rect: TextureRect
var _main_cam: Camera3D
var _main_mask := 0
var _orbit := 0.0
var _look := Vector3.ZERO
var _torch: Character
var _vis: Dictionary[VisualInstance3D, int] = {}
var _col: Dictionary[CollisionObject3D, Vector2i] = {}
var _lights: Dictionary[Light3D, int] = {}
var _areas: Array[Area3D] = []
var _terrain: Node
var _terrain_layers := Vector2i.ZERO # render, collision


## Takes over the outgoing scene: map, its bots, the menu camera's orbit. `rect` is a full-screen
## TextureRect above the 3D view (and under the menu) to show it in.
func hold(map: GameMap, bots: Array[Character], main_cam: Camera3D, rect: TextureRect,
		orbit: float, look: Vector3, torch: Character) -> void:
	_map = map
	_main_cam = main_cam
	_rect = rect
	_orbit = orbit
	_look = look
	_torch = torch
	var env := map.park_environment() # the incoming map's sky takes the world; this one rides along
	for n: Node in [map] + bots: _take(n)
	for c: Character in bots:
		c.collision_layer = 0          # the incoming bots don't bump into these
		c.collision_mask = OUT_LAYER   # and these only stand on their own map
		var brain := c.get_node_or_null(^"Brain")
		if brain: brain.process_mode = Node.PROCESS_MODE_DISABLED # no paths here any more: they run on as they were
	var root_vp := get_viewport()
	_vp = SubViewport.new()
	_vp.size = root_vp.get_visible_rect().size
	_vp.scaling_3d_mode = root_vp.scaling_3d_mode
	_vp.scaling_3d_scale = root_vp.scaling_3d_scale
	_vp.msaa_3d = root_vp.msaa_3d
	_vp.screen_space_aa = root_vp.screen_space_aa
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_cam = Camera3D.new()
	_cam.fov = main_cam.fov
	_cam.far = main_cam.far
	_cam.cull_mask = OUT_LAYER
	_cam.environment = env
	_vp.add_child(_cam)
	add_child(_vp)
	_cam.global_transform = main_cam.global_transform
	_cam.make_current()
	_main_mask = main_cam.cull_mask
	main_cam.cull_mask &= ~OUT_LAYER
	_rect.texture = _vp.get_texture()
	_rect.modulate.a = 1.0
	_rect.visible = true


## The incoming map's lights mustn't light (or shadow) the outgoing scene.
func adopt_lights(incoming: Node) -> void:
	for l: Node in incoming.find_children("*", "Light3D", true, false):
		var light := l as Light3D
		_lights[light] = light.light_cull_mask
		light.light_cull_mask &= ~OUT_LAYER


## Fades the outgoing scene out over `time`, its camera orbiting on (following its Torch).
func play(time: float) -> void:
	var t := 0.0
	while t < time:
		var delta := get_process_delta_time()
		t += delta
		_follow(delta)
		var k := clampf(t / time, 0.0, 1.0)
		_rect.modulate.a = 1.0 - k * k * (3.0 - 2.0 * k) # smoothstep out
		await get_tree().process_frame
	_rect.modulate.a = 0.0


## Everything back as it was (the outgoing map can be parked now, its bots freed).
func release() -> void:
	_rect.visible = false
	_rect.texture = null
	if is_instance_valid(_main_cam): _main_cam.cull_mask = _main_mask
	for vi: VisualInstance3D in _vis:
		if is_instance_valid(vi): vi.layers = _vis[vi]
	for co: CollisionObject3D in _col:
		if is_instance_valid(co):
			co.collision_layer = _col[co].x
			co.collision_mask = _col[co].y
	for light: Light3D in _lights:
		if is_instance_valid(light): light.light_cull_mask = _lights[light]
	for a: Area3D in _areas:
		if is_instance_valid(a): a.set_deferred(&"monitoring", true)
	if is_instance_valid(_terrain):
		_terrain.set(&"render_layers", _terrain_layers.x)
		_terrain.set(&"collision_layer", _terrain_layers.y)
	_vis.clear()
	_col.clear()
	_lights.clear()
	_areas.clear()
	if _vp: _vp.queue_free()
	_vp = null


func _take(n: Node) -> void:
	if n is VisualInstance3D:
		var vi := n as VisualInstance3D
		_vis[vi] = vi.layers
		vi.layers = OUT_LAYER
	if n is Light3D:
		var light := n as Light3D
		_lights[light] = light.light_cull_mask
		light.light_cull_mask = OUT_LAYER
	if n is CollisionObject3D and not n is Character:
		var co := n as CollisionObject3D
		if co is Area3D: # its pads mustn't fire for the incoming bots standing in the same spot
			_areas.append(co)
			co.set_deferred(&"monitoring", false)
		elif co.collision_layer != 0:
			_col[co] = Vector2i(co.collision_layer, co.collision_mask)
			co.collision_layer = OUT_LAYER
			co.collision_mask = 0
	if n.get_class() == &"Terrain3D":
		_terrain = n
		var render: int = n.get(&"render_layers")
		_terrain_layers = Vector2i(render, n.get(&"collision_layer"))
		n.set(&"render_layers", (render & ~_VIS_MASK) | OUT_LAYER)
		n.set(&"collision_layer", OUT_LAYER)
		return # its children are its own helpers
	for c: Node in n.get_children(): _take(c)


func _follow(delta: float) -> void:
	_orbit += delta * orbit_speed
	var center := _map.arena_center
	var want := _torch.global_position if is_instance_valid(_torch) else center
	_look = _look.lerp(want, 1.0 - exp(-orbit_follow * delta))
	_cam.global_position = center + Vector3(cos(_orbit), 0.0, sin(_orbit)) * orbit_radius + Vector3.UP * orbit_height
	_cam.look_at(_look + Vector3.UP * 2.0)
