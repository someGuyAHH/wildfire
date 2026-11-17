extends SceneTree

# Builds the Inferno greybox on the shared map generator (tools/mapgen/lib).
#   godot --headless --script res://tools/mapgen/inferno_gen.gd
#
# No terrain: everything floats over a lava sea (lava_height: fall in and you're back at the
# nearest checkpoint, slowed for 2 s, not dead). Layout (x = east, z = south):
#   centre       THE PIT: an octagonal shaft. A rim walkway at y 0 (the spokes come in here),
#                four floating platforms at 8 m and a spire at 20 m, all by pads, lava below
#   N/E/S/W      four roofless cathedral halls, 84 x 120 m, 30 m walls, from r 80 to r 200:
#                a lava river down the nave (chained bridge, stepping pillar, pads across),
#                side galleries at 8 m (ramps up, wall-jumps), an apse balcony at 16 m (pads),
#                nave columns, blocks to vault / climb / wall-jump
#   spokes       causeways from each hall's inner door to the pit rim
#   ring         long bridges between neighbouring halls' side doors, an island halfway
# Spawn: the south hall's west half.

const MapGen := preload("res://tools/mapgen/lib/map_gen.gd")
const MapKit := preload("res://tools/mapgen/lib/map_kit.gd")

const SIZE := 512
const ARENA_RADIUS := 210.0
const NAV_RADIUS := 230.0

const OUT_SCENE := "res://scn/map/inferno.tscn"
const MAP_SCRIPT := "res://src/map/terrain_map.gd"
const ENV := "res://assets/tres/environments/inferno_environment.tres"
const LAVA_SHADER := "res://assets/gdshaders/lava.gdshader"

const LAVA_Y := -14.0      # the sea's surface (looks)
const LAVA_HEIGHT := -8.0  # fall below this and it's lava (rules)
const FLOOR_THICK := 4.0

const HALL_R := 140.0      # hall centre from the middle
const HALL_HALF_W := 42.0  # across
const HALL_HALF_L := 60.0  # along (r 80 .. 200)
const WALL_T := 3.0
const WALL_H := 30.0
const DOOR_W := 12.0
const DOOR_H := 12.0
const RIVER_HALF := 5.0
const NARTHEX := 20.0      # solid floor across the inner end (the spoke lands on it)
const GALLERY_Y := 8.0
const GALLERY_IN := 35.0   # gallery from here to the wall
const BALCONY_Y := 16.0
const BALCONY_D := 10.0

const PIT_RIM_IN := 32.0
const PIT_RIM_OUT := 44.0
const PIT_WALL_H := 30.0
const PLATFORM_R := 22.0
const PLATFORM_HALF := 6.0
const PLATFORM_Y := 8.0
const SPIRE_Y := 20.0
const SPIRE_HALF := 9.0

const HALLS: Array[Vector3] = [Vector3(0, 0, -1), Vector3(1, 0, 0), Vector3(0, 0, 1), Vector3(-1, 0, 0)]
const HALL_NAMES: Array[String] = ["NAVE OF ASH", "BRIMSTONE NAVE", "CATHEDRAL OF CINDERS", "HALL OF CHAINS"]

const COLORS := {
	&"basalt": Color(0.27, 0.23, 0.22),  # floors, causeways
	&"wall": Color(0.2, 0.16, 0.16),     # hall and pit walls
	&"stone": Color(0.42, 0.36, 0.33),   # columns, blocks
	&"brim": Color(0.62, 0.48, 0.24),    # galleries, balconies, platforms
	&"iron": Color(0.24, 0.24, 0.27),    # bridges, chains, parapets
}

var g: MapGen
var _space: PhysicsDirectSpaceState3D
var _probe := PhysicsShapeQueryParameters3D.new()
var _checkpoints: Array[Vector3] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var t0 := Time.get_ticks_msec()
	g = MapGen.new(self, SIZE)
	g.nav_dir = "res://assets/navmesh/inferno"
	g.mesh_dir = "res://assets/meshes/inferno"
	g.nav_radius = NAV_RADIUS
	g.rng.seed = 666
	g.bake_heights(func(_x: float, _z: float) -> float: return 0.0) # the floors' tops: no terrain
	g.make_materials(COLORS)
	_make_ember_material()

	var map := g.begin_scene("Inferno", MAP_SCRIPT)
	map.set(&"arena_radius", ARENA_RADIUS)
	map.set(&"dry_edge_radius", 240.0) # past every wall: the dry edge never comes into play here
	map.set(&"lava_height", LAVA_HEIGHT)
	g.enter_tree()
	g.add_environment(ENV, 160.0)
	g.begin_props()
	_add_lava()

	_build_pit()
	for i: int in HALLS.size(): _build_hall(i)
	_build_spokes()
	_build_ring()
	for i: int in 6: await physics_frame # everything's solid now: pads check their arcs against it
	var sphere := SphereShape3D.new()
	sphere.radius = 0.6
	_probe.shape = sphere
	_space = g.root.get_world_3d().direct_space_state
	g.arc_blocked = _arc_hits_something
	_pit_pads()
	for i: int in HALLS.size(): _hall_pads(i)
	print("props: %d pads, %d nav links (%d ms)" % [g.pad_count, g.link_count, Time.get_ticks_msec() - t0])

	g.add_spawns(Vector2(-17.0, HALL_R), 8, 7.0)
	_add_checkpoints()
	var labels := {"THE PIT": Vector2.ZERO}
	for i: int in HALLS.size(): labels[HALL_NAMES[i]] = Vector2(HALLS[i].x, HALLS[i].z) * HALL_R
	g.add_labels(labels, 40.0)

	for i: int in 5: await physics_frame
	g.add_drop_links()
	await g.bake_navmesh(null)
	print("navmesh: %d ms" % (Time.get_ticks_msec() - t0))
	var err := g.save_scene(OUT_SCENE)
	print("scene %s: %s, done in %d ms" % [OUT_SCENE, error_string(err), Time.get_ticks_msec() - t0])
	quit()


#region looks

func _make_ember_material() -> void:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(1.0, 0.45, 0.12)
	m.emission_enabled = true
	m.emission = Color(1.0, 0.5, 0.15)
	m.emission_energy_multiplier = 3.0
	var path := "%s/ember.tres" % MapGen.MAT_DIR
	ResourceSaver.save(m, path)
	g.mats[&"ember"] = load(path)


## The lava sea: one big plane under everything (looks only; the rule is lava_height).
func _add_lava() -> void:
	var mi := MeshInstance3D.new()
	mi.name = "Lava"
	var plane := PlaneMesh.new()
	plane.size = Vector2(700.0, 700.0)
	plane.subdivide_width = 0
	mi.mesh = plane
	var mat := ShaderMaterial.new()
	mat.shader = load(LAVA_SHADER)
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position = Vector3(0.0, LAVA_Y, 0.0)
	g.root.add_child(mi)
	var glow := OmniLight3D.new() # the sea lights the undersides a little
	glow.name = "LavaGlow"
	glow.light_color = Color(1.0, 0.4, 0.1)
	glow.light_energy = 0.0 # placeholder: the env's ambient does the work; kept for the art pass
	g.root.add_child(glow)


## A brazier: pedestal, bowl, embers, and its light.
func _brazier(kit: MapKit, at: Vector3) -> void:
	kit.box(at + Vector3(0.0, 1.5, 0.0), Vector3(1.0, 3.0, 1.0), &"stone", PI * 0.25, false)
	kit.box(at + Vector3(0.0, 3.25, 0.0), Vector3(1.8, 0.5, 1.8), &"stone", PI * 0.25, false)
	kit.visual(at + Vector3(0.0, 3.6, 0.0), Vector3(1.3, 0.35, 1.3), &"ember", PI * 0.25)

#endregion


#region the pit

func _build_pit() -> void:
	var kit := MapKit.new()
	var mid := (PIT_RIM_IN + PIT_RIM_OUT) * 0.5
	var side := 2.0 * PIT_RIM_OUT * tan(PI / 8.0) + 1.0
	for k: int in 8:
		var a := k * PI * 0.25
		var radial := Vector3(cos(a), 0.0, sin(a))
		var yaw := atan2(-radial.z, radial.x) # long axis (local z) along the tangent
		# rim walkway
		kit.box(radial * mid + Vector3.UP * -FLOOR_THICK * 0.5, Vector3(PIT_RIM_OUT - PIT_RIM_IN, FLOOR_THICK, side), &"basalt", yaw, false)
		# a low parapet along the rim's inner edge (vault it if you mean to go in)
		var inner_side := 2.0 * PIT_RIM_IN * tan(PI / 8.0) + 0.6
		kit.box(radial * (PIT_RIM_IN + 0.3) + Vector3.UP * 0.55, Vector3(0.6, 1.1, inner_side), &"iron", yaw, false)
		# wall, a door where a spoke comes in (every other side: E, S, W, N)
		var wall_c := radial * (PIT_RIM_OUT + WALL_T * 0.5)
		var wall_side := 2.0 * (PIT_RIM_OUT + WALL_T) * tan(PI / 8.0) + 1.0
		var bottom := LAVA_Y - 2.0
		if k % 2 == 1:
			kit.box(wall_c + Vector3.UP * (bottom + PIT_WALL_H) * 0.5, Vector3(WALL_T, PIT_WALL_H - bottom, wall_side), &"wall", yaw, false)
		else:
			var tangent := Vector3(-radial.z, 0.0, radial.x)
			var piece := (wall_side - DOOR_W) * 0.5
			for s: float in [-1.0, 1.0]:
				kit.box(wall_c + tangent * s * (DOOR_W + piece) * 0.5 + Vector3.UP * (bottom + PIT_WALL_H) * 0.5, Vector3(WALL_T, PIT_WALL_H - bottom, piece), &"wall", yaw, false)
			kit.box(wall_c + Vector3.UP * (DOOR_H + PIT_WALL_H) * 0.5, Vector3(WALL_T, PIT_WALL_H - DOOR_H, DOOR_W), &"wall", yaw, false)
			kit.box(wall_c + Vector3.UP * (bottom - FLOOR_THICK) * 0.5, Vector3(WALL_T, -bottom - FLOOR_THICK, DOOR_W), &"wall", yaw, false) # under the door
	# the spire: a column out of the lava, a platform on top
	kit.box(Vector3(0.0, (LAVA_Y - 2.0 + SPIRE_Y) * 0.5, 0.0), Vector3(8.0, SPIRE_Y - LAVA_Y + 2.0, 8.0), &"stone", PI * 0.125, false)
	kit.box(Vector3(0.0, SPIRE_Y - 0.5, 0.0), Vector3(SPIRE_HALF * 2.0, 1.0, SPIRE_HALF * 2.0), &"brim", PI * 0.125, false)
	# four floating platforms between the spokes, each on a thin column
	for k: int in 4:
		var a := PI * 0.25 + k * PI * 0.5
		var p := Vector3(cos(a), 0.0, sin(a)) * PLATFORM_R
		kit.box(p + Vector3.UP * (PLATFORM_Y - 0.5), Vector3(PLATFORM_HALF * 2.0, 1.0, PLATFORM_HALF * 2.0), &"brim", a, false)
		kit.box(p + Vector3.UP * (LAVA_Y - 2.0 + PLATFORM_Y - 1.0) * 0.5, Vector3(2.0, PLATFORM_Y - 1.0 - LAVA_Y + 2.0, 2.0), &"stone", a, false)
		_checkpoints.append(Vector3(cos(a), 0.0, sin(a)) * mid)
	g.emit_world_kit(kit, "Pit")


## Rim -> platform (8 m), platform -> spire (20 m), spire -> rim (four, one toward each spoke).
func _pit_pads() -> void:
	var holder := g.node(g.props, "PitPads")
	for k: int in 4:
		var a := PI * 0.25 + k * PI * 0.5
		var out := Vector3(cos(a), 0.0, sin(a))
		_try_pad(holder, out * (PIT_RIM_IN + 4.0), out * (PLATFORM_R + 2.0) + Vector3.UP * PLATFORM_Y, 4.0)
		_try_pad(holder, out * (PLATFORM_R - 3.5) + Vector3.UP * PLATFORM_Y, out * 2.0 + Vector3.UP * SPIRE_Y, 4.0)
		var spoke := Vector3(cos(k * PI * 0.5), 0.0, sin(k * PI * 0.5))
		_try_pad(holder, spoke * 4.5 + Vector3.UP * SPIRE_Y, spoke * ((PIT_RIM_IN + PIT_RIM_OUT) * 0.5), 2.0)

#endregion


#region halls

func _hall_xf(i: int) -> Transform3D:
	var u := HALLS[i]
	return Transform3D(Basis(Vector3.UP, atan2(u.x, u.z)), u * HALL_R)


## One hall, in its own frame: local z runs outward (inner door at -HALF_L), x across.
func _build_hall(i: int) -> void:
	var kit := MapKit.new()
	var hw := HALL_HALF_W
	var hl := HALL_HALF_L
	var fy := -FLOOR_THICK * 0.5
	# floors: the narthex across the inner end, then two halves either side of the river
	kit.box(Vector3(0.0, fy, -hl + NARTHEX * 0.5), Vector3(hw * 2.0, FLOOR_THICK, NARTHEX), &"basalt", 0.0, false)
	var half_w := hw - RIVER_HALF
	var half_l := hl * 2.0 - NARTHEX
	for s: float in [-1.0, 1.0]:
		kit.box(Vector3(s * (RIVER_HALF + half_w * 0.5), fy, -hl + NARTHEX + half_l * 0.5), Vector3(half_w, FLOOR_THICK, half_l), &"basalt", 0.0, false)
	# walls: down into the lava, doors in the inner end and both sides (at the middle)
	var bottom := LAVA_Y - 2.0
	var wh := WALL_H - bottom
	var wy := (WALL_H + bottom) * 0.5
	_wall_with_door(kit, Vector3(0.0, wy, -hl - WALL_T * 0.5), Vector3(hw * 2.0 + WALL_T * 2.0, wh, WALL_T), true, bottom)
	kit.box(Vector3(0.0, wy, hl + WALL_T * 0.5), Vector3(hw * 2.0 + WALL_T * 2.0, wh, WALL_T), &"wall", 0.0, false)
	for s: float in [-1.0, 1.0]:
		_wall_with_door(kit, Vector3(s * (hw + WALL_T * 0.5), wy, 0.0), Vector3(WALL_T, wh, hl * 2.0), false, bottom)
	# the river: a chained bridge in the middle, a stepping pillar near the apse
	kit.slab(Vector3(-RIVER_HALF - 0.5, 0.0, 0.0), Vector3(RIVER_HALF + 0.5, 0.0, 0.0), 3.0, 0.6, &"iron", 0.0)
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			kit.box(Vector3(sx * (RIVER_HALF + 0.3), 1.25, sz * 1.6), Vector3(0.3, 2.5, 0.3), &"iron", 0.0, false)
		kit.visual(Vector3(0.0, 1.6, sx * 1.6), Vector3(RIVER_HALF * 2.0 + 0.6, 0.12, 0.12), &"iron") # chain rails
	kit.box(Vector3(0.0, (bottom + 0.0) * 0.5, hl - 15.0), Vector3(3.0, -bottom, 3.0), &"stone", 0.0, false)
	# galleries along both walls at 8 m (pillars under the inner edge), ramps up at the inner end
	var g_from := -20.0
	var g_to := hl - BALCONY_D - 2.0
	var g_w := hw - GALLERY_IN
	for s: float in [-1.0, 1.0]:
		kit.box(Vector3(s * (GALLERY_IN + g_w * 0.5), GALLERY_Y - 0.5, (g_from + g_to) * 0.5), Vector3(g_w, 1.0, g_to - g_from), &"brim", 0.0, false)
		for z: float in [-12.0, 12.0, 28.0, 44.0]:
			kit.box(Vector3(s * (GALLERY_IN + 0.75), (GALLERY_Y - 1.0) * 0.5, z), Vector3(1.5, GALLERY_Y - 1.0, 1.5), &"stone", 0.0, false)
		kit.slab(Vector3(s * (GALLERY_IN + g_w * 0.5), 0.0, -hl + 8.0), Vector3(s * (GALLERY_IN + g_w * 0.5), GALLERY_Y, g_from - 0.5), 6.0, 1.0, &"brim")
		# nave columns (none at the middle: the side doors' way in)
		for z: float in [-30.0, -15.0, 15.0, 30.0, 45.0]:
			kit.box(Vector3(s * 28.0, 14.0, z), Vector3(2.5, 28.0, 2.5), &"stone", 0.0, false)
	# the apse balcony at 16 m, right across the outer end
	kit.box(Vector3(0.0, BALCONY_Y - 0.5, hl - BALCONY_D * 0.5), Vector3(hw * 2.0, 1.0, BALCONY_D), &"brim", 0.0, false)
	# blocks on the floor halves: vault (1.2 m), climb (3 m), wall-jump (6 m)
	var heights: Array[float] = [1.2, 3.0, 6.0]
	for s: float in [-1.0, 1.0]:
		var k := 0
		for z: float in [-30.0, 14.0, 40.0]:
			var hgt: float = heights[(k + i + (1 if s > 0.0 else 0)) % 3]
			var size := Vector3(g.rng.randf_range(3.0, 5.0), hgt, g.rng.randf_range(3.0, 6.0))
			kit.box(Vector3(s * g.rng.randf_range(12.0, 20.0), hgt * 0.5, z + g.rng.randf_range(-3.0, 3.0)), size, &"stone", g.rng.randf_range(-0.3, 0.3), false)
			k += 1
	for s: float in [-1.0, 1.0]: _brazier(kit, Vector3(s * 14.0, 0.0, -hl + 6.0))
	var xf := _hall_xf(i)
	var holder := g.emit_kit(kit, Vector2(xf.origin.x, xf.origin.z), atan2(HALLS[i].x, HALLS[i].z), "Hall%d" % i)
	for s: float in [-1.0, 1.0]:
		var lamp := OmniLight3D.new()
		lamp.light_color = Color(1.0, 0.6, 0.3)
		lamp.light_energy = 2.0
		lamp.omni_range = 18.0
		lamp.position = Vector3(s * 14.0, 4.6, -hl + 6.0)
		holder.add_child(lamp)
	for p: Vector3 in [Vector3(-20.0, 0.0, -2.0), Vector3(20.0, 0.0, -2.0), Vector3(0.0, 0.0, -hl + 10.0)]:
		_checkpoints.append(xf * p)


## A wall box with a door (DOOR_W x DOOR_H, at the ground) in the middle of its long side.
func _wall_with_door(kit: MapKit, c: Vector3, size: Vector3, along_x: bool, bottom: float) -> void:
	var length := size.x if along_x else size.z
	var axis := Vector3.RIGHT if along_x else Vector3.BACK
	var piece := (length - DOOR_W) * 0.5
	var thick := Vector3(0.0, 0.0, size.z) if along_x else Vector3(size.x, 0.0, 0.0)
	for s: float in [-1.0, 1.0]:
		kit.box(c + axis * s * (DOOR_W + piece) * 0.5, thick + axis * piece + Vector3.UP * size.y, &"wall", 0.0, false)
	var top := c.y + size.y * 0.5
	kit.box(Vector3(c.x, (DOOR_H + top) * 0.5, c.z), thick + axis * DOOR_W + Vector3.UP * (top - DOOR_H), &"wall", 0.0, false)
	kit.box(Vector3(c.x, (bottom - FLOOR_THICK) * 0.5, c.z), thick + axis * DOOR_W + Vector3.UP * (-bottom - FLOOR_THICK), &"wall", 0.0, false)


## Pads in a hall: across the river both ways, floor -> gallery, gallery -> balcony.
func _hall_pads(i: int) -> void:
	var xf := _hall_xf(i)
	var holder := g.node(g.props, "Hall%dPads" % i)
	var hl := HALL_HALF_L
	var g_mid := (GALLERY_IN + HALL_HALF_W) * 0.5
	_try_pad(holder, xf * Vector3(-12.0, 0.0, 25.0), xf * Vector3(12.0, 0.0, 25.0), 5.0)
	_try_pad(holder, xf * Vector3(12.0, 0.0, 31.0), xf * Vector3(-12.0, 0.0, 31.0), 5.0)
	for s: float in [-1.0, 1.0]:
		_try_pad(holder, xf * Vector3(s * 22.0, 0.0, 36.0), xf * Vector3(s * g_mid, GALLERY_Y, 36.0), 3.0)
		_try_pad(holder, xf * Vector3(s * g_mid, GALLERY_Y, hl - BALCONY_D - 4.0), xf * Vector3(s * 26.0, BALCONY_Y, hl - BALCONY_D * 0.5), 3.0)


## A pad from `at` to `to` if its flight is clear of everything solid; tries a higher lob once.
func _try_pad(parent: Node3D, at: Vector3, to: Vector3, peak: float) -> void:
	for p: float in [peak, peak + 4.0]:
		if g.arc_clear(at, to, p, []):
			g.pad(parent, at, to, p, false)
			return
	print("  pad %s -> %s: no clear arc, skipped" % [at.snapped(Vector3.ONE * 0.1), to.snapped(Vector3.ONE * 0.1)])


## Is anything solid at this point of a pad arc (a body-sized sphere)? Floors under the final
## approach are fine: arc_clear stops checking near the landing.
func _arc_hits_something(pos: Vector2, y: float) -> bool:
	_probe.transform = Transform3D(Basis.IDENTITY, Vector3(pos.x, y + 0.9, pos.y))
	return not _space.intersect_shape(_probe, 1).is_empty()

#endregion


#region connections

## Causeways from each hall's inner door to the pit rim; a speed strip on two of them.
func _build_spokes() -> void:
	var kit := MapKit.new()
	for i: int in HALLS.size():
		var u := HALLS[i]
		var a := u * (PIT_RIM_OUT - 1.0)
		var b := u * (HALL_R - HALL_HALF_L + 1.0)
		_causeway(kit, a, b, DOOR_W)
		_checkpoints.append((a + b) * 0.5)
		if i % 2 == 1: kit.strips.append({"at": u * (HALL_R - HALL_HALF_L - 6.0), "yaw": atan2(-u.x, -u.z), "speed": 34.0})
	g.emit_world_kit(kit, "Spokes")


## Bridges between neighbouring halls' side doors, an island in the middle of each.
func _build_ring() -> void:
	var kit := MapKit.new()
	for i: int in HALLS.size():
		var j := (i + 1) % HALLS.size()
		var best := [Vector3.ZERO, Vector3.ZERO]
		var best_d := INF
		for si: float in [-1.0, 1.0]:
			for sj: float in [-1.0, 1.0]:
				var a := _hall_xf(i) * Vector3(si * (HALL_HALF_W + WALL_T - 1.0), 0.0, 0.0)
				var b := _hall_xf(j) * Vector3(sj * (HALL_HALF_W + WALL_T - 1.0), 0.0, 0.0)
				if a.distance_to(b) < best_d:
					best_d = a.distance_to(b)
					best = [a, b]
		var a: Vector3 = best[0]
		var b: Vector3 = best[1]
		var m := (a + b) * 0.5
		var dir := (b - a).normalized()
		kit.box(m + Vector3.UP * -FLOOR_THICK * 0.5, Vector3(16.0, FLOOR_THICK, 16.0), &"basalt", atan2(dir.x, dir.z), false)
		_causeway(kit, a, m - dir * 7.5, 10.0)
		_causeway(kit, m + dir * 7.5, b, 10.0)
		_brazier(kit, m + dir.cross(Vector3.UP) * 5.5)
		_checkpoints.append(m)
		kit.strips.append({"at": a + dir * 6.0, "yaw": atan2(dir.x, dir.z), "speed": 34.0})
	g.emit_world_kit(kit, "Ring")


## A straight walkway from a to b (tops at y 0) with low iron parapets you can vault.
func _causeway(kit: MapKit, a: Vector3, b: Vector3, width: float) -> void:
	kit.slab(a, b, width, FLOOR_THICK, &"basalt", 0.5)
	var side := (b - a).normalized().cross(Vector3.UP) * (width * 0.5 - 0.3)
	for s: float in [-1.0, 1.0]:
		kit.slab(a + side * s + Vector3.UP * 1.1, b + side * s + Vector3.UP * 1.1, 0.6, 1.1, &"iron", 0.0)

#endregion


func _add_checkpoints() -> void:
	var holder := g.node(g.root, "Checkpoints")
	for i: int in _checkpoints.size():
		var m := Marker3D.new()
		m.name = "Checkpoint%d" % i
		m.position = _checkpoints[i] + Vector3.UP * 0.5
		holder.add_child(m)
		m.add_to_group(&"checkpoint", true)
