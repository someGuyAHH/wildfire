extends SceneTree

# Builds the Overworld greybox on top of the shared map generator (tools/mapgen/lib): Terrain3D
# heightmap, landmarks, obstacle clusters, pads, strips, bot nav links, pre-baked navmesh chunks.
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

const MapGen := preload("res://tools/mapgen/lib/map_gen.gd")
const MapKit := preload("res://tools/mapgen/lib/map_kit.gd")
const MapKits := preload("res://tools/mapgen/lib/map_kits.gd")

const SIZE := 1024
const ARENA_RADIUS := 260.0
const NAV_RADIUS := 300.0
const RIM_START := 310.0
const RIM_FULL := 480.0

const OUT_SCENE := "res://scn/map/overworld.tscn"
const MAP_SCRIPT := "res://src/map/overworld.gd"
const ENV := "res://assets/tres/environments/gym_environment.tres"

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

const COLORS := {
	&"stone": Color(0.78, 0.68, 0.5),    # aqueduct, ruins
	&"rock": Color(0.55, 0.52, 0.5),     # blocks, mesa pillars
	&"ruin": Color(0.66, 0.58, 0.72),    # towers, pillar runs
	&"wood": Color(0.72, 0.5, 0.32),     # stilt platforms, bridges
	&"ramp": Color(0.86, 0.56, 0.26),    # kickers, ramps (same orange as the gym)
	&"hub": Color(0.42, 0.62, 0.82),     # launch hubs
}

var _roll := FastNoiseLite.new()
var _ridge_noise := FastNoiseLite.new()
var g: MapGen


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var t0 := Time.get_ticks_msec()
	g = MapGen.new(self, SIZE)
	g.data_dir = "res://assets/terrain/overworld"
	g.nav_dir = "res://assets/navmesh/overworld"
	g.mesh_dir = "res://assets/meshes/overworld"
	g.assets_path = "res://assets/tres/terrain/overworld_assets.tres"
	g.nav_radius = NAV_RADIUS
	g.arc_blocked = _landmark_in_the_way
	g.rng.seed = 4242
	_roll.seed = 7
	_roll.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_roll.frequency = 0.007
	_roll.fractal_octaves = 3
	_ridge_noise.seed = 11
	_ridge_noise.frequency = 0.006
	_ridge_noise.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	_ridge_noise.fractal_octaves = 4

	g.bake_heights(_height)
	print("heights: %d ms" % (Time.get_ticks_msec() - t0))
	await g.write_terrain_data()
	print("terrain data: %d ms" % (Time.get_ticks_msec() - t0))
	g.make_materials(COLORS)

	var map := g.begin_scene("Overworld", MAP_SCRIPT)
	map.set(&"arena_radius", ARENA_RADIUS)
	map.set(&"storm_height_scale", 2.0)
	g.enter_tree()
	g.add_environment(ENV)
	var terrain := g.add_terrain()
	map.set(&"terrain", terrain)
	g.begin_props()

	_build_aqueduct()
	_build_landmarks()
	g.place_clusters(MapKits.NAMES, MapKits.FLAT, MapKits.SLOPED, CLUSTER_SPACING, CLUSTER_MAX_R, _reserved,
			func(kit_name: StringName) -> MapKit: return MapKits.make(kit_name, g.rng, g.cfg))
	g.add_launchers({&"hub": 3, &"tower": 1}, 70.0, 170.0)
	g.add_open_pads_and_strips(14, 10, CLUSTER_MAX_R - 10.0, MEADOW_RADIUS, _reserved)
	print("props: %d clusters, %d pads, %d nav links (%d ms)" % [g.clusters.size(), g.pad_count, g.link_count, Time.get_ticks_msec() - t0])
	g.add_spawns()
	g.add_labels({
		"SLIDE HILL": Vector2(HILL_POS.x, HILL_POS.y + 30.0),
		"THE MESA": MESA_POS,
		"THE RIDGE": (RIDGE_A + RIDGE_B) * 0.5,
		"THE CRATER": CRATER_POS,
		"CANYON": Vector2(_canyon_x(40.0), 40.0),
		"AQUEDUCT": Vector2(40.0, AQUEDUCT_Z),
	})

	for i: int in 5: await physics_frame # let the terrain load its regions and the props register
	g.add_drop_links()
	await g.bake_navmesh(terrain)
	print("navmesh: %d ms" % (Time.get_ticks_msec() - t0))

	var err := g.save_scene(OUT_SCENE)
	print("scene %s: %s" % [OUT_SCENE, error_string(err)])
	print("height range %.1f .. %.1f m, done in %d ms" % [g.min_h(), g.max_h(), Time.get_ticks_msec() - t0])
	quit()


#region terrain

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

#endregion


#region landmarks

## Level deck from where the hill's flank reaches deck height to past the canyon's east rim.
## Two broken gaps to jump, collapsed slabs as ramps up from the meadow side.
func _build_aqueduct() -> void:
	var z := AQUEDUCT_Z
	var x0 := HILL_POS.x
	while g.h(x0, z) > AQUEDUCT_DECK - 0.3 and x0 < 0.0: x0 += 1.0 # walk off the hill to deck height
	var kit := MapKit.new()
	var segs := ceili((AQUEDUCT_X1 - x0) / AQUEDUCT_SEG)
	var gaps: Array[int] = [floori(segs / 3.0), floori(segs * 2.0 / 3.0)]
	var slabs: Array[float] = [-75.0, 45.0]
	for sx: float in slabs: # never break the deck right where a slab comes up
		var si := floori((sx - x0) / AQUEDUCT_SEG)
		for gi: int in gaps.size(): if absi(gaps[gi] - si) <= 1: gaps[gi] = si + 3
	for i: int in segs:
		var xs := x0 + i * AQUEDUCT_SEG
		var xc := xs + AQUEDUCT_SEG * 0.5
		var foot := g.h_min(xs, z, 1.5, 2.0) - 1.0
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
		var low := g.h(rx, z + 30.0)
		var rise := AQUEDUCT_DECK - low
		var run := 28.0
		kit.box(Vector3(rx, low + rise * 0.5 - 0.4, z + 2.5 + run * 0.5), Vector3(5.0, 0.8, sqrt(rise * rise + run * run)),
				&"stone", PI, false, atan2(rise, run))
	g.emit_world_kit(kit, "Aqueduct")


## The tower on Slide Hill, pillars on the mesa, a pad up the mesa cliff.
func _build_landmarks() -> void:
	var kit := MapKit.new()
	var hill_top := g.h(HILL_POS.x, HILL_POS.y)
	MapKits.tower(kit, Vector3(HILL_POS.x, hill_top, HILL_POS.y), 22.0)
	kit.pad(Vector3(HILL_POS.x + 18.0, 0.0, HILL_POS.y), Vector3(HILL_POS.x + 1.5, hill_top + 22.0, HILL_POS.y), 6.0, true)
	var tops: Array[float] = [8.0, 11.0, 14.0, 10.0, 16.0, 12.0, 18.0]
	for i: int in tops.size():
		var x := MESA_POS.x - 36.0 + i * 12.0
		var pz := MESA_POS.y + (8.0 if i % 2 else -8.0)
		var base := g.h_min(x, pz, 1.5, 1.5) - 0.5
		kit.box(Vector3(x, base + tops[i] * 0.5, pz), Vector3(3.0, tops[i], 3.0), &"rock", 0.0, false)
	# pad from the canyon side up onto the mesa's east cliff top
	var east := MESA_POS.x + MESA_HALF.x
	kit.pad(Vector3(east + 18.0, 0.0, MESA_POS.y + 20.0), Vector3(east - 12.0, g.h(east - 12.0, MESA_POS.y + 20.0), MESA_POS.y + 20.0), 6.0, true)
	g.emit_world_kit(kit, "Landmarks")


## Where clusters and open-ground props can't go.
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
	return g.bumpiness(p, 20.0) > 8.0


## Launch arcs mustn't clip the aqueduct deck, the hill tower or the mesa pillars.
func _landmark_in_the_way(pos: Vector2, y: float) -> bool:
	if absf(pos.y - AQUEDUCT_Z) < 5.0 and pos.x > HILL_POS.x and pos.x < AQUEDUCT_X1 + 6.0 and y < AQUEDUCT_DECK + 4.0: return true
	if pos.distance_to(HILL_POS) < 8.0 and y < g.h(HILL_POS.x, HILL_POS.y) + 26.0: return true
	var m := (pos - MESA_POS).abs() - MESA_HALF
	return m.x < 4.0 and m.y < 4.0 and y < MESA_HEIGHT + 22.0

#endregion
