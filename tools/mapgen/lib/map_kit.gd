extends RefCounted
# preload as MapKit: tools/ is .gdignore'd (kept out of the game), so no class_name here

## One obstacle cluster's worth of geometry, in its local space (y = 0 at the ground under its
## centre). MapGen.emit_kit() places it: grounded boxes get stretched down to the terrain, pads
## get aimed, everything is merged into one body + one mesh.

var boxes: Array[Dictionary] = []  # {xf: Transform3D, size: Vector3, mat: StringName, grounded: bool}
var pads: Array[Dictionary] = []   # {at: Vector3, to: Vector3, world_target: bool, peak: float}
var strips: Array[Dictionary] = [] # {at: Vector3, yaw: float, speed: float}
var links: Array[Dictionary] = []  # {from: Vector3, to: Vector3, kind: int, cost: float}: routes the auto links miss
## Footprint radius: other clusters, pads and launch arcs keep clear of it.
var radius := 20.0
## A high spot long-range pads can start from (towers).
var top := Vector3.ZERO
var has_top := false


## A box. The long axis is local Z: yaw turns it, tilt raises its +Z end (radians, + = up).
func box(pos: Vector3, size: Vector3, mat: StringName, yaw: float = 0.0, grounded: bool = true, tilt: float = 0.0) -> void:
	var b := Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, -tilt)
	boxes.append({"xf": Transform3D(b, pos), "size": size, "mat": mat, "grounded": grounded})


## A box you see but can't touch (canopy leaves, water): no collision, not on the navmesh.
func visual(pos: Vector3, size: Vector3, mat: StringName, yaw: float = 0.0) -> void:
	box(pos, size, mat, yaw, false)
	boxes[boxes.size() - 1]["solid"] = false


## A box you can't see but can't pass either (keeps you off wall tops): collision only.
func blocker(pos: Vector3, size: Vector3, yaw: float = 0.0) -> void:
	box(pos, size, &"", yaw, false)
	boxes[boxes.size() - 1]["seen"] = false


## A walkable slab whose top surface runs from `from` to `to` (ramps, bridges), poking
## `overlap` m past both ends so it tucks into whatever it joins.
func slab(from: Vector3, to: Vector3, width: float, thick: float, mat: StringName, overlap: float = 0.4) -> void:
	var flat := Vector2(to.x - from.x, to.z - from.z)
	var run := flat.length()
	var rise := to.y - from.y
	var tilt := atan2(rise, run)
	var yaw := atan2(flat.x, flat.y)
	# sink it along its own up (not straight down, which slides a thick slab's top face downhill)
	var up := Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, -tilt) * Vector3.UP
	# overlap only runs on past the low end (into the ground / under the lower deck): past the high
	# end a tilted slab keeps climbing, and its top edge pokes up through the floor it meets
	var flat_slab := absf(rise) < 0.05
	var ext_from := overlap if flat_slab or rise > 0.0 else 0.0
	var ext_to := overlap if flat_slab or rise < 0.0 else 0.0
	var dir := (to - from).normalized()
	var mid := (from + to) * 0.5 + dir * ((ext_to - ext_from) * 0.5) - up * (thick * 0.5)
	box(mid, Vector3(width, thick, (to - from).length() + ext_from + ext_to), mat, yaw, false, tilt)


## A box standing on the ground: (x, z) is the centre of its footprint, size.y its height.
func post(x: float, z: float, size: Vector3, mat: StringName, yaw: float = 0.0) -> void:
	box(Vector3(x, size.y * 0.5, z), size, mat, yaw, true)


## A pad from `at` (local, snapped to the ground) lobbing onto `to` (local, or world if world_target).
func pad(at: Vector3, to: Vector3, peak: float, world_target: bool = false) -> void:
	pads.append({"at": at, "to": to, "world_target": world_target, "peak": peak})


## A one-way nav link (GameMap.LINK_*) from `from` (local, snapped to the ground) to `to` (local),
## for a route bots can't work out themselves, like wall-jumping up a gap.
func link(from: Vector3, to: Vector3, kind: int, cost: float = 3.0) -> void:
	links.append({"from": from, "to": to, "kind": kind, "cost": cost})


## Distance from a square's centre to its edge along dir (yaw = the square's rotation).
static func square_edge(dir: Vector3, yaw: float, half: float) -> float:
	var local := Basis(Vector3.UP, -yaw) * dir
	return half / maxf(absf(local.x), absf(local.z))
