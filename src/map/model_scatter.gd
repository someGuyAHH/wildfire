@tool
extends MultiMeshInstance3D

## One model drawn many times (a map's trees): the map generator stores the transforms here and
## the MultiMesh is built when the node enters the tree, in the game and the editor alike.
## (Not saved as a MultiMesh resource: maps are generated headless, and headless Godot's dummy
## renderer keeps no MultiMesh data, so every instance saved as an empty transform at the origin.)

@export var model: Mesh
## 12 floats per instance: the basis columns x, y, z, then the origin.
@export var transforms := PackedFloat32Array()


func _ready() -> void:
	if not model or transforms.is_empty(): return
	if DisplayServer.get_name() == "headless": return # nothing draws there (and nothing would keep it)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = model
	var count := transforms.size() / 12
	mm.instance_count = count
	for i: int in count:
		var o := i * 12
		var b := Basis(Vector3(transforms[o], transforms[o + 1], transforms[o + 2]),
				Vector3(transforms[o + 3], transforms[o + 4], transforms[o + 5]),
				Vector3(transforms[o + 6], transforms[o + 7], transforms[o + 8]))
		mm.set_instance_transform(i, Transform3D(b, Vector3(transforms[o + 9], transforms[o + 10], transforms[o + 11])))
	multimesh = mm


## How many copies (works headless too, unlike reading the MultiMesh).
func get_count() -> int:
	return transforms.size() / 12


## Instance i's transform (local to this node).
func get_transform_of(i: int) -> Transform3D:
	var o := i * 12
	return Transform3D(Basis(Vector3(transforms[o], transforms[o + 1], transforms[o + 2]),
			Vector3(transforms[o + 3], transforms[o + 4], transforms[o + 5]),
			Vector3(transforms[o + 6], transforms[o + 7], transforms[o + 8])),
			Vector3(transforms[o + 9], transforms[o + 10], transforms[o + 11]))
