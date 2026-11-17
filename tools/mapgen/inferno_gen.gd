extends SceneTree

# Builds the Inferno greybox on the shared map generator (tools/mapgen/lib).
#   godot --headless --script res://tools/mapgen/inferno_gen.gd
#
# No terrain: everything floats over a lava sea (lava_height: fall in and you're back at the
# nearest checkpoint, slowed for 2 s, not dead). Layout (x = east, z = south):
#   centre   THE PIT: an octagonal shaft. A rim walkway at y 0 (the spokes come in here), four
#            floating platforms at 8 m and a spire at 20 m by pads; the spire's four pads throw
#            you over the walls into the hall that way. Lava below.
#   halls    four roofless halls, 100 x 140 m, 30 m walls (invisible ones above: no wall-walking),
#            from r 90 to r 230, each its own place (a round starts in a random one):
#     N  NAVE OF ASH          a sunken crypt of tombs round a plinth, ramps down, catwalks up the
#                             walls (pillars to wall-jump), an ash mound in the apse. In its dark
#                             apse corner, a doorway to a room that isn't there (a portal)
#     E  BRIMSTONE NAVE       a lava lake: islands to hop, chained bridges, fire vents (pads), a
#                             tower in the middle, a balcony over the apse altar
#     S  CATHEDRAL OF CINDERS pews down the nave, column pairs to wall-jump up onto capitals,
#                             chained bridges to the galleries, a choir loft over the altar
#     W  HALL OF CHAINS       a lava pit of platforms hung on chains, bridges and pads climbing
#                             to a cage at 16 m, walkways round the edge
#   spokes   causeways from each hall's inner door to the pit rim
#   ring     long bridges between neighbouring halls' side doors, an island halfway

const MapGen := preload("res://tools/mapgen/lib/map_gen.gd")
const MapKit := preload("res://tools/mapgen/lib/map_kit.gd")
const PORTAL := "res://src/props/portal.gd"

const SIZE := 640
const ARENA_RADIUS := 245.0
const NAV_RADIUS := 265.0

const OUT_SCENE := "res://scn/map/inferno.tscn"
const MAP_SCRIPT := "res://src/map/terrain_map.gd"
const ENV := "res://assets/tres/environments/inferno_environment.tres"
const LAVA_SHADER := "res://assets/gdshaders/lava.gdshader"

const LAVA_Y := -14.0      # the sea's surface (looks)
const LAVA_HEIGHT := -8.0  # fall below this and it's lava (rules)
const BOTTOM := LAVA_Y - 2.0 # walls and pillars reach down into it
const FLOOR_T := 6.0

const HALL_R := 160.0
const HW := 50.0           # hall half width
const HL := 70.0           # hall half length (r 90 .. 230)
const WT := 3.0            # wall thickness
const WALL_H := 30.0
const BLOCK_H := 100.0     # invisible wall above the visible one
const DOOR_W := 12.0
const DOOR_H := 12.0
const NARTHEX := 20.0      # solid floor across each hall's inner end (spawns, the spire's pads)

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
	&"wall": Color(0.2, 0.16, 0.16),     # walls
	&"stone": Color(0.42, 0.36, 0.33),   # columns, blocks, islands
	&"ash": Color(0.48, 0.47, 0.46),     # the crypt
	&"brim": Color(0.62, 0.48, 0.24),    # galleries, balconies, platforms
	&"iron": Color(0.24, 0.24, 0.27),    # bridges, chains, parapets
	&"gold": Color(0.85, 0.66, 0.22),    # the hidden room's prize
}

var g: MapGen
var _space: PhysicsDirectSpaceState3D
var _probe := PhysicsShapeQueryParameters3D.new()
var _checkpoints: Array[Vector3] = []
var _pads: Array[Array] = []   # [at, to, peak] in world space, placed once everything's solid
var _lights: Array[Array] = [] # [position (world), colour, range]
var _debug_arc := false


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var t0 := Time.get_ticks_msec()
	g = MapGen.new(self, SIZE)
	g.mat_dir = MapGen.MAT_DIR + "/inferno"
	g.nav_dir = "res://assets/navmesh/inferno"
	g.mesh_dir = "res://assets/meshes/inferno"
	g.nav_radius = NAV_RADIUS
	g.rng.seed = 666
	g.bake_heights(func(_x: float, _z: float) -> float: return 0.0) # the floors' tops: no terrain
	g.make_materials(COLORS)
	_make_ember_material()

	var map := g.begin_scene("Inferno", MAP_SCRIPT)
	map.set(&"arena_radius", ARENA_RADIUS)
	map.set(&"dry_edge_radius", 290.0) # past every wall: the dry edge never comes into play here
	map.set(&"lava_height", LAVA_HEIGHT)
	g.enter_tree()
	g.add_environment(ENV, 160.0)
	g.begin_props()
	_add_lava()

	_build_pit()
	_build_hall(0, _nave_of_ash)
	_build_hall(1, _brimstone_nave)
	_build_hall(2, _cathedral_of_cinders)
	_build_hall(3, _hall_of_chains)
	_build_spokes()
	_build_ring()
	for i: int in 6: await physics_frame # everything's solid now: pads check their arcs against it
	var sphere := SphereShape3D.new()
	sphere.radius = 0.6
	_probe.shape = sphere
	_space = g.root.get_world_3d().direct_space_state
	g.arc_blocked = _arc_hits_something
	var holder := g.node(g.props, "Pads")
	for p: Array in _pads: _try_pad(holder, p[0], p[1], p[2])
	_spire_pads(holder)
	var lights := g.node(g.root, "Lights")
	for l: Array in _lights:
		var lamp := OmniLight3D.new()
		lamp.light_color = l[1]
		lamp.light_energy = 2.0
		lamp.omni_range = l[2]
		lamp.position = l[0]
		lights.add_child(lamp)
	print("props: %d pads, %d nav links (%d ms)" % [g.pad_count, g.link_count, Time.get_ticks_msec() - t0])

	_add_spawns()
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
	var path := "%s/ember.tres" % g.mat_dir
	ResourceSaver.save(m, path)
	g.mats[&"ember"] = load(path)


## The lava sea: one big plane under everything (looks only; the rule is lava_height).
func _add_lava() -> void:
	var mi := MeshInstance3D.new()
	mi.name = "Lava"
	var plane := PlaneMesh.new()
	plane.size = Vector2(760.0, 760.0)
	mi.mesh = plane
	var mat := ShaderMaterial.new()
	mat.shader = load(LAVA_SHADER)
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position = Vector3(0.0, LAVA_Y, 0.0)
	g.root.add_child(mi)


## A brazier (pedestal, bowl, embers) at `at` (kit space), its light at `world` (+ 4.6 up).
func _brazier(kit: MapKit, at: Vector3, world: Vector3) -> void:
	kit.box(at + Vector3(0.0, 1.5, 0.0), Vector3(1.0, 3.0, 1.0), &"stone", PI * 0.25, false)
	kit.box(at + Vector3(0.0, 3.25, 0.0), Vector3(1.8, 0.5, 1.8), &"stone", PI * 0.25, false)
	kit.visual(at + Vector3(0.0, 3.6, 0.0), Vector3(1.3, 0.35, 1.3), &"ember", PI * 0.25)
	_lights.append([world + Vector3.UP * 4.6, Color(1.0, 0.6, 0.3), 18.0])


## A narrow iron bridge from a to b with chain rails (look) and posts at both ends.
func _chain_bridge(kit: MapKit, a: Vector3, b: Vector3, width: float = 2.5) -> void:
	kit.slab(a, b, width, 0.6, &"iron", 0.4)
	var side := (b - a).normalized().cross(Vector3.UP).normalized() * (width * 0.5 + 0.15)
	for s: float in [-1.0, 1.0]:
		for e: Vector3 in [a, b]: kit.box(e + side * s + Vector3.UP * 1.25, Vector3(0.3, 2.5, 0.3), &"iron", 0.0, false)
		var mid := (a + b) * 0.5 + side * s + Vector3.UP * 1.4
		var run := Vector2(b.x - a.x, b.z - a.z).length()
		var tilt := atan2(b.y - a.y, run)
		var len := sqrt(run * run + (b.y - a.y) * (b.y - a.y))
		kit.box(mid, Vector3(0.12, 0.12, len), &"iron", atan2(b.x - a.x, b.z - a.z), false, tilt)
		kit.boxes[kit.boxes.size() - 1]["solid"] = false

#endregion


#region the pit

func _build_pit() -> void:
	var kit := MapKit.new()
	var mid := (PIT_RIM_IN + PIT_RIM_OUT) * 0.5
	var side := 2.0 * PIT_RIM_OUT * tan(PI / 8.0) + 1.0
	for k: int in 8:
		var a := k * PI * 0.25
		var radial := Vector3(cos(a), 0.0, sin(a))
		var tangent := Vector3(-radial.z, 0.0, radial.x)
		var yaw := atan2(tangent.x, tangent.z) # long axis (local z) along the tangent
		kit.box(radial * mid + Vector3.UP * -FLOOR_T * 0.5, Vector3(PIT_RIM_OUT - PIT_RIM_IN, FLOOR_T, side), &"basalt", yaw, false)
		# a low parapet along the rim's inner edge (vault it if you mean to go in)
		var inner_side := 2.0 * PIT_RIM_IN * tan(PI / 8.0) + 0.6
		kit.box(radial * (PIT_RIM_IN + 0.3) + Vector3.UP * 0.55, Vector3(0.6, 1.1, inner_side), &"iron", yaw, false)
		# wall, a door where a spoke comes in (every other side: E, S, W, N)
		var wall_c := radial * (PIT_RIM_OUT + WT * 0.5)
		var wall_side := 2.0 * (PIT_RIM_OUT + WT) * tan(PI / 8.0) + 1.0
		if k % 2 == 1:
			kit.box(wall_c + Vector3.UP * (BOTTOM + PIT_WALL_H) * 0.5, Vector3(WT, PIT_WALL_H - BOTTOM, wall_side), &"wall", yaw, false)
		else:
			var piece := (wall_side - DOOR_W) * 0.5
			for s: float in [-1.0, 1.0]:
				kit.box(wall_c + tangent * s * (DOOR_W + piece) * 0.5 + Vector3.UP * (BOTTOM + PIT_WALL_H) * 0.5, Vector3(WT, PIT_WALL_H - BOTTOM, piece), &"wall", yaw, false)
			kit.box(wall_c + Vector3.UP * (DOOR_H + PIT_WALL_H) * 0.5, Vector3(WT, PIT_WALL_H - DOOR_H, DOOR_W), &"wall", yaw, false)
			kit.box(wall_c + Vector3.UP * BOTTOM * 0.5, Vector3(WT, -BOTTOM, DOOR_W), &"basalt", yaw, false) # the sill: level with the floors
		_checkpoints.append(Vector3(cos(a + PI / 8.0), 0.0, sin(a + PI / 8.0)) * mid if k % 2 == 0 else Vector3.INF)
	# the spire: a column out of the lava, a platform on top (the column stops just under it)
	kit.box(Vector3(0.0, (BOTTOM + SPIRE_Y - 1.1) * 0.5, 0.0), Vector3(8.0, SPIRE_Y - 1.1 - BOTTOM, 8.0), &"stone", PI * 0.125, false)
	kit.box(Vector3(0.0, SPIRE_Y - 0.5, 0.0), Vector3(SPIRE_HALF * 2.0, 1.0, SPIRE_HALF * 2.0), &"brim", PI * 0.125, false)
	# four floating platforms between the spokes, each on a thin column; pads rim -> platform -> spire
	for k: int in 4:
		var a := PI * 0.25 + k * PI * 0.5
		var out := Vector3(cos(a), 0.0, sin(a))
		var p := out * PLATFORM_R
		kit.box(p + Vector3.UP * (PLATFORM_Y - 0.5), Vector3(PLATFORM_HALF * 2.0, 1.0, PLATFORM_HALF * 2.0), &"brim", a, false)
		kit.box(p + Vector3.UP * (BOTTOM + PLATFORM_Y - 1.1) * 0.5, Vector3(2.0, PLATFORM_Y - 1.1 - BOTTOM, 2.0), &"stone", a, false)
		_pads.append([out * (PIT_RIM_IN + 4.0), out * (PLATFORM_R + 2.0) + Vector3.UP * PLATFORM_Y, 4.0])
		_pads.append([out * (PLATFORM_R - 3.5) + Vector3.UP * PLATFORM_Y, out * 2.0 + Vector3.UP * SPIRE_Y, 4.0])
	g.emit_world_kit(kit, "Pit")


## The spire's four pads: each throws you over the walls into the hall that way (its narthex).
func _spire_pads(holder: Node3D) -> void:
	for i: int in HALLS.size():
		var u := HALLS[i]
		var at := u * 5.0 + Vector3.UP * SPIRE_Y
		var to := _hall_xf(i) * Vector3(0.0, 0.0, -HL + NARTHEX * 0.5 + 2.0)
		var placed := false
		for peak: float in [30.0, 40.0, 50.0, 60.0]:
			if g.arc_clear(at, to, peak, []):
				g.pad(holder, at, to, peak, false)
				placed = true
				break
		if not placed:
			print("  spire pad to %s: no clear arc" % HALL_NAMES[i])
			_debug_arc = true
			g.arc_clear(at, to, 30.0, [])
			_debug_arc = false

#endregion


#region halls

func _hall_xf(i: int) -> Transform3D:
	var u := HALLS[i]
	return Transform3D(Basis(Vector3.UP, atan2(u.x, u.z)), u * HALL_R)


## The shared shell (walls with doors and their sills, invisible walls above, the narthex with
## braziers, spawn and checkpoint), then the hall's own design. Local frame: z runs outward
## (inner door at -HL), x across. `design` fills the rest: design(kit, xf, i).
func _build_hall(i: int, design: Callable) -> void:
	var kit := MapKit.new()
	var xf := _hall_xf(i)
	# walls: inner end (door), sides (a door each, at the middle), outer end (the N hall: a doorway)
	_wall(kit, false, -HL - WT * 0.5, HW + WT, [Vector3(0.0, DOOR_W, DOOR_H)], false)
	var outer_doors: Array = [Vector3(-44.0, 4.0, 5.0)] if i == 0 else []
	_wall(kit, false, HL + WT * 0.5, HW + WT, outer_doors, true)
	for s: float in [-1.0, 1.0]: _wall(kit, true, s * (HW + WT * 0.5), HL, [Vector3(0.0, DOOR_W, DOOR_H)], true)
	kit.box(Vector3(0.0, -FLOOR_T * 0.5, -HL + NARTHEX * 0.5), Vector3(HW * 2.0, FLOOR_T, NARTHEX), &"basalt", 0.0, false)
	for s: float in [-1.0, 1.0]: _brazier(kit, Vector3(s * 16.0, 0.0, -HL + 6.0), xf * Vector3(s * 16.0, 0.0, -HL + 6.0))
	_checkpoints.append(xf * Vector3(0.0, 0.0, -HL + NARTHEX * 0.5))
	design.call(kit, xf, i)
	g.emit_kit(kit, Vector2(xf.origin.x, xf.origin.z), atan2(HALLS[i].x, HALLS[i].z), "Hall%d" % i)


## A wall along local x (along_z = false: an end wall at z = pos) or z (a side wall at x = pos),
## half-length `half`, from the lava up to WALL_H, with doors [centre along it, width, height]
## (sill flush with the floor) and, if `block`, an invisible wall on top up to BLOCK_H.
func _wall(kit: MapKit, along_z: bool, pos: float, half: float, doors: Array, block: bool) -> void:
	var at := func(t: float, y: float) -> Vector3: return Vector3(pos, y, t) if along_z else Vector3(t, y, pos)
	var size_of := func(length: float, h: float) -> Vector3: return Vector3(WT, h, length) if along_z else Vector3(length, h, WT)
	var cuts: Array = doors.duplicate()
	cuts.sort_custom(func(a: Vector3, b: Vector3) -> bool: return a.x < b.x)
	var t := -half
	for d: Vector3 in cuts:
		var d0 := d.x - d.y * 0.5
		if d0 > t: kit.box(at.call((t + d0) * 0.5, (BOTTOM + WALL_H) * 0.5), size_of.call(d0 - t, WALL_H - BOTTOM), &"wall", 0.0, false)
		kit.box(at.call(d.x, (d.z + WALL_H) * 0.5), size_of.call(d.y, WALL_H - d.z), &"wall", 0.0, false) # lintel
		kit.box(at.call(d.x, BOTTOM * 0.5), size_of.call(d.y, -BOTTOM), &"basalt", 0.0, false) # sill
		t = d.x + d.y * 0.5
	if t < half: kit.box(at.call((t + half) * 0.5, (BOTTOM + WALL_H) * 0.5), size_of.call(half - t, WALL_H - BOTTOM), &"wall", 0.0, false)
	if block: kit.blocker(at.call(0.0, (WALL_H + BLOCK_H) * 0.5), size_of.call(half * 2.0, BLOCK_H - WALL_H))


## Floor slab (top at y), x0..x1 by z0..z1, FLOOR_T thick.
func _floor(kit: MapKit, x0: float, x1: float, z0: float, z1: float, y: float = 0.0, mat: StringName = &"basalt") -> void:
	kit.box(Vector3((x0 + x1) * 0.5, y - FLOOR_T * 0.5, (z0 + z1) * 0.5), Vector3(x1 - x0, FLOOR_T, z1 - z0), mat, 0.0, false)


## A pillar out of the lava with its top at y (islands, platforms' columns).
func _pillar(kit: MapKit, x: float, z: float, half: float, y: float, mat: StringName = &"stone") -> void:
	kit.box(Vector3(x, (BOTTOM + y) * 0.5, z), Vector3(half * 2.0, y - BOTTOM, half * 2.0), mat, 0.0, false)


func _pad(xf: Transform3D, at: Vector3, to: Vector3, peak: float) -> void:
	_pads.append([xf * at, xf * to, peak])


## N: a sunken crypt (y -6) of tombs round a plinth, ramps down from the narthex, the apse and
## both aisles; catwalks along the walls at 7 m (pillars under them to wall-jump; vents up);
## an ash mound in the apse; and in the dark apse corner, the doorway to the hidden room.
func _nave_of_ash(kit: MapKit, xf: Transform3D, _i: int) -> void:
	const CRYPT := -6.0
	for s: float in [-1.0, 1.0]: _floor(kit, 38.0 * s if s > 0.0 else -HW, HW if s > 0.0 else -38.0, -HL + NARTHEX, HL)
	_floor(kit, -38.0, 38.0, 52.0, HL)
	_floor(kit, -38.0, 38.0, -HL + NARTHEX, 52.0, CRYPT, &"ash")
	kit.slab(Vector3(0.0, 0.0, -HL + NARTHEX - 0.5), Vector3(0.0, CRYPT, -36.0), 12.0, 1.0, &"ash")
	kit.slab(Vector3(0.0, CRYPT, 38.0), Vector3(0.0, 0.0, 52.5), 12.0, 1.0, &"ash")
	for s: float in [-1.0, 1.0]:
		kit.slab(Vector3(s * 38.5, 0.0, 10.0), Vector3(s * 26.0, CRYPT, 10.0), 6.0, 1.0, &"ash")
	for x: float in [-30.0, -18.0, 18.0, 30.0]:
		for z: float in [-28.0, -14.0, 0.0, 24.0, 36.0]:
			kit.box(Vector3(x, CRYPT + 0.7, z), Vector3(3.0, 1.4, 6.0), &"ash", 0.0, false) # tombs: vault them
	kit.box(Vector3(0.0, CRYPT + 1.5, 6.0), Vector3(14.0, 3.0, 14.0), &"ash", 0.0, false) # the dais (-3)
	kit.box(Vector3(0.0, 0.5, 6.0), Vector3(5.0, 7.0, 5.0), &"stone", 0.0, false)          # the plinth (4): wall-jump it
	for s: float in [-1.0, 1.0]:
		kit.box(Vector3(s * 48.0, 6.5, 10.0), Vector3(4.0, 1.0, 100.0), &"brim", 0.0, false) # catwalk, z -40..60
		for z: float in [-36.0, -24.0, -12.0, 24.0, 36.0, 48.0]:
			kit.box(Vector3(s * 46.75, 3.0, z), Vector3(1.5, 6.0, 1.5), &"stone", 0.0, false)
		_pad(xf, Vector3(s * 3.5, 4.0, 6.0), Vector3(s * 48.0, 7.0, 6.0), 4.0)
		_pad(xf, Vector3(s * 20.0, CRYPT, -42.0), Vector3(s * 48.0, 7.0, -36.0), 4.0)
	# the ash mound (3 m steps)
	for k: int in 3:
		var hw := 30.0 - k * 10.0
		var z0 := 56.0 + k * 4.0
		kit.box(Vector3(0.0, (k + 1) * 3.0 - 1.5, (z0 + HL) * 0.5), Vector3(hw * 2.0, 3.0, HL - z0), &"ash", 0.0, false)
	for s: float in [-1.0, 1.0]: _brazier(kit, Vector3(s * 10.0, CRYPT, -26.0), xf * Vector3(s * 10.0, CRYPT, -26.0))
	_checkpoints.append(xf * Vector3(-44.0, 0.0, -20.0))
	_checkpoints.append(xf * Vector3(44.0, 0.0, 30.0))
	_checkpoints.append(xf * Vector3(-24.0, CRYPT, 8.0))
	_secret_room(kit, xf)


## The hidden room: a doorway in the N hall's dark apse corner (local x -44, in the outer wall)
## that leads into a room under the lava, 40 m down and behind: a portal pair, each doorway
## showing the other side live. A backstop behind the hall's doorway (it's only 3 m of wall).
func _secret_room(kit: MapKit, xf: Transform3D) -> void:
	const Y := -40.0
	const X := -44.0
	const Z0 := HL + 8.0  # the room's door wall
	const Z1 := Z0 + 16.0
	const H := 7.0
	kit.box(Vector3(X, 2.5, HL + WT + 0.5), Vector3(5.0, 6.0, 1.0), &"wall", 0.0, false) # backstop
	_floor(kit, X - 7.0, X + 7.0, Z0, Z1, Y, &"basalt")
	kit.box(Vector3(X, Y + H + 0.5, (Z0 + Z1) * 0.5), Vector3(14.0, 1.0, Z1 - Z0), &"wall", 0.0, false) # ceiling
	for s: float in [-1.0, 1.0]: kit.box(Vector3(X + s * 7.5, Y + H * 0.5, (Z0 + Z1) * 0.5), Vector3(1.0, H, Z1 - Z0), &"wall", 0.0, false)
	kit.box(Vector3(X, Y + H * 0.5, Z1 + 0.5), Vector3(16.0, H, 1.0), &"wall", 0.0, false)
	for s: float in [-1.0, 1.0]: kit.box(Vector3(X + s * 4.75, Y + H * 0.5, Z0 - 0.5), Vector3(5.5, H, 1.0), &"wall", 0.0, false) # door wall, a 4 m doorway
	kit.box(Vector3(X, Y + 6.0, Z0 - 0.5), Vector3(4.0, 2.0, 1.0), &"wall", 0.0, false)
	# what's in it: a prize on a plinth between two braziers
	kit.box(Vector3(X, Y + 0.75, Z1 - 4.0), Vector3(2.0, 1.5, 2.0), &"stone", 0.0, false)
	kit.box(Vector3(X, Y + 2.0, Z1 - 4.0), Vector3(0.9, 1.0, 0.9), &"gold", PI * 0.25, false)
	for s: float in [-1.0, 1.0]: _brazier(kit, Vector3(X + s * 4.5, Y, Z1 - 4.0), xf * Vector3(X + s * 4.5, Y, Z1 - 4.0))
	var room_label := Label3D.new()
	room_label.name = "VaultLabel"
	room_label.text = "THE ASHEN VAULT\nyou weren't supposed to find this"
	room_label.font_size = 64
	room_label.pixel_size = 0.02
	room_label.outline_size = 12
	room_label.position = xf * Vector3(X, Y + 5.2, Z1 - 0.6)
	room_label.rotation.y = xf.basis.get_euler().y + PI
	g.root.add_child(room_label)
	# the portals: A in the hall (face into the hall, -z local), B at the room's doorway (face in)
	var a_xf := xf * Transform3D(Basis(Vector3.UP, PI), Vector3(X, 0.0, HL))
	var b_xf := xf * Transform3D(Basis.IDENTITY, Vector3(X, Y, Z0))
	var portals := g.node(g.root, "Portals")
	var a := Node3D.new()
	a.name = "VaultDoor"
	a.set_script(load(PORTAL))
	a.transform = a_xf
	var b := Node3D.new()
	b.name = "VaultExit"
	b.set_script(load(PORTAL))
	b.transform = b_xf
	portals.add_child(a)
	portals.add_child(b)
	a.set(&"partner_path", NodePath("../VaultExit"))
	b.set(&"partner_path", NodePath("../VaultDoor"))
	# bots can follow you in (and out): portal links, starting just past each doorway's face
	g.link(a_xf * Vector3(0.0, 0.0, -0.35), b_xf * Vector3(0.0, 0.0, 1.5), GameMap.LINK_PORTAL, 1.0)
	g.link(b_xf * Vector3(0.0, 0.0, -0.35), a_xf * Vector3(0.0, 0.0, 1.5), GameMap.LINK_PORTAL, 1.0)
	var lo := xf * Vector3(X - 8.0, Y - 2.0, Z0 - 2.0)
	var hi := xf * Vector3(X + 8.0, Y + H + 2.0, Z1 + 2.0)
	var zone := AABB(lo.min(hi), (hi - lo).abs())
	g.root.set(&"safe_zones", [zone] as Array[AABB])
	_checkpoints.append(xf * Vector3(X, Y, Z0 + 4.0))


## E: a lava lake between two walkways: islands at three heights to hop (gaps a run-up jump
## clears), chained bridges, fire vents (pads), a tower in the middle, a balcony at 12 m over
## the apse altar.
func _brimstone_nave(kit: MapKit, xf: Transform3D, _i: int) -> void:
	for s: float in [-1.0, 1.0]: _floor(kit, 40.0 if s > 0.0 else -HW, HW if s > 0.0 else -40.0, -HL + NARTHEX, HL)
	_floor(kit, -40.0, 40.0, 56.0, HL)
	# islands: x, z, half, top
	var isles: Array[Vector4] = [
		Vector4(-26, -40, 5, 0), Vector4(-12, -32, 4, 1.5), Vector4(3, -40, 5, 0), Vector4(18, -33, 4, 1.5), Vector4(32, -41, 3, 0),
		Vector4(-31, -22, 4, 0), Vector4(-16, -16, 5, 3), Vector4(0, -24, 4, 1.5), Vector4(16, -16, 5, 0), Vector4(31, -21, 4, 1.5),
		Vector4(0, 4, 9, 0), Vector4(-26, 2, 5, 1.5), Vector4(25, 6, 5, 0),
		Vector4(-29, 21, 4, 0), Vector4(-13, 26, 5, 3), Vector4(12, 24, 4, 1.5), Vector4(28, 26, 4, 0),
		Vector4(-20, 42, 5, 1.5), Vector4(0, 40, 5, 0), Vector4(20, 44, 5, 3),
	]
	for v: Vector4 in isles: _pillar(kit, v.x, v.y, v.z + 1.5, v.w) # +1.5: gaps a rising jump clears
	_pillar(kit, 0.0, 4.0, 3.0, 10.0) # the tower
	_chain_bridge(kit, Vector3(-40.5, 0.0, -40.0), Vector3(-30.5, 0.0, -40.0))
	_chain_bridge(kit, Vector3(40.5, 0.0, 6.0), Vector3(29.5, 0.0, 6.0))
	_chain_bridge(kit, Vector3(-9.5, 0.0, 2.0), Vector3(-21.5, 1.5, 2.0))
	_chain_bridge(kit, Vector3(0.0, 0.0, 44.5), Vector3(0.0, 0.0, 56.5))
	_chain_bridge(kit, Vector3(20.0, 3.0, 48.5), Vector3(20.0, 0.0, 56.5))
	_chain_bridge(kit, Vector3(40.5, 0.0, 26.0), Vector3(33.0, 0.0, 26.0))
	_chain_bridge(kit, Vector3(22.5, 0.0, 25.0), Vector3(17.5, 1.5, 24.0))
	_chain_bridge(kit, Vector3(-40.5, 0.0, 21.0), Vector3(-32.5, 0.0, 21.0))
	_pad(xf, Vector3(44.0, 0.0, -10.0), Vector3(6.0, 0.0, 6.0), 6.0)
	_pad(xf, Vector3(-5.0, 0.0, 0.0), Vector3(0.0, 10.0, 4.0), 4.0)
	_pad(xf, Vector3(-44.0, 0.0, 30.0), Vector3(-13.0, 3.0, 26.0), 5.0)
	_pad(xf, Vector3(1.0, 10.0, 6.0), Vector3(0.0, 12.0, 66.0), 6.0)
	# the apse: an altar in steps, a balcony over it (vents up from the floor)
	kit.box(Vector3(0.0, 1.0, 65.0), Vector3(24.0, 2.0, 10.0), &"stone", 0.0, false)
	kit.box(Vector3(0.0, 3.0, 67.0), Vector3(12.0, 2.0, 6.0), &"stone", 0.0, false)
	kit.box(Vector3(0.0, 11.5, 67.0), Vector3(HW * 2.0, 1.0, 6.0), &"brim", 0.0, false)
	for s: float in [-1.0, 1.0]: _pad(xf, Vector3(s * 30.0, 0.0, 58.0), Vector3(s * 30.0, 12.0, 67.0), 3.0)
	_brazier(kit, Vector3(6.0, 0.0, 10.0), xf * Vector3(6.0, 0.0, 10.0))
	for s: float in [-1.0, 1.0]: _brazier(kit, Vector3(s * 20.0, 0.0, 60.0), xf * Vector3(s * 20.0, 0.0, 60.0))
	for p: Vector3 in [Vector3(-45, 0, -20), Vector3(45, 0, 40), Vector3(5, 0, 10), Vector3(-25, 0, 60)]: _checkpoints.append(xf * p)


## S: a full floor, pews down the nave, column pairs (wall-jump the gap) up to capitals at 9 m,
## chained bridges from the capitals to the galleries (9 m, on arcades), a choir loft at 18 m over
## the altar steps (vents up from the galleries).
func _cathedral_of_cinders(kit: MapKit, xf: Transform3D, _i: int) -> void:
	_floor(kit, -HW, HW, -HL + NARTHEX, HL)
	for s: float in [-1.0, 1.0]:
		kit.box(Vector3(s * 44.0, 8.5, 5.0), Vector3(12.0, 1.0, 90.0), &"brim", 0.0, false) # gallery, z -40..50
		for z: float in [-36.0, -24.0, -12.0, 12.0, 24.0, 36.0, 48.0]:
			kit.box(Vector3(s * 38.75, 4.0, z), Vector3(1.5, 8.0, 1.5), &"stone", 0.0, false)
		for z0: float in [-30.0, -6.0, 18.0, 42.0]:
			var x0 := s * 24.0
			for e: float in [-1.0, 1.0]: kit.box(Vector3(x0, 4.5, z0 + e * 3.2), Vector3(3.0, 9.0, 3.0), &"stone", 0.0, false)
			for e: float in [-1.0, 1.0]: kit.box(Vector3(x0 + e * 2.5, 8.6, z0), Vector3(2.0, 0.8, 9.4), &"brim", 0.0, false)
			kit.link(Vector3(x0, 0.0, z0), Vector3(x0 + s * 2.5, 9.0, z0), GameMap.LINK_WALLJUMP)
			if z0 == -30.0 or z0 == 18.0: _chain_bridge(kit, Vector3(x0 + s * 3.5, 9.0, z0), Vector3(s * 38.5, 9.0, z0))
		for z: float in range(-40, 31, 5): kit.box(Vector3(s * 11.0, 0.5, float(z)), Vector3(14.0, 1.0, 0.8), &"stone", 0.0, false) # pews
		_pad(xf, Vector3(s * 44.0, 9.0, 46.0), Vector3(s * 30.0, 18.0, 66.0), 3.0)
	for k: int in 3: # altar steps
		var hw := 24.0 - k * 6.0
		var z0 := 50.0 + k * 4.0
		kit.box(Vector3(0.0, k + 0.5, (z0 + HL) * 0.5), Vector3(hw * 2.0, 1.0, HL - z0), &"stone", 0.0, false)
	kit.box(Vector3(0.0, 3.75, 64.0), Vector3(6.0, 1.5, 3.0), &"gold", 0.0, false)
	kit.box(Vector3(0.0, 17.5, 66.0), Vector3(HW * 2.0, 1.0, 8.0), &"brim", 0.0, false) # choir loft
	for s: float in [-1.0, 1.0]: _brazier(kit, Vector3(s * 15.0, 2.0, 60.0), xf * Vector3(s * 15.0, 2.0, 60.0))
	for p: Vector3 in [Vector3(-30, 0, -20), Vector3(30, 0, 10), Vector3(0, 0, 40), Vector3(44, 9, 0)]: _checkpoints.append(xf * p)


## W: a lava pit of platforms hung on chains, bridges and vents climbing to a cage at 16 m,
## walkways round the edge.
func _hall_of_chains(kit: MapKit, xf: Transform3D, _i: int) -> void:
	for s: float in [-1.0, 1.0]: _floor(kit, 42.0 if s > 0.0 else -HW, HW if s > 0.0 else -42.0, -HL + NARTHEX, HL)
	_floor(kit, -42.0, 42.0, 60.0, HL)
	# platforms: x, z, half, top (the last one is the cage)
	var plats: Array[Vector4] = [
		Vector4(-30, -38, 5, 2), Vector4(-12, -30, 4, 4), Vector4(8, -38, 5, 2), Vector4(28, -28, 4, 5),
		Vector4(12, -14, 5, 7), Vector4(-10, -10, 4, 8), Vector4(-30, -4, 5, 5), Vector4(28, 2, 4, 9),
		Vector4(6, 8, 5, 11), Vector4(-16, 14, 5, 12), Vector4(-30, 30, 4, 9), Vector4(20, 24, 5, 13),
		Vector4(-14, 48, 4, 10), Vector4(24, 48, 5, 8), Vector4(0, 36, 7, 16),
	]
	for p: Vector4 in plats:
		kit.box(Vector3(p.x, p.w - 0.5, p.y), Vector3(p.z * 2.0, 1.0, p.z * 2.0), &"brim", 0.0, false)
		for c: Vector2 in [Vector2(-1, -1), Vector2(1, 1)]: # two chains up to the top of the walls
			kit.visual(Vector3(p.x + c.x * (p.z - 0.6), (p.w + WALL_H) * 0.5, p.y + c.y * (p.z - 0.6)), Vector3(0.18, WALL_H - p.w, 0.18), &"iron")
	var cage: Vector4 = plats[14]
	for k: int in 12: # the cage's bars (look)
		var a := TAU * k / 12.0
		if k % 3 == 0: continue # gaps to get in by
		kit.visual(Vector3(cage.x + cos(a) * (cage.z - 0.3), cage.w + 2.0, cage.y + sin(a) * (cage.z - 0.3)), Vector3(0.15, 4.0, 0.15), &"iron")
	var edge := func(from: Vector4, to: Vector4) -> Vector3:
		var d := Vector3(to.x - from.x, 0.0, to.y - from.y).normalized()
		return Vector3(from.x, from.w, from.y) + d * MapKit.square_edge(d, 0.0, from.z)
	var bridge := func(a: int, b: int) -> void:
		_chain_bridge(kit, edge.call(plats[a], plats[b]), edge.call(plats[b], plats[a]))
	_chain_bridge(kit, Vector3(-42.5, 0.0, -38.0), Vector3(-34.5, 2.0, -38.0))
	_chain_bridge(kit, Vector3(42.5, 0.0, -28.0), Vector3(31.5, 5.0, -28.0))
	_chain_bridge(kit, Vector3(-42.5, 0.0, -4.0), Vector3(-34.5, 5.0, -4.0))
	_chain_bridge(kit, Vector3(42.5, 0.0, 48.0), Vector3(29.5, 8.0, 48.0))
	_chain_bridge(kit, Vector3(8.0, 0.0, -50.5), Vector3(8.0, 2.0, -42.5))
	for pair: Vector2i in [Vector2i(0, 1), Vector2i(1, 5), Vector2i(5, 6), Vector2i(2, 4), Vector2i(3, 4), Vector2i(4, 8),
			Vector2i(5, 9), Vector2i(9, 10), Vector2i(8, 11), Vector2i(7, 8), Vector2i(11, 14), Vector2i(13, 11)]:
		bridge.call(pair.x, pair.y)
	_pad(xf, Vector3(44.0, 0.0, 2.0), Vector3(28.0, 9.0, 2.0), 3.0)
	_pad(xf, Vector3(-30.0, 9.0, 31.5), Vector3(-46.0, 0.0, 31.5), 2.0)
	_pad(xf, Vector3(-46.0, 0.0, 48.0), Vector3(-14.0, 10.0, 48.0), 4.0)
	_pad(xf, Vector3(-14.0, 10.0, 45.5), Vector3(-2.0, 16.0, 34.0), 3.0)
	_pad(xf, Vector3(3.0, 16.0, 40.0), Vector3(0.0, 0.0, 65.0), 3.0)
	_brazier(kit, Vector3(4.0, 16.0, 31.0), xf * Vector3(4.0, 16.0, 31.0))
	for p: Vector3 in [Vector3(-46, 0, -20), Vector3(46, 0, 30), Vector3(0, 0, 65), Vector3(-30, 5, -4)]: _checkpoints.append(xf * p)


## A pad from `at` to `to` if its flight is clear of everything solid; tries a higher lob once.
func _try_pad(parent: Node3D, at: Vector3, to: Vector3, peak: float) -> void:
	for p: float in [peak, peak + 4.0]:
		if g.arc_clear(at, to, p, []):
			g.pad(parent, at, to, p, false)
			return
	print("  pad %s -> %s: no clear arc, skipped" % [at.snapped(Vector3.ONE * 0.1), to.snapped(Vector3.ONE * 0.1)])


## Is anything solid at this point of a pad arc (a body-sized sphere)?
func _arc_hits_something(pos: Vector2, y: float) -> bool:
	_probe.transform = Transform3D(Basis.IDENTITY, Vector3(pos.x, y + 0.9, pos.y))
	var hits := _space.intersect_shape(_probe, 1)
	if _debug_arc and not hits.is_empty(): print("    blocked at %s by %s" % [Vector3(pos.x, y, pos.y).snapped(Vector3.ONE * 0.1), (hits[0].collider as Node).get_parent().name])
	return not hits.is_empty()

#endregion


#region connections

## Causeways from each hall's inner door to the pit rim; a speed strip on two of them.
func _build_spokes() -> void:
	var kit := MapKit.new()
	for i: int in HALLS.size():
		var u := HALLS[i]
		var a := u * (PIT_RIM_OUT - 1.0)
		var b := u * (HALL_R - HL + 1.0)
		_causeway(kit, a, b, DOOR_W)
		_checkpoints.append((a + b) * 0.5)
		if i % 2 == 1: kit.strips.append({"at": u * (HALL_R - HL - 6.0), "yaw": atan2(-u.x, -u.z), "speed": 34.0})
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
				var a := _hall_xf(i) * Vector3(si * (HW + WT - 1.0), 0.0, 0.0)
				var b := _hall_xf(j) * Vector3(sj * (HW + WT - 1.0), 0.0, 0.0)
				if a.distance_to(b) < best_d:
					best_d = a.distance_to(b)
					best = [a, b]
		var a: Vector3 = best[0]
		var b: Vector3 = best[1]
		var m := (a + b) * 0.5
		var dir := (b - a).normalized()
		kit.box(m + Vector3.UP * -FLOOR_T * 0.5, Vector3(16.0, FLOOR_T, 16.0), &"basalt", atan2(dir.x, dir.z), false)
		_causeway(kit, a, m - dir * 7.5, 10.0)
		_causeway(kit, m + dir * 7.5, b, 10.0)
		_brazier(kit, m + dir.cross(Vector3.UP) * 5.5, m + dir.cross(Vector3.UP) * 5.5)
		_checkpoints.append(m)
		kit.strips.append({"at": a + dir * 6.0, "yaw": atan2(dir.x, dir.z), "speed": 34.0})
	g.emit_world_kit(kit, "Ring")


## A straight walkway from a to b (tops at y 0) with low iron parapets you can vault.
func _causeway(kit: MapKit, a: Vector3, b: Vector3, width: float) -> void:
	kit.slab(a, b, width, FLOOR_T, &"basalt", 0.5)
	var side := (b - a).normalized().cross(Vector3.UP) * (width * 0.5 - 0.3)
	for s: float in [-1.0, 1.0]:
		kit.slab(a + side * s + Vector3.UP * 1.1, b + side * s + Vector3.UP * 1.1, 0.6, 1.1, &"iron", 0.0)

#endregion


## Eight spawn markers in each hall's narthex, tagged with the hall: each round starts in one.
func _add_spawns() -> void:
	var spawns := g.node(g.root, "Spawns")
	for i: int in HALLS.size():
		var xf := _hall_xf(i)
		for k: int in 8:
			var a := TAU * k / 8.0
			var m := Marker3D.new()
			m.name = "Spawn%d_%d" % [i, k]
			m.position = xf * Vector3(cos(a) * 6.0, 0.5, -HL + NARTHEX * 0.5 + sin(a) * 6.0)
			m.set_meta(&"room", i)
			spawns.add_child(m)
			m.add_to_group(&"spawn", true)


func _add_checkpoints() -> void:
	var holder := g.node(g.root, "Checkpoints")
	var n := 0
	for p: Vector3 in _checkpoints:
		if p == Vector3.INF: continue
		var m := Marker3D.new()
		m.name = "Checkpoint%d" % n
		n += 1
		m.position = p + Vector3.UP * 0.5
		holder.add_child(m)
		m.add_to_group(&"checkpoint", true)
