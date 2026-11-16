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
#   everywhere   forest: trunks you can wall-jump off, canopy leaves overhead (walk-through)
#   outside      the rim: mountains from r = 280

const MapGen := preload("res://tools/mapgen/lib/map_gen.gd")
const MapKit := preload("res://tools/mapgen/lib/map_kit.gd")
const MapKits := preload("res://tools/mapgen/lib/map_kits.gd")

const SIZE := 1024
const ARENA_RADIUS := 230.0
const NAV_RADIUS := 270.0
const RIM_START := 280.0
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
const WATERFALL_MAT := "res://assets/tres/materials/greybox/waterfall.tres"
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
	&"leaves": Color(0.2, 0.4, 0.2),     # canopy (walk-through)
	&"temple": Color(0.66, 0.64, 0.52),
}

var _roll := FastNoiseLite.new()
var _ridge_noise := FastNoiseLite.new()
var g: MapGen
var _terrain: Node3D # for draping: its own height lookup, exactly what's rendered
var _bridges: Array[PackedVector2Array] = [] # bridge segments, kept clear of forest trunks
var _bridge_y: Array[float] = []                # their mean deck height
var _tree_grid := {} # Vector2i(16 m cell) -> [Vector3(x, z, trunk top y)], for launch-arc checks
var _pad_paths: Array[PackedVector2Array] = [] # pad -> landing, kept clear of trunks
var _strip_lanes: Array[PackedVector2Array] = [] # speed strip -> where it flings you, kept clear too


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var t0 := Time.get_ticks_msec()
	g = MapGen.new(self, SIZE)
	g.data_dir = "res://assets/terrain/jungle"
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

	g.bake_heights(_height)
	print("heights: %d ms" % (Time.get_ticks_msec() - t0))
	await g.write_terrain_data()
	g.make_materials(COLORS)
	_make_water_material()

	var map := g.begin_scene("Jungle", MAP_SCRIPT)
	map.set(&"arena_radius", ARENA_RADIUS)
	map.set(&"storm_height_scale", 1.5)
	g.enter_tree()
	g.add_environment(ENV, 140.0)
	var terrain := g.add_terrain("jungle_floor_albedo", Color(0.36, 0.48, 0.28), "jungle_rock_albedo", Color(0.42, 0.44, 0.4))
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

	var err := g.save_scene(OUT_SCENE)
	print("scene %s: %s" % [OUT_SCENE, error_string(err)])
	print("height range %.1f .. %.1f m, done in %d ms" % [g.min_h(), g.max_h(), Time.get_ticks_msec() - t0])
	quit()


#region terrain

static func _cliff_z(x: float) -> float:
	return -150.0 + 12.0 * sin(x / 40.0)


## Distance from p to the river polyline.
static func _river_dist(p: Vector2) -> float:
	var best := INF
	for i: int in RIVER.size() - 1:
		best = minf(best, p.distance_to(Geometry2D.get_closest_point_to_segment(p, RIVER[i], RIVER[i + 1])))
	return best


func _height(x: float, z: float) -> float:
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
	# the river channel (south of the cliff only)
	if high < 0.5: h -= RIVER_DEPTH * (1.0 - smoothstep(7.0, 13.0, _river_dist(p)))
	# the rim
	var rim := pow(smoothstep(RIM_START, RIM_FULL, r), 1.6)
	h += rim * (90.0 + 40.0 * _ridge_noise.get_noise_2d(x, z))
	return h

#endregion


#region landmarks

func _make_water_material() -> void:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.3, 0.55, 0.65, 0.55)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.roughness = 0.15
	var path := "%s/water.tres" % MapGen.MAT_DIR
	ResourceSaver.save(m, path)
	g.mats[&"water"] = load(path)


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
	kit.box(base + Vector3(0.0, top_y + 7.5, 0.0), Vector3(top_half * 2.0 - 1.0, 1.0, top_half * 2.0 - 1.0), &"temple", 0.0, false)
	# the hall: four great pillars, and the shaft's ledges spiralling up from the floor (one per
	# 2.5 m, turning a side each time) to just under the summit's rim. Each spans only the middle
	# of its wall, so none hangs over the one below: the corners stay open to climb through
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			kit.box(base + Vector3(sx * 11.0, (TEMPLE_HALL_H - 2.0) * 0.5, sz * 11.0), Vector3(2.5, TEMPLE_HALL_H + 2.0, 2.5), &"temple", 0.0, false)
	var ledge := 2.4
	var k := 1
	while k * 2.5 < top_y - 1.0:
		var a := k * PI * 0.5
		var out := Vector3(sin(a), 0.0, cos(a))
		kit.box(base + out * (TEMPLE_SHAFT - ledge * 0.5) + Vector3.UP * (k * 2.5 - 0.3), Vector3(6.0, 0.6, ledge), &"stone", a, false)
		k += 1
	# grand ramp: from the plaza to the top tier's edge (~31 deg). A deep slab, solid down to the
	# plaza and the tiers (no hollow under it), but not so deep its top end pokes into the hall
	kit.slab(base + Vector3(0.0, 0.0, TEMPLE_HALF + TEMPLE_RAMP_OUT), base + Vector3(0.0, top_y, top_half), 10.0, 14.0, &"temple")
	var holder := g.emit_world_kit(kit, "Temple")
	for sx: float in [-1.0, 1.0]: # warm braziers by the pillars: the hall is mostly in shade
		for sz: float in [-1.0, 1.0]:
			var lamp := OmniLight3D.new()
			lamp.name = "Lamp%d%d" % [int(sx > 0.0), int(sz > 0.0)]
			lamp.light_color = Color(1.0, 0.72, 0.42)
			lamp.light_energy = 2.0
			lamp.omni_range = 16.0
			lamp.position = base + Vector3(sx * 9.0, 4.0, sz * 9.0)
			holder.add_child(lamp)


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
	for fx: float in FALLS_X:
		var cz := _cliff_z(fx)
		var pool_y := g.h(fx, cz + 13.0) + 1.0
		kit.visual(Vector3(fx, pool_y, cz + 13.0), Vector3(24.0, 0.3, 24.0), &"water")
	for chute_x: float in CHUTES_X:
		var cz := _cliff_z(chute_x)
		var top := Vector3(chute_x, g.h(chute_x, cz - 6.0), cz - 6.0)
		var drop := top.y - g.h(chute_x, cz + 40.0) + 1.5 # runs on 1.5 m into the floor
		var bottom := top + Vector3(0.0, -drop, drop / tan(deg_to_rad(CHUTE_ANGLE)))
		kit.slab(top, bottom, 4.0, 0.8, &"wood")
		for s: float in [-1.0, 1.0]: # rails keep you in at speed
			kit.slab(top + Vector3(s * 2.3, 0.8, 0.0), bottom + Vector3(s * 2.3, 0.8, 0.0), 0.5, 1.6, &"wood", 0.0)
		kit.strips.append({"at": top + Vector3(0.0, 0.0, -9.0), "yaw": 0.0, "speed": 34.0})
	var holder := g.emit_world_kit(kit, "Falls")
	var mat := load("res://assets/gdshaders/waterfall.gdshader") as Shader
	var sm := ShaderMaterial.new()
	sm.shader = mat
	ResourceSaver.save(sm, WATERFALL_MAT)
	for i: int in FALLS_X.size():
		var mi := MeshInstance3D.new()
		mi.name = "Water%d" % i
		var path := "%s/falls_water_%d.res" % [g.mesh_dir, i]
		ResourceSaver.save(_waterfall_mesh(FALLS_X[i]), path)
		mi.mesh = load(path)
		mi.material_override = load(WATERFALL_MAT)
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
	var surface := g.h(fx, cz + 13.0) + 1.0 + 0.2 # just over the pool's water
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
	for i: int in RIVER.size() - 1:
		var a := RIVER[i]
		var b := RIVER[i + 1]
		var n := ceili(a.distance_to(b) / 10.0)
		for k: int in n:
			var p := a.lerp(b, (k + 0.5) / n)
			if p.length() > RIM_START - 20.0: continue
			var y := g.h(p.x, p.y) + 1.2
			var d := (b - a).normalized()
			kit.visual(Vector3(p.x, y, p.y), Vector3(15.0, 0.2, a.distance_to(b) / n + 1.0), &"water", atan2(d.x, d.y))
	for t: float in [0.3, 0.55, 0.8]:
		var seg := int(t * (RIVER.size() - 1))
		var local := t * (RIVER.size() - 1) - seg
		var p := RIVER[seg].lerp(RIVER[seg + 1], local)
		var d := (RIVER[seg + 1] - RIVER[seg]).normalized()
		var across := Vector2(-d.y, d.x) * 12.0
		var from := Vector3(p.x - across.x, g.h(p.x - across.x, p.y - across.y), p.y - across.y)
		var to := Vector3(p.x + across.x, g.h(p.x + across.x, p.y + across.y), p.y + across.y)
		kit.slab(from + Vector3.UP * 0.4, to + Vector3.UP * 0.4, 2.2, 1.0, &"bark")
	g.emit_world_kit(kit, "River")

#endregion


#region groves

func _make_kit(kit_name: StringName) -> MapKit:
	match kit_name:
		&"treehouse": return _kit_treehouse()
		&"twins": return _kit_twins()
	return MapKits.make(kit_name, g.rng, g.cfg)


## Giant trunk with ledges spiralling up it to a deck ring around it; a ground pad onto the deck;
## canopy overhead. The deck ring starts where the ledges end, so the last ledge steps straight
## onto it, and nothing hangs over the ledges below. Its centre top is the kit's "top" (bridges).
func _kit_treehouse() -> MapKit:
	const TRUNK := 2.0
	const LEDGE := 2.4
	var k := MapKit.new()
	k.radius = 16.0
	var levels := g.rng.randi_range(6, 8)
	var deck_y := 2.0 + 2.0 * (levels - 1)
	var height := deck_y + g.rng.randf_range(14.0, 20.0)
	k.post(0.0, 0.0, Vector3(TRUNK * 2.0, height, TRUNK * 2.0), &"bark")
	for i: int in levels:
		var a := (i % 4) * PI * 0.5
		var out := Vector3(sin(a), 0.0, cos(a))
		var toward := Vector3(sin(a + PI * 0.5), 0.0, cos(a + PI * 0.5))
		var p := out * (TRUNK + LEDGE * 0.5) + toward * (LEDGE * 0.5) + Vector3.UP * (2.0 + i * 2.0 - 0.3)
		k.box(p, Vector3(LEDGE, 0.6, TRUNK * 2.0 + LEDGE), &"wood", atan2(toward.x, toward.z), false)
	# deck ring: inner edge where the ledges' outer edge is
	var inner := TRUNK + LEDGE
	var width := DECK_HALF - inner
	for s: float in [-1.0, 1.0]:
		k.box(Vector3(0.0, deck_y - 0.4, s * (inner + width * 0.5)), Vector3(DECK_HALF * 2.0, 0.8, width), &"wood", 0.0, false)
		k.box(Vector3(s * (inner + width * 0.5), deck_y - 0.4, 0.0), Vector3(width, 0.8, inner * 2.0), &"wood", 0.0, false)
	k.visual(Vector3(0.0, height, 0.0), Vector3(20.0, 4.0, 20.0), &"leaves")
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
		k.post(s * (GAP * 0.5 + 1.5), 0.0, Vector3(3.0, height, 3.0), &"bark")
		k.visual(Vector3(s * (GAP * 0.5 + 1.5), height, 0.0), Vector3(12.0, 3.0, 12.0), &"leaves")
	for s: float in [-1.0, 1.0]: # trunks are 3 m deep: each platform starts at their back/front face
		k.box(Vector3(0.0, DECK_Y - 0.4, s * 2.5), Vector3(GAP + 3.0, 0.8, 2.0), &"wood", 0.0, false)
	k.link(Vector3.ZERO, Vector3(0.0, DECK_Y, 2.5), GameMap.LINK_WALLJUMP)
	for i: int in 5:
		var a := g.rng.randf() * TAU
		var r := g.rng.randf_range(6.0, 10.0)
		k.post(cos(a) * r, sin(a) * r, Vector3(1.6, g.rng.randf_range(1.0, 3.2), 1.6), &"bark")
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
		var w := g.rng.randf_range(1.6, 2.6)
		var hgt := g.rng.randf_range(16.0, 30.0)
		var base := g.h(p.x, p.y)
		var tcell := Vector2i(floori(p.x / 16.0), floori(p.y / 16.0))
		if not _tree_grid.has(tcell): _tree_grid[tcell] = []
		(_tree_grid[tcell] as Array).append(Vector3(p.x, p.y, base + hgt))
		kit.box(Vector3(p.x, base + hgt * 0.5, p.y), Vector3(w, hgt, w), &"bark", g.rng.randf() * TAU, true)
		var cw := g.rng.randf_range(9.0, 14.0)
		kit.visual(Vector3(p.x, base + hgt, p.y), Vector3(cw, 3.0, cw), &"leaves", g.rng.randf() * TAU)
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
