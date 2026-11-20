class_name BakedGI
extends VoxelGI
## A map's baked bounce light (MapGen.add_baked_gi, baked by tools/mapgen/bake_gi.gd), shown on
## Lighting High (Settings sets `enabled`). Godot runs the GI pass over the whole screen once any
## VoxelGI is in view, however little of it shows: the Jungle temple's cost +7 ms seen from the
## plaza and +8.8 ms as a speck through the leaves 180 m off (2026-11-20, static lights changed
## nothing). So a box that doesn't cover the whole map (`near_only`) only switches on while the
## camera is in it or within `margin` of it, where its light shows.

## Lighting High (Settings).
@export var enabled := false:
	set(v):
		enabled = v
		_update()
## Only on while the camera is in the box or within `margin` (m) of it.
@export var near_only := false
@export var margin: float = 12.0


func _process(_delta: float) -> void:
	if near_only: _update()


func _update() -> void:
	if not is_inside_tree(): return
	var on := enabled
	if on and near_only:
		var cam := get_viewport().get_camera_3d()
		var box := AABB(-size * 0.5, size).grow(margin)
		on = cam != null and box.has_point(global_transform.affine_inverse() * cam.global_position)
	if visible != on: visible = on
