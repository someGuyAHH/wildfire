extends SceneTree
# How bright a map's playable places are, headless: a CPU model of the renderer's direct light at
# the game's default settings (Lighting Low: no GI, no SSAO, no volumetric fog). Samples every
# standable floor spot (2 m grid, every level), the walls and obstacles seen from them, and how lit
# a character standing there is, then reports the darkest regions and writes a top-down heat map.
#   MAP=res://scn/map/inferno.tscn [OUT=/abs/dir] timeout 300 godot --headless -s res://tools/checks/light_probe.gd
#
# The model (Godot 4 Forward+, non-physical light units, diffuse only):
#   radiance = albedo * (ambient(n) + sum over lights of colour * energy * max(n.l, 0) * attenuation * shadow)
#   ambient(n): the cosine-weighted ProceduralSky (gradient + the sun's halo) * ambient energy;
#     unoccluded, as the renderer does without GI or SSAO.
#   omni attenuation: (1 - (d/range)^4)^2 * d^-decay. Shadows only for lights that cast them,
#     by physics rays (the sun's stop at the wall tops: above them are only invisible blockers).
#   display: AgX (the polynomial fit Godot's is based on), exposure 1.
# What it can't see: glow/bloom, specular, the shaders' per-brick tone, grime and rim highlights,
# look-only geometry without collision (it neither shadows nor is sampled), depth fog (~11 % at 30 m),
# the lava's own emission (it lights nothing at Lighting Low: only real lights do).
#
# Readability bar (justified in docs/maps/inferno.md, "Lighting"): the light on a floor must be at
# least 1/6 of the sun's direct light on an open floor (~2.6 stops under it: deep shade that still
# shows form), and on a standing character at least 1/6 of the sun's on one.

const GRID := 2.0
const TOP := 29.5        # sample rays start under the wall tops (invisible blockers above)
const SUN_CEIL := 30.4   # the sun's shadow rays stop here: nothing visible stands above the walls
const LOW := -8.0        # lava line: below is not playable
const ARENA := 245.0
const HEADROOM := 1.8
const RATIO := 1.0 / 6.0 # the bar, against the sun-lit reference

const HALLS: Array[Vector3] = [Vector3(0, 0, -1), Vector3(1, 0, 0), Vector3(0, 0, 1), Vector3(-1, 0, 0)]
const HALL_NAMES: Array[String] = ["Ossuary (N)", "Mere (E)", "Basilica (S)", "Gallows (W)"]
const HALL_R := 160.0
const HW := 50.0
const HL := 70.0

# albedos (sRGB, as the inferno art materials' base colours)
const FLOOR_ALBEDO := Color(0.25, 0.2, 0.19)
const WALL_ALBEDO := Color(0.23, 0.17, 0.16)
const BODY_ALBEDO := Color(0.6, 0.6, 0.6)

var _space: PhysicsDirectSpaceState3D
var _dirs: Array[Vector3] = []   # unit sphere samples for the sky integral
var _sky_rad: Array[Color] = []  # sky radiance along each (linear, ambient energy in)
var _amb_cache := {}
var _suns: Array[Array] = []     # [dir to light, colour*energy (linear), shadows, angular size, drawn in the sky]
var _omnis: Array[Array] = []    # [pos, colour*energy, range, decay, shadows]
var _ref_floor := 0.0
var _ref_body := 0.0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var path := OS.get_environment("MAP")
	if path.is_empty(): path = "res://scn/map/inferno.tscn"
	var out_dir := OS.get_environment("OUT")
	var map := (load(path) as PackedScene).instantiate() as Node3D
	root.add_child(map)
	for i: int in 6: await physics_frame
	_space = map.get_world_3d().direct_space_state
	_read_lights(map)
	_read_sky(map)

	# references: the sun's direct light alone on an open floor and on a standing body (the bar is a
	# fraction of these, so it stays put whatever fill and ambient do)
	_ref_floor = _lum(_sun_only(Vector3.UP))
	var body_ref := Color()
	for d: Vector3 in [Vector3.RIGHT, Vector3.LEFT, Vector3.FORWARD, Vector3.BACK]: body_ref += _sun_only(d)
	_ref_body = _lum(body_ref * 0.25)
	print("lights: %d directional, %d omni (%d casting shadows)" % [_suns.size(), _omnis.size(), _omnis.filter(func(o: Array) -> bool: return o[4]).size()])
	print("sun-lit reference: floor E %.3f (display %.2f), body E %.3f; ambient alone: floor %.3f, side %.3f" % [
		_ref_floor, _display(FLOOR_ALBEDO, _sun_only(Vector3.UP) + _ambient(Vector3.UP)), _ref_body,
		_lum(_ambient(Vector3.UP)), _lum(_ambient(Vector3.RIGHT))])
	print("bar: floor E >= %.3f (display %.2f), body E >= %.3f" % [_ref_floor * RATIO,
		_display(FLOOR_ALBEDO, Color(1, 1, 1) * _ref_floor * RATIO), _ref_body * RATIO])

	var regions := {}  # name -> {floor: [], body: [], wall: [], cells: {Vector2i: [sum, n, min, local]}}
	var heat := Image.create(250, 250, false, Image.FORMAT_RGB8)
	heat.fill(Color(0.02, 0.0, 0.0))
	var t0 := Time.get_ticks_msec()
	var n := 0
	var x := -ARENA
	while x <= ARENA:
		var z := -ARENA
		while z <= ARENA:
			if Vector2(x, z).length() <= ARENA:
				var top := true
				for p: Vector3 in _floors(x, z):
					n += 1
					_sample(p, regions, heat if top else null, int(round(x / GRID)) % 2 == 0 and int(round(z / GRID)) % 2 == 0)
					top = false
			z += GRID
		x += GRID
	print("%d floor samples (%d ms)" % [n, Time.get_ticks_msec() - t0])
	_report(regions)
	if not out_dir.is_empty():
		heat.resize(500, 500, Image.INTERPOLATE_NEAREST)
		heat.save_png(out_dir.path_join("light_heat.png"))
		print("heat map: %s" % out_dir.path_join("light_heat.png"))
	quit()


#region lights

func _read_lights(map: Node) -> void:
	for l: Node in map.find_children("*", "Light3D", true, false):
		var light := l as Light3D
		if not light.visible or light.light_negative: continue
		var c := light.light_color.srgb_to_linear() * light.light_energy
		if light is DirectionalLight3D:
			_suns.append([light.global_basis.z.normalized(), c, light.shadow_enabled, deg_to_rad(light.light_angular_distance),
				(light as DirectionalLight3D).sky_mode != DirectionalLight3D.SKY_MODE_LIGHT_ONLY])
		elif light is OmniLight3D:
			var o := light as OmniLight3D
			_omnis.append([o.global_position, c, o.omni_range, o.omni_attenuation, o.shadow_enabled])


func _read_sky(map: Node) -> void:
	var we := map.find_children("*", "WorldEnvironment", true, false)[0] as WorldEnvironment
	var env := we.environment
	var mat := env.sky.sky_material as ProceduralSkyMaterial if env.sky else null
	var count := 2048
	var golden := PI * (3.0 - sqrt(5.0))
	for i: int in count:
		var y := 1.0 - (i + 0.5) / count * 2.0
		var r := sqrt(1.0 - y * y)
		var d := Vector3(cos(golden * i) * r, y, sin(golden * i) * r)
		_dirs.append(d)
		var rad := _sky(mat, d) if mat else env.background_color.srgb_to_linear()
		var amb := rad
		match env.ambient_light_source:
			Environment.AMBIENT_SOURCE_COLOR: amb = env.ambient_light_color.srgb_to_linear()
			Environment.AMBIENT_SOURCE_DISABLED: amb = Color(0, 0, 0)
			_: amb = env.ambient_light_color.srgb_to_linear().lerp(rad, env.ambient_light_sky_contribution)
		_sky_rad.append(amb * env.ambient_light_energy)
	print("environment: ambient source %d, energy %.2f, sky contribution %.2f" % [env.ambient_light_source, env.ambient_light_energy, env.ambient_light_sky_contribution])


## ProceduralSkyMaterial's shader, on the CPU (sun halos from the directional lights included).
func _sky(m: ProceduralSkyMaterial, d: Vector3) -> Color:
	var v_angle := acos(clampf(d.y, -1.0, 1.0))
	if d.y >= 0.0:
		var c := 1.0 - v_angle / (PI * 0.5)
		var col := m.sky_horizon_color.srgb_to_linear().lerp(m.sky_top_color.srgb_to_linear(), clampf(1.0 - pow(1.0 - c, 1.0 / m.sky_curve), 0.0, 1.0))
		col *= m.sky_energy_multiplier
		for s: Array in _suns:
			if not s[4]: continue
			var ang := acos(clampf(d.dot(s[0]), -1.0, 1.0))
			var amin: float = s[3]
			var amax := deg_to_rad(m.sun_angle_max)
			if ang < amin: col = s[1]
			elif ang < amax:
				var c2 := (ang - amin) / (amax - amin)
				col = (s[1] as Color).lerp(col, clampf(1.0 - pow(1.0 - c2, 1.0 / m.sun_curve), 0.0, 1.0))
		return col * m.energy_multiplier
	var cg := (v_angle - PI * 0.5) / (PI * 0.5)
	var g := m.ground_horizon_color.srgb_to_linear().lerp(m.ground_bottom_color.srgb_to_linear(), clampf(1.0 - pow(1.0 - cg, 1.0 / m.ground_curve), 0.0, 1.0))
	return g * m.ground_energy_multiplier * m.energy_multiplier


## Ambient irradiance on a surface facing `n` (cosine-weighted, unoccluded).
func _ambient(n: Vector3) -> Color:
	var key := (n * 8.0).round()
	if _amb_cache.has(key): return _amb_cache[key]
	var e := Color(0, 0, 0)
	for i: int in _dirs.size():
		var c := _dirs[i].dot(n)
		if c > 0.0: e += _sky_rad[i] * c
	e = e * (4.0 / _dirs.size()) # (4 pi / N) / pi
	_amb_cache[key] = e
	return e


## The sun's own light (the brightest directional, unshadowed) on a surface facing `n`.
func _sun_only(n: Vector3) -> Color:
	var sun: Array = _suns[0]
	for s: Array in _suns: if _lum(s[1]) > _lum(sun[1]): sun = s
	return (sun[1] as Color) * maxf(n.dot(sun[0]), 0.0)


## All the light reaching a surface at `p` facing `n`.
func _light(p: Vector3, n: Vector3) -> Color:
	var e := _ambient(n)
	var from := p + n * 0.06
	for s: Array in _suns:
		var nl := n.dot(s[0])
		if nl <= 0.0: continue
		var dir: Vector3 = s[0]
		if s[2]:
			var len := 600.0 if dir.y <= 0.01 else maxf((SUN_CEIL - from.y) / dir.y, 0.0)
			if len > 0.0 and _space.intersect_ray(PhysicsRayQueryParameters3D.create(from, from + dir * len)): continue
		e += (s[1] as Color) * nl
	for o: Array in _omnis:
		var to: Vector3 = o[0] - p
		var d := to.length()
		var rng: float = o[2]
		if d >= rng: continue
		var nl := n.dot(to / maxf(d, 0.0001))
		if nl <= 0.0: continue
		if o[4] and _space.intersect_ray(PhysicsRayQueryParameters3D.create(from, o[0])): continue
		var nd := d / rng
		nd = maxf(1.0 - nd * nd * nd * nd, 0.0)
		e += (o[1] as Color) * nl * nd * nd * pow(maxf(d, 0.0001), -float(o[3]))
	return e

#endregion


#region sampling

## Standable floor spots in the column at (x, z), top first.
func _floors(x: float, z: float) -> Array[Vector3]:
	var out: Array[Vector3] = []
	var y := TOP
	for k: int in 8:
		var hit := _space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(x, y, z), Vector3(x, LOW, z)))
		if not hit: break
		var p: Vector3 = hit.position
		if (hit.normal as Vector3).y > 0.7:
			var up := p + Vector3.UP * 0.05
			if not _space.intersect_ray(PhysicsRayQueryParameters3D.create(up, up + Vector3.UP * HEADROOM)): out.append(p)
		y = p.y - 0.1
	return out


func _sample(p: Vector3, regions: Dictionary, heat: Image, walls: bool) -> void:
	var reg := _region(p)
	var r: Dictionary = regions.get_or_add(reg[0], {"floor": [], "body": [], "wall": [], "cells": {}})
	var ef := _lum(_light(p, Vector3.UP))
	var body := Color()
	var chest := p + Vector3.UP * 1.0
	for d: Vector3 in [Vector3.RIGHT, Vector3.LEFT, Vector3.FORWARD, Vector3.BACK]: body += _light(chest, d)
	var eb := _lum(body * 0.25)
	r.floor.append(ef)
	r.body.append(eb)
	var local: Vector3 = reg[1]
	var cell := Vector2i(floori(local.x / 10.0), floori(local.z / 10.0))
	var c: Array = r.cells.get_or_add(cell, [0.0, 0, INF, local, 0.0])
	c[0] += ef
	c[1] += 1
	c[2] = minf(c[2], ef)
	c[4] += eb
	if walls:
		for d: Vector3 in [Vector3.RIGHT, Vector3.LEFT, Vector3.FORWARD, Vector3.BACK]:
			var eye := p + Vector3.UP * 1.5
			var hit := _space.intersect_ray(PhysicsRayQueryParameters3D.create(eye, eye + d * 30.0))
			if hit and absf((hit.normal as Vector3).y) < 0.3:
				r.wall.append(_lum(_light(hit.position, hit.normal)))
	if heat:
		var px := Vector2i(int((p.x + 250.0) / 2.0), int((p.z + 250.0) / 2.0))
		if px.x >= 0 and px.y >= 0 and px.x < 250 and px.y < 250:
			var v := ef / _ref_floor
			# under the bar: red; over it, a grey ramp in stops (bar .. sun-lit)
			var col := Color(0.85, 0.08, 0.05) if v < RATIO else Color.from_hsv(0.08, 0.5, clampf(0.25 + 0.75 * (log(v / RATIO) / log(1.0 / RATIO)), 0.0, 1.0))
			heat.set_pixelv(px, col)


## [region name, local position]: a hall (hall-local x across, z outward) or the rest.
func _region(p: Vector3) -> Array:
	for i: int in HALLS.size():
		var u := HALLS[i]
		var xf := Transform3D(Basis(Vector3.UP, atan2(u.x, u.z)), u * HALL_R)
		var l := xf.affine_inverse() * p
		if absf(l.x) <= HW + 0.5 and absf(l.z) <= HL + 0.5: return [HALL_NAMES[i], l]
		if i == 3 and l.z > HL and l.z < HL + 20.0 and l.x > HW - 20.0 and l.x < HW + 10.0: return ["Ashen Vault", l]
	if Vector2(p.x, p.z).length() < 48.0: return ["Maw (pit)", p]
	return ["Spokes + ring", p]

#endregion


#region report

func _report(regions: Dictionary) -> void:
	var names := regions.keys()
	names.sort()
	var worst_all := INF
	var under_floor := 0
	var under_body := 0
	var total := 0
	print("\nregion            floor E: min    p5   med  | body E: min    p5   med  | walls E: p5   med | under bar: floor  body")
	for name: String in names:
		var r: Dictionary = regions[name]
		var f: Array = r.floor
		var b: Array = r.body
		var w: Array = r.wall
		f.sort()
		b.sort()
		w.sort()
		var uf := f.filter(func(v: float) -> bool: return v < _ref_floor * RATIO).size()
		var ub := b.filter(func(v: float) -> bool: return v < _ref_body * RATIO).size()
		under_floor += uf
		under_body += ub
		total += f.size()
		worst_all = minf(worst_all, f[0])
		print("%-16s  %10.3f %5.3f %5.3f  | %9.3f %5.3f %5.3f  | %11.3f %5.3f | %8.1f%% %5.1f%%" % [name, f[0], _pct(f, 0.05), _pct(f, 0.5),
			b[0], _pct(b, 0.05), _pct(b, 0.5), _pct(w, 0.05) if w else 0.0, _pct(w, 0.5) if w else 0.0,
			100.0 * uf / f.size(), 100.0 * ub / b.size()])
	print("ALL: %d floor samples, %.1f%% of floor and %.1f%% of body spots under the bar; darkest floor E %.3f (%.2f of the sun-lit floor, %.1f stops under; a basalt floor there displays %.2f)" % [
		total, 100.0 * under_floor / total, 100.0 * under_body / total, worst_all, worst_all / _ref_floor,
		log(_ref_floor / maxf(worst_all, 1e-6)) / log(2.0), _display(FLOOR_ALBEDO, Color(1, 1, 1) * worst_all)])
	# the darkest 10 m cells anywhere (by mean floor light)
	var cells: Array = []
	for name: String in names:
		var r: Dictionary = regions[name]
		for k: Vector2i in r.cells:
			var c: Array = r.cells[k]
			if c[1] >= 6: cells.append([c[0] / c[1], name, k, c[4] / c[1]])
	cells.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	print("\ndarkest 10 m cells (mean floor E, x/sun-lit; mean body E; hall-local x across, z outward from the pit):")
	for i: int in mini(12, cells.size()):
		var c: Array = cells[i]
		print("  %-14s x %4d..%-4d z %4d..%-4d  floor %.3f (%.2f)  body %.3f" % [c[1], c[2].x * 10, c[2].x * 10 + 10, c[2].y * 10, c[2].y * 10 + 10, c[0], c[0] / _ref_floor, c[3]])


func _pct(a: Array, q: float) -> float:
	return a[clampi(int(q * (a.size() - 1)), 0, a.size() - 1)]


func _lum(c: Color) -> float:
	return 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b


## Display value (0..1) of a surface of `albedo` (sRGB) under light `e`: AgX, exposure 1, luma.
func _display(albedo: Color, e: Color) -> float:
	var a := albedo.srgb_to_linear()
	var rad := Vector3(a.r * e.r, a.g * e.g, a.b * e.b)
	var inset := Basis(Vector3(0.842479062253094, 0.0423282422610123, 0.0423756549057051),
		Vector3(0.0784335999999992, 0.878468636469772, 0.0784336),
		Vector3(0.0792237451477643, 0.0791661274605434, 0.879142973793104))
	var outset := Basis(Vector3(1.19687900512017, -0.0528968517574562, -0.0529716355144438),
		Vector3(-0.0980208811401368, 1.15190312990417, -0.0980434501171241),
		Vector3(-0.0990297440797205, -0.0989611768448433, 1.15107367264116))
	var v := inset * rad
	var lo := -12.47393
	var hi := 4.026069
	for k: int in 3:
		var x := (clampf(log(maxf(v[k], 1e-10)) / log(2.0), lo, hi) - lo) / (hi - lo)
		var x2 := x * x
		var x4 := x2 * x2
		v[k] = 15.5 * x4 * x2 - 40.14 * x4 * x + 31.96 * x4 - 6.868 * x2 * x + 0.4298 * x2 + 0.1191 * x - 0.00232
	v = outset * v
	return clampf(0.2126 * v.x + 0.7152 * v.y + 0.0722 * v.z, 0.0, 1.0)

#endregion
