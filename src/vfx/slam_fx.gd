class_name SlamFx
extends Node3D
## The slam-jump's impact, scaled by how high the slam started (the same intensity as its launch sound):
## cracks on the ground (a decal, so it lies on terrain, stone and wood and bends over slopes and steps)
## with embers glowing in them at the top end, a ring of dust thrown out along the ground, dust that hangs
## about, rock chunks kicked up, a pale shockwave ring racing out, and a camera shake for the player.
## Tuning: SlamFxConfig (assets/tres/vfx/slam_fx.tres).
##
## Everything is made once, up front: a fixed pool of impacts (config.pool_size), each two decals and three
## GPU particle emitters with fixed amounts. An impact only moves them, sets a few material numbers and
## amount_ratio, and restarts them: nothing is created, freed or resized while playing (resizing particle
## buffers at runtime is a suspect in a renderer error). Past the pool, the oldest impact is taken over.
## Main makes one, watches every character with watch(), and prewarms it at match load.

const CONFIG: SlamFxConfig = preload("res://assets/tres/vfx/slam_fx.tres")
const _CRACKS: Array[Texture2D] = [
	preload("res://assets/images/vfx/slam_cracks_0.png"),
	preload("res://assets/images/vfx/slam_cracks_1.png"),
	preload("res://assets/images/vfx/slam_cracks_2.png"),
]
const _GLOWS: Array[Texture2D] = [
	preload("res://assets/images/vfx/slam_cracks_glow_0.png"),
	preload("res://assets/images/vfx/slam_cracks_glow_1.png"),
	preload("res://assets/images/vfx/slam_cracks_glow_2.png"),
]
const _RING: Texture2D = preload("res://assets/images/vfx/slam_ring.png")
const _PUFF: Texture2D = preload("res://assets/images/vfx/slam_puff.png")

## Fixed particle counts per impact (intensity picks the share shown through amount_ratio).
const DUST_AMOUNT := 36
const LINGER_AMOUNT := 12
const DEBRIS_AMOUNT := 18
const _DUST_LIFE := 0.9
const _LINGER_LIFE := 3.0
const _DEBRIS_LIFE := 1.25
const _WORLD_MASK := 1
const _EMBER_COLOUR := Color(1.0, 0.5, 0.15)

## One impact's nodes and where it's at.
class Impact extends RefCounted:
	var root: Node3D
	var cracks: Decal
	var shock: Decal
	var dust: GPUParticles3D
	var linger: GPUParticles3D
	var debris: GPUParticles3D
	var dust_mat: ParticleProcessMaterial
	var linger_mat: ParticleProcessMaterial
	var debris_mat: ParticleProcessMaterial
	var active := false
	var local := false # the player's own
	var age := 0.0
	var started := 0 # play order, for taking over the oldest
	var life := 0.0
	var amount := 0.0 # the response (0..1) it was played at
	var crack_radius := 0.0
	var shock_radius := 0.0
	var ember := 0.0
	var tint := Color.WHITE

var config: SlamFxConfig = CONFIG
## Whose slam-jumps are "yours" (never culled, shake the camera fully).
var local_character: Character
## Gets add_shake(trauma) for slams that shake the camera (the player's camera rig).
var shake_target: Object
## The current map's name, for its dust colour.
var map_name: StringName = &""

## What happened, for checks and the perf HUD.
var played := 0
var culled := 0
var taken_over := 0
var last_shake := 0.0

var _impacts: Array[Impact] = []
var _anchors: Array[Decal] = [] # hidden decals holding every texture in the decal atlas (no rebuild mid-match)
var _ray := PhysicsRayQueryParameters3D.new()
var _exclude: Array[RID] = []
var _count := 0


func _ready() -> void:
	top_level = true
	_ray.collision_mask = _WORLD_MASK
	_ray.hit_from_inside = true
	var dust_draw := _puff_mesh()
	var rock := _rock_mesh()
	var base_dust := _dust_material()
	var base_linger := _linger_material()
	var base_debris := _debris_material()
	for i: int in config.pool_size:
		var im := Impact.new()
		im.root = Node3D.new()
		im.root.name = "Impact%d" % i
		im.root.visible = false
		add_child(im.root)
		im.cracks = _decal(_CRACKS[0], _GLOWS[0])
		im.root.add_child(im.cracks)
		im.shock = _decal(_RING, null)
		im.root.add_child(im.shock)
		im.dust_mat = base_dust.duplicate() as ParticleProcessMaterial
		im.linger_mat = base_linger.duplicate() as ParticleProcessMaterial
		im.debris_mat = base_debris.duplicate() as ParticleProcessMaterial
		im.dust = _emitter(DUST_AMOUNT, _DUST_LIFE, im.dust_mat, dust_draw, AABB(Vector3(-7, -2, -7), Vector3(14, 6, 14)))
		im.linger = _emitter(LINGER_AMOUNT, _LINGER_LIFE, im.linger_mat, dust_draw, AABB(Vector3(-6, -2, -6), Vector3(12, 6, 12)))
		im.debris = _emitter(DEBRIS_AMOUNT, _DEBRIS_LIFE, im.debris_mat, rock, AABB(Vector3(-8, -3, -8), Vector3(16, 9, 16)))
		im.linger.explosiveness = 0.85
		for p: GPUParticles3D in [im.dust, im.linger, im.debris]:
			p.position = Vector3(0.0, 0.08, 0.0)
			im.root.add_child(p)
		_impacts.append(im)
	# every crack and glow texture stays referenced, so swapping them on an impact never rebuilds the atlas
	for i: int in _CRACKS.size():
		var a := _decal(_CRACKS[i], _GLOWS[i])
		a.visible = false
		a.name = "Anchor%d" % i
		add_child(a)
		_anchors.append(a)
	set_process(false)


#region playing

## Shows this character's slam-jumps.
func watch(c: Character) -> void:
	c.jumped.connect(_on_jumped.bind(c))


func _on_jumped(kind: int, c: Character) -> void:
	if kind != Character.JUMP_SLAM_BOUNCE or not is_instance_valid(c): return
	impact(c.global_position, c.config.slam_jump_intensity(c.velocity.y), c == local_character, c)


## An impact at `at` (feet), intensity 0..1 (more is clamped). Returns the impact's pool index, or -1 when
## it was too far from the camera to show.
func impact(at: Vector3, intensity: float, is_local: bool = false, source: CollisionObject3D = null) -> int:
	var cam := get_viewport().get_camera_3d()
	var dist := cam.global_position.distance_to(at) if cam else 0.0
	if not is_local and dist > config.cull_distance:
		culled += 1
		return -1
	# the ground right under the feet: its point, its slope, what it is
	var point := at
	var normal := Vector3.UP
	var surface: StringName = &""
	_ray.from = at + Vector3.UP * 0.6
	_ray.to = at + Vector3.DOWN * 1.6
	_exclude.clear()
	if source: _exclude.append(source.get_rid())
	_ray.exclude = _exclude
	var hit := get_world_3d().direct_space_state.intersect_ray(_ray)
	if hit:
		point = hit.position
		normal = hit.normal
		var body := hit.collider as Node
		if body and body.has_meta(&"surface"): surface = StringName(body.get_meta(&"surface"))
	var index := _take()
	_play(_impacts[index], point, normal, config.amount(intensity), config.dust_colour(map_name, surface), is_local)
	_shake(intensity, is_local, at)
	return index


func _take() -> int:
	var oldest := -1
	var oldest_bot := -1
	for i: int in _impacts.size():
		var im := _impacts[i]
		if not im.active: return i
		if oldest < 0 or im.started < _impacts[oldest].started: oldest = i
		if not im.local and (oldest_bot < 0 or im.started < _impacts[oldest_bot].started): oldest_bot = i
	taken_over += 1
	return oldest_bot if oldest_bot >= 0 else oldest


func _play(im: Impact, point: Vector3, normal: Vector3, t: float, dust: Color, is_local: bool) -> void:
	var c := config
	_count += 1
	played += 1
	im.active = true
	im.local = is_local
	im.age = 0.0
	im.started = _count
	im.amount = t
	im.tint = dust
	im.root.global_transform = Transform3D(_ground_basis(normal), point)
	im.root.visible = true

	# cracks: radius, pattern and embers by size
	im.crack_radius = lerpf(c.crack_radius_min, c.crack_radius_max, t)
	var level := 2 if t >= c.crack_heavy_from else (1 if t >= c.crack_medium_from else 0)
	im.cracks.texture_albedo = _CRACKS[level]
	im.cracks.texture_emission = _GLOWS[level]
	im.cracks.size = Vector3(im.crack_radius * 2.0, c.crack_depth * 2.0, im.crack_radius * 2.0)
	im.cracks.modulate = Color.WHITE
	im.ember = c.ember_energy * SlamFxConfig.ramp_from(t, c.ember_from)
	im.cracks.emission_energy = im.ember
	im.cracks.visible = true

	# shockwave
	im.shock_radius = lerpf(c.shock_radius_min, c.shock_radius_max, t)
	im.shock.size = Vector3(0.5, c.crack_depth * 2.0, 0.5)
	im.shock.modulate = Color(dust.lightened(0.45), c.shock_alpha)
	im.shock.visible = true

	# dust ring along the ground
	var size := lerpf(c.dust_size_min, c.dust_size_max, t)
	var speed := lerpf(c.dust_speed_min, c.dust_speed_max, t)
	var radius := lerpf(c.dust_radius_min, c.dust_radius_max, t)
	im.dust_mat.emission_ring_radius = radius
	im.dust_mat.emission_ring_inner_radius = radius * 0.6
	im.dust_mat.radial_velocity_min = speed * 0.6
	im.dust_mat.radial_velocity_max = speed
	im.dust_mat.scale_min = 0.55 * size
	im.dust_mat.scale_max = 1.0 * size
	im.dust_mat.color = dust
	_fire(im.dust, lerpf(c.dust_ratio_min, c.dust_ratio_max, t))

	# lingering dust
	im.linger_mat.emission_ring_radius = radius * 1.6
	im.linger_mat.emission_ring_inner_radius = radius * 0.5
	im.linger_mat.scale_min = 1.2 * size
	im.linger_mat.scale_max = 2.0 * size
	im.linger_mat.color = dust
	_fire(im.linger, SlamFxConfig.ramp_from(t, c.linger_from))

	# rock chunks
	var debris_size := lerpf(c.debris_size_min, c.debris_size_max, t)
	im.debris_mat.initial_velocity_min = lerpf(c.debris_speed_min, c.debris_speed_max, t) * 0.6
	im.debris_mat.initial_velocity_max = lerpf(c.debris_speed_min, c.debris_speed_max, t)
	im.debris_mat.scale_min = 0.6 * debris_size
	im.debris_mat.scale_max = 1.2 * debris_size
	im.debris_mat.color = Color(dust * c.debris_shade, 1.0)
	_fire(im.debris, SlamFxConfig.ramp_from(t, c.debris_from))

	im.life = maxf(c.crack_hold + c.crack_fade, _LINGER_LIFE)
	set_process(true)


func _fire(p: GPUParticles3D, ratio: float) -> void:
	p.amount_ratio = ratio
	if ratio <= 0.0:
		p.emitting = false
		return
	p.restart()


func _shake(intensity: float, is_local: bool, at: Vector3) -> void:
	last_shake = 0.0
	if not shake_target or not is_instance_valid(shake_target): return
	var t := config.amount(intensity)
	var trauma := lerpf(config.shake_min, config.shake_max, t)
	if not is_local:
		if not local_character or not is_instance_valid(local_character): return
		var k := 1.0 - local_character.global_position.distance_to(at) / config.shake_radius
		if k <= 0.0: return
		trauma *= k * k * 0.6
	last_shake = trauma
	shake_target.call(&"add_shake", trauma)


func _process(delta: float) -> void:
	var any := false
	for im: Impact in _impacts:
		if not im.active: continue
		im.age += delta
		if im.age >= im.life:
			_stop(im)
			continue
		any = true
		var c := config
		# shockwave: out fast, easing off, fading
		if im.shock.visible:
			var p := im.age / c.shock_time
			if p >= 1.0: im.shock.visible = false
			else:
				var r := lerpf(0.4, im.shock_radius, 1.0 - (1.0 - p) * (1.0 - p))
				im.shock.size = Vector3(r * 2.0, im.shock.size.y, r * 2.0)
				im.shock.modulate.a = c.shock_alpha * (1.0 - p)
		# cracks: hold, then fade; embers cool from the start
		if im.cracks.visible:
			var fade := clampf((im.age - c.crack_hold) / maxf(c.crack_fade, 0.01), 0.0, 1.0)
			im.cracks.modulate.a = 1.0 - fade
			if im.ember > 0.0:
				var cool := clampf(1.0 - im.age / c.ember_time, 0.0, 1.0)
				im.cracks.emission_energy = im.ember * cool * cool
	if not any: set_process(false)


func _stop(im: Impact) -> void:
	im.active = false
	im.local = false
	im.cracks.visible = false
	im.shock.visible = false
	im.root.visible = false
	for p: GPUParticles3D in [im.dust, im.linger, im.debris]: p.emitting = false


## Every impact off (a match ends; the title screen starts clean).
func clear() -> void:
	for im: Impact in _impacts: _stop(im)
	set_process(false)


## Plays one full-size impact a few metres in front of `cam` for a couple of frames, then clears it: the
## particle and draw shaders compile now (behind the match's burn-in), not on the first slam.
func prewarm(cam: Camera3D) -> void:
	if not cam or _impacts.is_empty(): return
	var im := _impacts[0]
	var at := cam.global_position - cam.global_basis.z * 4.0 + Vector3.DOWN
	_play(im, at, Vector3.UP, 1.0, config.default_dust, false)
	played -= 1
	for i: int in 3: await get_tree().process_frame
	if is_instance_valid(self) and im.started == _count: _stop(im)

#endregion


#region queries (checks, debug)

func pool_size() -> int:
	return _impacts.size()


func active_count() -> int:
	var n := 0
	for im: Impact in _impacts: if im.active: n += 1
	return n


## Decals showing now (cracks and shockwaves).
func visible_decals() -> int:
	var n := 0
	for im: Impact in _impacts:
		if im.cracks.visible: n += 1
		if im.shock.visible: n += 1
	return n


## The nodes of every impact, to tell they're the same ones each time.
func node_ids() -> PackedInt64Array:
	var out := PackedInt64Array()
	for im: Impact in _impacts:
		for n: Node in [im.root, im.cracks, im.shock, im.dust, im.linger, im.debris]: out.append(n.get_instance_id())
	return out


## How impact `index` was sized: response, crack radius and pattern, shockwave radius, ember energy and the
## particle shares.
func describe(index: int) -> Dictionary:
	var im := _impacts[index]
	return {
		amount = im.amount, crack_radius = im.crack_radius, crack_level = _CRACKS.find(im.cracks.texture_albedo),
		shock_radius = im.shock_radius, ember = im.ember, dust = im.dust.amount_ratio,
		linger = im.linger.amount_ratio if im.linger.emitting else 0.0,
		debris = im.debris.amount_ratio if im.debris.emitting else 0.0,
		dust_speed = im.dust_mat.radial_velocity_max, dust_size = im.dust_mat.scale_max,
		up = im.root.global_basis.y, at = im.root.global_position,
	}

#endregion


#region building (once)

## Ground-aligned, turned a random way round the normal (no two crack patterns line up).
func _ground_basis(n: Vector3) -> Basis:
	n = n.normalized()
	var ref := Vector3.FORWARD if absf(n.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT
	var x := n.cross(ref).normalized()
	return Basis(x, n, x.cross(n)).rotated(n, randf() * TAU).orthonormalized()


func _decal(albedo: Texture2D, emission: Texture2D) -> Decal:
	var d := Decal.new()
	d.texture_albedo = albedo
	d.texture_emission = emission
	d.emission_energy = 0.0
	d.albedo_mix = 1.0
	d.normal_fade = 0.35 # stays off walls and off legs standing in it
	d.upper_fade = 0.25
	d.lower_fade = 0.25
	d.distance_fade_enabled = true
	d.distance_fade_begin = 45.0
	d.distance_fade_length = 15.0
	d.cull_mask = 1 # the world, not your first-person body
	d.visible = false
	return d


func _emitter(amount: int, life: float, mat: ParticleProcessMaterial, mesh: Mesh, box: AABB) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = amount # fixed for good: only amount_ratio changes
	p.lifetime = life
	p.one_shot = true
	p.explosiveness = 1.0
	p.randomness = 0.4
	p.local_coords = false
	p.emitting = false
	p.process_material = mat
	p.draw_pass_1 = mesh
	p.visibility_aabb = box
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.layers = 1
	return p


func _fade_ramp(peak: float) -> GradientTexture1D:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.15, 1.0])
	g.colors = PackedColorArray([Color(1, 1, 1, peak), Color(1, 1, 1, peak), Color(1, 1, 1, 0.0)])
	var tex := GradientTexture1D.new()
	tex.gradient = g
	tex.width = 64
	return tex


func _curve(points: Array[Vector2]) -> CurveTexture:
	var cv := Curve.new()
	for pt: Vector2 in points: cv.add_point(pt)
	var tex := CurveTexture.new()
	tex.curve = cv
	tex.width = 64
	return tex


## A little light-and-dark spread so the puffs and chunks aren't one flat colour.
func _shade_ramp(lo: float) -> GradientTexture1D:
	var g := Gradient.new()
	g.colors = PackedColorArray([Color(lo, lo, lo), Color.WHITE])
	var tex := GradientTexture1D.new()
	tex.gradient = g
	tex.width = 16
	return tex


func _dust_material() -> ParticleProcessMaterial:
	var m := ParticleProcessMaterial.new()
	m.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
	m.emission_ring_axis = Vector3.UP
	m.emission_ring_height = 0.0
	m.direction = Vector3.UP
	m.spread = 15.0
	m.initial_velocity_min = 0.4
	m.initial_velocity_max = 1.4
	m.damping_min = 7.0
	m.damping_max = 9.0
	# radial velocity is held over the life, not damped: this curve is what slows the ring down
	m.radial_velocity_curve = _curve([Vector2(0.0, 1.0), Vector2(0.25, 0.3), Vector2(1.0, 0.0)])
	m.gravity = Vector3(0.0, 0.4, 0.0)
	m.angle_min = -180.0
	m.angle_max = 180.0
	m.scale_curve = _curve([Vector2(0.0, 0.45), Vector2(0.35, 1.0), Vector2(1.0, 1.25)])
	m.color_ramp = _fade_ramp(0.9)
	m.color_initial_ramp = _shade_ramp(0.82)
	return m


func _linger_material() -> ParticleProcessMaterial:
	var m := ParticleProcessMaterial.new()
	m.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
	m.emission_ring_axis = Vector3.UP
	m.emission_ring_height = 0.3
	m.direction = Vector3.UP
	m.spread = 60.0
	m.initial_velocity_min = 0.2
	m.initial_velocity_max = 0.6
	m.radial_velocity_min = 0.3
	m.radial_velocity_max = 1.0
	m.damping_min = 0.5
	m.damping_max = 1.0
	m.gravity = Vector3(0.0, 0.12, 0.0)
	m.angle_min = -180.0
	m.angle_max = 180.0
	m.angular_velocity_min = -12.0
	m.angular_velocity_max = 12.0
	m.scale_curve = _curve([Vector2(0.0, 0.5), Vector2(0.4, 1.0), Vector2(1.0, 1.3)])
	m.color_ramp = _fade_ramp(0.35)
	m.color_initial_ramp = _shade_ramp(0.88)
	return m


func _debris_material() -> ParticleProcessMaterial:
	var m := ParticleProcessMaterial.new()
	m.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	m.emission_sphere_radius = 0.45
	m.direction = Vector3.UP
	m.spread = 38.0
	m.gravity = Vector3(0.0, -24.0, 0.0)
	m.angle_min = -180.0
	m.angle_max = 180.0
	m.angular_velocity_min = -540.0
	m.angular_velocity_max = 540.0
	# full size, then shrinking away at the end (they'd sink into the ground otherwise)
	m.scale_curve = _curve([Vector2(0.0, 1.0), Vector2(0.7, 1.0), Vector2(1.0, 0.0)])
	m.color_initial_ramp = _shade_ramp(0.7)
	return m


func _puff_mesh() -> QuadMesh:
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_VERTEX
	mat.vertex_color_use_as_albedo = true
	mat.albedo_texture = _PUFF
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.roughness = 1.0
	mat.disable_receive_shadows = true
	var q := QuadMesh.new()
	q.size = Vector2(0.7, 0.7)
	q.material = mat
	return q


## A low-poly rock: a squashed, jittered octahedron with flat faces.
func _rock_mesh() -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	var v: Array[Vector3] = [Vector3.RIGHT, Vector3.LEFT, Vector3.UP * 0.7, Vector3.DOWN * 0.6, Vector3.BACK, Vector3.FORWARD]
	for i: int in v.size():
		v[i] = (v[i] + Vector3(rng.randf_range(-0.2, 0.2), rng.randf_range(-0.15, 0.15), rng.randf_range(-0.2, 0.2))) * 0.12
	var faces := [[2, 4, 0], [2, 0, 5], [2, 5, 1], [2, 1, 4], [3, 0, 4], [3, 5, 0], [3, 1, 5], [3, 4, 1]]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for f: Array in faces:
		var a: Vector3 = v[f[0]]
		var b: Vector3 = v[f[1]]
		var c: Vector3 = v[f[2]]
		var n := (b - a).cross(c - a).normalized()
		for p: Vector3 in [a, c, b]: # (clockwise from outside: Godot's front face)
			st.set_normal(n)
			st.add_vertex(p)
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.95
	st.set_material(mat)
	return st.commit()

#endregion
