extends RefCounted
# preload as MapGen (tools/ is .gdignore'd, so no class_name)

const MapKit := preload("res://tools/mapgen/lib/map_kit.gd")

## Shared map generator: everything a greybox map script needs except its own layout.
##   heightfield  bake a height function into a grid, sample it (h, h_min, bumpiness)
##   terrain      Terrain3D data + scene node (greybox textures, full collision, lightweight shader)
##   props        place MapKits (Poisson-spaced clusters), merged bodies/meshes, aimed pads,
##                speed strips, long-range launchers, hop pads
##   navigation   chunked pre-baked navmesh (welded), pad/drop links, auto jump/climb/drop links
##   scene        environment, spawns, labels, owners, save
## A map script (see overworld_gen.gd) creates one, sets the output paths, seeds rng, and calls
## these in order. Everything is deterministic for a given seed.

const GREYBOX := "res://assets/tres/materials/greybox.tres"
const MAT_DIR := "res://assets/tres/materials/greybox"
const TEX_DIR := "res://assets/images/terrain"
const JUMP_PAD := "res://scn/props/jump_pad.tscn"
const SPEED_STRIP := "res://scn/props/speed_strip.tscn"
const MOVEMENT := "res://assets/tres/movement/default_movement.tres"

# auto jump links, from the default movement: jump apex ~2.5 m, vault pulls you up 1.5 m more,
# a running jump at 14 m/s carries ~10 m on the flat (kept well short of that)
const CLIMB_UP_MAX := 3.6
const CLIMB_REACH := 2.0
const GAP_MIN := 1.0
const GAP_MAX := 6.0
const GAP_RISE := 2.2         # a running jump lands this much higher...
const GAP_RISE_REACH := 4.5   # ...if it's within this far (level gaps get the full GAP_MAX)
const DROP_REACH := 4.0
# wall-jumping up a wall (jump + 3 wall-jumps, leaning in) tops out ~11.6 m: links up to this
const WALLJUMP_UP_MAX := 9.0
const WALLJUMP_REACH := 2.5
const EDGE_STEP := 1.5

# outputs (set by the map script)
var data_dir := ""   # Terrain3D region files
var nav_dir := ""    # navmesh chunks + jump_links.res
var mesh_dir := ""   # merged cluster meshes
var assets_path := "" # Terrain3DAssets .tres

## Navigable disc (terrain nav bit, navmesh chunks) around the origin.
var nav_radius := 300.0
var nav_chunk := 128.0
var nav_border := 2.0
## Optional (pos: Vector2, y: float) -> bool: true where a launch arc would hit a map landmark.
var arc_blocked := Callable()
## > 0: emitted meshes stop drawing past this distance (dense maps: far forest isn't worth it).
var fade_distance := 0.0
## > 0: open speed strips point down a lane this long that's clear of every cluster (and of
## arc_blocked), turned as little as possible off the nearest cluster. 0: straight at it.
var strip_lane := 0.0

var tree: SceneTree
var cfg: MovementConfig
var rng := RandomNumberGenerator.new()
var size := 1024
var half := 512
var heights := PackedFloat32Array()
var root: Node3D
var props: Node3D
var nav: Node3D
var mats := {}
var clusters: Array[Dictionary] = [] # {pos: Vector2, kit: StringName, radius: float, node: Node3D}
var pad_count := 0
var link_count := 0
var raised_landings: Array[Vector3] = [] # pad targets above the ground: bots need a way back down
var chunk_meshes: Array[NavigationMesh] = []


func _init(tree_: SceneTree, size_: int) -> void:
	tree = tree_
	size = size_
	half = size_ / 2
	cfg = load(MOVEMENT) as MovementConfig


#region heightfield

## Fills the grid from height(x, z) -> float, one sample per metre, centred on the origin.
func bake_heights(height: Callable) -> void:
	heights.resize(size * size)
	for iz: int in size:
		for ix: int in size:
			heights[iz * size + ix] = height.call(float(ix - half), float(iz - half))


## Sampled height (nearest vertex).
func h(x: float, z: float) -> float:
	var ix := clampi(roundi(x) + half, 0, size - 1)
	var iz := clampi(roundi(z) + half, 0, size - 1)
	return heights[iz * size + ix]


## Lowest terrain height under a footprint (corners + centre).
func h_min(x: float, z: float, half_x: float, half_z: float) -> float:
	var m := INF
	for sx: float in [-half_x, 0.0, half_x]:
		for sz: float in [-half_z, 0.0, half_z]:
			m = minf(m, h(x + sx, z + sz))
	return m


## Height spread (max - min) over a disc, sampled on a coarse grid. Small = flat.
func bumpiness(p: Vector2, radius: float) -> float:
	var lo := INF
	var hi := -INF
	for sx: int in range(-2, 3):
		for sz: int in range(-2, 3):
			var o := Vector2(sx, sz) * radius * 0.5
			if o.length() > radius: continue
			var v := h(p.x + o.x, p.y + o.y)
			lo = minf(lo, v)
			hi = maxf(hi, v)
	return hi - lo


func min_h() -> float:
	var m := INF
	for v: float in heights: m = minf(m, v)
	return m


func max_h() -> float:
	var m := -INF
	for v: float in heights: m = maxf(m, v)
	return m

#endregion


#region terrain

## Imports the heights and the control map into a throwaway Terrain3D and saves its region files.
## Kept apart from the scene's terrain: importing and saving in the same node that then gets
## configured and packed crashed Terrain3D 1.1 headless (SIGFPE, never pinned down).
func write_terrain_data() -> void:
	var terrain: Node3D = ClassDB.instantiate(&"Terrain3D")
	terrain.set(&"free_editor_textures", false)
	tree.root.add_child(terrain)
	var cam := Camera3D.new() # Terrain3D wants something to centre its LODs on
	cam.position = Vector3(0.0, 80.0, 0.0)
	tree.root.add_child(cam)
	terrain.call(&"set_camera", cam)
	await tree.process_frame

	var height_img := Image.create_empty(size, size, false, Image.FORMAT_RF)
	var control_img := Image.create_empty(size, size, false, Image.FORMAT_RF)
	var util := &"Terrain3DUtil"
	var auto_bits: int = ClassDB.class_call_static(util, &"enc_auto", true)
	var nav_bits: int = ClassDB.class_call_static(util, &"enc_nav", true)
	var walk: float = ClassDB.class_call_static(util, &"as_float", auto_bits | nav_bits)
	var rim: float = ClassDB.class_call_static(util, &"as_float", auto_bits)
	for iz: int in size:
		for ix: int in size:
			height_img.set_pixel(ix, iz, Color(heights[iz * size + ix], 0.0, 0.0, 1.0))
			var r := Vector2(ix - half, iz - half).length()
			control_img.set_pixel(ix, iz, Color(walk if r < nav_radius else rim, 0.0, 0.0, 1.0))
	var data: Object = terrain.get(&"data")
	data.call(&"import_images", [height_img, control_img, null], Vector3(-half, 0.0, -half), 0.0, 1.0)
	for i: int in 30: await tree.process_frame
	clear_dir(data_dir)
	data.call(&"save_directory", data_dir)
	terrain.queue_free()
	cam.queue_free()
	await tree.process_frame


## The scene's terrain: loads the saved regions, slope-textured greybox look, full collision.
## ground / rock: flat-ground and slope colours (each gets a greybox grid texture).
func add_terrain(ground_file: String = "ground_albedo", ground := Color(0.66, 0.6, 0.38),
		rock_file: String = "rock_albedo", rock := Color(0.5, 0.49, 0.5)) -> Node3D:
	_write_png(_grid_image(rock), rock_file)
	_write_png(_grid_image(ground), ground_file)
	var normal := Image.create_empty(512, 512, false, Image.FORMAT_RGBA8)
	normal.fill(Color(0.5, 0.5, 1.0, 0.85)) # flat normal, roughness in alpha
	_write_png(normal, "flat_normal")
	# a headless SceneTree can't import, so run Godot's importer once for this project
	OS.execute(OS.get_executable_path(), ["--headless", "--path", ProjectSettings.globalize_path("res://"), "--import"])
	var assets: Resource = ClassDB.instantiate(&"Terrain3DAssets")
	assets.call(&"set_texture_asset", 0, _texture_asset("Rock", rock_file, 0))
	assets.call(&"set_texture_asset", 1, _texture_asset("Ground", ground_file, 1))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(assets_path.get_base_dir()))
	ResourceSaver.save(assets, assets_path)

	var terrain: Node3D = ClassDB.instantiate(&"Terrain3D")
	terrain.name = "Terrain3D"
	terrain.set(&"assets", load(assets_path))
	terrain.set(&"data_directory", data_dir)
	terrain.set(&"collision_mode", 3) # FULL_GAME: bots far from the camera need ground too
	terrain.set(&"cast_shadows", 0) # hills shading themselves isn't worth redrawing the terrain per shadow map
	root.add_child(terrain)
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


#region scene setup

## Greybox materials, one per name: colors = {name: Color}. Saved as .tres so scenes reference them.
func make_materials(colors: Dictionary) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(MAT_DIR))
	var base := load(GREYBOX) as ShaderMaterial
	for key: StringName in colors:
		var m := base.duplicate() as ShaderMaterial
		m.set_shader_parameter(&"base_color", colors[key])
		m.set_shader_parameter(&"line_color", (colors[key] as Color).darkened(0.55))
		var path := "%s/%s.tres" % [MAT_DIR, key]
		ResourceSaver.save(m, path)
		mats[key] = load(path)


## The map's root node (with its GameMap script) in the tree, ready for children.
func begin_scene(node_name: String, script_path: String) -> Node3D:
	root = Node3D.new()
	root.name = node_name
	root.set_script(load(script_path))
	return root


## Adds the root to the tree (after the caller has set its exported properties).
func enter_tree() -> void:
	tree.root.add_child(root)


## Holder nodes for props and navigation; clears the mesh output folder.
func begin_props() -> void:
	props = node(root, "Props")
	nav = node(root, "Navigation")
	clear_dir(mesh_dir)


func add_environment(env_path: String, shadow_distance: float = 160.0) -> void:
	var env := WorldEnvironment.new()
	env.name = "WorldEnvironment"
	env.environment = load(env_path)
	root.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation_degrees = Vector3(-50.0, -30.0, 0.0)
	sun.light_energy = 1.2
	sun.shadow_enabled = true
	# a big map at 400 m / 4 splits redrew the terrain into 4 shadow maps: too much for integrated GPUs
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.directional_shadow_max_distance = shadow_distance
	root.add_child(sun)


## A ring of spawn markers on the ground around `centre`.
func add_spawns(centre: Vector2 = Vector2.ZERO, count: int = 8, radius: float = 12.0) -> void:
	var spawns := node(root, "Spawns")
	for i: int in count:
		var p := centre + Vector2.from_angle(TAU * i / count) * radius
		var m := Marker3D.new()
		m.name = "Spawn%d" % i
		m.position = Vector3(p.x, h(p.x, p.y) + 0.5, p.y)
		spawns.add_child(m)
		m.add_to_group(&"spawn", true)


## Big floating names: spots = {text: Vector2}, `lift` m above the ground there (or lifts[text]).
func add_labels(spots: Dictionary, lift: float = 32.0, lifts: Dictionary = {}) -> void:
	var labels := node(root, "Labels")
	for text: String in spots:
		var p: Vector2 = spots[text]
		var l := Label3D.new()
		l.name = text.replace(" ", "")
		l.text = text
		l.position = Vector3(p.x, h(p.x, p.y) + float(lifts.get(text, lift)), p.y)
		l.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
		l.font_size = 256
		l.pixel_size = 0.04
		l.outline_size = 40
		labels.add_child(l)
		l.add_to_group(&"map_labels", true)


func node(parent: Node, node_name: String) -> Node3D:
	var n := Node3D.new()
	n.name = node_name
	parent.add_child(n)
	return n


static func clear_dir(res_dir: String) -> void:
	var dir := ProjectSettings.globalize_path(res_dir)
	if DirAccess.dir_exists_absolute(dir): # stale files from an older layout would hang around
		for f: String in DirAccess.get_files_at(dir): DirAccess.remove_absolute(dir.path_join(f))
	DirAccess.make_dir_recursive_absolute(dir)


## Owns every generated node to the root and saves the scene. Returns the save error.
func save_scene(path: String) -> Error:
	_own(root, root)
	var scene := PackedScene.new()
	var err := scene.pack(root)
	if err == OK: err = ResourceSaver.save(scene, path)
	return err


func _own(n: Node, owner_node: Node) -> void:
	for c: Node in n.get_children():
		c.owner = owner_node
		# instanced scenes (pads, strips) keep their own children, and Terrain3D's children are its
		# own runtime helpers (mouse/buffer viewports, labels), rebuilt every time it loads
		if c.scene_file_path.is_empty() and c.get_class() != &"Terrain3D": _own(c, owner_node)

#endregion


#region clusters

## Poisson-spaced cluster sites (at least `spacing` apart, within `max_r`, not where
## reserved(p: Vector2, margin: float) -> bool says), each built by make_kit(name: StringName) ->
## MapKit. Kit names cycle through `kits` in shuffled rounds; a `flat` kit on bumpy ground swaps
## for one of `sloped`.
func place_clusters(kits: Array[StringName], flat: Array[StringName], sloped: Array[StringName],
		spacing: float, max_r: float, reserved: Callable, make_kit: Callable) -> void:
	var order: Array[StringName] = kits.duplicate()
	var sites: Array[Vector2] = []
	var tries := 0
	while tries < 8000:
		tries += 1
		var p := Vector2.from_angle(rng.randf() * TAU) * sqrt(rng.randf()) * max_r
		if reserved.call(p, 26.0): continue
		var ok := true
		for s: Vector2 in sites:
			if s.distance_to(p) < spacing:
				ok = false
				break
		if ok: sites.append(p)
	for i: int in sites.size():
		if i % order.size() == 0: _shuffle(order)
		var p := sites[i]
		var kit_name := order[i % order.size()]
		# kits with long flat runs need flat ground; fall back to ones that cope with slopes
		if kit_name in flat and bumpiness(p, 24.0) > 3.0: kit_name = sloped[i % sloped.size()]
		var kit: MapKit = make_kit.call(kit_name)
		var holder := emit_kit(kit, p, rng.randf() * TAU, "C%02d_%s" % [i, kit_name])
		clusters.append({"pos": p, "kit": kit_name, "radius": kit.radius, "node": holder})


func _shuffle(a: Array[StringName]) -> void:
	for i: int in range(a.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp := a[i]
		a[i] = a[j]
		a[j] = tmp


## Long-range pads: clusters whose kit is in `counts` ({kit: pads}) throw you to that many other
## clusters between min_d and max_d away (hubs from their disc, towers from their top), each arc
## checked for clearance (higher arcs first, then another target).
func add_launchers(counts: Dictionary, min_d: float, max_d: float) -> void:
	for i: int in clusters.size():
		var c := clusters[i]
		var kit_name: StringName = c.kit
		if not counts.has(kit_name): continue
		var p: Vector2 = c.pos
		var holder: Node3D = c.node
		var targets: Array[Dictionary] = []
		for j: int in clusters.size():
			if j == i: continue
			var d := (clusters[j].pos as Vector2).distance_to(p)
			if d > min_d and d < max_d: targets.append(clusters[j])
		if targets.is_empty(): continue
		targets.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			return (a.pos as Vector2).angle_to_point(p) < (b.pos as Vector2).angle_to_point(p))
		var want: int = counts[kit_name]
		var step := maxi(1, floori(targets.size() / float(want)))
		var made := 0
		for t: int in targets.size():
			if made >= want: break
			var tc := targets[(t * step + i) % targets.size()]
			var tp: Vector2 = tc.pos
			# land on open ground just in front of the target cluster
			var back := (p - tp).normalized()
			var land := tp + back * ((tc.radius as float) + 8.0)
			var land3 := Vector3(land.x, h(land.x, land.y), land.y)
			var from: Vector3
			if holder.has_meta(&"top"):
				from = holder.get_meta(&"top") as Vector3
			else:
				var o := Vector2.from_angle(TAU * made / want) * 4.0
				from = Vector3(p.x + o.x, holder.position.y + 1.5, p.y + o.y)
			var base_peak := clampf(from.distance_to(land3) * 0.12, 8.0, 30.0)
			for k: float in [1.0, 1.6, 2.4]:
				if arc_clear(from, land3, base_peak * k, [c, tc]):
					pad(holder, from, land3, base_peak * k, false)
					made += 1
					break


## Hop pads and speed strips out in the open between clusters, aimed at the nearest cluster.
## Sampled within max_r; reserved() as for place_clusters (ignored inside free_r of the centre).
func add_open_pads_and_strips(want_pads: int, want_strips: int, max_r: float, free_r: float,
		reserved: Callable) -> void:
	var open := node(props, "Open")
	var made_pads := 0
	var made_strips := 0
	var placed: Array[Vector2] = [] # open pads and strips keep apart: a strip under a pad boosts the launch
	var tries := 0
	while (made_pads < want_pads or made_strips < want_strips) and tries < 4000:
		tries += 1
		var p := Vector2.from_angle(rng.randf() * TAU) * sqrt(rng.randf()) * max_r
		if p.length() > free_r and reserved.call(p, 6.0): continue
		var clear := true
		for q: Vector2 in placed: clear = clear and q.distance_to(p) >= 14.0
		var nearest := {}
		var nd := INF
		for c: Dictionary in clusters:
			var d := (c.pos as Vector2).distance_to(p)
			if d < (c.radius as float) + 10.0: clear = false
			if d < nd and d > 35.0:
				nd = d
				nearest = c
		if not clear or nearest.is_empty() or nd > 85.0: continue
		var tp: Vector2 = nearest.pos
		var dir := (tp - p).normalized()
		if made_pads < want_pads and (made_strips >= want_strips or rng.randf() < 0.55):
			var land := tp - dir * ((nearest.radius as float) + 6.0)
			var from := Vector3(p.x, h(p.x, p.y), p.y)
			var to := Vector3(land.x, h(land.x, land.y), land.y)
			var peak := clampf(nd * 0.15, 6.0, 16.0)
			if not arc_clear(from, to, peak, [nearest]): continue
			pad(open, from, to, peak, false)
			placed.append(p)
			made_pads += 1
		elif made_strips < want_strips and bumpiness(p, 8.0) < 1.5:
			var heading := _open_heading(p, dir, max_r) if strip_lane > 0.0 else dir
			if heading == Vector2.ZERO: continue
			strip(open, Vector3(p.x, h(p.x, p.y), p.y), atan2(heading.x, heading.y), 34.0)
			placed.append(p)
			made_strips += 1

## The direction nearest `toward` (within 90 deg) whose strip_lane is clear; ZERO if none.
func _open_heading(p: Vector2, toward: Vector2, max_r: float) -> Vector2:
	for k: int in 13:
		var turn := deg_to_rad(15.0 * ceili(k / 2.0)) * (1.0 if k % 2 else -1.0)
		var d := toward.rotated(turn)
		if (p + d * strip_lane).length() < max_r + 15.0 and _lane_clear(p, d): return d
	return Vector2.ZERO


func _lane_clear(p: Vector2, d: Vector2) -> bool:
	var end := p + d * strip_lane
	for c: Dictionary in clusters:
		var cp: Vector2 = c.pos
		if cp.distance_to(Geometry2D.get_closest_point_to_segment(cp, p, end)) < (c.radius as float) + 2.0: return false
	if arc_blocked.is_valid():
		for i: int in range(1, int(strip_lane / 3.0) + 1):
			var q := p + d * (i * 3.0)
			if arc_blocked.call(q, h(q.x, q.y) + 1.0): return false
	return true

#endregion


#region emitting

## Places a kit at site p (ground under it = local y 0), rotated by yaw. Grounded boxes are
## stretched down to the lowest ground under them so nothing floats on a slope.
func emit_kit(kit: MapKit, p: Vector2, yaw: float, node_name: String, parent: Node3D = null) -> Node3D:
	var base := Transform3D(Basis(Vector3.UP, yaw), Vector3(p.x, h(p.x, p.y), p.y))
	var holder := node(parent if parent else props, node_name)
	holder.transform = base
	_emit_boxes(holder, kit.boxes, base)
	for pd: Dictionary in kit.pads:
		var at: Vector3 = base * (pd.at as Vector3)
		at.y = h(at.x, at.z)
		var to: Vector3 = pd.to if pd.world_target else base * (pd.to as Vector3)
		pad(holder, at, to, pd.peak, true)
	for s: Dictionary in kit.strips:
		var at: Vector3 = base * (s.at as Vector3)
		strip(holder, Vector3(at.x, h(at.x, at.z), at.z), (s.yaw as float) + yaw, s.speed)
	_emit_links(kit, base)
	if kit.has_top: holder.set_meta(&"top", base * kit.top)
	return holder


## Kit already in world space (landmarks).
func emit_world_kit(kit: MapKit, node_name: String) -> Node3D:
	var holder := node(props, node_name)
	_emit_boxes(holder, kit.boxes, Transform3D.IDENTITY)
	for pd: Dictionary in kit.pads:
		var at: Vector3 = pd.at
		at.y = h(at.x, at.z)
		pad(holder, at, pd.to, pd.peak, true)
	for s: Dictionary in kit.strips:
		var at: Vector3 = s.at
		strip(holder, Vector3(at.x, h(at.x, at.z), at.z), s.yaw, s.speed)
	_emit_links(kit, Transform3D.IDENTITY)
	return holder


func _emit_links(kit: MapKit, base: Transform3D) -> void:
	for l: Dictionary in kit.links:
		var from: Vector3 = base * (l.from as Vector3)
		from.y = h(from.x, from.z)
		link(from, base * (l.to as Vector3), l.kind, l.cost)


## One StaticBody3D with a box shape per piece, and one merged mesh (a surface per material),
## saved binary in mesh_dir.
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
		var box_size: Vector3 = b.size
		if b.grounded: # stretch down to the lowest ground under it (+0.5 m buried)
			var top := xf.origin.y + box_size.y * 0.5
			var reach := maxf(box_size.x, box_size.z) * 0.5
			var ground := h_min(xf.origin.x, xf.origin.z, reach, reach) - 0.5
			if ground < top - box_size.y:
				box_size.y = top - ground
				xf.origin.y = top - box_size.y * 0.5
		var local := inv * xf
		if b.get("solid", true):
			var shape := BoxShape3D.new()
			shape.size = box_size
			var col := CollisionShape3D.new()
			col.name = "S%03d" % i
			col.shape = shape
			col.transform = local
			body.add_child(col)
		var mesh := BoxMesh.new()
		mesh.size = box_size
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
		am.surface_set_material(am.get_surface_count() - 1, mats[key])
	var path := "%s/%s.res" % [mesh_dir, holder.name.to_snake_case()]
	ResourceSaver.save(am, path)
	var mi := MeshInstance3D.new()
	mi.name = "Mesh"
	mi.mesh = load(path)
	if fade_distance > 0.0: mi.visibility_range_end = fade_distance
	body.add_child(mi)


## Jump pad at world `at` that lobs you onto world `to`, peaking `peak` m above the higher of the
## two. The sideways speed comes from simulating the character's own hands-off flight (gravity,
## fall multiplier, air drag, soft speed cap), so it lands on target with no input.
## Adds a nav link so bots know where the pad goes.
func pad(parent: Node3D, at: Vector3, to: Vector3, peak: float, short: bool) -> void:
	var up := maxf(to.y, at.y) - at.y + peak
	var hi := lob_speed(at, to, up)
	var dir := Vector2(to.x - at.x, to.z - at.z).normalized()
	var p := (load(JUMP_PAD) as PackedScene).instantiate() as Node3D
	p.name = "Pad%d" % pad_count
	pad_count += 1
	parent.add_child(p)
	p.global_position = at + Vector3(0.0, 0.05, 0.0)
	p.global_rotation = Vector3.ZERO # launch_velocity is in pad space: keep it world-aligned
	p.set(&"launch_height", up)
	p.set(&"launch_velocity", Vector3(dir.x, 0.0, dir.y) * hi)
	p.set(&"keep_horizontal", false)
	p.set(&"landing", to)
	link(at, to, GameMap.LINK_PAD, 0.5 if short else 0.3)
	if to.y - h(to.x, to.z) > 2.0: raised_landings.append(to)


## Sideways launch speed that lands a hands-off lob from `at` on `to`, going `up` m high.
func lob_speed(at: Vector3, to: Vector3, up: float) -> float:
	var vy := sqrt(2.0 * cfg.gravity * up)
	var dist := Vector2(to.x - at.x, to.z - at.z).length()
	var lo := 0.0
	var hi := 200.0
	for it: int in 40: # bisect
		var mid := (lo + hi) * 0.5
		if flight_distance(mid, vy, to.y - at.y) < dist: lo = mid
		else: hi = mid
	return hi


## True if the lob from `at` to `to` (peaking `peak` m above the higher end) stays 3 m over the
## terrain, clear of arc_blocked landmarks, and 25 m over every cluster it passes (except the
## ones in `skip`) until it comes down.
func arc_clear(at: Vector3, to: Vector3, peak: float, skip: Array) -> bool:
	const DT := 1.0 / 30.0
	var up := maxf(to.y, at.y) - at.y + peak
	var v := lob_speed(at, to, up)
	var vy := sqrt(2.0 * cfg.gravity * up)
	var dir := Vector2(to.x - at.x, to.z - at.z).normalized()
	var pos := Vector2(at.x, at.z)
	var y := at.y
	var end := Vector2(to.x, to.z)
	for i: int in 600:
		var g := cfg.gravity * (cfg.fall_gravity_mult if vy < 0.0 else 1.0)
		v = maxf(v - cfg.air_decel * DT, 0.0)
		vy = maxf(vy - g * DT, -cfg.terminal_velocity)
		if v > cfg.soft_speed_cap:
			v = maxf(v - cfg.soft_cap_drag * v * (v - cfg.soft_speed_cap) * DT, cfg.soft_speed_cap)
		pos += dir * v * DT
		y += vy * DT
		if pos.distance_to(end) < 12.0 or (vy < 0.0 and y <= to.y): return true # final approach
		if pos.distance_to(Vector2(at.x, at.z)) < 12.0: continue # still leaving the pad's own cluster
		if y < h(pos.x, pos.y) + 3.0: return false
		if arc_blocked.is_valid() and arc_blocked.call(pos, y): return false
		for c: Dictionary in clusters:
			if c in skip: continue
			var cp: Vector2 = c.pos
			if pos.distance_to(cp) < (c.radius as float) and y < h(cp.x, cp.y) + 25.0: return false
	return true


## Horizontal distance covered before coming back down to height dy, hands-off.
func flight_distance(speed: float, vy: float, dy: float) -> float:
	const DT := 1.0 / 120.0
	var y := 0.0
	var x := 0.0
	var v := speed
	for i: int in 2400:
		var g := cfg.gravity * (cfg.fall_gravity_mult if vy < 0.0 else 1.0)
		v = maxf(v - cfg.air_decel * DT, 0.0)
		vy = maxf(vy - g * DT, -cfg.terminal_velocity)
		if v > cfg.soft_speed_cap:
			v = maxf(v - cfg.soft_cap_drag * v * (v - cfg.soft_speed_cap) * DT, cfg.soft_speed_cap)
		x += v * DT
		y += vy * DT
		if vy < 0.0 and y <= dy: return x
	return x


## Speed strip pushing toward yaw (radians, 0 = +Z).
func strip(parent: Node3D, at: Vector3, yaw: float, speed: float) -> void:
	var s := (load(SPEED_STRIP) as PackedScene).instantiate() as Node3D
	s.name = "Strip%d" % parent.get_child_count()
	parent.add_child(s)
	s.global_position = at + Vector3(0.0, 0.05, 0.0)
	s.global_rotation = Vector3(0.0, yaw + PI, 0.0) # the strip pushes along its own -Z
	s.set(&"boost_speed", speed)


## One-way NavigationLink3D node (pads, drops). Godot's default is two-way: bots would plan to
## ride pads backwards.
func link(from: Vector3, to: Vector3, kind: int, cost: float) -> void:
	var l := NavigationLink3D.new()
	l.name = "Link%d" % link_count
	link_count += 1
	l.start_position = from
	l.end_position = to
	l.bidirectional = false
	l.travel_cost = cost
	l.set_meta(GameMap.LINK_KIND, kind)
	nav.add_child(l)

#endregion


#region navigation

## Every pad that lands you on top of something (pillar, tower, platform, arch) gets a drop link
## back down, or a bot that rode it up has no way off. Finds clear ground with downward rays.
## Needs the props registered with physics (wait a few physics frames first).
func add_drop_links() -> void:
	var space := root.get_world_3d().direct_space_state
	var made := 0
	for top: Vector3 in raised_landings:
		for reach: float in [4.0, 6.0, 9.0]:
			var done := false
			for k: int in 8:
				var d := Vector2.from_angle(TAU * k / 8.0) * reach
				var q := PhysicsRayQueryParameters3D.create(Vector3(top.x + d.x, top.y + 0.5, top.z + d.y), Vector3(top.x + d.x, top.y - 80.0, top.z + d.y))
				var hit := space.intersect_ray(q)
				if hit.is_empty(): continue
				var p: Vector3 = hit.position
				if absf(p.y - h(p.x, p.z)) > 0.6: continue # landed on another prop, not the ground
				link(top, p, GameMap.LINK_DROP, 1.0)
				made += 1
				done = true
				break
			if done: break
	print("drop links: %d / %d raised landings" % [made, raised_landings.size()])


## Bakes the navmesh in nav_chunk squares (borders cut so neighbours line up and the navigation
## map joins them) from the props + the terrain, welds each, saves it, adds a NavigationRegion3D
## per chunk, then adds the auto jump links.
func bake_navmesh(terrain: Node3D) -> void:
	props.add_to_group(&"nav_source")
	var probe := GameMap.make_navmesh()
	var props_src := NavigationMeshSourceGeometryData3D.new()
	NavigationServer3D.parse_source_geometry_data(probe, props_src, root)
	clear_dir(nav_dir)
	var n := ceili(nav_radius / nav_chunk)
	var count := 0
	var buried := 0
	for gx: int in range(-n, n):
		for gz: int in range(-n, n):
			var x0 := gx * nav_chunk
			var z0 := gz * nav_chunk
			var nearest := Vector2(clampf(0.0, x0, x0 + nav_chunk), clampf(0.0, z0, z0 + nav_chunk))
			if nearest.length() > nav_radius: continue
			var nm := GameMap.make_navmesh()
			nm.border_size = nav_border
			nm.edge_max_error = 1.0
			nm.edge_max_length = 0.0 # open terrain: no need to chop big polygons up (fewer = faster queries)
			nm.filter_baking_aabb = AABB(Vector3(x0 - nav_border, -60.0, z0 - nav_border),
					Vector3(nav_chunk + nav_border * 2.0, 260.0, nav_chunk + nav_border * 2.0))
			var src := NavigationMeshSourceGeometryData3D.new()
			src.merge(props_src)
			if terrain:
				var faces: PackedVector3Array = terrain.call(&"generate_nav_mesh_source_geometry", nm.filter_baking_aabb, true)
				src.add_faces(faces, Transform3D.IDENTITY)
			NavigationServer3D.bake_from_source_geometry_data(nm, src)
			weld_navmesh(nm, 0.15)
			buried += drop_buried(nm, root.get_world_3d().direct_space_state)
			chunk_meshes.append(nm)
			if nm.get_polygon_count() == 0: continue
			var path := "%s/chunk_%d_%d.res" % [nav_dir, gx, gz]
			ResourceSaver.save(nm, path)
			var region := NavigationRegion3D.new()
			region.name = "Chunk_%d_%d" % [gx, gz]
			region.navigation_mesh = load(path)
			nav.add_child(region)
			count += 1
		await tree.process_frame
	props.remove_from_group(&"nav_source")
	print("navmesh chunks: %d (%d buried polygons dropped)" % [count, buried])
	_add_jump_links()


## Bots only walk the navmesh, so anything a player would jump up, across or off needs a link.
## Samples every open navmesh edge (not chunk seams), pairs samples a jump can connect, checks the
## way is clear with rays, thins them out and adds LINK_VAULT (climb), LINK_JUMP (gap) and
## LINK_DROP (down) links, saved as one NavLinkSet the map registers at load.
func _add_jump_links() -> void:
	var samples: Array[Dictionary] = [] # {p: Vector3, out: Vector3 (horizontal, away from the walkable side)}
	for nm: NavigationMesh in chunk_meshes:
		var v := nm.get_vertices()
		var uses := {}
		for pi: int in nm.get_polygon_count():
			var poly := nm.get_polygon(pi)
			for k: int in poly.size():
				var key := Vector2i(mini(poly[k], poly[(k + 1) % poly.size()]), maxi(poly[k], poly[(k + 1) % poly.size()]))
				uses[key] = (uses.get(key, 0) as int) + 1
		for pi: int in nm.get_polygon_count():
			var poly := nm.get_polygon(pi)
			var centre := Vector3.ZERO
			for idx: int in poly: centre += v[idx]
			centre /= poly.size()
			for k: int in poly.size():
				var i0 := poly[k]
				var i1 := poly[(k + 1) % poly.size()]
				if (uses[Vector2i(mini(i0, i1), maxi(i0, i1))] as int) > 1: continue
				var a := v[i0]
				var b := v[i1]
				if _on_seam(a, b): continue
				var e := Vector3(b.x - a.x, 0.0, b.z - a.z)
				if e.length() < 0.2: continue
				e = e.normalized()
				var out := Vector3(e.z, 0.0, -e.x)
				var mid := (a + b) * 0.5
				if out.dot(Vector3(mid.x - centre.x, 0.0, mid.z - centre.z)) < 0.0: out = -out
				var count := maxi(1, ceili(a.distance_to(b) / EDGE_STEP))
				for s: int in count: samples.append({"p": a.lerp(b, (s + 0.5) / count), "out": out})
	var grid := {}
	for i: int in samples.size():
		var p: Vector3 = samples[i].p
		var cell := Vector2i(floori(p.x / GAP_MAX), floori(p.z / GAP_MAX))
		if not grid.has(cell): grid[cell] = []
		(grid[cell] as Array).append(i)
	# best (shortest) candidate per kind and start/end cell pair, so one ledge doesn't get dozens
	var best := {}
	for i: int in samples.size():
		var a: Dictionary = samples[i]
		var pa: Vector3 = a.p
		var cell := Vector2i(floori(pa.x / GAP_MAX), floori(pa.z / GAP_MAX))
		for dx: int in range(-1, 2):
			for dz: int in range(-1, 2):
				for j: int in grid.get(cell + Vector2i(dx, dz), []):
					if j == i: continue
					var b: Dictionary = samples[j]
					var pb: Vector3 = b.p
					var flat := Vector3(pb.x - pa.x, 0.0, pb.z - pa.z)
					var d := flat.length()
					if d < 0.3 or d > GAP_MAX: continue
					# each side has to face the other across its open edge
					if flat.dot(a.out) < 0.3 * d or -flat.dot(b.out) < 0.3 * d: continue
					var dh := pa.y - pb.y # a above b when positive
					if dh > 0.7:
						if dh <= CLIMB_UP_MAX and d <= CLIMB_REACH: _keep(best, GameMap.LINK_VAULT, pb, pa, d)
						elif dh > CLIMB_UP_MAX and dh <= WALLJUMP_UP_MAX and d <= WALLJUMP_REACH: _keep(best, GameMap.LINK_WALLJUMP, pb, pa, d)
						if d <= DROP_REACH: _keep(best, GameMap.LINK_DROP, pa, pb, d)
					elif absf(dh) <= GAP_RISE and d >= GAP_MIN and i < j:
						if absf(dh) <= 1.0 or d <= GAP_RISE_REACH: _keep(best, GameMap.LINK_JUMP, pa, pb, d)
	var space := root.get_world_3d().direct_space_state
	var made := {GameMap.LINK_VAULT: 0, GameMap.LINK_JUMP: 0, GameMap.LINK_DROP: 0, GameMap.LINK_WALLJUMP: 0}
	var links := NavLinkSet.new()
	for key: String in best:
		var c: Dictionary = best[key]
		var from: Vector3 = c.from
		var to: Vector3 = c.to
		var kind: int = c.kind
		var top := maxf(from.y, to.y) + 1.2
		# a gap jump needs an actual gap: if the middle is solid at that height it's walkable already
		if kind == GameMap.LINK_JUMP:
			var mid := (from + to) * 0.5
			var under := space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(mid.x, top, mid.z), Vector3(mid.x, minf(from.y, to.y) - 0.6, mid.z)))
			if not under.is_empty(): continue
		# a wall-jump climb needs a wall to climb: something steep between them halfway up
		if kind == GameMap.LINK_WALLJUMP:
			var mid_y := from.y + (to.y - from.y) * 0.5
			var across := Vector3(to.x - from.x, 0.0, to.z - from.z)
			var wall := space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(from.x, mid_y, from.z), Vector3(from.x, mid_y, from.z) + across.normalized() * (across.length() + 1.0)))
			if wall.is_empty() or absf((wall.normal as Vector3).y) > 0.5: continue
		# the way has to be clear: up over the lip, then across
		if not _clear(space, from + Vector3.UP * 0.9, Vector3(from.x, top, from.z)): continue
		if not _clear(space, Vector3(from.x, top, from.z), Vector3(to.x, top, to.z)): continue
		if not _clear(space, Vector3(to.x, top, to.z), to + Vector3.UP * 0.9): continue
		# a bit dearer than walking: hop only when it actually saves the trip
		links.add(from, to, kind, kind == GameMap.LINK_JUMP, 4.0 if kind == GameMap.LINK_WALLJUMP else 2.0)
		made[kind] += 1
	# thousands of links: a binary array resource the map registers at load, not a node each
	var path := "%s/jump_links.res" % nav_dir
	ResourceSaver.save(links, path)
	root.set(&"jump_links", load(path))
	print("jump links: %d climbs, %d wall-jump climbs, %d gap jumps, %d drops (from %d edge samples)" % [made[GameMap.LINK_VAULT], made[GameMap.LINK_WALLJUMP], made[GameMap.LINK_JUMP], made[GameMap.LINK_DROP], samples.size()])


## Keeps the shortest candidate per slot. Gap jumps: one per start/end cell pair. Climbs and
## drops: one per start cell (a bot only needs one way up or down from a spot, it walks from
## wherever it lands), and tall drops (cliffs) every TALL_CELL: walking a few metres along a
## cliff to the next one is nothing, and every link costs the navigation map's rebuild
## (the Jungle went from 21k links and a 4-8 s first build to ~6k and 1.5-2.5 s).
func _keep(best: Dictionary, kind: int, from: Vector3, to: Vector3, d: float) -> void:
	const CELL := 3.5
	const CLIMB_CELL := 2.5 # climbs are the fewest and matter most: keep them denser
	const TALL_DROP := 6.0
	const TALL_CELL := 8.0
	var key: String
	if kind == GameMap.LINK_JUMP:
		key = "%d|%s|%s" % [kind, Vector3i((from / CELL).floor()), Vector3i((to / CELL).floor())]
	else:
		var cell := CLIMB_CELL if kind == GameMap.LINK_VAULT else TALL_CELL if from.y - to.y > TALL_DROP else CELL
		key = "%d|%s" % [kind, Vector3i((from / cell).floor())]
	if best.has(key) and (best[key].d as float) <= d: return
	best[key] = {"kind": kind, "from": from, "to": to, "d": d}


static func _clear(space: PhysicsDirectSpaceState3D, a: Vector3, b: Vector3) -> bool:
	if a.distance_to(b) < 0.05: return true
	return space.intersect_ray(PhysicsRayQueryParameters3D.create(a, b)).is_empty()


## True for an edge lying along a chunk border (it joins the neighbouring chunk, it isn't open).
func _on_seam(a: Vector3, b: Vector3) -> bool:
	var on_grid := func(x: float) -> bool: return absf(x / nav_chunk - roundf(x / nav_chunk)) * nav_chunk < 0.05
	return (absf(a.x - b.x) < 0.05 and on_grid.call(a.x)) or (absf(a.z - b.z) < 0.05 and on_grid.call(a.z))


## Merges navmesh vertices closer than eps and drops polygons that collapse. Recast leaves the odd
## cluster of near-identical vertices where a prop meets the terrain at a shallow angle; the
## navigation map then finds 3+ edges in one spot ("edge merge errors") and can't connect them.
static func weld_navmesh(nm: NavigationMesh, eps: float) -> void:
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


## Drops polygons that sit inside solid geometry. Recast only sees surfaces, so the top of a box
## buried in another (stacked tiers, a ramp through a step) or ground covered by a box reads as
## floor if there's head room up to the next surface. Bots would snap targets onto those floors
## and never get there. Needs the props registered with physics. Returns how many it dropped.
static func drop_buried(nm: NavigationMesh, space: PhysicsDirectSpaceState3D) -> int:
	var verts := nm.get_vertices()
	var q := PhysicsPointQueryParameters3D.new()
	var keep: Array[PackedInt32Array] = []
	for pi: int in nm.get_polygon_count():
		var poly := nm.get_polygon(pi)
		var c := Vector3.ZERO
		for idx: int in poly: c += verts[idx]
		q.position = c / poly.size() + Vector3.UP * 0.3
		if space.intersect_point(q, 1).is_empty(): keep.append(poly)
	var dropped := nm.get_polygon_count() - keep.size()
	if dropped:
		nm.clear_polygons()
		for poly: PackedInt32Array in keep: nm.add_polygon(poly)
	return dropped


static func _root_of(parent: PackedInt32Array, i: int) -> int:
	while parent[i] != i: i = parent[i]
	return i

#endregion
