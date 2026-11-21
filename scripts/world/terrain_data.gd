class_name TerrainData
extends RefCounted
## The shape of the land: an analytic height function sampled into a grid,
## plus the forest-density field and the sites of cabin and hunting towers.

const SIZE := 1024.0
const HALF := 512.0
const N := 513              ## grid samples per side
const CELL := 2.0           ## metres between samples
const PLAY_RADIUS := 425.0
const VERSION := 8

var seed_v := 1905
var heights := PackedFloat32Array()
var forest := PackedFloat32Array()
var ready := false

## [cx, cz, rx, rz, depth]
var lakes := [
	[40.0, 30.0, 195.0, 122.0, 10.0],
	[-255.0, -175.0, 88.0, 70.0, 5.5],
	[240.0, -240.0, 70.0, 96.0, 5.0],
	[-200.0, 255.0, 66.0, 54.0, 4.0],
	[300.0, 190.0, 52.0, 46.0, 3.0],
]

var cabin_pos := Vector3.ZERO
var cabin_yaw := 0.0
var spawn_pos := Vector3.ZERO
var spawn_yaw := 0.0
var menu_cam_pos := Vector3.ZERO
var tower_sites: Array = []      ## [Vector3 pos, float yaw]
var exclusions: Array = []       ## Vector3(x, z, radius): no trees here
var clear_zones: Array = []      ## Vector3(x, z, radius): nothing at all is scattered here (yards)

var n_base := FastNoiseLite.new()
var n_detail := FastNoiseLite.new()
var n_ridge := FastNoiseLite.new()
var n_warp := FastNoiseLite.new()
var n_mtn := FastNoiseLite.new()
var n_forest := FastNoiseLite.new()
var n_species := FastNoiseLite.new()
var n_patch := FastNoiseLite.new()

func _init(p_seed := 1905) -> void:
	seed_v = p_seed
	_noise(n_base, 0, 0.0026, 4)
	_noise(n_detail, 1, 0.021, 3)
	_noise(n_ridge, 2, 0.0046, 2)
	_noise(n_warp, 3, 0.008, 2)
	_noise(n_mtn, 4, 0.0017, 5)
	_noise(n_forest, 5, 0.0068, 3)
	_noise(n_species, 6, 0.0042, 2)
	_noise(n_patch, 7, 0.03, 2)

func _noise(nz: FastNoiseLite, salt: int, freq: float, octaves: int) -> void:
	nz.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	nz.seed = seed_v * 31 + salt * 7919
	nz.frequency = freq
	nz.fractal_type = FastNoiseLite.FRACTAL_FBM
	nz.fractal_octaves = octaves
	nz.fractal_gain = 0.5
	nz.fractal_lacunarity = 2.0

# ------------------------------------------------------------ height field
func height_fn(x: float, z: float) -> float:
	var wx := x + n_warp.get_noise_2d(x, z) * 34.0
	var wz := z + n_warp.get_noise_2d(x + 517.0, z - 291.0) * 34.0
	var b := n_base.get_noise_2d(wx, wz)
	var h := 13.0 + b * 30.0
	var rd := 1.0 - absf(n_ridge.get_noise_2d(wx, wz))
	h += rd * rd * rd * 15.0 * smoothstep(-0.15, 0.45, b)
	h += n_detail.get_noise_2d(x, z) * 1.5
	# keep stray dips from flooding into random ponds: soften anything below 1.5 m
	if h < 1.6:
		h = 1.6 - 0.95 * (1.0 - exp(-(1.6 - h) / 3.5))
	# lakes: carve a basin with a flat boggy margin
	for L in lakes:
		var dx: float = (wx - L[0]) / L[2]
		var dz: float = (wz - L[1]) / L[3]
		var d := sqrt(dx * dx + dz * dz)
		if d < 1.7:
			var k := 1.0 - smoothstep(0.62, 1.7, d)
			var floor_h: float = -L[4] * (1.0 - smoothstep(0.0, 0.95, d)) + 1.1 * smoothstep(0.85, 1.5, d)
			h = lerpf(h, floor_h, k)
	# mountains ring the valley
	var r := sqrt(x * x + z * z)
	if r > 360.0:
		var m := smoothstep(400.0, 1050.0, r)
		var mn := n_mtn.get_noise_2d(x, z)
		var rm := 1.0 - absf(mn)
		h += m * (46.0 + 360.0 * m * rm * rm + 70.0 * (mn * 0.5 + 0.5))
		h += smoothstep(360.0, 470.0, r) * 9.0
	return h

func alloc() -> void:
	heights.resize(N * N)
	forest.resize(N * N)

func generate_rows(z0: int, z1: int) -> void:
	for j in range(z0, mini(z1, N)):
		var z := -HALF + j * CELL
		var row := j * N
		for i in N:
			heights[row + i] = height_fn(-HALF + i * CELL, z)

func height(x: float, z: float) -> float:
	var fx := (x + HALF) / CELL
	var fz := (z + HALF) / CELL
	if fx < 0.0 or fz < 0.0 or fx >= N - 1.0 or fz >= N - 1.0:
		return height_fn(x, z)
	var ix := int(fx)
	var iz := int(fz)
	var tx := fx - ix
	var tz := fz - iz
	var i := iz * N + ix
	var h00 := heights[i]
	var h11 := heights[i + N + 1]
	if tx > tz:
		var h10 := heights[i + 1]
		return h00 + (h10 - h00) * tx + (h11 - h10) * tz
	var h01 := heights[i + N]
	return h00 + (h11 - h01) * tx + (h01 - h00) * tz

func grid_h(ix: int, iz: int) -> float:
	return heights[clampi(iz, 0, N - 1) * N + clampi(ix, 0, N - 1)]

func grid_normal(ix: int, iz: int) -> Vector3:
	return Vector3(grid_h(ix - 1, iz) - grid_h(ix + 1, iz), 2.0 * CELL, grid_h(ix, iz - 1) - grid_h(ix, iz + 1)).normalized()

func normal(x: float, z: float) -> Vector3:
	var e := 1.0
	return Vector3(height(x - e, z) - height(x + e, z), 2.0 * e, height(x, z - e) - height(x, z + e)).normalized()

func slope(x: float, z: float) -> float:
	return 1.0 - normal(x, z).y

func inside(x: float, z: float) -> bool:
	return absf(x) < HALF - 2.0 and absf(z) < HALF - 2.0

func water_depth(x: float, z: float) -> float:
	return maxf(0.0, -height(x, z))

# ----------------------------------------------------------------- forest
func _forest_fn(x: float, z: float, h: float, sl: float) -> float:
	if h < 0.7:
		return 0.0
	var f := n_forest.get_noise_2d(x, z) * 0.5 + 0.5
	f = smoothstep(0.34, 0.6, f)
	f *= 0.1 + 0.9 * smoothstep(1.3, 4.5, h)
	f *= 1.0 - smoothstep(0.26, 0.48, sl)
	f *= 1.0 - smoothstep(105.0, 170.0, h)
	for e in exclusions:
		var dx: float = x - e.x
		var dz: float = z - e.y
		var d2 := dx * dx + dz * dz
		if d2 < e.z * e.z * 2.3:
			f *= smoothstep(e.z * 0.85, e.z * 1.5, sqrt(d2))
	return f

## Fills the forest grid and the baked shader maps (normal xz, forest) for rows z0..z1.
func build_field_rows(z0: int, z1: int, map_bytes: PackedByteArray, depth_bytes: PackedByteArray) -> void:
	var inv := 1.0 / (2.0 * CELL)
	for j in range(z0, mini(z1, N)):
		var z := -HALF + j * CELL
		var row := j * N
		var up := maxi(j - 1, 0) * N
		var dn := mini(j + 1, N - 1) * N
		for i in N:
			var il := maxi(i - 1, 0)
			var ir := mini(i + 1, N - 1)
			var nrm := Vector3((heights[row + il] - heights[row + ir]) * inv, 1.0, (heights[up + i] - heights[dn + i]) * inv).normalized()
			var h := heights[row + i]
			var f := _forest_fn(-HALF + i * CELL, z, h, 1.0 - nrm.y)
			forest[row + i] = f
			var k := (row + i) * 4
			map_bytes[k] = int(clampf(nrm.x * 0.5 + 0.5, 0.0, 1.0) * 255.0)
			map_bytes[k + 1] = int(clampf(nrm.z * 0.5 + 0.5, 0.0, 1.0) * 255.0)
			map_bytes[k + 2] = int(f * 255.0)
			map_bytes[k + 3] = 255
			depth_bytes[row + i] = int(clampf(-h / 8.0, 0.0, 1.0) * 255.0)

## Forest density 0..1 (0 = open ground, 1 = dense spruce).
func forest_at(x: float, z: float) -> float:
	var fx := clampf((x + HALF) / CELL, 0.0, N - 1.001)
	var fz := clampf((z + HALF) / CELL, 0.0, N - 1.001)
	var ix := int(fx)
	var iz := int(fz)
	var tx := fx - ix
	var tz := fz - iz
	var i := iz * N + ix
	return lerpf(lerpf(forest[i], forest[i + 1], tx), lerpf(forest[i + N], forest[i + N + 1], tx), tz)

## 0 = spruce country, 1 = birch/pine mix; used to pick tree species.
func species_at(x: float, z: float) -> float:
	return n_species.get_noise_2d(x, z) * 0.5 + 0.5

func patch_at(x: float, z: float) -> float:
	return n_patch.get_noise_2d(x, z) * 0.5 + 0.5

## Approximate ground colour (matches the terrain shader's palette closely
## enough for dust puffs, grass tint and the map).
func ground_color(x: float, z: float) -> Color:
	var h := height(x, z)
	var f := forest_at(x, z)
	var sl := slope(x, z)
	var p := patch_at(x, z)
	var col := Color(0.30, 0.31, 0.12).lerp(Color(0.44, 0.37, 0.17), p)
	col = col.lerp(Color(0.13, 0.17, 0.07).lerp(Color(0.19, 0.14, 0.08), p), f)
	var wet := 1.0 - smoothstep(0.9, 2.6, h)
	col = col.lerp(Color(0.42, 0.33, 0.13).lerp(Color(0.16, 0.12, 0.07), p * p), wet * (1.0 - f))
	col = col.lerp(Color(0.40, 0.33, 0.20), smoothstep(110.0, 170.0, h))
	col = col.lerp(Color(0.40, 0.40, 0.38), smoothstep(0.26, 0.42, sl))
	col = col.lerp(Color(0.40, 0.36, 0.28), 1.0 - smoothstep(0.05, 0.7, h))
	col = col.lerp(Color(0.9, 0.92, 0.95), smoothstep(250.0, 300.0, h))
	return col

# ------------------------------------------------------------------ sites
func place_sites() -> void:
	exclusions.clear()
	clear_zones.clear()
	tower_sites.clear()
	# cabin on the south-west shore of the big lake, facing the water
	var L: Array = lakes[0]
	var c := Vector2(L[0], L[1])
	var site := _walk_to_shore(c, deg_to_rad(205.0), 1.5, 9.0)
	cabin_yaw = atan2(c.x - site.x, c.y - site.y)   # local +Z faces the lake
	_flatten(site, 8.5, 19.0)
	cabin_pos = Vector3(site.x, height(site.x, site.y), site.y)
	exclusions.append(Vector3(site.x, site.y, 17.0))
	clear_zones.append(Vector3(site.x, site.y, 10.5))
	var fwd := Vector2(sin(cabin_yaw), cos(cabin_yaw))
	var sp := site + fwd * 8.5 + Vector2(fwd.y, -fwd.x) * 2.5
	spawn_pos = Vector3(sp.x, height(sp.x, sp.y), sp.y)
	spawn_yaw = cabin_yaw
	exclusions.append(Vector3(sp.x, sp.y, 8.0))
	# the menu camera stands on the slope in front of the cabin, the morning sun behind it
	var mc := site + fwd * 13.0 + Vector2(fwd.y, -fwd.x) * 10.0
	menu_cam_pos = Vector3(mc.x, maxf(height(mc.x, mc.y), 0.6), mc.y)
	exclusions.append(Vector3(mc.x, mc.y, 10.0))
	clear_zones.append(Vector3(mc.x, mc.y, 4.0))
	# hunting towers overlooking the smaller lakes' bogs
	for spec in [[1, 35.0], [2, 150.0], [3, -40.0], [0, 20.0]]:
		var Lk: Array = lakes[spec[0]]
		var lc := Vector2(Lk[0], Lk[1])
		var t := _walk_to_shore(lc, deg_to_rad(spec[1]), 3.0, 26.0)
		var pos := Vector3(t.x, height(t.x, t.y), t.y)
		tower_sites.append([pos, atan2(lc.x - t.x, lc.y - t.y)])
		exclusions.append(Vector3(t.x, t.y, 13.0))
		clear_zones.append(Vector3(t.x, t.y, 3.2))

func in_clear_zone(x: float, z: float) -> bool:
	for e in clear_zones:
		var dx: float = x - e.x
		var dz: float = z - e.y
		if dx * dx + dz * dz < e.z * e.z:
			return true
	return false

## Level the grid around `c` to its centre height (inner radius flat, blended out to `outer`).
func _flatten(c: Vector2, inner: float, outer: float) -> void:
	var target := maxf(height(c.x, c.y), 1.3)
	var i0 := int((c.x - outer + HALF) / CELL)
	var i1 := int((c.x + outer + HALF) / CELL) + 1
	var j0 := int((c.y - outer + HALF) / CELL)
	var j1 := int((c.y + outer + HALF) / CELL) + 1
	for j in range(maxi(j0, 0), mini(j1, N)):
		for i in range(maxi(i0, 0), mini(i1, N)):
			var d := Vector2(-HALF + i * CELL, -HALF + j * CELL).distance_to(c)
			var k := smoothstep(inner, outer, d)
			heights[j * N + i] = lerpf(target, heights[j * N + i], k)

func _walk_to_shore(center: Vector2, angle: float, min_h: float, extra: float) -> Vector2:
	var dir := Vector2(sin(angle), cos(angle))
	var d := 10.0
	while d < 400.0:
		var p := center + dir * d
		if height(p.x, p.y) > min_h and height(p.x + dir.x * 6.0, p.y + dir.y * 6.0) > min_h:
			# then continue to the flattest spot within the next stretch
			var best := p + dir * extra
			var best_s := 99.0
			for k in 8:
				var q := p + dir * (extra * 0.5 + k * 3.0)
				var s := slope(q.x, q.y)
				if s < best_s and height(q.x, q.y) > min_h:
					best_s = s
					best = q
			return best
		d += 2.0
	return center + dir * 120.0

# --------------------------------------------------------------- raycast
## Segment vs terrain. Returns the hit point, or null.
func ray(from: Vector3, to: Vector3):
	var d := to - from
	var length := d.length()
	if length < 0.001:
		return null
	var steps := maxi(1, int(ceil(length / 1.6)))
	var prev := from
	for i in range(1, steps + 1):
		var p := from + d * (float(i) / steps)
		if p.y < height(p.x, p.z):
			var a := prev
			var b := p
			for k in 7:
				var m := (a + b) * 0.5
				if m.y < height(m.x, m.z):
					b = m
				else:
					a = m
			return (a + b) * 0.5
		prev = p
	return null

## True if nothing but air lies between the two points (terrain only).
func line_clear(from: Vector3, to: Vector3) -> bool:
	var d := to - from
	var steps := maxi(2, int(d.length() / 6.0))
	for i in range(1, steps):
		var p := from + d * (float(i) / steps)
		if p.y < height(p.x, p.z):
			return false
	return true

# ----------------------------------------------------------------- cache
func _cache_path() -> String:
	return "user://world_%d_v%d.bin" % [seed_v, VERSION]

func load_cache() -> bool:
	if G.args.has("nocache") or not FileAccess.file_exists(_cache_path()):
		return false
	var f := FileAccess.open(_cache_path(), FileAccess.READ)
	if f == null or f.get_length() != N * N * 4:
		return false
	heights = f.get_buffer(N * N * 4).to_float32_array()
	forest.resize(N * N)
	return heights.size() == N * N

func save_cache() -> void:
	var f := FileAccess.open(_cache_path(), FileAccess.WRITE)
	if f:
		f.store_buffer(heights.to_byte_array())
