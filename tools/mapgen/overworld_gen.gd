extends SceneTree

# Builds the Overworld greybox: Terrain3D heightmap (+ textures, control map), dozens of obstacle
# clusters, pads and speed strips with bot nav links, pre-baked navmesh chunks, and the map scene.
# Deterministic: rerunning regenerates the exact same map (and overwrites every output).
#   godot --headless --script res://tools/mapgen/overworld_gen.gd
#
# Layout (x = east, z = south, 1 m per terrain vertex, 1024 m square, playable circle r = 260):
#   centre       flat spawn meadow
#   west         SLIDE HILL: 45 m smooth dome for long slides, a climbing tower on top
#   north-west   THE RIDGE: a long 14 m spine to slide down either side of
#   south-west   THE CRATER: a ring ridge around a sunken bowl (skate-bowl circuits)
#   north        THE MESA: 24 m plateau, sheer cliffs, one ramp, pillars on top
#   east         CANYON: 16 m deep north-south cut, wall-jump slot, four ramp exits
#   across       AQUEDUCT: 13 m-high ruined deck from the hill over the canyon, broken gaps
#   everywhere   obstacle clusters (Poisson-spaced, 8 kits) with open ground between them,
#                long-range launch pads between clusters, hop pads and speed strips in the open
#   outside      the rim: mountains from r = 310, nothing navigable out there

const SIZE := 1024
const HALF := SIZE / 2
const ARENA_RADIUS := 260.0
const NAV_RADIUS := 300.0
const RIM_START := 310.0
const RIM_FULL := 480.0
const NAV_CHUNK := 128.0
const NAV_BORDER := 2.0

const OUT_SCENE := "res://scn/map/overworld.tscn"
const MAP_SCRIPT := "res://src/map/overworld.gd"
const DATA_DIR := "res://assets/terrain/overworld"
const NAV_DIR := "res://assets/navmesh/overworld"
const MESH_DIR := "res://assets/meshes/overworld" # merged cluster meshes, binary (keeps the .tscn small)
const ASSETS_PATH := "res://assets/tres/terrain/overworld_assets.tres"
const TEX_DIR := "res://assets/images/terrain"
const MAT_DIR := "res://assets/tres/materials/greybox"
const ENV := "res://assets/tres/environments/gym_environment.tres"
const GREYBOX := "res://assets/tres/materials/greybox.tres"
const JUMP_PAD := "res://scn/props/jump_pad.tscn"
const SPEED_STRIP := "res://scn/props/speed_strip.tscn"
const MOVEMENT := "res://assets/tres/movement/default_movement.tres"

# terrain features
const HILL_POS := Vector2(-165.0, 25.0)
const HILL_RADIUS := 105.0
const HILL_HEIGHT := 45.0
const RIDGE_A := Vector2(-255.0, -40.0)
const RIDGE_B := Vector2(-95.0, -225.0)
const RIDGE_HEIGHT := 14.0
const RIDGE_HALF_WIDTH := 22.0
const CRATER_POS := Vector2(-135.0, 165.0)
const CRATER_RADIUS := 38.0
const CRATER_RIDGE := 13.0
const CRATER_DEPTH := 6.0
const MESA_POS := Vector2(20.0, -195.0)
const MESA_HALF := Vector2(55.0, 34.0)
const MESA_HEIGHT := 24.0
const MESA_RAMP_RUN := 62.0
const CANYON_DEPTH := 16.0
# (z, side): ramp exits out of the canyon. side +1 = east wall, -1 = west wall
const CANYON_EXITS: Array[Vector2] = [Vector2(-165.0, 1.0), Vector2(-35.0, -1.0), Vector2(85.0, 1.0), Vector2(195.0, -1.0)]
const AQUEDUCT_Z := -55.0
const AQUEDUCT_DECK := 13.0
const AQUEDUCT_X1 := 195.0
const AQUEDUCT_SEG := 12.0

# clusters
const CLUSTER_SPACING := 52.0
const CLUSTER_MAX_R := 238.0
const MEADOW_RADIUS := 55.0
const KITS: Array[StringName] = [&"ruins", &"pillars", &"stilts", &"kickers", &"tower", &"blocks", &"vaults", &"hub"]
const FLAT_KITS: Array[StringName] = [&"kickers", &"blocks", &"vaults", &"hub"]
const SLOPE_KITS: Array[StringName] = [&"ruins", &"pillars", &"stilts", &"tower"]

const COLORS := {
	&"stone": Color(0.78, 0.68, 0.5),    # aqueduct, ruins
	&"rock": Color(0.55, 0.52, 0.5),     # blocks, mesa pillars
	&"ruin": Color(0.66, 0.58, 0.72),    # towers, pillar runs
	&"wood": Color(0.72, 0.5, 0.32),     # stilt platforms, bridges
	&"ramp": Color(0.86, 0.56, 0.26),    # kickers, ramps (same orange as the gym)
	&"hub": Color(0.42, 0.62, 0.82),     # launch hubs
}

## One cluster's worth of geometry, in its local space (y = 0 at the ground under its centre).
class Kit:
	var boxes: Array[Dictionary] = [] # {xf: Transform3D, size: Vector3, mat: StringName, grounded: bool}
	var pads: Array[Dictionary] = []  # {at: Vector3, to: Vector3, world_target: bool, peak: float}
	var strips: Array[Dictionary] = [] # {at: Vector3, yaw: float, speed: float}
	var radius := 20.0
	var top := Vector3.ZERO # a high spot long-range pads can start from (towers)
	var has_top := false

	## A box. The long axis is local Z: yaw turns it, tilt raises its +Z end (radians, + = up).
	func box(pos: Vector3, size: Vector3, mat: StringName, yaw: float = 0.0, grounded: bool = true, tilt: float = 0.0) -> void:
		var b := Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, -tilt)
		boxes.append({"xf": Transform3D(b, pos), "size": size, "mat": mat, "grounded": grounded})

	## A box standing on the ground: (x, z) is the centre of its footprint, size.y its height.
	func post(x: float, z: float, size: Vector3, mat: StringName, yaw: float = 0.0) -> void:
		box(Vector3(x, size.y * 0.5, z), size, mat, yaw, true)


var _roll := FastNoiseLite.new()
var _ridge_noise := FastNoiseLite.new()
var _heights := PackedFloat32Array()
var _rng := RandomNumberGenerator.new()
var _mats := {}
var _cfg: MovementConfig
var _root: Node3D
var _props: Node3D
var _nav: Node3D
var _clusters: Array[Dictionary] = [] # {pos: Vector2, kit: StringName, radius: float, node: Node3D}
var _pad_count := 0
var _raised_landings: Array[Vector3] = [] # pad targets above the ground: bots need a way back down
var _link_count := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var t0 := Time.get_ticks_msec()
	_rng.seed = 4242
	_roll.seed = 7
	_roll.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_roll.frequency = 0.007
	_roll.fractal_octaves = 3
	_ridge_noise.seed = 11
	_ridge_noise.frequency = 0.006
	_ridge_noise.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	_ridge_noise.fractal_octaves = 4
	_cfg = load(MOVEMENT) as MovementConfig

	_bake_heights()
	print("heights: %d ms" % (Time.get_ticks_msec() - t0))
	await _write_terrain_data()
	print("terrain data: %d ms" % (Time.get_ticks_msec() - t0))
	_make_materials()

	_root = Node3D.new()
	_root.name = "Overworld"
	_root.set_script(load(MAP_SCRIPT))
	_root.set(&"arena_radius", ARENA_RADIUS)
	_root.set(&"storm_height_scale", 2.0)
	root.add_child(_root)
	_add_environment()
	var terrain := _add_terrain()
	_root.set(&"terrain", terrain)
	_props = _node(_root, "Props")
	_nav = _node(_root, "Navigation")
	_clear_dir(MESH_DIR)

	_build_aqueduct()
	_build_landmarks()
	_place_clusters()
	_add_launchers()
	_add_open_ground_pads_and_strips()
	print("props: %d clusters, %d pads, %d nav links (%d ms)" % [_clusters.size(), _pad_count, _link_count, Time.get_ticks_msec() - t0])
	_add_spawns()
	_add_labels()

	for i: int in 5: await physics_frame # let the terrain load its regions and the props register
	_add_drop_links()
	await _bake_navmesh(terrain)
	print("navmesh: %d ms" % (Time.get_ticks_msec() - t0))

	_own(_root, _root)
	var scene := PackedScene.new()
	var err := scene.pack(_root)
	if err == OK: err = ResourceSaver.save(scene, OUT_SCENE)
	print("scene %s: %s" % [OUT_SCENE, error_string(err)])
	print("height range %.1f .. %.1f m, done in %d ms" % [_min_h(), _max_h(), Time.get_ticks_msec() - t0])
	quit()


#region heights

func _bake_heights() -> void:
	_heights.resize(SIZE * SIZE)
	for iz: int in SIZE:
		for ix: int in SIZE:
			_heights[iz * SIZE + ix] = _height(float(ix - HALF), float(iz - HALF))


static func _canyon_x(z: float) -> float:
	return 125.0 + 32.0 * sin(z / 65.0)


## Terrain height in metres at world (x, z). Pure function of position (and the noise seeds).
func _height(x: float, z: float) -> float:
	var p := Vector2(x, z)
	var r := p.length()
	# rolling ground, rougher toward the south and west
	var rough := clampf((-x + z) / 300.0 + 0.3, 0.2, 1.0)
	var ground := _roll.get_noise_2d(x, z) * 7.0 * rough
	ground = lerpf(ground, 1.0, 1.0 - smoothstep(30.0, 65.0, r)) # flat spawn meadow

	# slide hill: cos² dome
	var dh := p.distance_to(HILL_POS) / HILL_RADIUS
	var hill := HILL_HEIGHT * 0.5 * (1.0 + cos(PI * dh)) if dh < 1.0 else 0.0

	# the ridge: cos² cross-section along a segment, tapering at the ends
	var seg := RIDGE_B - RIDGE_A
	var t := clampf((p - RIDGE_A).dot(seg) / seg.length_squared(), 0.0, 1.0)
	var dr := p.distance_to(RIDGE_A + seg * t) / RIDGE_HALF_WIDTH
	var taper := smoothstep(0.0, 0.15, t) * smoothstep(1.0, 0.85, t)
	var ridge := RIDGE_HEIGHT * taper * 0.5 * (1.0 + cos(PI * dr)) if dr < 1.0 else 0.0

	# crater: a gaussian ring ridge around a parabolic bowl
	var dc := p.distance_to(CRATER_POS)
	var crater := CRATER_RIDGE * exp(-pow((dc - CRATER_RADIUS) / 12.0, 2.0))
	if dc < CRATER_RADIUS: crater -= CRATER_DEPTH * (1.0 - pow(dc / CRATER_RADIUS, 2.0))

	# mesa: rounded box with 3 m cliff edges, plus a ramp down its west side
	var q := (p - MESA_POS).abs() - MESA_HALF + Vector2(8.0, 8.0)
	var sd := Vector2(maxf(q.x, 0.0), maxf(q.y, 0.0)).length() + minf(maxf(q.x, q.y), 0.0) - 8.0
	var plateau := 1.0 - smoothstep(-1.5, 1.5, sd)
	var west := MESA_POS.x - MESA_HALF.x
	var ramp_t := clampf((x - (west - MESA_RAMP_RUN)) / MESA_RAMP_RUN, 0.0, 1.0)
	var ramp_side := 1.0 - smoothstep(8.0, 10.0, absf(z - MESA_POS.y))
	var ramp := ramp_t * ramp_side if x < MESA_POS.x else 0.0
	var mesa := MESA_HEIGHT * maxf(plateau, ramp)
	ground *= 1.0 - 0.7 * plateau

	var h := ground + hill + ridge + crater + mesa

	# canyon
	var cx := _canyon_x(z)
	var slope := 32.0 / 65.0 * cos(z / 65.0)
	var d := absf(x - cx) / sqrt(1.0 + slope * slope)
	var floor_half := 8.0 + 4.0 * sin(z / 40.0 + 1.0)
	var side := signf(x - cx)
	var soft := 3.0
	for e: Vector2 in CANYON_EXITS:
		if side == e.y: soft = lerpf(soft, 38.0, 1.0 - smoothstep(9.0, 20.0, absf(z - e.x)))
	var depth := CANYON_DEPTH * (1.0 - smoothstep(RIM_START - 40.0, RIM_START + 20.0, r))
	h -= depth * (1.0 - smoothstep(floor_half, floor_half + soft, d))

	# the rim
	var rim := pow(smoothstep(RIM_START, RIM_FULL, r), 1.6)
	h += rim * (95.0 + 45.0 * _ridge_noise.get_noise_2d(x, z))
	return h


## Sampled height (nearest vertex).
func _h(x: float, z: float) -> float:
	var ix := clampi(roundi(x) + HALF, 0, SIZE - 1)
	var iz := clampi(roundi(z) + HALF, 0, SIZE - 1)
	return _heights[iz * SIZE + ix]


## Lowest terrain height under a footprint (corners + centre).
func _h_min(x: float, z: float, half_x: float, half_z: float) -> float:
	var m := INF
	for sx: float in [-half_x, 0.0, half_x]:
		for sz: float in [-half_z, 0.0, half_z]:
			m = minf(m, _h(x + sx, z + sz))
	return m


## Height spread (max - min) over a disc, sampled on a coarse grid. Small = flat.
func _bumpiness(p: Vector2, radius: float) -> float:
	var lo := INF
	var hi := -INF
	for sx: int in range(-2, 3):
		for sz: int in range(-2, 3):
			var o := Vector2(sx, sz) * radius * 0.5
			if o.length() > radius: continue
			var v := _h(p.x + o.x, p.y + o.y)
			lo = minf(lo, v)
			hi = maxf(hi, v)
	return hi - lo


func _min_h() -> float:
	var m := INF
	for v: float in _heights: m = minf(m, v)
	return m


func _max_h() -> float:
	var m := -INF
	for v: float in _heights: m = maxf(m, v)
	return m

#endregion


#region terrain

## Imports the heights and the control map into a throwaway Terrain3D and saves its region files.
## Kept apart from the scene's terrain: importing and saving in the same node that then gets
## configured and packed crashed Terrain3D 1.1 headless (SIGFPE, never pinned down).
func _write_terrain_data() -> void:
	var terrain: Node3D = ClassDB.instantiate(&"Terrain3D")
	terrain.set(&"free_editor_textures", false)
	root.add_child(terrain)
	var cam := Camera3D.new() # Terrain3D wants something to centre its LODs on
	cam.position = Vector3(0.0, 80.0, 0.0)
	root.add_child(cam)
	terrain.call(&"set_camera", cam)
	await process_frame

	var height_img := Image.create_empty(SIZE, SIZE, false, Image.FORMAT_RF)
	var control_img := Image.create_empty(SIZE, SIZE, false, Image.FORMAT_RF)
	var util := &"Terrain3DUtil"
	var auto_bits: int = ClassDB.class_call_static(util, &"enc_auto", true)
	var nav_bits: int = ClassDB.class_call_static(util, &"enc_nav", true)
	var walk: float = ClassDB.class_call_static(util, &"as_float", auto_bits | nav_bits)
	var rim: float = ClassDB.class_call_static(util, &"as_float", auto_bits)
	for iz: int in SIZE:
		for ix: int in SIZE:
			height_img.set_pixel(ix, iz, Color(_heights[iz * SIZE + ix], 0.0, 0.0, 1.0))
			var r := Vector2(ix - HALF, iz - HALF).length()
			control_img.set_pixel(ix, iz, Color(walk if r < NAV_RADIUS else rim, 0.0, 0.0, 1.0))
	var data: Object = terrain.get(&"data")
	data.call(&"import_images", [height_img, control_img, null], Vector3(-HALF, 0.0, -HALF), 0.0, 1.0)
	for i: int in 30: await process_frame
	_clear_dir(DATA_DIR)
	data.call(&"save_directory", DATA_DIR)
	terrain.queue_free()
	cam.queue_free()
	await process_frame


## The scene's terrain: loads the saved regions, slope-textured greybox look, full collision.
func _add_terrain() -> Node3D:
	_write_png(_grid_image(Color(0.5, 0.49, 0.5)), "rock_albedo")
	_write_png(_grid_image(Color(0.66, 0.6, 0.38)), "ground_albedo")
	var normal := Image.create_empty(512, 512, false, Image.FORMAT_RGBA8)
	normal.fill(Color(0.5, 0.5, 1.0, 0.85)) # flat normal, roughness in alpha
	_write_png(normal, "flat_normal")
	# a headless SceneTree can't import, so run Godot's importer once for this project
	OS.execute(OS.get_executable_path(), ["--headless", "--path", ProjectSettings.globalize_path("res://"), "--import"])
	var assets: Resource = ClassDB.instantiate(&"Terrain3DAssets")
	assets.call(&"set_texture_asset", 0, _texture_asset("Rock", "rock_albedo", 0))
	assets.call(&"set_texture_asset", 1, _texture_asset("Ground", "ground_albedo", 1))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(ASSETS_PATH.get_base_dir()))
	ResourceSaver.save(assets, ASSETS_PATH)

	var terrain: Node3D = ClassDB.instantiate(&"Terrain3D")
	terrain.name = "Terrain3D"
	terrain.set(&"assets", load(ASSETS_PATH))
	terrain.set(&"data_directory", DATA_DIR)
	terrain.set(&"collision_mode", 3) # FULL_GAME: bots far from the camera need ground too
	terrain.set(&"cast_shadows", 0) # hills shading themselves isn't worth redrawing the terrain per shadow map
	_root.add_child(terrain)
	# auto shader: overlay texture on flat ground, base texture on slopes
	var mat: Object = terrain.get(&"material")
	mat.set(&"world_background", 0) # NONE: no endless terrain past the regions
	mat.set(&"auto_shader_enabled", true)
	# Terrain3D's bundled lightweight shader: measured ~4.5 ms/frame cheaper on an Iris Xe at
	# 3072x1602 (0.6 render scale) than the full one, and the greybox look doesn't need the rest
	mat.set(&"shader_override", load("res://addons/terrain_3d/extras/shaders/lightweight.gdshader"))
	mat.set(&"shader_override_enabled", true)
	mat.call(&"set_shader_param", &"auto_base_texture", 0)
	mat.call(&"set_shader_param", &"auto_overlay_texture", 1)
	mat.call(&"set_shader_param", &"auto_slope", 4.0)
	mat.call(&"set_shader_param", &"blend_sharpness", 0.9)
	return terrain


## Greybox texture: flat color with 1 m minor and 8 m major grid lines (the texture spans 8 m).
## Alpha is the height channel Terrain3D blends with (flat here).
func _grid_image(color: Color) -> Image:
	const RES := 512
	var img := Image.create_empty(RES, RES, false, Image.FORMAT_RGBA8)
	for y: int in RES:
		for x: int in RES:
			var c := color
			if x < 3 or y < 3: c = color.darkened(0.55)
			elif x % 64 == 0 or y % 64 == 0: c = color.darkened(0.35)
			c.a = 0.5
			img.set_pixel(x, y, c)
	return img


## Writes a PNG plus an .import asking for mipmaps (Terrain3D needs them) on first write.
func _write_png(img: Image, file: String) -> void:
	var path := "%s/%s.png" % [TEX_DIR, file]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(TEX_DIR))
	img.save_png(path)
	if FileAccess.file_exists(path + ".import"): return
	var f := FileAccess.open(path + ".import", FileAccess.WRITE)
	f.store_string('[remap]\n\nimporter="texture"\ntype="CompressedTexture2D"\n\n[params]\n\ncompress/mode=0\nmipmaps/generate=true\n')
	f.close()


func _texture_asset(asset_name: String, albedo_file: String, id: int) -> Resource:
	var ta: Resource = ClassDB.instantiate(&"Terrain3DTextureAsset")
	ta.set(&"name", asset_name)
	ta.set(&"id", id)
	ta.set(&"albedo_texture", load("%s/%s.png" % [TEX_DIR, albedo_file]))
	ta.set(&"normal_texture", load("%s/flat_normal.png" % TEX_DIR))
	ta.set(&"uv_scale", 0.125)
	return ta

#endregion


#region landmarks

func _make_materials() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(MAT_DIR))
	var base := load(GREYBOX) as ShaderMaterial
	for key: StringName in COLORS:
		var m := base.duplicate() as ShaderMaterial
		m.set_shader_parameter(&"base_color", COLORS[key])
		m.set_shader_parameter(&"line_color", (COLORS[key] as Color).darkened(0.55))
		var path := "%s/%s.tres" % [MAT_DIR, key]
		ResourceSaver.save(m, path)
		_mats[key] = load(path)


## Level deck from where the hill's flank reaches deck height to past the canyon's east rim.
## Two broken gaps to jump, collapsed slabs as ramps up from the meadow side.
func _build_aqueduct() -> void:
	var z := AQUEDUCT_Z
	var x0 := HILL_POS.x
	while _h(x0, z) > AQUEDUCT_DECK - 0.3 and x0 < 0.0: x0 += 1.0 # walk off the hill to deck height
	var kit := Kit.new()
	var segs := ceili((AQUEDUCT_X1 - x0) / AQUEDUCT_SEG)
	var gaps: Array[int] = [floori(segs / 3.0), floori(segs * 2.0 / 3.0)]
	var slabs: Array[float] = [-75.0, 45.0]
	for sx: float in slabs: # never break the deck right where a slab comes up
		var si := floori((sx - x0) / AQUEDUCT_SEG)
		for g: int in gaps.size(): if absi(gaps[g] - si) <= 1: gaps[g] = si + 3
	for i: int in segs:
		var xs := x0 + i * AQUEDUCT_SEG
		var xc := xs + AQUEDUCT_SEG * 0.5
		var foot := _h_min(xs, z, 1.5, 2.0) - 1.0
		kit.box(Vector3(xs, (foot + AQUEDUCT_DECK - 1.0) * 0.5, z), Vector3(3.0, AQUEDUCT_DECK - 1.0 - foot, 4.0), &"stone", 0.0, false)
		if i in gaps: continue
		kit.box(Vector3(xc, AQUEDUCT_DECK - 0.5, z), Vector3(AQUEDUCT_SEG, 1.0, 5.0), &"stone", 0.0, false)
		for s: float in [-1.0, 1.0]:
			var slab_here := false
			for sx: float in slabs: slab_here = slab_here or (s > 0.0 and absf(sx - xc) < AQUEDUCT_SEG * 0.5)
			if slab_here: continue # open the parapet where a slab comes up
			kit.box(Vector3(xc, AQUEDUCT_DECK + 0.3, z + s * 2.25), Vector3(AQUEDUCT_SEG, 0.6, 0.5), &"stone", 0.0, false)
	# collapsed slabs: ramps from the ground (south side) up to the deck
	for rx: float in slabs:
		var low := _h(rx, z + 30.0)
		var rise := AQUEDUCT_DECK - low
		var run := 28.0
		kit.box(Vector3(rx, low + rise * 0.5 - 0.4, z + 2.5 + run * 0.5), Vector3(5.0, 0.8, sqrt(rise * rise + run * run)),
				&"stone", PI, false, atan2(rise, run))
	_emit_world_kit(kit, "Aqueduct")


## The tower on Slide Hill, pillars on the mesa, a pad up the mesa cliff.
func _build_landmarks() -> void:
	var kit := Kit.new()
	var hill_top := _h(HILL_POS.x, HILL_POS.y)
	_tower(kit, Vector3(HILL_POS.x, hill_top, HILL_POS.y), 22.0)
	kit.pads.append({"at": Vector3(HILL_POS.x + 18.0, 0.0, HILL_POS.y), "to": Vector3(HILL_POS.x + 1.5, hill_top + 22.0, HILL_POS.y), "world_target": true, "peak": 6.0})
	var tops: Array[float] = [8.0, 11.0, 14.0, 10.0, 16.0, 12.0, 18.0]
	for i: int in tops.size():
		var x := MESA_POS.x - 36.0 + i * 12.0
		var pz := MESA_POS.y + (8.0 if i % 2 else -8.0)
		var base := _h_min(x, pz, 1.5, 1.5) - 0.5
		kit.box(Vector3(x, base + tops[i] * 0.5, pz), Vector3(3.0, tops[i], 3.0), &"rock", 0.0, false)
	# pad from the canyon side up onto the mesa's east cliff top
	var east := MESA_POS.x + MESA_HALF.x
	kit.pads.append({"at": Vector3(east + 18.0, 0.0, MESA_POS.y + 20.0), "to": Vector3(east - 12.0, _h(east - 12.0, MESA_POS.y + 20.0), MESA_POS.y + 20.0), "world_target": true, "peak": 6.0})
	_emit_world_kit(kit, "Landmarks")


## A climbing tower: core block with ledges spiralling up its sides every 2 m.
func _tower(kit: Kit, base: Vector3, height: float) -> void:
	var half := 4.0
	kit.box(Vector3(base.x, base.y + height * 0.5 - 1.0, base.z), Vector3(half * 2.0, height + 2.0, half * 2.0), &"ruin", 0.0, false)
	var n := int((height - 1.0) / 2.0)
	for i: int in n:
		var a := (i % 4) * PI * 0.5
		var out := Vector3(sin(a), 0.0, cos(a))
		var along := out.cross(Vector3.UP)
		var p := base + out * (half + 1.4) + along * 1.6 + Vector3.UP * (2.0 + i * 2.0 - 0.3)
		kit.box(p, Vector3(5.0, 0.6, 2.8), &"ruin", a, false)
	# long-range pads start from the -x half of the top; ground pads land on the +x half
	kit.top = base + Vector3(-2.2, height, 0.0)
	kit.has_top = true

#endregion


#region clusters

## Poisson-spaced cluster sites over the open ground, each built from a kit.
func _place_clusters() -> void:
	var order: Array[StringName] = KITS.duplicate()
	var sites: Array[Vector2] = []
	var tries := 0
	while tries < 8000:
		tries += 1
		var p := Vector2.from_angle(_rng.randf() * TAU) * sqrt(_rng.randf()) * CLUSTER_MAX_R
		if _reserved(p, 26.0): continue
		var ok := true
		for s: Vector2 in sites:
			if s.distance_to(p) < CLUSTER_SPACING:
				ok = false
				break
		if ok: sites.append(p)
	for i: int in sites.size():
		if i % order.size() == 0: _shuffle(order)
		var p := sites[i]
		var kit_name := order[i % order.size()]
		# kits with long flat runs need flat ground; fall back to ones that cope with slopes
		if kit_name in FLAT_KITS and _bumpiness(p, 24.0) > 3.0: kit_name = SLOPE_KITS[i % SLOPE_KITS.size()]
		var kit: Kit = call("_kit_" + kit_name)
		var node := _emit_kit(kit, p, _rng.randf() * TAU, "C%02d_%s" % [i, kit_name])
		_clusters.append({"pos": p, "kit": kit_name, "radius": kit.radius, "node": node})


func _reserved(p: Vector2, margin: float) -> bool:
	var r := p.length()
	if r > CLUSTER_MAX_R or r < MEADOW_RADIUS: return true # rim side, spawn meadow
	if absf(p.x - _canyon_x(p.y)) < 24.0 + margin: return true
	if absf(p.y - AQUEDUCT_Z) < 8.0 + margin and p.x > HILL_POS.x and p.x < AQUEDUCT_X1 + 10.0: return true
	var m := (p - MESA_POS).abs() - MESA_HALF
	if m.x < margin and m.y < margin: return true
	if p.x < MESA_POS.x - MESA_HALF.x and p.x > MESA_POS.x - MESA_HALF.x - MESA_RAMP_RUN - margin and absf(p.y - MESA_POS.y) < 10.0 + margin: return true
	if p.distance_to(HILL_POS) < HILL_RADIUS * 0.7: return true # keep the slide slopes clean
	if p.distance_to(CRATER_POS) < CRATER_RADIUS + 18.0 + margin: return true
	var seg := RIDGE_B - RIDGE_A
	var t := clampf((p - RIDGE_A).dot(seg) / seg.length_squared(), 0.0, 1.0)
	if p.distance_to(RIDGE_A + seg * t) < RIDGE_HALF_WIDTH + margin * 0.5: return true
	return _bumpiness(p, 20.0) > 8.0


func _shuffle(a: Array[StringName]) -> void:
	for i: int in range(a.size() - 1, 0, -1):
		var j := _rng.randi_range(0, i)
		var tmp := a[i]
		a[i] = a[j]
		a[j] = tmp


## Ring of broken walls (some low enough to vault), sometimes a wall-jump chimney with a ledge on top.
func _kit_ruins() -> Kit:
	var k := Kit.new()
	k.radius = 20.0
	var n := _rng.randi_range(7, 10)
	var heights: Array[float] = [1.2, 1.2, 2.6, 4.5, 6.5]
	for i: int in n:
		var a := TAU * i / n + _rng.randf_range(-0.2, 0.2)
		var r := _rng.randf_range(10.0, 17.0)
		var seg_len := _rng.randf_range(5.0, 11.0)
		var h := heights[_rng.randi() % heights.size()]
		k.post(cos(a) * r, sin(a) * r, Vector3(1.0, h, seg_len), &"stone", -a + _rng.randf_range(-0.4, 0.4))
	if _rng.randf() < 0.6:
		var gap := 3.6
		for s: float in [-1.0, 1.0]:
			k.post(s * (gap * 0.5 + 0.6), 0.0, Vector3(1.2, 9.5, 8.0), &"stone")
		k.box(Vector3(0.0, 10.0, 0.0), Vector3(gap + 2.4, 1.0, 8.0), &"stone", 0.0, false)
	return k


## Pillars spiralling up from 2 m to ~20 m: a hop chain, with a pad from the start to the top.
func _kit_pillars() -> Kit:
	var k := Kit.new()
	k.radius = 22.0
	var n := _rng.randi_range(9, 13)
	var a0 := _rng.randf() * TAU
	var first := Vector3.ZERO
	var last := Vector3.ZERO
	for i: int in n:
		var a := a0 + i * 0.55
		var r := lerpf(6.0, 18.0, float(i) / (n - 1))
		var h := 2.0 + i * 1.5
		var p := Vector3(cos(a) * r, h, sin(a) * r)
		k.post(p.x, p.z, Vector3(2.6, h, 2.6), &"ruin")
		if i == 0: first = p
		last = p
	var flat_first := Vector3(first.x, 0.0, first.z)
	k.pads.append({"at": flat_first - flat_first.normalized() * 4.0, "to": last, "world_target": false, "peak": 4.0})
	return k


## Platforms on stilts at different heights, bridged in a loop; ramp to the lowest, pad to the highest.
func _kit_stilts() -> Kit:
	var k := Kit.new()
	k.radius = 26.0
	var n := _rng.randi_range(3, 4)
	var heights: Array[float] = [7.0, 10.5, 14.0, 17.5]
	var pick: Array[int] = [0, 2, 1, 3]
	var tops: Array[Vector3] = []
	var a0 := _rng.randf() * TAU
	for i: int in n:
		var a := a0 + TAU * i / n
		var h := heights[pick[i] % n]
		var c := Vector3(cos(a) * 14.0, h, sin(a) * 14.0)
		tops.append(c)
		k.box(Vector3(c.x, h - 0.5, c.z), Vector3(9.0, 1.0, 9.0), &"wood", a, false)
		for cx: float in [-3.8, 3.8]:
			for cz: float in [-3.8, 3.8]:
				var leg := Basis(Vector3.UP, a) * Vector3(cx, 0.0, cz)
				k.post(c.x + leg.x, c.z + leg.z, Vector3(0.8, h - 1.0, 0.8), &"wood")
	for i: int in n:
		var a := tops[i]
		var b := tops[(i + 1) % n]
		var dir := Vector3(b.x - a.x, 0.0, b.z - a.z).normalized()
		var start := a + dir * 4.0
		var end := b - dir * 4.0
		var rise := end.y - start.y
		var run := Vector2(end.x - start.x, end.z - start.z).length()
		var mid := (start + end) * 0.5
		k.box(Vector3(mid.x, mid.y - 0.3, mid.z), Vector3(2.4, 0.6, sqrt(rise * rise + run * run) + 1.0),
				&"wood", atan2(dir.x, dir.z), false, atan2(rise, run))
	# ramp from the ground up to the lowest platform, pointing outward
	var low := 0
	var high := 0
	for i: int in n:
		if tops[i].y < tops[low].y: low = i
		if tops[i].y > tops[high].y: high = i
	var lt := tops[low]
	var out := Vector3(lt.x, 0.0, lt.z).normalized()
	var run := lt.y / tan(deg_to_rad(24.0))
	var ramp_mid := Vector3(lt.x, 0.0, lt.z) + out * (4.5 + run * 0.5)
	# +Z points outward (down the ramp), so the high end is -Z: tilt down
	k.box(Vector3(ramp_mid.x, lt.y * 0.5 - 0.4, ramp_mid.z), Vector3(3.0, 0.8, sqrt(lt.y * lt.y + run * run)), &"wood",
			atan2(out.x, out.z), false, -atan2(lt.y, run))
	k.pads.append({"at": Vector3.ZERO, "to": tops[high], "world_target": false, "peak": 4.0})
	return k


## Launch ramps of different angles, a steep quarter ramp onto a deck, a speed strip into the big one.
func _kit_kickers() -> Kit:
	var k := Kit.new()
	k.radius = 24.0
	var n := _rng.randi_range(3, 4)
	var angles: Array[float] = [16.0, 22.0, 28.0, 34.0]
	var biggest := Vector3.ZERO
	var biggest_yaw := 0.0
	var biggest_run := 0.0
	for i: int in n:
		var a := TAU * i / n + _rng.randf_range(-0.3, 0.3)
		var ang := deg_to_rad(angles[i])
		var top := _rng.randf_range(2.0, 4.0)
		var length := top / sin(ang)
		var run := top / tan(ang)
		var face := a + PI * 0.5 + _rng.randf_range(-0.5, 0.5) # roughly tangential
		var fwd := Vector3(sin(face), 0.0, cos(face))
		var c := Vector3(cos(a) * 13.0, 0.0, sin(a) * 13.0)
		# ramp rises toward +fwd (+Z), with a support block under its lip
		k.box(c + Vector3(0.0, top * 0.5 - 0.35, 0.0), Vector3(6.0, 0.7, length), &"ramp", face, false, ang)
		k.post(c.x + fwd.x * (run * 0.5 - 0.5), c.z + fwd.z * (run * 0.5 - 0.5), Vector3(6.0, top - 0.6, 1.0), &"ramp", face)
		if run > biggest_run:
			biggest_run = run
			biggest = c
			biggest_yaw = face
	# quarter ramp: 45° up to a 5 m deck
	var qa := _rng.randf() * TAU
	var qc := Vector3(cos(qa) * 4.0, 0.0, sin(qa) * 4.0)
	var qf := Vector3(sin(qa), 0.0, cos(qa))
	k.box(qc + Vector3(0.0, 2.5, 0.0), Vector3(6.0, 0.7, 5.0 * sqrt(2.0)), &"ramp", qa, false, PI * 0.25)
	k.post(qc.x + qf.x * 5.0, qc.z + qf.z * 5.0, Vector3(6.0, 5.0, 5.0), &"ramp", qa)
	# speed strip lined up with the biggest kicker, run-in from behind it
	var bf := Vector3(sin(biggest_yaw), 0.0, cos(biggest_yaw))
	k.strips.append({"at": biggest - bf * (biggest_run * 0.5 + 9.0), "yaw": biggest_yaw, "speed": 32.0})
	return k


## A climbing tower (ledges every 2 m) with a ground pad to its top. The pad stands far enough
## out that the lob is already coming down when it passes over the ledges.
func _kit_tower() -> Kit:
	var k := Kit.new()
	k.radius = 20.0
	var h := _rng.randf_range(20.0, 30.0)
	_tower(k, Vector3.ZERO, h)
	k.pads.append({"at": Vector3(18.0, 0.0, 0.0), "to": Vector3(1.6, h, 0.0), "world_target": false, "peak": 6.0})
	return k


## Grid of blocks at mixed heights with lanes between: juke field.
func _kit_blocks() -> Kit:
	var k := Kit.new()
	k.radius = 22.0
	var heights: Array[float] = [1.0, 2.0, 3.5, 6.0]
	for gx: int in range(-2, 3):
		for gz: int in range(-2, 3):
			if gx == 0 and gz == 0: continue # landing spot
			if _rng.randf() < 0.45: continue
			var s := Vector3(_rng.randf_range(3.0, 5.0), heights[_rng.randi() % heights.size()], _rng.randf_range(3.0, 5.0))
			k.post(gx * 8.0 + _rng.randf_range(-1.0, 1.0), gz * 8.0 + _rng.randf_range(-1.0, 1.0), s, &"rock")
	return k


## Rows of vaultable walls (under vault height) with one taller wall to wall-jump off.
func _kit_vaults() -> Kit:
	var k := Kit.new()
	k.radius = 20.0
	var n := _rng.randi_range(4, 6)
	var tall := floori(n * 0.5)
	for i: int in n:
		var z := (i - (n - 1) * 0.5) * 6.0
		var h := 4.0 if i == tall else _rng.randf_range(0.9, _cfg.vault_height - 0.15)
		k.post(_rng.randf_range(-2.0, 2.0), z, Vector3(14.0, h, 0.8), &"stone")
	return k


## Raised launch disc with two gentle ramps up; long-range pads get added later (_add_launchers).
func _kit_hub() -> Kit:
	var k := Kit.new()
	k.radius = 18.0
	k.box(Vector3(0.0, 0.75, 0.0), Vector3(14.0, 1.5, 14.0), &"hub", 0.0, true)
	var run := 1.5 / tan(deg_to_rad(14.0))
	for s: float in [-1.0, 1.0]:
		# +Z points away from the disc, so the ramp drops toward +Z
		k.box(Vector3(s * (7.0 + run * 0.5), 0.75 - 0.3, 0.0), Vector3(5.0, 0.6, sqrt(run * run + 2.25) + 0.5), &"hub",
				PI * 0.5 * s, false, -atan2(1.5, run))
	return k


## Long-range pads: every hub throws you to 3 other clusters, every tower top to 1.
func _add_launchers() -> void:
	for i: int in _clusters.size():
		var c := _clusters[i]
		var kit_name: StringName = c.kit
		if kit_name != &"hub" and kit_name != &"tower": continue
		var p: Vector2 = c.pos
		var node: Node3D = c.node
		var targets: Array[Dictionary] = []
		for j: int in _clusters.size():
			if j == i: continue
			var d := (_clusters[j].pos as Vector2).distance_to(p)
			if d > 70.0 and d < 170.0: targets.append(_clusters[j])
		if targets.is_empty(): continue
		targets.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			return (a.pos as Vector2).angle_to_point(p) < (b.pos as Vector2).angle_to_point(p))
		var want := 3 if kit_name == &"hub" else 1
		var step := maxi(1, floori(targets.size() / float(want)))
		var made := 0
		for t: int in targets.size():
			if made >= want: break
			var tc := targets[(t * step + i) % targets.size()]
			var tp: Vector2 = tc.pos
			# land on open ground just in front of the target cluster
			var back := (p - tp).normalized()
			var land := tp + back * ((tc.radius as float) + 8.0)
			var land3 := Vector3(land.x, _h(land.x, land.y), land.y)
			var from: Vector3
			if kit_name == &"hub":
				var o := Vector2.from_angle(TAU * made / want) * 4.0
				from = Vector3(p.x + o.x, node.position.y + 1.5, p.y + o.y)
			else:
				from = node.get_meta(&"top", node.position) as Vector3
			# higher arcs until it clears the hills and clusters on the way; else try another target
			var base_peak := clampf(from.distance_to(land3) * 0.12, 8.0, 30.0)
			for k: float in [1.0, 1.6, 2.4]:
				if _arc_clear(from, land3, base_peak * k, [c, tc]):
					_pad_world(node, from, land3, base_peak * k, false)
					made += 1
					break


## Hop pads and speed strips out in the open between clusters, aimed at the nearest cluster.
func _add_open_ground_pads_and_strips() -> void:
	var open := _node(_props, "Open")
	var made_pads := 0
	var made_strips := 0
	var tries := 0
	while (made_pads < 14 or made_strips < 10) and tries < 4000:
		tries += 1
		var p := Vector2.from_angle(_rng.randf() * TAU) * sqrt(_rng.randf()) * (CLUSTER_MAX_R - 10.0)
		if p.length() > MEADOW_RADIUS and _reserved(p, 6.0): continue
		var clear := true
		var nearest := {}
		var nd := INF
		for c: Dictionary in _clusters:
			var d := (c.pos as Vector2).distance_to(p)
			if d < (c.radius as float) + 10.0: clear = false
			if d < nd and d > 35.0:
				nd = d
				nearest = c
		if not clear or nearest.is_empty() or nd > 85.0: continue
		var tp: Vector2 = nearest.pos
		var dir := (tp - p).normalized()
		if made_pads < 14 and (made_strips >= 10 or _rng.randf() < 0.55):
			var land := tp - dir * ((nearest.radius as float) + 6.0)
			var from := Vector3(p.x, _h(p.x, p.y), p.y)
			var to := Vector3(land.x, _h(land.x, land.y), land.y)
			var peak := clampf(nd * 0.15, 6.0, 16.0)
			if not _arc_clear(from, to, peak, [nearest]): continue
			_pad_world(open, from, to, peak, false)
			made_pads += 1
		elif made_strips < 10 and _bumpiness(p, 8.0) < 1.5:
			_strip(open, Vector3(p.x, _h(p.x, p.y), p.y), atan2(dir.x, dir.y), 34.0)
			made_strips += 1

#endregion


#region emitting

## Places a kit at site p (ground under it = local y 0), rotated by yaw. Grounded boxes are
## stretched down to the lowest ground under them so nothing floats on a slope.
func _emit_kit(kit: Kit, p: Vector2, yaw: float, node_name: String) -> Node3D:
	var base := Transform3D(Basis(Vector3.UP, yaw), Vector3(p.x, _h(p.x, p.y), p.y))
	var holder := _node(_props, node_name)
	holder.transform = base
	_emit_boxes(holder, kit.boxes, base)
	for pad: Dictionary in kit.pads:
		var at: Vector3 = base * (pad.at as Vector3)
		at.y = _h(at.x, at.z)
		var to: Vector3 = pad.to if pad.world_target else base * (pad.to as Vector3)
		_pad_world(holder, at, to, pad.peak, true)
	for s: Dictionary in kit.strips:
		var at: Vector3 = base * (s.at as Vector3)
		_strip(holder, Vector3(at.x, _h(at.x, at.z), at.z), (s.yaw as float) + yaw, s.speed)
	if kit.has_top: holder.set_meta(&"top", base * kit.top)
	return holder


## Kit already in world space (landmarks, aqueduct).
func _emit_world_kit(kit: Kit, node_name: String) -> void:
	var holder := _node(_props, node_name)
	_emit_boxes(holder, kit.boxes, Transform3D.IDENTITY)
	for pad: Dictionary in kit.pads:
		var at: Vector3 = pad.at
		at.y = _h(at.x, at.z)
		_pad_world(holder, at, pad.to, pad.peak, true)


## One StaticBody3D with a box shape per piece, and one merged mesh (a surface per material).
func _emit_boxes(holder: Node3D, boxes: Array[Dictionary], base: Transform3D) -> void:
	if boxes.is_empty(): return
	var body := StaticBody3D.new()
	body.name = "Body"
	holder.add_child(body)
	var inv := base.affine_inverse()
	var tools := {}
	var i := 0
	for b: Dictionary in boxes:
		var xf: Transform3D = base * (b.xf as Transform3D)
		var size: Vector3 = b.size
		if b.grounded: # stretch down to the lowest ground under it (+0.5 m buried)
			var top := xf.origin.y + size.y * 0.5
			var reach := maxf(size.x, size.z) * 0.5
			var ground := _h_min(xf.origin.x, xf.origin.z, reach, reach) - 0.5
			if ground < top - size.y:
				size.y = top - ground
				xf.origin.y = top - size.y * 0.5
		var local := inv * xf
		var shape := BoxShape3D.new()
		shape.size = size
		var col := CollisionShape3D.new()
		col.name = "S%03d" % i
		col.shape = shape
		col.transform = local
		body.add_child(col)
		var mesh := BoxMesh.new()
		mesh.size = size
		var st: SurfaceTool = tools.get(b.mat)
		if not st:
			st = SurfaceTool.new()
			st.begin(Mesh.PRIMITIVE_TRIANGLES)
			tools[b.mat] = st
		st.append_from(mesh, 0, local)
		i += 1
	var am := ArrayMesh.new()
	for key: StringName in tools:
		(tools[key] as SurfaceTool).commit(am)
		am.surface_set_material(am.get_surface_count() - 1, _mats[key])
	var path := "%s/%s.res" % [MESH_DIR, holder.name.to_snake_case()]
	ResourceSaver.save(am, path)
	var mi := MeshInstance3D.new()
	mi.name = "Mesh"
	mi.mesh = load(path)
	body.add_child(mi)


## Jump pad at world `at` that lobs you onto world `to`, peaking `peak` m above the higher of the
## two. The sideways speed comes from simulating the character's own hands-off flight (gravity,
## fall multiplier, air drag, soft speed cap), so it lands on target with no input.
## Adds a nav link so bots know where the pad goes.
func _pad_world(parent: Node3D, at: Vector3, to: Vector3, peak: float, short: bool) -> void:
	var up := maxf(to.y, at.y) - at.y + peak
	var hi := _lob_speed(at, to, up)
	var dir := Vector2(to.x - at.x, to.z - at.z).normalized()
	var pad := (load(JUMP_PAD) as PackedScene).instantiate() as Node3D
	pad.name = "Pad%d" % _pad_count
	_pad_count += 1
	parent.add_child(pad)
	pad.global_position = at + Vector3(0.0, 0.05, 0.0)
	pad.global_rotation = Vector3.ZERO # launch_velocity is in pad space: keep it world-aligned
	pad.set(&"launch_height", up)
	pad.set(&"launch_velocity", Vector3(dir.x, 0.0, dir.y) * hi)
	pad.set(&"keep_horizontal", false)
	_link(at, to, GameMap.LINK_PAD, 0.5 if short else 0.3)
	if to.y - _h(to.x, to.z) > 2.0: _raised_landings.append(to)


## Sideways launch speed that lands a hands-off lob from `at` on `to`, going `up` m high.
func _lob_speed(at: Vector3, to: Vector3, up: float) -> float:
	var vy := sqrt(2.0 * _cfg.gravity * up)
	var dist := Vector2(to.x - at.x, to.z - at.z).length()
	var lo := 0.0
	var hi := 200.0
	for it: int in 40: # bisect
		var mid := (lo + hi) * 0.5
		if _flight_distance(mid, vy, to.y - at.y) < dist: lo = mid
		else: hi = mid
	return hi


## True if the lob from `at` to `to` (peaking `peak` m above the higher end) stays 3 m over the
## terrain and 25 m over every cluster it passes (except the ones in `skip`) until it comes down.
func _arc_clear(at: Vector3, to: Vector3, peak: float, skip: Array) -> bool:
	const DT := 1.0 / 30.0
	var up := maxf(to.y, at.y) - at.y + peak
	var v := _lob_speed(at, to, up)
	var vy := sqrt(2.0 * _cfg.gravity * up)
	var dir := Vector2(to.x - at.x, to.z - at.z).normalized()
	var pos := Vector2(at.x, at.z)
	var y := at.y
	var end := Vector2(to.x, to.z)
	for i: int in 600:
		var g := _cfg.gravity * (_cfg.fall_gravity_mult if vy < 0.0 else 1.0)
		v = maxf(v - _cfg.air_decel * DT, 0.0)
		vy = maxf(vy - g * DT, -_cfg.terminal_velocity)
		if v > _cfg.soft_speed_cap:
			v = maxf(v - _cfg.soft_cap_drag * v * (v - _cfg.soft_speed_cap) * DT, _cfg.soft_speed_cap)
		pos += dir * v * DT
		y += vy * DT
		if pos.distance_to(end) < 12.0 or (vy < 0.0 and y <= to.y): return true # final approach
		if pos.distance_to(Vector2(at.x, at.z)) < 12.0: continue # still leaving the pad's own cluster
		if y < _h(pos.x, pos.y) + 3.0: return false
		# landmarks: aqueduct deck, the hill tower, the mesa pillars
		if absf(pos.y - AQUEDUCT_Z) < 5.0 and pos.x > HILL_POS.x and pos.x < AQUEDUCT_X1 + 6.0 and y < AQUEDUCT_DECK + 4.0: return false
		if pos.distance_to(HILL_POS) < 8.0 and y < _h(HILL_POS.x, HILL_POS.y) + 26.0: return false
		var m := (pos - MESA_POS).abs() - MESA_HALF
		if m.x < 4.0 and m.y < 4.0 and y < MESA_HEIGHT + 22.0: return false
		for c: Dictionary in _clusters:
			if c in skip: continue
			var cp: Vector2 = c.pos
			if pos.distance_to(cp) < (c.radius as float) and y < _h(cp.x, cp.y) + 25.0: return false
	return true


## Horizontal distance covered before coming back down to height dy, hands-off.
func _flight_distance(speed: float, vy: float, dy: float) -> float:
	const DT := 1.0 / 120.0
	var y := 0.0
	var x := 0.0
	var v := speed
	for i: int in 2400:
		var g := _cfg.gravity * (_cfg.fall_gravity_mult if vy < 0.0 else 1.0)
		v = maxf(v - _cfg.air_decel * DT, 0.0)
		vy = maxf(vy - g * DT, -_cfg.terminal_velocity)
		if v > _cfg.soft_speed_cap:
			v = maxf(v - _cfg.soft_cap_drag * v * (v - _cfg.soft_speed_cap) * DT, _cfg.soft_speed_cap)
		x += v * DT
		y += vy * DT
		if vy < 0.0 and y <= dy: return x
	return x


## Every pad that lands you on top of something (pillar, tower, platform, arch) gets a drop link
## back down, or a bot that rode it up has no way off. Finds clear ground with downward rays.
func _add_drop_links() -> void:
	var space := _root.get_world_3d().direct_space_state
	var made := 0
	for top: Vector3 in _raised_landings:
		for reach: float in [4.0, 6.0, 9.0]:
			var done := false
			for k: int in 8:
				var d := Vector2.from_angle(TAU * k / 8.0) * reach
				var q := PhysicsRayQueryParameters3D.create(Vector3(top.x + d.x, top.y + 0.5, top.z + d.y), Vector3(top.x + d.x, top.y - 80.0, top.z + d.y))
				var hit := space.intersect_ray(q)
				if hit.is_empty(): continue
				var p: Vector3 = hit.position
				if absf(p.y - _h(p.x, p.z)) > 0.6: continue # landed on another prop, not the ground
				_link(top, p, GameMap.LINK_DROP, 1.0)
				made += 1
				done = true
				break
			if done: break
	print("drop links: %d / %d raised landings" % [made, _raised_landings.size()])


## Merges navmesh vertices closer than eps and drops polygons that collapse. Recast leaves the odd
## cluster of near-identical vertices where a prop meets the terrain at a shallow angle; the
## navigation map then finds 3+ edges in one spot ("edge merge errors") and can't connect them.
func _weld_navmesh(nm: NavigationMesh, eps: float) -> void:
	var verts := nm.get_vertices()
	var parent := PackedInt32Array()
	parent.resize(verts.size())
	for i: int in verts.size(): parent[i] = i
	var grid := {}
	for i: int in verts.size():
		var key := Vector3i((verts[i] / eps).floor())
		for dx: int in range(-1, 2):
			for dy: int in range(-1, 2):
				for dz: int in range(-1, 2):
					for j: int in grid.get(key + Vector3i(dx, dy, dz), []):
						if verts[i].distance_to(verts[j]) < eps: parent[i] = _root_of(parent, j)
		if not grid.has(key): grid[key] = []
		(grid[key] as Array).append(i)
	# the navigation map rasterizes vertices into cell-sized buckets to find shared edges: anything
	# sharing a bucket is the same vertex to it, so make it the same vertex here too
	var buckets := {}
	for i: int in verts.size():
		var v := verts[i]
		var b := Vector3i(floori(v.x / GameMap.NAV_CELL), floori(v.y / GameMap.NAV_CELL_HEIGHT), floori(v.z / GameMap.NAV_CELL))
		if buckets.has(b): parent[_root_of(parent, i)] = _root_of(parent, buckets[b])
		else: buckets[b] = i
	var polys: Array[PackedInt32Array] = []
	for pi: int in nm.get_polygon_count():
		var out := PackedInt32Array()
		for idx: int in nm.get_polygon(pi):
			var r := _root_of(parent, idx)
			if out.is_empty() or (out[out.size() - 1] != r and out[0] != r): out.append(r)
		if out.size() >= 3: polys.append(out)
	# a valid mesh uses each directed edge once; a polygon reusing one overlaps a neighbour
	# (Recast leaves the odd stray triangle like that), so drop it
	var used := {}
	nm.clear_polygons()
	for poly: PackedInt32Array in polys:
		var overlaps := false
		for k: int in poly.size():
			if used.has(Vector2i(poly[k], poly[(k + 1) % poly.size()])): overlaps = true
		if overlaps: continue
		for k: int in poly.size(): used[Vector2i(poly[k], poly[(k + 1) % poly.size()])] = true
		nm.add_polygon(poly)


func _root_of(parent: PackedInt32Array, i: int) -> int:
	while parent[i] != i: i = parent[i]
	return i


## Speed strip pushing toward yaw (radians, 0 = +Z).
func _strip(parent: Node3D, at: Vector3, yaw: float, speed: float) -> void:
	var strip := (load(SPEED_STRIP) as PackedScene).instantiate() as Node3D
	strip.name = "Strip%d" % parent.get_child_count()
	parent.add_child(strip)
	strip.global_position = at + Vector3(0.0, 0.05, 0.0)
	strip.global_rotation = Vector3(0.0, yaw + PI, 0.0) # the strip pushes along its own -Z
	strip.set(&"boost_speed", speed)


func _link(from: Vector3, to: Vector3, kind: int, cost: float) -> void:
	var link := NavigationLink3D.new()
	link.name = "Link%d" % _link_count
	_link_count += 1
	link.start_position = from
	link.end_position = to
	link.travel_cost = cost
	link.set_meta(GameMap.LINK_KIND, kind)
	_nav.add_child(link)

#endregion


#region navmesh

## Bakes the navmesh in NAV_CHUNK squares (borders cut so neighbours line up and the navigation
## map joins them), saves each chunk and adds a NavigationRegion3D for it.
func _bake_navmesh(terrain: Node3D) -> void:
	_props.add_to_group(&"nav_source")
	var probe := GameMap.make_navmesh()
	var props_src := NavigationMeshSourceGeometryData3D.new()
	NavigationServer3D.parse_source_geometry_data(probe, props_src, _root)
	_clear_dir(NAV_DIR)
	var n := ceili(NAV_RADIUS / NAV_CHUNK)
	var count := 0
	for gx: int in range(-n, n):
		for gz: int in range(-n, n):
			var x0 := gx * NAV_CHUNK
			var z0 := gz * NAV_CHUNK
			var nearest := Vector2(clampf(0.0, x0, x0 + NAV_CHUNK), clampf(0.0, z0, z0 + NAV_CHUNK))
			if nearest.length() > NAV_RADIUS: continue
			var nm := GameMap.make_navmesh()
			nm.border_size = NAV_BORDER
			nm.edge_max_error = 1.0
			nm.edge_max_length = 0.0 # open terrain: no need to chop big polygons up (fewer = faster queries)
			nm.filter_baking_aabb = AABB(Vector3(x0 - NAV_BORDER, -60.0, z0 - NAV_BORDER),
					Vector3(NAV_CHUNK + NAV_BORDER * 2.0, 260.0, NAV_CHUNK + NAV_BORDER * 2.0))
			var src := NavigationMeshSourceGeometryData3D.new()
			src.merge(props_src)
			var faces: PackedVector3Array = terrain.call(&"generate_nav_mesh_source_geometry", nm.filter_baking_aabb, true)
			src.add_faces(faces, Transform3D.IDENTITY)
			NavigationServer3D.bake_from_source_geometry_data(nm, src)
			_weld_navmesh(nm, 0.15)
			if nm.get_polygon_count() == 0: continue
			var path := "%s/chunk_%d_%d.res" % [NAV_DIR, gx, gz]
			ResourceSaver.save(nm, path)
			var region := NavigationRegion3D.new()
			region.name = "Chunk_%d_%d" % [gx, gz]
			region.navigation_mesh = load(path)
			_nav.add_child(region)
			count += 1
		await process_frame
	_props.remove_from_group(&"nav_source")
	print("navmesh chunks: %d" % count)

#endregion


#region scene

func _add_environment() -> void:
	var env := WorldEnvironment.new()
	env.name = "WorldEnvironment"
	env.environment = load(ENV)
	_root.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation_degrees = Vector3(-50.0, -30.0, 0.0)
	sun.light_energy = 1.2
	sun.shadow_enabled = true
	# a big map at 400 m / 4 splits redrew the terrain into 4 shadow maps: too much for integrated GPUs
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.directional_shadow_max_distance = 160.0
	_root.add_child(sun)


func _add_spawns() -> void:
	var spawns := _node(_root, "Spawns")
	for i: int in 8:
		var p := Vector2.from_angle(TAU * i / 8.0) * 12.0
		var m := Marker3D.new()
		m.name = "Spawn%d" % i
		m.position = Vector3(p.x, _h(p.x, p.y) + 0.5, p.y)
		spawns.add_child(m)
		m.add_to_group(&"spawn", true)


func _add_labels() -> void:
	var labels := _node(_root, "Labels")
	var spots := {
		"SLIDE HILL": Vector2(HILL_POS.x, HILL_POS.y + 30.0),
		"THE MESA": MESA_POS,
		"THE RIDGE": (RIDGE_A + RIDGE_B) * 0.5,
		"THE CRATER": CRATER_POS,
		"CANYON": Vector2(_canyon_x(40.0), 40.0),
		"AQUEDUCT": Vector2(40.0, AQUEDUCT_Z),
	}
	for text: String in spots:
		var p: Vector2 = spots[text]
		var l := Label3D.new()
		l.name = text.replace(" ", "")
		l.text = text
		l.position = Vector3(p.x, _h(p.x, p.y) + 32.0, p.y)
		l.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
		l.font_size = 256
		l.pixel_size = 0.04
		l.outline_size = 40
		labels.add_child(l)
		l.add_to_group(&"map_labels", true)


func _node(parent: Node, node_name: String) -> Node3D:
	var n := Node3D.new()
	n.name = node_name
	parent.add_child(n)
	return n


func _clear_dir(res_dir: String) -> void:
	var dir := ProjectSettings.globalize_path(res_dir)
	if DirAccess.dir_exists_absolute(dir): # stale files from an older layout would hang around
		for f: String in DirAccess.get_files_at(dir): DirAccess.remove_absolute(dir.path_join(f))
	DirAccess.make_dir_recursive_absolute(dir)


func _own(node: Node, owner_node: Node) -> void:
	for c: Node in node.get_children():
		c.owner = owner_node
		# instanced scenes (pads, strips) keep their own children, and Terrain3D's children are its
		# own runtime helpers (mouse/buffer viewports, labels), rebuilt every time it loads
		if c.scene_file_path.is_empty() and c.get_class() != &"Terrain3D": _own(c, owner_node)

#endregion
