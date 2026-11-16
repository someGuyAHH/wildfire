extends RefCounted
# preload as MapKits (tools/ is .gdignore'd, so no class_name)

const MapKit := preload("res://tools/mapgen/lib/map_kit.gd")

## The standard obstacle kits every map can draw from. Each builds a MapKit in local space from
## the generator's RNG (so a map's seed fixes its layout) and movement config.
## Materials used: stone, rock, ruin, wood, ramp, hub (MapGen.make_materials needs them).

const NAMES: Array[StringName] = [&"ruins", &"pillars", &"stilts", &"kickers", &"tower", &"blocks", &"vaults", &"hub"]
## Kits with long flat runs: only on flat ground.
const FLAT: Array[StringName] = [&"kickers", &"blocks", &"vaults", &"hub"]
## Kits that cope with slopes.
const SLOPED: Array[StringName] = [&"ruins", &"pillars", &"stilts", &"tower"]


static func make(kit_name: StringName, rng: RandomNumberGenerator, cfg: MovementConfig) -> MapKit:
	match kit_name:
		&"ruins": return ruins(rng)
		&"pillars": return pillars(rng)
		&"stilts": return stilts(rng)
		&"kickers": return kickers(rng)
		&"tower": return tower_kit(rng)
		&"blocks": return blocks(rng)
		&"vaults": return vaults(rng, cfg)
		&"hub": return hub()
	push_error("MapKits: no kit called '%s'" % kit_name)
	return MapKit.new()


## Ring of broken walls (some low enough to vault), sometimes a wall-jump chimney with a ledge on top.
static func ruins(rng: RandomNumberGenerator) -> MapKit:
	var k := MapKit.new()
	k.radius = 20.0
	var n := rng.randi_range(7, 10)
	var heights: Array[float] = [1.2, 1.2, 2.6, 4.5, 6.5]
	for i: int in n:
		var a := TAU * i / n + rng.randf_range(-0.2, 0.2)
		var r := rng.randf_range(10.0, 17.0)
		var seg_len := rng.randf_range(5.0, 11.0)
		var h := heights[rng.randi() % heights.size()]
		k.post(cos(a) * r, sin(a) * r, Vector3(1.0, h, seg_len), &"stone", -a + rng.randf_range(-0.4, 0.4))
	if rng.randf() < 0.6:
		var gap := 3.6
		for s: float in [-1.0, 1.0]:
			k.post(s * (gap * 0.5 + 0.6), 0.0, Vector3(1.2, 9.5, 8.0), &"stone")
		k.box(Vector3(0.0, 10.0, 0.0), Vector3(gap + 2.4, 1.0, 8.0), &"stone", 0.0, false)
	return k


## Pillars spiralling up from 2 m to ~20 m: a hop chain, with a pad from the start to the top.
static func pillars(rng: RandomNumberGenerator) -> MapKit:
	var k := MapKit.new()
	k.radius = 22.0
	var n := rng.randi_range(9, 13)
	var a0 := rng.randf() * TAU
	var first := Vector3.ZERO
	var last := Vector3.ZERO
	for i: int in n:
		var a := a0 + i * 0.55
		var r := lerpf(6.0, 18.0, float(i) / (n - 1))
		var h := 2.0 + i * 1.5
		var p := Vector3(cos(a) * r, h, sin(a) * r)
		k.post(p.x, p.z, Vector3(2.6, h, 2.6), &"ruin")
		if i == 0: first = p
		last = p
	var flat_first := Vector3(first.x, 0.0, first.z)
	k.pad(flat_first - flat_first.normalized() * 4.0, last, 4.0)
	return k


## Platforms on stilts at different heights, bridged in a loop; ramp to the lowest, pad to the highest.
## Everything a bot walks on meets exactly at platform edges (bots only step up 0.75 m), and the
## ramp runs on into the ground so it meets the terrain whatever the slope there.
static func stilts(rng: RandomNumberGenerator) -> MapKit:
	const HALF := 4.5
	var k := MapKit.new()
	k.radius = 26.0
	var n := rng.randi_range(3, 4)
	var heights: Array[float] = [7.0, 10.5, 14.0, 17.5]
	var pick: Array[int] = [0, 2, 1, 3]
	var tops: Array[Vector3] = []
	var yaws: Array[float] = []
	var a0 := rng.randf() * TAU
	for i: int in n:
		var a := a0 + TAU * i / n
		var h := heights[pick[i] % n]
		var c := Vector3(cos(a) * 14.0, h, sin(a) * 14.0)
		var yaw := atan2(c.x, c.z) # square to its spoke, so the ramp meets an edge face-on
		tops.append(c)
		yaws.append(yaw)
		k.box(Vector3(c.x, h - 0.5, c.z), Vector3(HALF * 2.0, 1.0, HALF * 2.0), &"wood", yaw, false)
		for cx: float in [-3.8, 3.8]:
			for cz: float in [-3.8, 3.8]:
				var leg := Basis(Vector3.UP, yaw) * Vector3(cx, 0.0, cz)
				k.post(c.x + leg.x, c.z + leg.z, Vector3(0.8, h - 1.0, 0.8), &"wood")
	for i: int in n:
		var j := (i + 1) % n
		var dir := Vector3(tops[j].x - tops[i].x, 0.0, tops[j].z - tops[i].z).normalized()
		var from := tops[i] + dir * MapKit.square_edge(dir, yaws[i], HALF)
		var to := tops[j] - dir * MapKit.square_edge(-dir, yaws[j], HALF)
		k.slab(from, to, 2.4, 0.6, &"wood")
	# ramp from the lowest platform's outer edge down into the ground at 24°
	var low := 0
	var high := 0
	for i: int in n:
		if tops[i].y < tops[low].y: low = i
		if tops[i].y > tops[high].y: high = i
	var lt := tops[low]
	var out := Vector3(lt.x, 0.0, lt.z).normalized()
	var top := lt + out * MapKit.square_edge(out, yaws[low], HALF)
	var drop := lt.y + 2.0 # 2 m below the centre's ground level
	k.slab(top, top + out * (drop / tan(deg_to_rad(24.0))) - Vector3.UP * drop, 3.0, 0.8, &"wood")
	k.pad(Vector3.ZERO, tops[high], 4.0)
	return k


## Launch ramps of different angles, a steep quarter ramp onto a deck, a speed strip into the big one.
static func kickers(rng: RandomNumberGenerator) -> MapKit:
	var k := MapKit.new()
	k.radius = 24.0
	var n := rng.randi_range(3, 4)
	var angles: Array[float] = [16.0, 22.0, 28.0, 34.0]
	var biggest := Vector3.ZERO
	var biggest_yaw := 0.0
	var biggest_run := 0.0
	for i: int in n:
		var a := TAU * i / n + rng.randf_range(-0.3, 0.3)
		var ang := deg_to_rad(angles[i])
		var top := rng.randf_range(2.0, 4.0)
		var length := top / sin(ang)
		var run := top / tan(ang)
		var face := a + PI * 0.5 + rng.randf_range(-0.5, 0.5) # roughly tangential
		var fwd := Vector3(sin(face), 0.0, cos(face))
		var c := Vector3(cos(a) * 13.0, 0.0, sin(a) * 13.0)
		# ramp rises toward +fwd (+Z), with a support block under its lip
		k.box(c + Vector3(0.0, top * 0.5 - 0.35, 0.0), Vector3(6.0, 0.7, length), &"ramp", face, false, ang)
		k.post(c.x + fwd.x * (run * 0.5 - 0.5), c.z + fwd.z * (run * 0.5 - 0.5), Vector3(6.0, top - 0.6, 1.0), &"ramp", face)
		if run > biggest_run:
			biggest_run = run
			biggest = c
			biggest_yaw = face
	# quarter ramp: 45° up to a 5 m deck
	var qa := rng.randf() * TAU
	var qc := Vector3(cos(qa) * 4.0, 0.0, sin(qa) * 4.0)
	var qf := Vector3(sin(qa), 0.0, cos(qa))
	k.box(qc + Vector3(0.0, 2.5, 0.0), Vector3(6.0, 0.7, 5.0 * sqrt(2.0)), &"ramp", qa, false, PI * 0.25)
	k.post(qc.x + qf.x * 5.0, qc.z + qf.z * 5.0, Vector3(6.0, 5.0, 5.0), &"ramp", qa)
	# speed strip lined up with the biggest kicker, run-in from behind it
	var bf := Vector3(sin(biggest_yaw), 0.0, cos(biggest_yaw))
	k.strips.append({"at": biggest - bf * (biggest_run * 0.5 + 9.0), "yaw": biggest_yaw, "speed": 32.0})
	return k


## A climbing tower (ledges every 2 m) with a ground pad to its top. The pad stands far enough
## out that the lob is already coming down when it passes over the ledges.
static func tower_kit(rng: RandomNumberGenerator) -> MapKit:
	var k := MapKit.new()
	k.radius = 20.0
	var h := rng.randf_range(20.0, 30.0)
	tower(k, Vector3.ZERO, h)
	k.pad(Vector3(18.0, 0.0, 0.0), Vector3(1.6, h, 0.0), 6.0)
	return k


## Adds a climbing tower to a kit: core block with ledges spiralling up its sides every 2 m. Each
## ledge runs its whole side and wraps round the corner it heads toward, so the next ledge (2 m
## up, next side) starts right beside it: a short hop up at every corner, for players and bots.
static func tower(kit: MapKit, base: Vector3, height: float, mat: StringName = &"ruin") -> void:
	var half := 4.0
	var depth := 2.8
	kit.box(Vector3(base.x, base.y + height * 0.5 - 1.0, base.z), Vector3(half * 2.0, height + 2.0, half * 2.0), mat, 0.0, false)
	var n := int((height - 1.0) / 2.0)
	for i: int in n:
		var a := (i % 4) * PI * 0.5
		var out := Vector3(sin(a), 0.0, cos(a))
		var toward := Vector3(sin(a + PI * 0.5), 0.0, cos(a + PI * 0.5)) # the next side's outward
		var p := base + out * (half + depth * 0.5) + toward * (depth * 0.5) + Vector3.UP * (2.0 + i * 2.0 - 0.3)
		kit.box(p, Vector3(depth, 0.6, half * 2.0 + depth), mat, atan2(toward.x, toward.z), false)
	# long-range pads start from the -x half of the top; ground pads land on the +x half
	kit.top = base + Vector3(-2.2, height, 0.0)
	kit.has_top = true


## Grid of blocks at mixed heights with lanes between: juke field.
static func blocks(rng: RandomNumberGenerator) -> MapKit:
	var k := MapKit.new()
	k.radius = 22.0
	var heights: Array[float] = [1.0, 2.0, 3.5, 6.0]
	for gx: int in range(-2, 3):
		for gz: int in range(-2, 3):
			if gx == 0 and gz == 0: continue # landing spot
			if rng.randf() < 0.45: continue
			var s := Vector3(rng.randf_range(3.0, 5.0), heights[rng.randi() % heights.size()], rng.randf_range(3.0, 5.0))
			k.post(gx * 8.0 + rng.randf_range(-1.0, 1.0), gz * 8.0 + rng.randf_range(-1.0, 1.0), s, &"rock")
	return k


## Rows of vaultable walls (under vault height) with one taller wall to wall-jump off.
static func vaults(rng: RandomNumberGenerator, cfg: MovementConfig) -> MapKit:
	var k := MapKit.new()
	k.radius = 20.0
	var n := rng.randi_range(4, 6)
	var tall := floori(n * 0.5)
	for i: int in n:
		var z := (i - (n - 1) * 0.5) * 6.0
		var h := 4.0 if i == tall else rng.randf_range(0.9, cfg.vault_height - 0.15)
		k.post(rng.randf_range(-2.0, 2.0), z, Vector3(14.0, h, 0.8), &"stone")
	return k


## Raised launch disc with two gentle ramps up; MapGen.add_launchers() gives it long-range pads.
static func hub() -> MapKit:
	var k := MapKit.new()
	k.radius = 18.0
	k.box(Vector3(0.0, 0.75, 0.0), Vector3(14.0, 1.5, 14.0), &"hub", 0.0, true)
	for s: float in [-1.0, 1.0]: # ramps down from the disc edge, running on 1.5 m into the ground
		k.slab(Vector3(s * 7.0, 1.5, 0.0), Vector3(s * (7.0 + 3.0 / tan(deg_to_rad(14.0))), -1.5, 0.0), 5.0, 0.6, &"hub")
	return k
