extends SceneTree

# Builds the Jungle greybox on the shared map generator (tools/mapgen/lib).
#   godot --headless --script res://tools/mapgen/jungle_gen.gd
#
# Layout (x = east, z = south, 1 m per terrain vertex, 1024 m square, playable circle r = 230):
#   centre       THE TEMPLE: eight 3.5 m tiers (jump + vault each) on a wide open plaza, a grand
#                ramp up the south face, a shrine on top; hollow: doorways E/W/N into a pillared
#                hall, a ledge-spiral shaft from there up to the summit; spawn clearing south
#                (the forest keeps clear of the plaza, and of every speed strip's run-out)
#   north        THE FALLS: a 20 m highland cliff (wall-jumpable), two streams spilling over it
#                (draped, flowing water ribbons) into pools,
#                two slide chutes down from the top with speed strips at their heads
#   east         THE RIVER: a shallow winding channel from the east pool to the rim, log bridges
#   groves       treehouses (giant trunk, ledges spiralling up to a deck ring ~14-16 m up),
#                rope bridges between neighbouring decks (the canopy level), twin-trunk
#                wall-jump chimneys, plus the standard kits
#   everywhere   forest: model trees (tools/blender/trees.py, real bark and leaves), their trunks
#                unseen boxes you can wall-jump off; crowns overhead (look only)
#   outside      the rim: mountains from r = 280

const MapGen := preload("res://tools/mapgen/lib/map_gen.gd")
const MapKit := preload("res://tools/mapgen/lib/map_kit.gd")
const MapKits := preload("res://tools/mapgen/lib/map_kits.gd")
## The landmarks' modelled pieces (tools/blender/landmark_props.py): each box keeps its collision.
const LANDMARKS_GLB := "res://assets/models/landmarks/jungle_landmarks.glb"

const SIZE := 1024
const ARENA_RADIUS := 230.0
const NAV_RADIUS := 270.0
const RIM_START := 280.0
const ART := "res://assets/tres/materials/art/jungle"
const TREES_GLB := "res://assets/models/trees/jungle_trees.glb"
const TREE_MESH_DIR := "res://assets/meshes/jungle/trees"
# the tree models' trunk (keep in sync with tools/blender/trees.py: H, R_BASE, R_TOP)
const TREE_H := 24.0
const TREE_R_BASE := 1.2
const TREE_R_TOP := 0.45
# the crowns' leaf cards cast shadows this close; past it, solid stand-ins (<tree>_shadow) do: the
# cards drawn into every shadow map were ~6 ms, and stopping there made shadows pop out of existence
const CROWN_SHADOW_NEAR := 45.0
const RIM_FULL := 450.0

const OUT_SCENE := "res://scn/map/jungle.tscn"
const MAP_SCRIPT := "res://src/map/terrain_map.gd"
const ENV := "res://assets/tres/environments/jungle_environment.tres"

const TEMPLE_POS := Vector2(0.0, -30.0)
const TEMPLE_GROUND := 1.5
const TEMPLE_TIERS := 8
const TEMPLE_TIER_H := 3.5
const TEMPLE_HALF := 44.0
const TEMPLE_STEP := 3.4
const TEMPLE_HALL := 20.0     # the hall inside: half-width...
const TEMPLE_HALL_H := 10.5   # ...and height: tiers starting below this ring the hall (3 tiers)
const TEMPLE_SHAFT := 5.0     # half-width of the shaft from the hall's ceiling to the summit
const TEMPLE_DOOR_W := 6.0
const TEMPLE_DOOR_H := 4.5
const TEMPLE_RAMP_OUT := 22.0 # the grand ramp's foot, this far out from the south face
const TEMPLE_PLAZA := 32.0 # flat ground past the base (well past the ramp's foot) before the floor rolls
const SPAWN_POS := Vector2(0.0, 105.0)
const HIGHLAND_H := 20.0
const FALLS_X: Array[float] = [-55.0, 65.0]
const STREAM_LEN := 60.0 # each fall's stream runs this far across the highland to the lip
const CHUTES_X: Array[float] = [-10.0, 125.0]
const CHUTE_ANGLE := 30.0
# river centreline, from the east pool to past the rim
const RIVER: Array[Vector2] = [Vector2(65.0, -122.0), Vector2(88.0, -60.0), Vector2(135.0, 0.0), Vector2(150.0, 80.0),
		Vector2(205.0, 150.0), Vector2(260.0, 215.0)]
const RIVER_DEPTH := 2.5

const CLUSTER_SPACING := 46.0
const CLUSTER_MAX_R := 212.0
const TREE_SPACING := 9.0
const KITS: Array[StringName] = [&"twins", &"twins", &"ruins", &"pillars", &"vaults", &"stilts", &"hub", &"blocks"]
const FLAT: Array[StringName] = [&"vaults", &"hub", &"blocks"]
const SLOPED: Array[StringName] = [&"twins", &"ruins", &"pillars", &"stilts"]
# groves: (centre, radius) areas of treehouses ~30 m apart, all bridged into a canopy network
const GROVES: Array[Vector3] = [Vector3(-130.0, 30.0, 62.0), Vector3(55.0, 150.0, 52.0), Vector3(-95.0, -100.0, 40.0)]
const GROVE_SPACING := 28.0
const BRIDGE_MAX := 40.0
const DECK_HALF := 9.0

const COLORS := {
	&"stone": Color(0.62, 0.62, 0.52),   # ruins, vault walls
	&"rock": Color(0.5, 0.52, 0.48),
	&"ruin": Color(0.55, 0.6, 0.62),     # pillar runs
	&"wood": Color(0.62, 0.45, 0.3),     # decks, bridges, stilts, chutes
	&"ramp": Color(0.8, 0.55, 0.28),
	&"hub": Color(0.38, 0.6, 0.72),
	&"bark": Color(0.42, 0.31, 0.21),    # trunks
	&"temple": Color(0.66, 0.64, 0.52),
}

## The art pass's ground: vector layers drawn by tools/texgen/vector_ground.py, painted per
## vertex by _paint: mossy rock on the steep, leaf litter, moss, wet mud (ids in this order).
const TERRAIN_TEX := "res://assets/images/terrain/"
const GROUND_LAYERS := [
	{"name": "Rock", "albedo": TERRAIN_TEX + "ground_jrock_ah.png", "normal": TERRAIN_TEX + "ground_jrock_nr.png", "uv_scale": 0.18},
	{"name": "Floor", "albedo": TERRAIN_TEX + "ground_jfloor_ah.png", "normal": TERRAIN_TEX + "ground_jfloor_nr.png", "uv_scale": 0.5},
	{"name": "Moss", "albedo": TERRAIN_TEX + "ground_jmoss_ah.png", "normal": TERRAIN_TEX + "ground_jmoss_nr.png", "uv_scale": 0.5},
	{"name": "Mud", "albedo": TERRAIN_TEX + "ground_jmud_ah.png", "normal": TERRAIN_TEX + "ground_jmud_nr.png", "uv_scale": 0.45},
]
const G_ROCK := 0
const G_FLOOR := 1
const G_MOSS := 2
const G_MUD := 3

var _roll := FastNoiseLite.new()
var _moss_noise := FastNoiseLite.new()
var _ridge_noise := FastNoiseLite.new()
var g: MapGen
var _terrain: Node3D # for draping: its own height lookup, exactly what's rendered
var _bridges: Array[PackedVector2Array] = [] # bridge segments, kept clear of forest trunks
var _bridge_y: Array[float] = []                # their mean deck height
var _tree_grid := {} # Vector2i(16 m cell) -> [Vector3(x, z, trunk top y)], for launch-arc checks
var _pad_paths: Array[PackedVector2Array] = [] # pad -> landing, kept clear of trunks
var _strip_lanes: Array[PackedVector2Array] = [] # speed strip -> where it flings you, kept clear too
var _trunk_count := 0 # thick trunks made so far (each its own mesh, its own ridges)
var _bed := PackedFloat32Array() # the riverbed per course point (_river_bed)


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var t0 := Time.get_ticks_msec()
	g = MapGen.new(self, SIZE)
	g.data_dir = "res://assets/terrain/jungle"
	g.mat_dir = MapGen.MAT_DIR + "/jungle"
	g.art_dir = "res://assets/tres/materials/art/jungle" # M6: finished materials by role
	g.nav_dir = "res://assets/navmesh/jungle"
	g.mesh_dir = "res://assets/meshes/jungle"
	g.assets_path = "res://assets/tres/terrain/jungle_assets.tres"
	g.nav_radius = NAV_RADIUS
	g.arc_blocked = _landmark_in_the_way
	g.strip_lane = 70.0
	g.rng.seed = 2718
	_roll.seed = 23
	_roll.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_roll.frequency = 0.009
	_roll.fractal_octaves = 3
	_ridge_noise.seed = 29
	_ridge_noise.frequency = 0.007
	_ridge_noise.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	_ridge_noise.fractal_octaves = 4
	_moss_noise.seed = 37
	_moss_noise.frequency = 0.03
	_moss_noise.fractal_octaves = 3
	g.paint = _paint

	g.bake_heights(_height)
	print("heights: %d ms" % (Time.get_ticks_msec() - t0))
	await g.write_terrain_data()
	g.make_materials(COLORS)
	g.load_models(MapKits.KIT_GLB, g.mesh_dir + "/kits") # the obstacle kits' pieces
	g.occluder_roles = [&"temple"] # the temple's mass hides what's behind it
	_load_trees()
	_make_ember_material()
	g.load_models(LANDMARKS_GLB, g.mesh_dir + "/landmarks") # (after the ember material: the braziers use it)

	var map := g.begin_scene("Jungle", MAP_SCRIPT)
	map.set(&"arena_radius", ARENA_RADIUS)
	map.set(&"dry_edge_radius", CLUSTER_MAX_R + 24.0) # the dry edge starts past the last cluster
	map.set(&"storm_height_scale", 1.5)
	# the storm closes in on the temple and stops where the forest starts (the plaza's edge)
	map.set(&"storm_center", Vector3(TEMPLE_POS.x, 0.0, TEMPLE_POS.y))
	map.set(&"storm_end_radius", TEMPLE_HALF + TEMPLE_PLAZA - 1.0)
	map.set(&"storm_bottom", floorf(g.min_h()) - 1.0) # under the lowest ground (the floor mustn't show beneath the storm)
	g.enter_tree()
	g.add_environment(ENV, 140.0)
	# baked bounce light round the temple only (its hall lit warm by the braziers): over the open
	# forest it made the shade darker than the sky's own fill (the canopy bakes as a solid roof)
	g.add_baked_gi("jungle", Vector3(TEMPLE_POS.x, TEMPLE_GROUND + 20.0, TEMPLE_POS.y), Vector3(100.0, 46.0, 100.0), 0.6, Color(0.28, 0.22, 0.13), VoxelGI.SUBDIV_128)
	var terrain := g.add_terrain_layers(GROUND_LAYERS, "res://assets/gdshaders/terrain_art.gdshader", {
		&"blend_sharpness": 0.7,
		&"noise_texture": load(TERRAIN_TEX + "macro_noise.png"),
		&"macro_variation_enabled": true,
		&"macro_variation1": Color(0.86, 0.94, 0.8), # greener, mossier stretches
		&"macro_variation2": Color(0.92, 0.9, 0.85),
		&"noise1_scale": 0.08,
		&"noise2_scale": 0.3,
		&"detile_scale": 0.02,
	})
	map.set(&"terrain", terrain)
	_terrain = terrain
	g.begin_props()

	_build_temple()
	_build_falls()
	_build_river()
	_build_groves()
	g.place_clusters(KITS, FLAT, SLOPED, CLUSTER_SPACING, CLUSTER_MAX_R, _reserved, _make_kit)
	_build_bridges()
	g.add_launchers({&"hub": 3}, 60.0, 150.0)
	g.add_open_pads_and_strips(10, 6, CLUSTER_MAX_R - 10.0, 0.0, _reserved)
	_build_forest() # last: keeps clear of every pad, landing spot and launch corridor
	print("props: %d clusters, %d pads, %d nav links (%d ms)" % [g.clusters.size(), g.pad_count, g.link_count, Time.get_ticks_msec() - t0])
	g.add_spawns(SPAWN_POS)
	g.add_labels({
		"THE TEMPLE": TEMPLE_POS,
		"THE FALLS": Vector2(0.0, _cliff_z(0.0) - 10.0),
		"THE RIVER": RIVER[3],
	}, 36.0, {"THE TEMPLE": TEMPLE_TIERS * TEMPLE_TIER_H + 14.0})

	for i: int in 5: await physics_frame
	g.add_drop_links()
	await g.bake_navmesh(terrain)
	print("navmesh: %d ms" % (Time.get_ticks_msec() - t0))

	await g.bake_minimap("res://assets/images/minimap/jungle.png", ARENA_RADIUS + 20.0, Color(0.14, 0.26, 0.12), Color(0.62, 0.66, 0.48)) # the HUD's minimap
	var err := g.save_scene(OUT_SCENE)
	print("scene %s: %s" % [OUT_SCENE, error_string(err)])
	print("height range %.1f .. %.1f m, done in %d ms" % [g.min_h(), g.max_h(), Time.get_ticks_msec() - t0])
	quit()


#region terrain

static func _cliff_z(x: float) -> float:
	return -150.0 + 12.0 * sin(x / 40.0)


# the river's actual course (see _river_course): a smoothed, meandering line every 2 m, its width
# factor per point, and the line's segments bucketed in 16 m cells for fast distance lookups
static var _course := PackedVector2Array()
static var _course_w := PackedFloat32Array()
static var _course_cells := {}
static var _river_idx := 0 # the course point nearest the last _river_dist() query
const _RIVER_CELL := 16.0


## The river's course: RIVER smoothed (Catmull-Rom), then bent side to side in slow loops
## (two sines along its length), its width swelling and narrowing (factor 0.8-1.3). Every 2 m.
static func _river_course() -> void:
	if not _course.is_empty(): return
	var smooth := PackedVector2Array()
	for i: int in RIVER.size() - 1:
		var p0 := RIVER[maxi(i - 1, 0)]
		var p1 := RIVER[i]
		var p2 := RIVER[i + 1]
		var p3 := RIVER[mini(i + 2, RIVER.size() - 1)]
		var n := ceili(p1.distance_to(p2) / 2.0)
		for k: int in n:
			var t := float(k) / n
			var t2 := t * t
			smooth.append(0.5 * ((2.0 * p1) + (-p0 + p2) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2 + (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t2 * t))
	smooth.append(RIVER[RIVER.size() - 1])
	var s := 0.0
	for i: int in smooth.size():
		if i > 0: s += smooth[i].distance_to(smooth[i - 1])
		var d := (smooth[mini(i + 1, smooth.size() - 1)] - smooth[maxi(i - 1, 0)]).normalized()
		var side := Vector2(-d.y, d.x)
		var ease := smoothstep(0.0, 25.0, s) # leaves the pool straight, then wanders
		var bend := (sin(s * 0.045 + 0.7) * 7.0 + sin(s * 0.13 + 2.1) * 2.5) * ease
		_course.append(smooth[i] + side * bend)
		_course_w.append(1.05 + 0.25 * sin(s * 0.031 + 1.3) * ease)
	for i: int in _course.size() - 1:
		var a := _course[i]
		var b := _course[i + 1]
		var lo := Vector2i(floori(minf(a.x, b.x) / _RIVER_CELL) - 1, floori(minf(a.y, b.y) / _RIVER_CELL) - 1)
		var hi := Vector2i(floori(maxf(a.x, b.x) / _RIVER_CELL) + 1, floori(maxf(a.y, b.y) / _RIVER_CELL) + 1)
		for cx: int in range(lo.x, hi.x + 1):
			for cz: int in range(lo.y, hi.y + 1):
				var key := Vector2i(cx, cz)
				# packed arrays are values: append to a copy, then put it back (appending to the one
				# in the dictionary changes nothing)
				var list: PackedInt32Array = _course_cells.get(key, PackedInt32Array())
				list.append(i)
				_course_cells[key] = list


## Distance from p to the river, in units of its width there (1 = 1 m where the river's at its
## base width; a wide stretch reads nearer). 999 when it's more than ~16 m away.
static func _river_dist(p: Vector2) -> float:
	_river_course()
	var cell: Variant = _course_cells.get(Vector2i(floori(p.x / _RIVER_CELL), floori(p.y / _RIVER_CELL)))
	if cell == null: return 999.0
	var best := INF
	var best_w := 1.0
	for i: int in cell as PackedInt32Array:
		var q := Geometry2D.get_closest_point_to_segment(p, _course[i], _course[i + 1])
		var d := p.distance_to(q)
		if d < best:
			best = d
			best_w = _course_w[i]
			_river_idx = i
	return best / best_w


## The ground's look at a terrain vertex: Vector3i(base, overlay, blend 0-255 toward the overlay).
## Mossy rock on anything steep; wet mud along the river and round the pools; elsewhere leaf
## litter with moss thinning in through it in patches (more of it near water). Moss kept under
## half: the height blend is nearly winner-takes-all (see overworld_gen._paint).
func _paint(ix: int, iz: int, slope: float) -> Vector3i:
	var x := float(ix - g.half)
	var z := float(iz - g.half)
	var p := Vector2(x, z)
	var rock := smoothstep(0.16, 0.3, slope)
	var wet := 0.0
	var near_water := 0.0
	if smoothstep(_cliff_z(x) + 3.0, _cliff_z(x) - 3.0, z) < 0.5:
		var d := _river_dist(p)
		wet = 1.0 - smoothstep(5.0, 9.0, d)
		near_water = 1.0 - smoothstep(9.0, 18.0, d)
	for fx: float in FALLS_X:
		var dp := p.distance_to(Vector2(fx, _cliff_z(fx) + 13.0))
		wet = maxf(wet, 1.0 - smoothstep(13.0, 17.0, dp))
		near_water = maxf(near_water, 1.0 - smoothstep(17.0, 26.0, dp))
	var moss := 0.46 * maxf(smoothstep(-0.1, 0.45, _moss_noise.get_noise_2d(x, z)), near_water)
	if rock > 0.01: return Vector3i(G_ROCK, G_MUD if wet > 0.5 else G_MOSS, roundi((1.0 - rock) * 255.0))
	if wet > 0.01: return Vector3i(G_FLOOR, G_MUD, roundi(wet * 255.0))
	return Vector3i(G_FLOOR, G_MOSS, roundi(moss * 255.0))


func _height(x: float, z: float) -> float:
	return _height_at(x, z, true)


## The riverbed's height at every course point: the ground along the course (without the river),
## smoothed over ~60 m, RIVER_DEPTH down, and never rising downstream (water can't climb: where
## the land rises the river cuts a little gorge). The water sits 1.2 m over it.
func _river_bed() -> PackedFloat32Array:
	if not _bed.is_empty(): return _bed
	_river_course()
	var ground := PackedFloat32Array()
	for p: Vector2 in _course: ground.append(_height_at(p.x, p.y, false))
	var bed := PackedFloat32Array()
	for i: int in ground.size():
		var sum := 0.0
		var cnt := 0
		for j: int in range(maxi(i - 15, 0), mini(i + 16, ground.size())):
			sum += ground[j]
			cnt += 1
		bed.append(sum / cnt - RIVER_DEPTH)
	for i: int in range(1, bed.size()): bed[i] = minf(bed[i], bed[i - 1])
	_bed = bed
	return _bed


func _height_at(x: float, z: float, river: bool) -> float:
	var p := Vector2(x, z)
	var r := p.length()
	var ground := _roll.get_noise_2d(x, z) * 4.0
	# flat temple plateau and spawn clearing
	ground = lerpf(ground, TEMPLE_GROUND, 1.0 - smoothstep(TEMPLE_HALF + TEMPLE_PLAZA, TEMPLE_HALF + TEMPLE_PLAZA + 18.0, p.distance_to(TEMPLE_POS)))
	ground = lerpf(ground, 1.0, 1.0 - smoothstep(20.0, 34.0, p.distance_to(SPAWN_POS)))
	# the highland north of the cliff (a 6 m-wide face, steep enough to wall-jump)
	var high := smoothstep(_cliff_z(x) + 3.0, _cliff_z(x) - 3.0, z)
	var h := ground + HIGHLAND_H * high + high * _roll.get_noise_2d(x * 1.7, z * 1.7) * 2.0
	# each fall's stream bed, notching the lip
	for fx: float in FALLS_X:
		var cz := _cliff_z(fx)
		h -= 1.2 * high * (1.0 - smoothstep(2.5, 5.5, absf(x - fx))) * smoothstep(cz - STREAM_LEN - 4.0, cz - STREAM_LEN + 2.0, z)
	# pools under the falls
	for fx: float in FALLS_X:
		var pool := Vector2(fx, _cliff_z(fx) + 13.0)
		h -= 3.0 * (1.0 - smoothstep(8.0, 16.0, p.distance_to(pool)))
	# the river channel (south of the cliff only): down to the bed in the middle, back up to the
	# ground by 13 m (in the river's width units) out
	if river and high < 0.5:
		var d := _river_dist(p)
		if d < 13.0:
			var bed := _river_bed()[_river_idx]
			h = minf(h, lerpf(bed, h, smoothstep(7.0, 13.0, d)))
	# the rim
	var rim := pow(smoothstep(RIM_START, RIM_FULL, r), 1.6)
	h += rim * (90.0 + 40.0 * _ridge_noise.get_noise_2d(x, z))
	return h

#endregion


#region landmarks

## A water surface (MeshInstance3D, look only, casts no shadow) into `parent`: its mesh saved
## binary in the mesh dir, its material one of the art water materials.
func _water(parent: Node3D, node_name: String, st: SurfaceTool, material: String) -> void:
	st.generate_tangents()
	var mesh := st.commit()
	var path := "%s/%s.res" % [g.mesh_dir, node_name.to_snake_case()]
	ResourceSaver.save(mesh, path)
	var mi := MeshInstance3D.new()
	mi.name = node_name
	mi.mesh = load(path)
	mi.material_override = load("%s/%s.tres" % [ART, material])
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)


## The water level of the pool under the fall at fx: 1 m over its bottom, but held by its bank all
## round (just under the lowest ground on its rim; the east pool drains into the river there).
func _pool_level(fx: float) -> float:
	var c := Vector2(fx, _cliff_z(fx) + 13.0)
	var level := g.h(c.x, c.y) + 1.0
	for k: int in 48:
		var rim := c + Vector2.from_angle(TAU * k / 48.0) * 14.5
		if _river_dist(rim) < 13.0: continue # where the river leaves: it drains there, it doesn't hold
		level = minf(level, g.h(rim.x, rim.y) - 0.3)
	return level


## A flat disc of water (a pool): `radius` m, its edges under the banks (the terrain cuts the
## shoreline). UV = metres (x, z).
func _pool_surface(centre: Vector3, radius: float) -> SurfaceTool:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	const SEG := 48
	for s: int in SEG:
		var a0 := TAU * s / SEG
		var a1 := TAU * (s + 1) / SEG
		var pts: Array[Vector3] = [Vector3.ZERO, Vector3(cos(a1), 0.0, sin(a1)) * radius, Vector3(cos(a0), 0.0, sin(a0)) * radius]
		if (pts[1] - pts[0]).cross(pts[2] - pts[0]).y > 0.0: pts = [pts[0], pts[2], pts[1]] # front (up) winds clockwise
		for p: Vector3 in pts:
			st.set_normal(Vector3.UP)
			st.set_uv(Vector2(p.x, p.z))
			st.add_vertex(centre + p)
	return st


func _make_ember_material() -> void:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(1.0, 0.45, 0.12)
	m.emission_enabled = true
	m.emission = Color(1.0, 0.5, 0.15)
	m.emission_energy_multiplier = 3.0
	var path := "%s/ember.tres" % g.mat_dir
	ResourceSaver.save(m, path)
	g.mats[&"ember"] = load(path)


## Stepped pyramid: eight tiers you can jump-and-vault up, a grand ramp up the south face, a
## shrine (four pillars and a roof) on top. It's hollow: doorways east, west and north lead into
## a pillared hall, and a shaft climbs from the hall's ceiling to the summit (a spiral of ledges
## starting in the hall). Tiers are rings around the hall / shaft, so nothing is buried in them.
func _build_temple() -> void:
	var kit := MapKit.new()
	var base := Vector3(TEMPLE_POS.x, TEMPLE_GROUND, TEMPLE_POS.y)
	for i: int in TEMPLE_TIERS:
		var half := TEMPLE_HALF - i * TEMPLE_STEP
		var top := (i + 1) * TEMPLE_TIER_H
		var bottom := i * TEMPLE_TIER_H - (2.0 if i == 0 else 0.0)
		var hole := TEMPLE_HALL if bottom < TEMPLE_HALL_H else TEMPLE_SHAFT
		_temple_ring(kit, base, half, hole, bottom, top, bottom < TEMPLE_DOOR_H)
	var top_y := TEMPLE_TIERS * TEMPLE_TIER_H
	var top_half := TEMPLE_HALF - (TEMPLE_TIERS - 1) * TEMPLE_STEP
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			kit.box(base + Vector3(sx * (top_half - 2.0), top_y + 3.5, sz * (top_half - 2.0)), Vector3(2.0, 7.0, 2.0), &"temple", 0.0, false)
			kit.look(&"temple_pillar", &"fit", Vector3(2.0, 7.0, 2.0))
	# roof flush with the pillars' outer faces: you can wall-jump up one and over its edge
	kit.box(base + Vector3(0.0, top_y + 7.5, 0.0), Vector3(top_half * 2.0 - 2.0, 1.0, top_half * 2.0 - 2.0), &"temple", 0.0, false)
	kit.look(&"temple_roof", &"fit", Vector3(38.4, 1.0, 38.4))
	_temple_dressing(kit, base)
	# the hall: four great pillars, and the shaft's ledges spiralling up from the floor (one per
	# 2.5 m, turning a side each time) to just under the summit's rim. Each spans only the middle
	# of its wall, so none hangs over the one below: the corners stay open to climb through
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			kit.box(base + Vector3(sx * 11.0, (TEMPLE_HALL_H - 2.0) * 0.5, sz * 11.0), Vector3(2.5, TEMPLE_HALL_H + 2.0, 2.5), &"temple", 0.0, false)
			kit.look(&"hall_pillar", &"fit", Vector3(2.5, 12.5, 2.5))
	# the hall's paving and the three doorways' (look only, 2 cm proud of the plaza: you walk on the
	# ground under it). A hair in from the walls so no face lies on theirs
	kit.visual(base + Vector3.UP * -0.03, Vector3(TEMPLE_HALL * 2.0 - 0.02, 0.1, TEMPLE_HALL * 2.0 - 0.02), &"temple")
	for out: Vector3 in [Vector3.FORWARD, Vector3.RIGHT, Vector3.LEFT]:
		var across := Vector3(absf(out.z), 0.0, absf(out.x))
		var run := TEMPLE_HALF + 0.5 - TEMPLE_HALL
		kit.visual(base + out * (TEMPLE_HALL + run * 0.5) + Vector3.UP * -0.03,
				across * (TEMPLE_DOOR_W - 0.02) + out.abs() * run + Vector3.UP * 0.1, &"temple")
	var ledge := 2.4
	var k := 1
	while k * 2.5 < top_y - 1.0:
		var a := k * PI * 0.5
		var out := Vector3(sin(a), 0.0, cos(a))
		kit.box(base + out * (TEMPLE_SHAFT - ledge * 0.5) + Vector3.UP * (k * 2.5 - 0.3), Vector3(6.0, 0.6, ledge), &"stone", a, false)
		kit.look(&"temple_ledge", &"fit", Vector3(6.0, 0.6, 2.4))
		k += 1
	# grand ramp: from the plaza to the top tier's edge (~31 deg). A deep slab, solid down to the
	# plaza and the tiers (no hollow under it), but not so deep its top end pokes into the hall
	kit.slab(base + Vector3(0.0, 0.0, TEMPLE_HALF + TEMPLE_RAMP_OUT), base + Vector3(0.0, top_y, top_half), 10.0, 14.0, &"temple")
	kit.look(&"grand_stair", &"tile", Vector3(10.0, 14.0, 2.3006)) # (a staircase: steps cut just under the slope)
	# braziers by the pillars (the hall is mostly in shade): pedestal, bowl, glowing embers
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			var at := base + Vector3(sx * 8.0, 0.0, sz * 8.0)
			kit.blocker(at + Vector3(0.0, 1.5, 0.0), Vector3(1.0, 3.0, 1.0), PI * 0.25)
			kit.blocker(at + Vector3(0.0, 3.25, 0.0), Vector3(1.8, 0.5, 1.8), PI * 0.25)
			kit.model(&"brazier", Transform3D(Basis.IDENTITY, at))
	var holder := g.emit_world_kit(kit, "Temple")
	for sx: float in [-1.0, 1.0]: # their light
		for sz: float in [-1.0, 1.0]:
			var lamp := OmniLight3D.new()
			lamp.name = "Lamp%d%d" % [int(sx > 0.0), int(sz > 0.0)]
			lamp.light_color = Color(1.0, 0.72, 0.42)
			lamp.light_energy = 2.0
			lamp.omni_range = 16.0
			lamp.position = base + Vector3(sx * 8.0, 4.6, sz * 8.0)
			holder.add_child(lamp)


## The tiers' dressing (look only): a cornice and a carved frieze under it along every tier's four
## outer faces, a stepped corbel-arch frame round the three doorways (on the second tier's face,
## where the doorways' lintels are).
func _temple_dressing(kit: MapKit, base: Vector3) -> void:
	for i: int in TEMPLE_TIERS:
		var half := TEMPLE_HALF - i * TEMPLE_STEP
		var top := (i + 1) * TEMPLE_TIER_H
		for out: Vector3 in [Vector3.FORWARD, Vector3.BACK, Vector3.RIGHT, Vector3.LEFT]:
			var b := Basis(Vector3.UP, atan2(out.x, out.z))
			var along := Vector3(absf(out.z), 0.0, absf(out.x))
			# the bottom tier is lower than the doorways, so on their sides it's cut through: the bands
			# stop at the cut's edges instead of hanging across the opening
			var spans := [Vector2(-half, half)]
			if top < TEMPLE_DOOR_H and out != Vector3.BACK:
				spans = [Vector2(-half, -TEMPLE_DOOR_W * 0.5), Vector2(TEMPLE_DOOR_W * 0.5, half)]
			elif out == Vector3.BACK: # the grand ramp lies over the south face (the top tier's would poke through)
				spans = [Vector2(-half, -5.6), Vector2(5.6, half)]
			for span: Vector2 in spans:
				var n := maxi(1, roundi((span.y - span.x) / 4.0))
				var seg := (span.y - span.x) / n
				for k: int in n:
					var at := base + out * half + along * (span.x + (k + 0.5) * seg) + Vector3.UP * top
					kit.model(&"temple_cornice", Transform3D(b.scaled_local(Vector3(seg / 4.0, 1.0, 1.0)), at))
					kit.model(&"temple_frieze", Transform3D(b.scaled_local(Vector3(seg / 4.0, 1.0, 1.0)), at + Vector3.DOWN * 0.9))
				# the cornice stands 0.35 proud of the tier's edge with its top flush: solid, so the edge you
				# see is the edge you stand on
				var mid := base + out * (half + 0.175) + along * (span.x + span.y) * 0.5 + Vector3.UP * (top - 0.3)
				kit.blocker(mid, along * (span.y - span.x) + out.abs() * 0.35 + Vector3.UP * 0.6)
	var half1 := TEMPLE_HALF - TEMPLE_STEP
	for out: Vector3 in [Vector3.FORWARD, Vector3.RIGHT, Vector3.LEFT]:
		kit.model(&"temple_door", Transform3D(Basis(Vector3.UP, atan2(out.x, out.z)), base + out * half1))


## One tier as four walls around a square hole (the hall or the shaft), from bottom to top
## (local y). With doors, the east, west and north walls get a doorway at the ground.
func _temple_ring(kit: MapKit, base: Vector3, half: float, hole: float, bottom: float, top: float, doors: bool) -> void:
	var depth := half - hole
	var mid := (half + hole) * 0.5
	# side: (outward direction, length along the wall, has a door)
	for side: Array in [[Vector3.FORWARD, half * 2.0, doors], [Vector3.BACK, half * 2.0, false],
			[Vector3.RIGHT, hole * 2.0, doors], [Vector3.LEFT, hole * 2.0, doors]]:
		var out: Vector3 = side[0]
		var length: float = side[1]
		var along := Vector3(absf(out.z), 0.0, absf(out.x)) # the wall's long axis
		var c := base + out * mid
		var thick := Vector3(absf(out.x), 0.0, absf(out.z)) * depth
		if not side[2]:
			kit.box(c + Vector3.UP * (top + bottom) * 0.5, thick + along * length + Vector3.UP * (top - bottom), &"temple", 0.0, false)
			continue
		var piece := (length - TEMPLE_DOOR_W) * 0.5
		for s: float in [-1.0, 1.0]:
			kit.box(c + along * s * (TEMPLE_DOOR_W + piece) * 0.5 + Vector3.UP * (top + bottom) * 0.5,
					thick + along * piece + Vector3.UP * (top - bottom), &"temple", 0.0, false)
		if top > TEMPLE_DOOR_H: # lintel over the doorway
			var lb := maxf(bottom, TEMPLE_DOOR_H)
			kit.box(c + Vector3.UP * (top + lb) * 0.5, thick + along * TEMPLE_DOOR_W + Vector3.UP * (top - lb), &"temple", 0.0, false)


## The highland's waterfalls (a stream draped down its bed, over the lip and down the cliff
## face into each pool) and the slide chutes: walled ramps from the cliff top down to the floor,
## a speed strip at each head.
func _build_falls() -> void:
	var kit := MapKit.new()
	for chute_x: float in CHUTES_X:
		var cz := _cliff_z(chute_x)
		var top := Vector3(chute_x, g.h(chute_x, cz - 6.0), cz - 6.0)
		var drop := top.y - g.h(chute_x, cz + 40.0) + 1.5 # runs on 1.5 m into the floor
		var bottom := top + Vector3(0.0, -drop, drop / tan(deg_to_rad(CHUTE_ANGLE)))
		kit.slab(top, bottom, 4.0, 0.8, &"wood")
		kit.look(&"chute", &"tile", Vector3(4.0, 0.8, 2.0))
		for s: float in [-1.0, 1.0]: # rails keep you in at speed
			kit.slab(top + Vector3(s * 2.3, 0.8, 0.0), bottom + Vector3(s * 2.3, 0.8, 0.0), 0.5, 1.6, &"wood", 0.0)
			kit.look(&"chute_rail", &"tile", Vector3(0.5, 1.6, 2.0))
		kit.strips.append({"at": top + Vector3(0.0, 0.0, -9.0), "yaw": 0.0, "speed": 34.0})
	var holder := g.emit_world_kit(kit, "Falls")
	for i: int in FALLS_X.size(): # the pools: round, their shore wherever the bowl's bank rises out of them
		var fx := FALLS_X[i]
		var cz := _cliff_z(fx)
		_water(holder, "Pool%d" % i, _pool_surface(Vector3(fx, _pool_level(fx), cz + 13.0), 15.0), "pool_water")
	var mat := load("res://assets/gdshaders/waterfall.gdshader") as Shader
	var sm := ShaderMaterial.new()
	sm.shader = mat
	ResourceSaver.save(sm, "%s/waterfall.tres" % g.mat_dir)
	for i: int in FALLS_X.size():
		var mi := MeshInstance3D.new()
		mi.name = "Water%d" % i
		var path := "%s/falls_water_%d.res" % [g.mesh_dir, i]
		ResourceSaver.save(_waterfall_mesh(FALLS_X[i]), path)
		mi.mesh = load(path)
		mi.material_override = load("%s/waterfall.tres" % g.mat_dir)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		holder.add_child(mi)


## Terrain height as Terrain3D renders it (g.h() is nearest-sample, too coarse on a cliff face).
func _hs(x: float, z: float) -> float:
	return _terrain.get(&"data").call(&"get_height", Vector3(x, 0.0, z))


## One fall's water as a ribbon draped on the ground (lifted along the normal): down the stream
## bed, over the lip, down the face; where it meets the pool it spreads out flat as foam.
## UV = metres (across, downstream); COLOR.r = foam, COLOR.g = edge fade (waterfall.gdshader).
func _waterfall_mesh(fx: float) -> ArrayMesh:
	const COLS := 10
	const STEP := 0.25
	const LIFT := 0.4
	const SPREAD := 7.0
	var cz := _cliff_z(fx)
	var surface := _pool_level(fx) + 0.2 # just over the pool's water
	var rows: Array[PackedVector3Array] = []
	var vs: PackedFloat32Array = []
	var foam: PackedFloat32Array = []
	var fade: PackedFloat32Array = []
	var widths: PackedFloat32Array = []
	var v := 0.0
	var z := cz - STREAM_LEN
	var splash := -1.0 # downstream metres where it hit the pool
	var prev := Vector3.INF
	while z < cz + 30.0:
		var width := lerpf(5.0, 8.5, smoothstep(cz - 8.0, cz, z))
		var slope := absf(_hs(fx, z + 0.5) - _hs(fx, z - 0.5))
		var f := 0.35 * smoothstep(0.4, 2.0, slope) # falling water runs whiter
		var a := 1.0
		if splash >= 0.0:
			width += (v - splash) * 1.2
			f = 1.0 - smoothstep(0.0, SPREAD, v - splash) * 0.8
			a = 1.0 - smoothstep(SPREAD * 0.4, SPREAD, v - splash)
		var row := PackedVector3Array()
		for c: int in COLS:
			var u := (float(c) / (COLS - 1) - 0.5) * width
			var x := fx + u
			var n := Vector3(_hs(x - 0.5, z) - _hs(x + 0.5, z), 1.0, _hs(x, z - 0.5) - _hs(x, z + 0.5)).normalized()
			var p := Vector3(x, _hs(x, z), z) + n * LIFT
			p.y = maxf(p.y, surface)
			row.append(p)
		var mid := row[COLS / 2]
		if prev != Vector3.INF: v += prev.distance_to(mid)
		prev = mid
		if splash < 0.0 and mid.y <= surface + 0.01: splash = v
		rows.append(row)
		vs.append(v)
		foam.append(f)
		fade.append(a)
		widths.append(width)
		if splash >= 0.0 and v - splash > SPREAD: break
		# finer steps down the face, where the ground is steep
		z += STEP if slope > 0.5 or splash >= 0.0 else STEP * 4.0
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for r: int in rows.size():
		for c: int in COLS:
			var t := float(c) / (COLS - 1)
			st.set_color(Color(foam[r], fade[r] * (1.0 - smoothstep(0.65, 1.0, absf(t - 0.5) * 2.0)), 0.0))
			st.set_uv(Vector2(t * widths[r], vs[r]))
			st.set_normal(Vector3.UP)
			st.add_vertex(rows[r][c])
	for r: int in rows.size() - 1:
		for c: int in COLS - 1:
			var i := r * COLS + c
			for k: int in [i, i + 1, i + COLS, i + 1, i + COLS + 1, i + COLS]: st.add_index(k)
	return st.commit()


## River surface (walk-through water) and three log bridges across it.
func _build_river() -> void:
	var kit := MapKit.new()
	_river_course()
	for t: float in [0.3, 0.55, 0.8]: # log bridges, across the course, long enough for its width there
		var i := int(t * (_course.size() - 1))
		var p := _course[i]
		var d := (_course[mini(i + 3, _course.size() - 1)] - _course[maxi(i - 3, 0)]).normalized()
		var across := Vector2(-d.y, d.x) * (13.0 * _course_w[i] + 1.0)
		var from := Vector3(p.x - across.x, g.h(p.x - across.x, p.y - across.y), p.y - across.y)
		var to := Vector3(p.x + across.x, g.h(p.x + across.x, p.y + across.y), p.y + across.y)
		kit.slab(from + Vector3.UP * 0.4, to + Vector3.UP * 0.4, 2.2, 1.0, &"bark")
		kit.look(&"log_bridge", &"tile", Vector3(2.2, 1.0, 2.0))
	var holder := g.emit_world_kit(kit, "River")
	_water(holder, "Water", _river_surface(), "river_water")


## The river's water: one ribbon down the river's course (_river_course), 13 m x its width
## factor each side (wider than the channel: the banks cut its edges), its level 1.2 m over the
## riverbed (_river_bed), under both banks, never rising downstream. UV.x = metres across, UV.y = downstream.
func _river_surface() -> SurfaceTool:
	_river_course()
	var pts: Array[Vector2] = []
	var widths: Array[float] = []
	for i: int in range(0, _course.size(), 2): # every 4 m
		pts.append(_course[i])
		widths.append(_course_w[i])
	var cut := pts.size()
	for i: int in pts.size(): # stop short of the rim
		if pts[i].length() > RIM_START - 15.0:
			cut = i
			break
	pts.resize(cut)
	widths.resize(cut)
	var bed := _river_bed()
	var eased := PackedFloat32Array()
	for i: int in pts.size(): # 1.2 m over the bed, under both banks; never rising downstream
		var p := pts[i]
		var d := (pts[mini(i + 1, pts.size() - 1)] - pts[maxi(i - 1, 0)]).normalized()
		var side := Vector2(-d.y, d.x) * 13.0 * widths[i]
		var bank := minf(g.h(p.x + side.x, p.y + side.y), g.h(p.x - side.x, p.y - side.y))
		eased.append(minf(bed[mini(i * 2, bed.size() - 1)] + 1.2, bank - 0.3))
	for i: int in range(1, eased.size()): eased[i] = minf(eased[i], eased[i - 1])
	# where it leaves the east pool: just under the pool's surface, so the two waters meet without a
	# step (its first row lies inside the pool)
	var pool_c := Vector2(65.0, _cliff_z(65.0) + 13.0)
	var pool_level := _pool_level(65.0)
	for i: int in eased.size(): # (only those rows: nothing downstream follows the pool down)
		if pts[i].distance_to(pool_c) < 15.0: eased[i] = minf(eased[i], pool_level - 0.05)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	const HALF := 13.0
	var along := 0.0
	var rows: Array = []
	for i: int in pts.size():
		var d := (pts[mini(i + 1, pts.size() - 1)] - pts[maxi(i - 1, 0)]).normalized()
		var side := Vector2(-d.y, d.x)
		if i > 0: along += pts[i].distance_to(pts[i - 1])
		var half := HALF * widths[i]
		var l := Vector3(pts[i].x - side.x * half, eased[i], pts[i].y - side.y * half)
		var r := Vector3(pts[i].x + side.x * half, eased[i], pts[i].y + side.y * half)
		rows.append([l, r, along])
	for i: int in rows.size() - 1:
		var a: Array = rows[i]
		var b: Array = rows[i + 1]
		var quad: Array = [[a[0], Vector2(-HALF, a[2])], [a[1], Vector2(HALF, a[2])], [b[1], Vector2(HALF, b[2])], [b[0], Vector2(-HALF, b[2])]]
		for tri: Array in [[0, 1, 2], [0, 2, 3]]:
			var v0: Vector3 = quad[tri[0]][0]
			var v1: Vector3 = quad[tri[1]][0]
			var v2: Vector3 = quad[tri[2]][0]
			var order: Array = tri if (v1 - v0).cross(v2 - v0).y < 0.0 else [tri[0], tri[2], tri[1]] # up = front, clockwise
			for k: int in order:
				st.set_normal(Vector3.UP)
				st.set_uv(quad[k][1])
				st.add_vertex(quad[k][0])
	return st

#endregion


#region groves

func _make_kit(kit_name: StringName) -> MapKit:
	match kit_name:
		&"treehouse": return _kit_treehouse()
		&"twins": return _kit_twins()
	return MapKits.make(kit_name, g.rng, g.cfg)


#region thick trunks

## A thick trunk's mean radius at height y (before its ridges and root flare): `base` at the
## ground, thinning to base * taper at the top.
static func _trunk_r(base: float, taper: float, height: float, y: float) -> float:
	return base * (1.0 - (1.0 - taper) * clampf(y / height, 0.0, 1.0))


## A thick, old trunk (look only): 9-13 ridges round it, each its own height, angular (a
## triangle wave, so they meet in sharp valleys and peaks), twisting a little as they climb;
## small bumps over everything; a root flare; thinning to base * taper at the top; a cap.
## Built at its real size (a mesh of its own: nothing stretched), from `bury` m below the ground.
## Bark: the world-projected bark material. Returns the model's name in g.models.
func _trunk_model(base: float, height: float, taper: float, bury: float = 1.5) -> StringName:
	var rng := RandomNumberGenerator.new()
	rng.seed = 9100 + _trunk_count
	var key := StringName("trunk_%d" % _trunk_count)
	_trunk_count += 1
	var ridges := rng.randi_range(9, 13)
	var amps := PackedFloat32Array()
	for i: int in ridges: amps.append(rng.randf_range(0.07, 0.16))
	# buttress roots: a few big lobes flaring out at the foot, gone a third of the way up
	var lobes := rng.randi_range(4, 6)
	var lobe_phase := rng.randf() * TAU
	var lobe_amp := rng.randf_range(0.28, 0.42)
	var lobe_top := minf(height * 0.33, 9.0)
	var twist := rng.randf_range(0.12, 0.3)
	var twist_f := rng.randf_range(0.05, 0.1)
	var phase := rng.randf() * TAU
	var seg := ridges * 6
	var rings := maxi(8, ceili((height + bury) / 1.1))
	var flare := minf(2.2, height * 0.12)
	var grid: Array[PackedVector3Array] = []
	for j: int in rings + 1:
		var y := -bury + (height + bury) * j / rings
		var r := _trunk_r(base, taper, height, maxf(y, 0.0))
		if y < flare: r *= 1.0 + 0.32 * pow(1.0 - maxf(y, 0.0) / flare, 2.0)
		var ring := PackedVector3Array()
		for s: int in seg + 1:
			var a := TAU * s / seg
			var u := a / TAU * ridges + twist * sin(y * twist_f * TAU + phase)
			var i := posmod(floori(u), ridges)
			var prof := 1.0 - absf(2.0 * (u - floorf(u)) - 1.0) # 0 in a valley, 1 on a peak
			var bump := amps[i] * (prof * 2.0 - 1.0)
			# whole-number frequencies round the trunk: 7.3 and 13.1 didn't come back to where they
			# started, so the last column missed the first and left a slit down every trunk
			var noise := 0.022 * sin(a * 7.0 + y * 1.7 + phase) + 0.014 * sin(a * 13.0 - y * 2.9)
			var fade := pow(1.0 - clampf(y / lobe_top, 0.0, 1.0), 2.0)
			var lobe := pow(maxf(0.0, cos(lobes * 0.5 * (a - lobe_phase))), 4.0) * lobe_amp * fade
			var rr := r * (1.0 + bump * (1.0 - 0.5 * fade) + noise + lobe)
			ring.append(Vector3(cos(a) * rr, y, sin(a) * rr))
		ring[seg] = ring[0] # closed exactly
		grid.append(ring)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var normal_at := func(j: int, s: int) -> Vector3:
		var ds := grid[j][posmod(s + 1, seg)] - grid[j][posmod(s - 1, seg)] # wraps round the seam
		var dy := grid[mini(j + 1, rings)][s] - grid[maxi(j - 1, 0)][s]
		var n := dy.cross(ds).normalized()
		var out := Vector3(grid[j][s].x, 0.0, grid[j][s].z)
		return n if n.dot(out) > 0.0 else -n
	var tri := func(p: Array) -> void: # [[j, s], ...] x3, wound so the outside is the front
		var v: Array[Vector3] = [grid[p[0][0]][p[0][1]], grid[p[1][0]][p[1][1]], grid[p[2][0]][p[2][1]]]
		var c := (v[0] + v[1] + v[2]) / 3.0
		var order := [0, 1, 2] if (v[1] - v[0]).cross(v[2] - v[0]).dot(Vector3(c.x, 0.0, c.z)) < 0.0 else [0, 2, 1]
		for k: int in order:
			var js: Array = p[k]
			st.set_normal(normal_at.call(js[0], js[1]))
			st.set_uv(Vector2(float(js[1]) / seg * TAU * base / 3.0, grid[js[0]][js[1]].y / 3.0))
			st.add_vertex(v[k])
	for j: int in rings:
		for s: int in seg:
			tri.call([[j, s], [j + 1, s], [j + 1, s + 1]])
			tri.call([[j, s], [j + 1, s + 1], [j, s + 1]])
	# the top: a cap (a fan to the middle), facing up
	var top := Vector3(0.0, height, 0.0)
	for s: int in seg:
		var a0 := grid[rings][s]
		var a1 := grid[rings][s + 1]
		var order: Array = [top, a0, a1] if (a0 - top).cross(a1 - top).y < 0.0 else [top, a1, a0]
		for v: Vector3 in order:
			st.set_normal(Vector3.UP)
			st.set_uv(Vector2(v.x, v.z) / 3.0)
			st.add_vertex(v)
	st.generate_tangents()
	var mesh := st.commit()
	mesh.surface_set_material(0, g.mats[&"bark"])
	var path := "%s/%s.res" % [g.mesh_dir, key]
	ResourceSaver.save(MapGen.with_lods(mesh), path)
	g.models[key] = load(path)
	return key


## A thick trunk's collision (unseen): octagons (two boxes 45 deg apart) in 3 m steps, each inside
## the trunk's valleys at its height. `fixed_half` > 0: every step that wide (the twins: their gap
## faces stay where the wall-jump chimney needs them).
func _trunk_collision(k: MapKit, at: Vector3, base: float, taper: float, height: float, fixed_half: float = 0.0) -> void:
	var y0 := -1.0
	while y0 < height - 0.5:
		var h := minf(3.0, height - y0)
		var half := fixed_half if fixed_half > 0.0 else _trunk_r(base, taper, height, y0 + h * 0.5) * 0.86
		for yaw: float in [0.0, PI * 0.25]:
			k.box(at + Vector3(0.0, y0 + h * 0.5, 0.0), Vector3(half * 2.0, h, half * 2.0), &"", yaw, y0 < 0.0)
			k.boxes[k.boxes.size() - 1]["seen"] = false
		y0 += h

#endregion


## Giant trunk with ledges spiralling up it to a deck ring around it; a ground pad onto the deck;
## canopy overhead. The deck ring starts where the ledges end, so the last ledge steps straight
## onto it, and nothing hangs over the ledges below. Its centre top is the kit's "top" (bridges).
func _kit_treehouse() -> MapKit:
	const TRUNK := 3.0   # the trunk's radius at the ground (it thins to TAPER of that at the top)
	const TAPER := 0.8
	const LEDGE := 2.4
	const TUCK := 0.2    # ledges reach this far into the bark (its valleys), no gap behind them
	var k := MapKit.new()
	k.radius = 16.0
	var levels := g.rng.randi_range(6, 8)
	var deck_y := 2.0 + 2.0 * (levels - 1)
	var height := deck_y + g.rng.randf_range(14.0, 20.0)
	k.mesh(_trunk_model(TRUNK, height, TAPER), Vector3.ZERO, g.rng.randf() * TAU)
	_trunk_collision(k, Vector3.ZERO, TRUNK, TAPER, height)
	for i: int in levels:
		var a := (i % 4) * PI * 0.5
		var out := Vector3(sin(a), 0.0, cos(a))
		var toward := Vector3(sin(a + PI * 0.5), 0.0, cos(a + PI * 0.5))
		var y := 2.0 + i * 2.0 - 0.3
		var r := _trunk_r(TRUNK, TAPER, height, y) - TUCK # the trunk here: ledges hug it as it thins
		var p := out * (r + LEDGE * 0.5) + toward * (LEDGE * 0.5) + Vector3.UP * y
		k.box(p, Vector3(LEDGE, 0.6, r * 2.0 + LEDGE), &"wood", atan2(toward.x, toward.z), false)
	# deck ring: inner edge where the ledges' outer edge is
	var inner := _trunk_r(TRUNK, TAPER, height, deck_y) - TUCK + LEDGE
	var width := DECK_HALF - inner
	for s: float in [-1.0, 1.0]:
		k.box(Vector3(0.0, deck_y - 0.4, s * (inner + width * 0.5)), Vector3(DECK_HALF * 2.0, 0.8, width), &"wood", 0.0, false)
		k.box(Vector3(s * (inner + width * 0.5), deck_y - 0.4, 0.0), Vector3(width, 0.8, inner * 2.0), &"wood", 0.0, false)
	var crown_yaw := g.rng.randf() * TAU
	for part: StringName in [&"crown_leaves", &"crown_shadow"]:
		k.mesh(part, Vector3(0.0, height - 1.5, 0.0), crown_yaw, 1.35)
	k.pad(Vector3(DECK_HALF + 5.0, 0.0, 0.0), Vector3(inner + width * 0.5, deck_y, 0.0), 4.0)
	k.top = Vector3(0.0, deck_y, 0.0)
	k.has_top = true
	return k


## Two trunks 3.4 m apart: wall-jump up the gap to the platforms bridging them on either side of
## it (the gap itself stays open above: you climb past their edge and vault on); stumps to hop
## around. DECK_Y is in reach of a jump and three wall-jumps. Bots get a wall-jump link up.
func _kit_twins() -> MapKit:
	const GAP := 3.4
	const DECK_Y := 8.0
	var k := MapKit.new()
	k.radius = 12.0
	var height := g.rng.randf_range(22.0, 28.0)
	for s: float in [-1.0, 1.0]:
		# a thick ridged trunk (a little thinner at the top); its collision keeps the old 3 m
		# square's faces, so the chimney between the two is the 3.4 m it was
		var at := Vector3(s * (GAP * 0.5 + 1.5), 0.0, 0.0)
		k.mesh(_trunk_model(1.62, height, 0.9), at, g.rng.randf() * TAU)
		_trunk_collision(k, at, 1.62, 0.9, height, 1.5)
		var crown_yaw := g.rng.randf() * TAU
		for part: StringName in [&"crown_leaves", &"crown_shadow"]:
			k.mesh(part, Vector3(s * (GAP * 0.5 + 1.5), height - 1.0, 0.0), crown_yaw, 0.85)
	for s: float in [-1.0, 1.0]: # trunks are 3 m deep: each platform starts at their back/front face
		k.box(Vector3(0.0, DECK_Y - 0.4, s * 2.5), Vector3(GAP + 3.0, 0.8, 2.0), &"wood", 0.0, false)
	k.link(Vector3.ZERO, Vector3(0.0, DECK_Y, 2.5), GameMap.LINK_WALLJUMP)
	for i: int in 5:
		var a := g.rng.randf() * TAU
		var r := g.rng.randf_range(6.0, 10.0)
		var stump_h := g.rng.randf_range(1.0, 3.2) # stumps: short thick trunks too
		var at := Vector3(cos(a) * r, 0.0, sin(a) * r)
		k.mesh(_trunk_model(0.85, stump_h, 0.85, 0.8), at, g.rng.randf() * TAU)
		_trunk_collision(k, at, 0.85, 0.85, stump_h)
	return k


## Treehouses packed into each grove (Poisson, GROVE_SPACING apart), registered as clusters so
## everything else keeps clear of them.
func _build_groves() -> void:
	for gi: int in GROVES.size():
		var centre := Vector2(GROVES[gi].x, GROVES[gi].y)
		var radius := GROVES[gi].z
		var sites: Array[Vector2] = []
		for tries: int in 600:
			var p := centre + Vector2.from_angle(g.rng.randf() * TAU) * sqrt(g.rng.randf()) * radius
			if _grove_blocked(p): continue
			var ok := true
			for s: Vector2 in sites: ok = ok and s.distance_to(p) >= GROVE_SPACING
			if ok: sites.append(p)
		for i: int in sites.size():
			var kit := _kit_treehouse()
			var holder := g.emit_kit(kit, sites[i], g.rng.randf() * TAU, "G%d_%02d_treehouse" % [gi, i])
			g.clusters.append({"pos": sites[i], "kit": &"treehouse", "radius": kit.radius, "node": holder})


func _grove_blocked(p: Vector2) -> bool:
	if p.length() > CLUSTER_MAX_R or p.distance_to(TEMPLE_POS) < TEMPLE_HALF + TEMPLE_PLAZA + 10.0 or p.distance_to(SPAWN_POS) < 30.0: return true
	if absf(p.y - _cliff_z(p.x)) < 14.0 or _river_dist(p) < 16.0: return true
	return g.bumpiness(p, 18.0) > 6.0


## Rope bridges between neighbouring treehouse decks: every pair within BRIDGE_MAX whose bridge
## wouldn't cut through a tall cluster (decks sit 12-16 m up, above the low kits) or the temple.
func _build_bridges() -> void:
	var decks: Array[Dictionary] = []
	for c: Dictionary in g.clusters:
		if c.kit == &"treehouse":
			var holder: Node3D = c.node
			decks.append({"top": holder.get_meta(&"top"), "yaw": holder.rotation.y, "pos": c.pos})
	var kit := MapKit.new()
	var done := {}
	for i: int in decks.size():
		for j: int in decks.size():
			if j == i or (decks[i].pos as Vector2).distance_to(decks[j].pos) > BRIDGE_MAX: continue
			var key := Vector2i(mini(i, j), maxi(i, j))
			if done.has(key): continue
			var a: Vector3 = decks[i].top
			var b: Vector3 = decks[j].top
			var dir := Vector3(b.x - a.x, 0.0, b.z - a.z).normalized()
			# keep clear of each deck's own ground pad (it lobs in from local +x)
			var pad_a := Basis(Vector3.UP, decks[i].yaw) * Vector3.RIGHT
			var pad_b := Basis(Vector3.UP, decks[j].yaw) * Vector3.RIGHT
			if dir.dot(pad_a) > cos(deg_to_rad(40.0)) or (-dir).dot(pad_b) > cos(deg_to_rad(40.0)): continue
			var from := a + dir * MapKit.square_edge(dir, decks[i].yaw, DECK_HALF)
			var to := b - dir * MapKit.square_edge(-dir, decks[j].yaw, DECK_HALF)
			var seg := PackedVector2Array([Vector2(from.x, from.z), Vector2(to.x, to.z)])
			if not _bridge_clear(seg, decks[i].pos, decks[j].pos): continue
			done[key] = true
			kit.slab(from, to, 2.2, 0.5, &"wood")
			kit.look(&"plank_walk", &"tile", Vector3(2.4, 0.6, 2.0))
			_bridges.append(seg)
			_bridge_y.append((from.y + to.y) * 0.5)
	g.emit_world_kit(kit, "Bridges")
	print("canopy bridges: %d between %d treehouses" % [_bridges.size(), decks.size()])


func _bridge_clear(seg: PackedVector2Array, a: Vector2, b: Vector2) -> bool:
	const TALL: Array[StringName] = [&"treehouse", &"twins", &"pillars", &"stilts"]
	for c: Dictionary in g.clusters:
		var p: Vector2 = c.pos
		if p == a or p == b or not (c.kit in TALL): continue
		if p.distance_to(Geometry2D.get_closest_point_to_segment(p, seg[0], seg[1])) < (c.radius as float): return false
	return TEMPLE_POS.distance_to(Geometry2D.get_closest_point_to_segment(TEMPLE_POS, seg[0], seg[1])) > TEMPLE_HALF + 4.0


## Poisson-spaced trunks everywhere that's free, with walk-through canopy on top, merged per 64 m
## cell (fading out past 220 m). Planted after the pads so no trunk stands in a lob's way.
## The tree models (tools/blender/trees.py -> assets/models/trees/jungle_trees.glb): each mesh's
## surfaces get the bark and foliage materials, saved binary, registered with MapGen as models.
func _load_trees() -> void:
	var bark := load(ART + "/tree_bark.tres") as Material
	var leaves := load(ART + "/foliage.tres") as Material
	var scene := (load(TREES_GLB) as PackedScene).instantiate()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(TREE_MESH_DIR))
	# each model splits in two: <name>_wood (trunk, branches: shadows everywhere, cheap) and
	# <name>_leaves (crown: shadows only near the camera, see MapGen.model_opts)
	for n: Node in scene.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if String(mi.name).ends_with("_shadow"): # the crown's solid stand-in for distant shadows
			var path_s := "%s/%s.res" % [TREE_MESH_DIR, mi.name]
			ResourceSaver.save(MapGen.with_lods(mi.mesh as ArrayMesh), path_s)
			g.models[StringName(mi.name)] = load(path_s)
			g.model_opts[StringName(mi.name)] = {"shadow_far": CROWN_SHADOW_NEAR}
			continue
		var src := mi.mesh as ArrayMesh
		for part: String in ["wood", "leaves"]:
			var mesh := ArrayMesh.new()
			for s: int in src.get_surface_count():
				var m := src.surface_get_material(s)
				var is_leaves := m != null and m.resource_name.begins_with("leaves")
				if is_leaves != (part == "leaves"): continue
				mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, src.surface_get_arrays(s))
				mesh.surface_set_material(mesh.get_surface_count() - 1, leaves if is_leaves else bark)
			if mesh.get_surface_count() == 0: continue
			var key := "%s_%s" % [mi.name, part]
			var path := "%s/%s.res" % [TREE_MESH_DIR, key]
			ResourceSaver.save(MapGen.with_lods(mesh), path)
			g.models[StringName(key)] = load(path)
			if part == "leaves": g.model_opts[StringName(key)] = {"shadow_near": CROWN_SHADOW_NEAR}
	scene.free()


func _build_forest() -> void:
	_pad_paths.clear()
	for l: Node in g.nav.get_children():
		var link := l as NavigationLink3D
		if link and int(link.get_meta(GameMap.LINK_KIND, 0)) == GameMap.LINK_PAD:
			_pad_paths.append(PackedVector2Array([Vector2(link.start_position.x, link.start_position.z), Vector2(link.end_position.x, link.end_position.z)]))
	_strip_lanes.clear()
	for s: Node in g.props.find_children("Strip*", "", true, false):
		var n3 := s as Node3D
		var fwd := -n3.global_basis.z # strips push along their own -Z
		var at := Vector2(n3.global_position.x, n3.global_position.z)
		_strip_lanes.append(PackedVector2Array([at - Vector2(fwd.x, fwd.z) * 4.0, at + Vector2(fwd.x, fwd.z) * 75.0]))
	var cells := {}
	var trees: Array[Vector2] = []
	var grid := {}
	var tries := 0
	while tries < 20000:
		tries += 1
		var p := Vector2.from_angle(g.rng.randf() * TAU) * sqrt(g.rng.randf()) * (RIM_START - 25.0)
		if _forest_blocked(p): continue
		var cell := Vector2i(floori(p.x / TREE_SPACING), floori(p.y / TREE_SPACING))
		var ok := true
		for dx: int in range(-1, 2):
			for dz: int in range(-1, 2):
				for q: Vector2 in grid.get(cell + Vector2i(dx, dz), []):
					if q.distance_to(p) < TREE_SPACING: ok = false
		if not ok: continue
		if not grid.has(cell): grid[cell] = []
		(grid[cell] as Array).append(p)
		trees.append(p)
	for p: Vector2 in trees:
		var key := Vector2i(floori(p.x / 64.0), floori(p.y / 64.0))
		if not cells.has(key): cells[key] = MapKit.new()
		var kit: MapKit = cells[key]
		var hgt := g.rng.randf_range(16.0, 30.0)
		var base := g.h(p.x, p.y)
		var tcell := Vector2i(floori(p.x / 16.0), floori(p.y / 16.0))
		if not _tree_grid.has(tcell): _tree_grid[tcell] = []
		(_tree_grid[tcell] as Array).append(Vector3(p.x, p.y, base + hgt))
		# a model tree (one of four), and its trunk as an unseen box (collision, wall-jumps, the
		# navmesh): as thick as the model's trunk a third of the way up, up to where it branches
		var s := hgt / TREE_H
		var side := 2.0 * (TREE_R_BASE + (TREE_R_TOP - TREE_R_BASE) * 0.33) * s * 0.9
		var yaw := g.rng.randf() * TAU
		kit.box(Vector3(p.x, base + hgt * 0.3, p.y), Vector3(side, hgt * 0.6, side), &"", yaw, true)
		kit.boxes[kit.boxes.size() - 1]["seen"] = false
		var variant := g.rng.randi_range(0, 3)
		for part: String in ["wood", "leaves", "shadow"]:
			kit.mesh(StringName("tree_%d_%s" % [variant, part]), Vector3(p.x, base, p.y), yaw, s)
	g.fade_distance = 220.0
	for key: Vector2i in cells:
		g.emit_world_kit(cells[key], "Forest_%d_%d" % [key.x, key.y])
	g.fade_distance = 0.0
	print("forest: %d trees" % trees.size())


func _forest_blocked(p: Vector2) -> bool:
	if p.distance_to(TEMPLE_POS) < TEMPLE_HALF + TEMPLE_PLAZA or p.distance_to(SPAWN_POS) < 26.0: return true
	if absf(p.y - _cliff_z(p.x)) < 9.0: return true
	for fx: float in FALLS_X:
		if p.distance_to(Vector2(fx, _cliff_z(fx) + 13.0)) < 18.0: return true
	for cx: float in CHUTES_X:
		var cz := _cliff_z(cx)
		if absf(p.x - cx) < 6.0 and p.y > cz - 16.0 and p.y < cz + 45.0: return true
	if _river_dist(p) < 11.0: return true
	for c: Dictionary in g.clusters:
		if p.distance_to(c.pos) < (c.radius as float) + 3.0: return true
	for seg: PackedVector2Array in _bridges:
		if p.distance_to(Geometry2D.get_closest_point_to_segment(p, seg[0], seg[1])) < 4.0: return true
	for seg: PackedVector2Array in _strip_lanes: # 34 m/s straight into a trunk is a concussion
		if p.distance_to(Geometry2D.get_closest_point_to_segment(p, seg[0], seg[1])) < 5.0: return true
	for seg: PackedVector2Array in _pad_paths:
		if p.distance_to(seg[0]) < 5.0 or p.distance_to(seg[1]) < 6.0: return true
		if p.distance_to(Geometry2D.get_closest_point_to_segment(p, seg[0], seg[1])) < 3.0: return true
	return false


## Where clusters and open-ground props can't go.
func _reserved(p: Vector2, margin: float) -> bool:
	if p.length() > CLUSTER_MAX_R: return true
	for gr: Vector3 in GROVES:
		if p.distance_to(Vector2(gr.x, gr.y)) < gr.z + 10.0 + margin * 0.5: return true
	if p.distance_to(TEMPLE_POS) < TEMPLE_HALF + TEMPLE_PLAZA + margin: return true
	if p.distance_to(SPAWN_POS) < 30.0 + margin * 0.5: return true
	if absf(p.y - _cliff_z(p.x)) < 12.0 + margin * 0.5: return true
	for fx: float in FALLS_X:
		if p.distance_to(Vector2(fx, _cliff_z(fx) + 13.0)) < 16.0 + margin: return true
	for cx: float in CHUTES_X:
		var cz := _cliff_z(cx)
		if absf(p.x - cx) < 6.0 + margin and p.y > cz - 16.0 and p.y < cz + 45.0: return true
	if _river_dist(p) < 12.0 + margin: return true
	return g.bumpiness(p, 20.0) > 8.0


## Launch arcs mustn't clip the temple, a forest trunk or a canopy bridge.
func _landmark_in_the_way(pos: Vector2, y: float) -> bool:
	if pos.distance_to(TEMPLE_POS) < TEMPLE_HALF * 1.2 and y < TEMPLE_GROUND + TEMPLE_TIERS * TEMPLE_TIER_H + 8.0: return true
	var cell := Vector2i(floori(pos.x / 16.0), floori(pos.y / 16.0))
	for dx: int in range(-1, 2):
		for dz: int in range(-1, 2):
			for tr: Vector3 in _tree_grid.get(cell + Vector2i(dx, dz), []):
				if Vector2(tr.x, tr.y).distance_to(pos) < 2.5 and y < tr.z + 1.0: return true
	for i: int in _bridges.size():
		var seg := _bridges[i]
		if pos.distance_to(Geometry2D.get_closest_point_to_segment(pos, seg[0], seg[1])) < 2.5 and absf(y - _bridge_y[i]) < 3.0: return true
	return false

#endregion
