"""
Base for playable maps. Owns the navigation mesh bots path on: maps build their geometry,
then call bake_navigation(); Main waits for is_nav_ready() / navigation_ready before bots think.
Static colliders on layer 1 under nav_source_root are what gets baked.
"""

@tool
class_name GameMap
extends Node3D

signal navigation_ready

# keep in sync: the navigation map's cell size has to match the navmesh's or nothing connects
const NAV_CELL        := 0.4
const NAV_CELL_HEIGHT := 0.25
const _NAV_GROUP      := &"nav_source"
# bots climb what players auto-step (the navmesh needs it rounded down to its cell height)
const _MOVEMENT := preload("res://assets/tres/movement/default_movement.tres")

# dry edge look
const _EDGE_LIFT        := 0.03
const _EDGE_OUTER_MULT  := 1.2
const _EDGE_LINE_WIDTH  := 0.6
const _EDGE_SEGMENTS    := 96
const _EDGE_BAND_COLOR  := Color(0.85, 0.5, 0.15, 0.22)
const _EDGE_LINE_COLOR  := Color(1.0, 0.5, 0.1, 0.85)

## Middle of the playable area; bots treat leaving its radius as running off the map.
@export var arena_center := Vector3.ZERO
@export var arena_radius: float = 190.0

var _nav_region: NavigationRegion3D
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
	var map_rid := get_world_3d().navigation_map
	NavigationServer3D.map_set_cell_size(map_rid, NAV_CELL)
	NavigationServer3D.map_set_cell_height(map_rid, NAV_CELL_HEIGHT)
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
	if _nav_region: _nav_region.queue_free()
	_nav_region = NavigationRegion3D.new()
	_nav_region.name = "Navigation"
	_nav_region.navigation_mesh = nm
	add_child(_nav_region)
	_nav_region.bake_finished.connect(on_bake_finished, CONNECT_ONE_SHOT)
	_nav_region.bake_navigation_mesh(true)


## Paints the dry edge on the ground: a translucent band from inner_radius outward, with a bright
## line at the inner border so you can see where heating starts. Flat maps only for now (ground_y).
func mark_dry_edge(inner_radius: float, ground_y: float = 0.0) -> void:
	var old := get_node_or_null(^"DryEdge")
	if old: old.free()
	var root := Node3D.new()
	root.name = "DryEdge"
	root.position = Vector3(arena_center.x, ground_y + _EDGE_LIFT, arena_center.z)
	add_child(root)
	root.add_child(_annulus(inner_radius, arena_radius * _EDGE_OUTER_MULT, _EDGE_BAND_COLOR))
	root.add_child(_annulus(inner_radius, inner_radius + _EDGE_LINE_WIDTH, _EDGE_LINE_COLOR))


func on_bake_finished() -> void:
	_nav_ready = true
	navigation_ready.emit()


func _annulus(r0: float, r1: float, color: Color) -> MeshInstance3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i: int in _EDGE_SEGMENTS:
		var a0 := TAU * i / _EDGE_SEGMENTS
		var a1 := TAU * (i + 1) / _EDGE_SEGMENTS
		var d0 := Vector3(cos(a0), 0.0, sin(a0))
		var d1 := Vector3(cos(a1), 0.0, sin(a1))
		for v: Vector3 in [d0 * r0, d0 * r1, d1 * r1, d0 * r0, d1 * r1, d1 * r0]:
			st.set_normal(Vector3.UP)
			st.add_vertex(v)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.albedo_color = color
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi
