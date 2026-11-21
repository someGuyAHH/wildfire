"""
Base for playable maps. Owns the navigation mesh bots path on: maps build their geometry,
then call bake_navigation(); Main waits for is_nav_ready() / navigation_ready before bots think.
Static colliders on layer 1 under nav_source_root are what gets baked.
"""

@tool
class_name GameMap
extends Node3D

signal navigation_ready

# nav link kinds: how a bot has to move to get from a link's start to its end
const LINK_PAD      := 1   # step on the pad, steer toward the end while flying
const LINK_VAULT    := 2   # run at the ledge with jump held (the vault pops you up)
const LINK_DROP     := 3   # walk off the edge
const LINK_WALLJUMP := 4   # jump, wall-jump between walls, vault onto the top
const LINK_JUMP     := 5   # running jump across a gap, taking off at the link start
const LINK_KIND     := &"link_kind"
## Group for floating signs/labels on a map (the title screen hides them).
const MAP_LABELS    := &"map_labels"

# keep in sync: the navigation map's cell size has to match the navmesh's or nothing connects
const NAV_CELL        := 0.4
const NAV_CELL_HEIGHT := 0.25
const _NAV_GROUP      := &"nav_source"
# bots climb what players auto-step (the navmesh needs it rounded down to its cell height)
const _MOVEMENT := preload("res://assets/tres/movement/default_movement.tres")

# dry edge look
const _EDGE_LIFT        := 0.03
const _EDGE_DRAPE_LIFT  := 0.2 # over the ground at each vertex: the flat cells cut into bumps less
const _EDGE_OUTER_MULT  := 1.2
const _EDGE_LINE_WIDTH  := 0.6
const _EDGE_SEGMENTS    := 96
const _EDGE_CELL        := 3.0
const _EDGE_BAND_COLOR  := Color(0.85, 0.5, 0.15, 0.22)
const _EDGE_LINE_COLOR  := Color(1.0, 0.5, 0.1, 0.85)
# storm wall (hot potato)
const _STORM_SCENE := preload("res://scn/vfx/storm_wall.tscn")
const _EDGE_MAT    := preload("res://assets/tres/materials/dry_edge.tres")

## Middle of the playable area; bots treat leaving its radius as running off the map.
@export var arena_center := Vector3.ZERO
@export var arena_radius: float = 190.0
## Where the dry edge starts (m from arena_center). 0 = arena_radius * the rules' edge_start.
## Generated maps set it just past their outermost content, so the edge is the empty outer band.
@export var dry_edge_radius: float = 0.0
## Below this height is lava (Inferno): you're put back at the nearest "checkpoint" marker (or
## spawn), slowed for a moment. Not a death. Default: no lava.
@export var lava_height: float = -INF
@export var lava_slow_time: float = 2.0
@export var lava_slow_mult: float = 0.5
## Nothing legitimate to stand on above this height (the Inferno: its wall tops, which an
## invisible lid keeps almost everyone off): a character resting on a floor up there for
## stand_limit_time is put back like a lava fall (the stonework is white-hot). Default: no limit.
@export var stand_limit: float = INF
@export var stand_limit_time: float = 1.5
## Stretches the Hot Potato storm wall upward (1 = 60 m) for maps with tall hills.
@export var storm_height_scale: float = 1.0
## World height (above arena_center) where the storm wall starts: below the lowest floor anyone
## can stand on, or the floor shows under it (the Inferno's crypt is at -6: it starts in the lava).
@export var storm_bottom: float = -2.0
## Where the Hot Potato storm closes in on (it starts round arena_center at arena_radius and
## drifts here as it shrinks). INF = arena_center.
@export var storm_center := Vector3.INF
## How small the storm ends up on this map (metres); 0 = the mode's storm_end_radius. Maps set
## it so the last circle sits on something worth fighting over, not through a wall.
@export var storm_end_radius: float = 0.0
## The minimap's picture (baked by the map generator, MapGen.bake_minimap): the map from above,
## centred on the world origin, minimap_half_extent m each way.
## This map's own defaults for some settings ({&"leaf_shadows": 1.0, ...}): Settings.set_map. The
## player's own choice for a setting here still wins, and is kept for this map only.
@export var graphics_defaults: Dictionary = {}
@export var minimap: Texture2D
@export var minimap_half_extent: float = 0.0

var _nav_region: NavigationRegion3D
var _server_links: Array[RID] = []
var _parked_envs: Array[Dictionary] = [] # {node, parent}: WorldEnvironments taken out while parked
var _link_kind_tags: Dictionary[int, RefCounted] = {} # owner objects bots read LINK_KIND from
var _storm: Node3D
var _nav_ready := false


func is_nav_ready() -> bool:
	return _nav_ready


## Bakes a navmesh from every static collider under source_root, on a thread.
## Emits navigation_ready when done. Does nothing in the editor (it'd hitch the editor on every rebuild).
func bake_navigation(source_root: Node3D) -> void:
	if Engine.is_editor_hint(): return
	if not source_root:
		push_error("bake_navigation() needs the node holding the level geometry")
		return
	_nav_ready = false
	source_root.add_to_group(_NAV_GROUP)
	_setup_nav_map()
	var nm := make_navmesh()
	if _nav_region: _nav_region.queue_free()
	_nav_region = NavigationRegion3D.new()
	_nav_region.name = "Navigation"
	_nav_region.navigation_mesh = nm
	add_child(_nav_region)
	_nav_region.bake_finished.connect(on_bake_finished, CONNECT_ONE_SHOT)
	_nav_region.bake_navigation_mesh(true)


## Navmesh settings every map bakes with (live here, or offline by a map generator).
## Collects static colliders under nodes in the nav_source group.
static func make_navmesh() -> NavigationMesh:
	var nm := NavigationMesh.new()
	nm.cell_size = NAV_CELL
	nm.cell_height = NAV_CELL_HEIGHT
	nm.agent_height = 2.0 # multiple of cell_height (body is 1.8)
	nm.agent_radius = 0.4 # multiple of cell_size, same as the capsule
	nm.agent_max_climb = floorf(_MOVEMENT.step_height / NAV_CELL_HEIGHT) * NAV_CELL_HEIGHT
	nm.agent_max_slope = 55.0 # under floor_max_angle (62) so bots stay off the very steepest stuff
	nm.region_min_size = 4.0
	nm.edge_max_length = 12.0
	nm.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	nm.geometry_collision_mask = 1
	nm.geometry_source_geometry_mode = NavigationMesh.SOURCE_GEOMETRY_GROUPS_WITH_CHILDREN
	nm.geometry_source_group_name = _NAV_GROUP
	return nm


## For maps that ship pre-baked NavigationRegion3D chunks: matches the navigation map to the
## bake settings and reports ready once the server has synced them in.
func use_baked_navigation() -> void:
	if Engine.is_editor_hint(): return
	_nav_ready = false
	_setup_nav_map()
	var map_rid := get_world_3d().navigation_map
	var probe := arena_center + Vector3.UP * 5.0
	for i: int in 1200: # a big map's first syncs take a while (they run async): wait until it answers
		if not is_inside_tree(): return
		await get_tree().physics_frame
		if NavigationServer3D.map_get_iteration_id(map_rid) > 0 \
				and NavigationServer3D.map_get_closest_point_owner(map_rid, probe).is_valid(): break
	_nav_ready = true
	navigation_ready.emit()


## Nearest point on the navmesh to p. Big maps override this to search only nearby chunks.
func nav_snap(p: Vector3) -> Vector3:
	return NavigationServer3D.map_get_closest_point(get_world_3d().navigation_map, p)


## Parks a loaded map out of play, or brings it back: hidden, not processing, no collision
## (layers zeroed, pads disarmed), navigation off, its WorldEnvironment out of the world. Keeping
## visited maps parked in the tree makes switching back instant: re-adding a Terrain3D map
## costs ~0.8 s because it rebuilds its collision every time it enters the tree.
func set_active(on: bool) -> void:
	visible = on
	process_mode = Node.PROCESS_MODE_INHERIT if on else Node.PROCESS_MODE_DISABLED
	if on:
		for e: Dictionary in _parked_envs: (e.parent as Node).add_child(e.node)
		_parked_envs.clear()
	_park(self, on)
	var map_rid := get_world_3d().navigation_map if on else RID()
	for rid: RID in _server_links:
		NavigationServer3D.link_set_enabled(rid, on)
		NavigationServer3D.link_set_map(rid, map_rid)


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE: # parked WorldEnvironments are out of the tree: free them with the map
		for e: Dictionary in _parked_envs: (e.node as Node).free()


func _park(n: Node, on: bool) -> void:
	if n is CollisionObject3D:
		var co := n as CollisionObject3D
		if not on and not co.has_meta(&"park_layers"):
			co.set_meta(&"park_layers", Vector2i(co.collision_layer, co.collision_mask))
			co.collision_layer = 0
			co.collision_mask = 0
		elif on and co.has_meta(&"park_layers"):
			var l: Vector2i = co.get_meta(&"park_layers")
			co.collision_layer = l.x
			co.collision_mask = l.y
			co.remove_meta(&"park_layers")
		if co is Area3D: co.set_deferred(&"monitoring", on)
	# off the navigation map entirely, not just disabled: a disabled region still catches other
	# maps' links (they attach to the closest floor, even a parked map's) and still costs its rebuild
	elif n is NavigationRegion3D:
		(n as NavigationRegion3D).enabled = on
		(n as NavigationRegion3D).set_navigation_map(get_world_3d().navigation_map if on else RID())
	elif n is NavigationLink3D:
		(n as NavigationLink3D).enabled = on
		(n as NavigationLink3D).set_navigation_map(get_world_3d().navigation_map if on else RID())
	elif n is WorldEnvironment and not on:
		_parked_envs.append({"node": n, "parent": n.get_parent()})
		n.get_parent().remove_child(n)
		return
	elif n.get_class() == &"Terrain3D":
		if not on and not n.has_meta(&"park_layer"):
			n.set_meta(&"park_layer", n.get(&"collision_layer"))
			n.set(&"collision_layer", 0)
		elif on and n.has_meta(&"park_layer"):
			n.set(&"collision_layer", n.get_meta(&"park_layer"))
			n.remove_meta(&"park_layer")
		return # its children are its own helpers
	for c: Node in n.get_children(): _park(c, on)


## The dry edge's inner radius (see dry_edge_radius).
func get_dry_edge(edge_start: float) -> float:
	return dry_edge_radius if dry_edge_radius > 0.0 else arena_radius * edge_start


## Spawn markers grouped by their "room" meta (maps with several start rooms: each round starts
## in one of them). One group when no marker says.
func spawn_rooms(group: StringName = &"spawn") -> Array[PackedVector3Array]:
	var rooms := {} # room -> Array (not a packed array in the dictionary: those copy on read)
	for n: Node in get_tree().get_nodes_in_group(group):
		if not (n is Node3D and is_ancestor_of(n)): continue
		var r: int = n.get_meta(&"room", 0)
		if not rooms.has(r): rooms[r] = []
		(rooms[r] as Array).append((n as Node3D).global_position)
	var out: Array[PackedVector3Array] = []
	for r: int in rooms: out.append(PackedVector3Array(rooms[r]))
	return out


## Where someone who fell in the lava at `from` comes back: the nearest checkpoint (or spawn).
func nearest_checkpoint(from: Vector3) -> Vector3:
	var best := arena_center
	var best_d := INF
	for group: StringName in [&"checkpoint", &"spawn"]:
		for n: Node in get_tree().get_nodes_in_group(group):
			if not (n is Node3D and is_ancestor_of(n)): continue
			var d := (n as Node3D).global_position.distance_squared_to(from)
			if d < best_d:
				best_d = d
				best = (n as Node3D).global_position
		if best_d < INF: break # checkpoints first; spawns only when the map has none
	return best


## Nobody gets further than this from arena_center: the dry edge band's outer rim.
func get_bound_radius() -> float:
	return arena_radius * _EDGE_OUTER_MULT


## Ground height under (x, z), for draping things over the map. Flat maps: arena_center.y.
func ground_height(_x: float, _z: float) -> float:
	return arena_center.y


func _setup_nav_map() -> void:
	var map_rid := get_world_3d().navigation_map
	NavigationServer3D.map_set_cell_size(map_rid, NAV_CELL)
	NavigationServer3D.map_set_cell_height(map_rid, NAV_CELL_HEIGHT)


## Paints the dry edge on the ground: a translucent band from inner_radius outward, with a bright
## line at the inner border so you can see where heating starts. Follows ground_height().
func mark_dry_edge(inner_radius: float) -> void:
	var old := get_node_or_null(^"DryEdge")
	if old and is_equal_approx(old.get_meta(&"inner", -1.0), inner_radius): return # already right
	if old: old.free()
	var root := Node3D.new()
	root.name = "DryEdge"
	root.position = Vector3(arena_center.x, _EDGE_LIFT, arena_center.z)
	root.set_meta(&"inner", inner_radius)
	add_child(root)
	root.add_child(_annulus(inner_radius, arena_radius * _EDGE_OUTER_MULT, _EDGE_BAND_COLOR))
	root.add_child(_annulus(inner_radius, inner_radius + _EDGE_LINE_WIDTH, _EDGE_LINE_COLOR))


## Adds a shortcut bots can path through (jump pads, vaults, drops, wall-jump climbs).
## kind = LINK_*. cost scales how much the pathfinder likes it (lower = more appealing).
func add_nav_link(from: Vector3, to: Vector3, kind: int, bidirectional: bool = false,
				cost: float = 1.0) -> NavigationLink3D:
	var link := NavigationLink3D.new()
	link.start_position = from
	link.end_position = to
	link.bidirectional = bidirectional
	link.travel_cost = cost
	link.set_meta(LINK_KIND, kind)
	add_child(link)
	return link


## Registers a NavLinkSet's links directly with the navigation server (no nodes). Bots read each
## link's kind from its owner object, same as with NavigationLink3D nodes.
func add_link_set(links: NavLinkSet) -> void:
	if Engine.is_editor_hint() or not links: return
	var map_rid := get_world_3d().navigation_map
	for i: int in links.size():
		var kind := int(links.kinds[i])
		if not _link_kind_tags.has(kind):
			var tag := RefCounted.new()
			tag.set_meta(LINK_KIND, kind)
			_link_kind_tags[kind] = tag
		var rid := NavigationServer3D.link_create()
		NavigationServer3D.link_set_map(rid, map_rid)
		NavigationServer3D.link_set_start_position(rid, links.starts[i])
		NavigationServer3D.link_set_end_position(rid, links.ends[i])
		NavigationServer3D.link_set_bidirectional(rid, links.two_way[i] == 1)
		NavigationServer3D.link_set_travel_cost(rid, links.costs[i])
		NavigationServer3D.link_set_owner_id(rid, _link_kind_tags[kind].get_instance_id())
		_server_links.append(rid)


func _exit_tree() -> void:
	for rid: RID in _server_links: NavigationServer3D.free_rid(rid)
	_server_links.clear()


## Shows the Hot Potato storm as a ring of fire `radius` metres around arena_center (hidden when
## on is false). Cheap to call every tick: it only rescales one mesh.
func set_storm(radius: float, on: bool, center: Vector3 = Vector3.INF) -> void:
	if not on:
		if _storm: _storm.visible = false
		return
	if not _storm: _build_storm()
	_storm.visible = true
	var r := maxf(radius, 0.5)
	_storm.scale = Vector3(r, storm_height_scale, r)
	_place_storm(center)


func on_bake_finished() -> void:
	_nav_ready = true
	navigation_ready.emit()


# a flat ring from r0 to r1, cut into ~6 m cells so it can follow the ground
func _annulus(r0: float, r1: float, color: Color) -> MeshInstance3D:
	var segs := maxi(_EDGE_SEGMENTS, ceili(TAU * r1 / _EDGE_CELL))
	var rings := maxi(1, ceili((r1 - r0) / _EDGE_CELL))
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var at := func(a: float, r: float) -> Vector3:
		var d := Vector3(cos(a), 0.0, sin(a)) * r
		d.y = ground_height(arena_center.x + d.x, arena_center.z + d.z) + _EDGE_DRAPE_LIFT
		return d
	for i: int in segs:
		var a0 := TAU * i / segs
		var a1 := TAU * (i + 1) / segs
		for j: int in rings:
			var ra := lerpf(r0, r1, float(j) / rings)
			var rb := lerpf(r0, r1, float(j + 1) / rings)
			var p00: Vector3 = at.call(a0, ra)
			var p01: Vector3 = at.call(a0, rb)
			var p11: Vector3 = at.call(a1, rb)
			var p10: Vector3 = at.call(a1, ra)
			for v: Vector3 in [p00, p01, p11, p00, p11, p10]:
				st.set_normal(Vector3.UP)
				st.add_vertex(v)
	var mat := _EDGE_MAT.duplicate() as StandardMaterial3D
	mat.albedo_color = color
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


func _build_storm() -> void:
	_storm = _STORM_SCENE.instantiate() as Node3D
	_storm.scale.y = storm_height_scale
	_place_storm(Vector3.INF)
	add_child(_storm)


# the wall's mesh runs from -2 to 58 m in the scene (times storm_height_scale): put that bottom at storm_bottom
func _place_storm(center: Vector3) -> void:
	var c := arena_center if center == Vector3.INF else Vector3(center.x, arena_center.y, center.z)
	_storm.position = c + Vector3.UP * (storm_bottom + 2.0 * storm_height_scale)
