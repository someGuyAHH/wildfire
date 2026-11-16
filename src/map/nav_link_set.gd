class_name NavLinkSet
extends Resource

## A big batch of navigation links in plain arrays, for maps with thousands of them (a node per
## link bloats the scene). GameMap.add_link_set() registers them straight with the server.

@export var starts := PackedVector3Array()
@export var ends := PackedVector3Array()
## GameMap.LINK_* per link.
@export var kinds := PackedByteArray()
## 1 = two-way.
@export var two_way := PackedByteArray()
@export var costs := PackedFloat32Array()


func add(from: Vector3, to: Vector3, kind: int, bidirectional: bool, cost: float) -> void:
	starts.append(from)
	ends.append(to)
	kinds.append(kind)
	two_way.append(1 if bidirectional else 0)
	costs.append(cost)


func size() -> int:
	return starts.size()
