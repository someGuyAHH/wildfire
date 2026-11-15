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


func on_bake_finished() -> void:
	_nav_ready = true
	navigation_ready.emit()
