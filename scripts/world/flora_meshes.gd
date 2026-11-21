class_name FloraMeshes
extends RefCounted
## Procedural plants and rocks. Vertex colour = albedo, alpha = wind sway.
##
## The three big trees are a solid part (trunk, limbs, a dark heart) plus foliage
## "cards": flat pieces carrying a painted bough, needle cluster or leaf spray
## (see FloraTextures). Their meshes have two surfaces, solid then cards. The
## `_plain_*` builders are the simple all-solid models, kept as the distant
## stand-in for when the far pictures cannot be taken.

static func _rng(seed_v: int) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = seed_v
	return r

static func _c(col: Color, sway: float) -> Color:
	return Color(col.r, col.g, col.b, sway)

## One drooping whorl of spruce branches: a jagged cone with a dark underside.
static func _tier(k: MeshKit, y: float, rad: float, th: float, sides: int, rng: RandomNumberGenerator,
		col_tip: Color, col_in: Color, col_under: Color, sway: float, underside: bool) -> void:
	var v0 := k.count()
	var i0 := k.idx.size()
	var apex := k.vert(Vector3(0, y + th, 0), Vector3.UP, _c(col_in, sway * 0.5))
	var rim := []
	for i in sides:
		var a := TAU * float(i) / sides + rng.randf_range(-0.12, 0.12)
		var long_b := (i % 2) == 0
		var rr := rad * (rng.randf_range(0.92, 1.1) if long_b else rng.randf_range(0.6, 0.78))
		var yy := y - (rad * 0.16 if long_b else 0.0) + rng.randf_range(-0.08, 0.08)
		rim.append(Vector3(cos(a) * rr, yy, sin(a) * rr))
	var rim_i := []
	for i in sides:
		rim_i.append(k.vert(rim[i], Vector3.UP, _c(col_tip if (i % 2) == 0 else col_tip.lerp(col_in, 0.5), sway)))
	for i in sides:
		k.tri(apex, rim_i[(i + 1) % sides], rim_i[i])
	k.smooth_normals(v0, i0)
	if underside:
		var cu := k.vert(Vector3(0, y + th * 0.42, 0), Vector3.DOWN, _c(col_under, sway * 0.4))
		var ub := k.count()
		for i in sides:
			var out := Vector3(rim[i].x, 0, rim[i].z).normalized()
			k.vert(rim[i], (Vector3.DOWN * 0.8 + out * 0.6).normalized(), _c(col_under.lerp(col_tip, 0.35), sway))
		for i in sides:
			k.tri(cu, ub + i, ub + (i + 1) % sides)

static func _plain_spruce(lod: int, seed_v := 11, crown_base := 1.5, width := 1.0) -> ArrayMesh:
	var k := MeshKit.new()
	var rng := _rng(seed_v)
	var hgt := 12.0
	var bark := Color(0.36, 0.29, 0.24)
	var tip := Color(0.27, 0.37, 0.24)
	var inner := Color(0.17, 0.25, 0.18)
	var under := Color(0.11, 0.16, 0.13)
	if lod == 0:
		k.cyl(Vector3(0, -0.5, 0), Vector3(0, hgt * 0.92, 0), 0.25, 0.04, 6, _c(bark, 0.0), _c(bark, 0.5))
		var tiers := 9
		for t in tiers:
			var u := float(t) / (tiers - 1)
			var y := 1.4 + u * (hgt - 3.5)
			var rad := lerpf(2.6, 0.58, pow(u, 0.85)) * rng.randf_range(0.93, 1.07)
			var th := lerpf(2.9, 1.7, u)
			_tier(k, y, rad, th, 11, rng, tip.lerp(Color(0.35, 0.43, 0.27), u * 0.6), inner, under, 0.35 + 0.65 * u, true)
		_tier(k, hgt - 1.7, 0.42, 2.1, 5, rng, tip, tip, under, 1.0, false)
	else:
		k.cyl(Vector3(0, -0.5, 0), Vector3(0, crown_base + 0.9, 0), 0.25, 0.2, 3, _c(bark, 0.0))
		var mid := tip.lerp(inner, 0.45)
		var span := clampf((12.1 - crown_base) / 10.6, 0.3, 1.0)
		for t in 3:
			var u := float(t) / 2.0
			_tier(k, crown_base + u * 5.2 * span, lerpf(2.4, 1.0, u) * width, lerpf(5.0, 5.4, u) * span, 6, rng, mid.lerp(tip, 0.4), mid, under, 0.4 + 0.6 * u, false)
	return k.commit()

## A young spruce, about one and a half metres: a thin stem with a few whorls
## of small sprays, drooping a little below and reaching up at the top.
static func sapling(seed_v := 21) -> ArrayMesh:
	var solid := MeshKit.new()
	var cards := MeshKit.new()
	var rng := _rng(seed_v)
	var bark := Color(0.36, 0.29, 0.24)
	var c_in := Color(0.24, 0.35, 0.28)
	var c_tip := Color(0.37, 0.50, 0.40)
	var t_a := FloraTextures.tile_rect(FloraTextures.SPRUCE)
	var t_b := FloraTextures.tile_rect(FloraTextures.SPRUCE_B)
	var trim_a := FloraTextures.spray_trap(FloraTextures.SPRUCE)
	var trim_b := FloraTextures.spray_trap(FloraTextures.SPRUCE_B)
	solid.cyl(Vector3(0, -0.2, 0), Vector3(0, 1.45, 0), 0.04, 0.01, 4, _c(bark, 0.0), _c(bark, 0.6))
	var levels := 5
	var twist := rng.randf() * TAU
	for lv in levels:
		var u := float(lv) / (levels - 1)
		var y := lerpf(0.12, 1.22, u) + rng.randf_range(-0.03, 0.03)
		twist += 2.4 + rng.randf_range(-0.3, 0.3)
		var n_b := 5 if lv < 2 else 4
		for b in n_b:
			var a := twist + TAU * b / n_b + rng.randf_range(-0.25, 0.25)
			var ln := lerpf(0.72, 0.24, u) * rng.randf_range(0.8, 1.15)
			var use_a := rng.randf() < 0.5
			_bough(cards, t_a if use_a else t_b, Vector3(0, y, 0), a, ln, ln * 0.85,
				lerpf(0.05, 0.6, u), lerpf(0.42, 0.15, u), rng.randf_range(-0.25, 0.25), 0.55, c_in, c_tip, 0.5 + 0.4 * u, 0.2, rng.randf() < 0.5, trim_a if use_a else trim_b)
	# the leader
	for i in 2:
		var a := twist + PI * i / 2.0
		var side := Vector3(cos(a), 0, sin(a)) * 0.05
		var nrm := Vector3(0, 0.8, 0)
		var i0 := _cv(cards, Vector3(0, 1.25, 0) - side, (nrm - side).normalized(), _c(c_tip, 0.9), t_a, Vector2(0.36, 0.16))
		var i1 := _cv(cards, Vector3(0, 1.25, 0) + side, (nrm + side).normalized(), _c(c_tip, 0.9), t_a, Vector2(0.64, 0.16))
		var i2 := _cv(cards, Vector3(0, 1.62, 0) + side, (nrm + side).normalized(), _c(c_tip, 1.0), t_a, Vector2(0.64, 0.0))
		var i3 := _cv(cards, Vector3(0, 1.62, 0) - side, (nrm - side).normalized(), _c(c_tip, 1.0), t_a, Vector2(0.36, 0.0))
		cards.quad(i0, i1, i2, i3)
	return _two_surfaces(solid, cards)

## A tapering, slightly bent trunk. Texture coordinates run once round the trunk
## (u) and up it in metres (v), with a doubled seam so bark can be drawn on it.
static func _trunk(k: MeshKit, ys: Array, r0: float, r1: float, sides: int, col_fn: Callable, bend: float, seed_v: int) -> Array:
	var rings := []
	var cols := []
	var centers := []
	var hgt: float = ys[-1]
	for j in ys.size():
		var y: float = ys[j]
		var u := clampf(y / hgt, 0.0, 1.0)
		var cx := sin(u * 2.6 + seed_v) * bend * u
		var cz := cos(u * 1.9 + seed_v * 2.0) * bend * u * 0.7
		var c := Vector3(cx, y, cz)
		centers.append(c)
		var r := lerpf(r0, r1, pow(u, 0.8))
		if j == 0:
			r *= 1.35
		# travel is +Y: need u x w = +Y -> u = Z, w = X
		var ring := MeshKit.ring_uw(c, Vector3(0, 0, 1), Vector3(1, 0, 0), r, r, sides)
		ring.append(ring[0])
		rings.append(ring)
		var ring_cols := []
		for i in sides + 1:
			ring_cols.append(col_fn.call(u, j, i % sides))
		cols.append(ring_cols)
	var base := k.count()
	k.loft(rings, cols, false, true)
	var m := sides + 1
	for j in ys.size():
		var first := base + j * m
		var last := first + sides
		var nn := (k.n[first] + k.n[last]).normalized()
		k.n[first] = nn
		k.n[last] = nn
		for i in m:
			k.uv[first + i] = Vector2(float(i) / sides, ys[j])
	return centers

static func _plain_pine(lod: int, seed_v := 31) -> ArrayMesh:
	var k := MeshKit.new()
	var low := Color(0.40, 0.33, 0.28)
	var high := Color(0.72, 0.44, 0.25)
	var col_fn := func(u: float, _j: int, _i: int) -> Color:
		return _c(low.lerp(high, smoothstep(0.25, 0.6, u)), u * u * 0.5)
	var top := Color(0.34, 0.44, 0.27)
	var bot := Color(0.17, 0.26, 0.18)
	if lod == 0:
		var centers := _trunk(k, [-0.5, 1.8, 4.2, 6.8, 9.2, 11.2, 12.6], 0.27, 0.07, 6, col_fn, 0.45, seed_v)
		var tp: Vector3 = centers[-1]
		var blobs := [
			[tp + Vector3(0.1, 0.5, 0.0), Vector3(2.0, 1.55, 1.9)],
			[tp + Vector3(1.5, -1.3, 0.5), Vector3(1.5, 1.05, 1.4)],
			[tp + Vector3(-1.3, -1.9, -0.8), Vector3(1.5, 1.0, 1.4)],
			[tp + Vector3(-0.4, -0.8, 1.4), Vector3(1.3, 0.95, 1.2)],
			[tp + Vector3(0.6, -2.9, -1.2), Vector3(1.15, 0.8, 1.1)],
		]
		var bi := 0
		for b in blobs:
			k.sphere(b[0], b[1], 7, 4, _c(top, 1.0), _c(bot, 0.8), Basis.from_euler(Vector3(0, bi * 1.3, 0)), 0.22, seed_v + bi)
			k.cyl(Vector3(tp.x * 0.8, (b[0] as Vector3).y - 1.1, tp.z * 0.8), b[0] - Vector3(0, 0.5, 0), 0.07, 0.03, 3, _c(high, 0.3))
			bi += 1
		k.cyl(centers[3], centers[3] + Vector3(1.0, 0.35, -0.5), 0.045, 0.012, 3, _c(low, 0.2))
		k.cyl(centers[2], centers[2] + Vector3(-0.8, 0.25, 0.6), 0.05, 0.012, 3, _c(low, 0.2))
	else:
		var centers := _trunk(k, [-0.5, 6.0, 12.4], 0.27, 0.08, 3, col_fn, 0.45, seed_v)
		var tp: Vector3 = centers[-1]
		var mid := top.lerp(bot, 0.25)
		k.sphere(tp + Vector3(0.1, 0.5, 0.0), Vector3(1.75, 1.75, 1.7), 5, 3, _c(mid.lightened(0.06), 1.0), _c(bot, 0.8), Basis.IDENTITY, 0.15, seed_v)
		k.sphere(tp + Vector3(0.4, -1.6, 0.2), Vector3(2.0, 1.45, 1.9), 5, 3, _c(mid, 1.0), _c(bot, 0.8), Basis.from_euler(Vector3(0, 0.6, 0)), 0.15, seed_v + 1)
		k.sphere(tp + Vector3(-0.5, -3.3, -0.3), Vector3(1.5, 1.0, 1.5), 5, 2, _c(mid, 1.0), _c(bot, 0.8), Basis.from_euler(Vector3(0, 1.2, 0)), 0.15, seed_v + 2)
	return k.commit()

static func _plain_birch(lod: int, seed_v := 41) -> ArrayMesh:
	var k := MeshKit.new()
	var white := Color(0.88, 0.87, 0.82)
	var dark := Color(0.17, 0.16, 0.15)
	var col_fn := func(u: float, j: int, i: int) -> Color:
		var d := G.hash2(i, j, seed_v) < (0.5 if u < 0.12 else 0.2)
		return _c(dark if d else white.darkened(G.hash2(j, i, seed_v + 3) * 0.12), u * u * 0.6)
	var gold := Color(0.95, 0.79, 0.20)
	var gold_d := Color(0.74, 0.52, 0.12)
	var lime := Color(0.74, 0.76, 0.24)
	var orange := Color(0.95, 0.62, 0.17)
	if lod == 0:
		var centers := _trunk(k, [-0.4, 0.9, 1.9, 3.0, 4.3, 5.6, 6.9, 8.1, 9.2], 0.17, 0.03, 5, col_fn, 0.5, seed_v)
		var tp: Vector3 = centers[-1]
		var rng := _rng(seed_v + 9)
		var palette := [gold, gold, lime, orange, gold.lightened(0.12), gold.lerp(orange, 0.5), gold]
		# an airy crown: small clumps of leaves spiralling down a tall ovoid, thinning towards the top
		var clumps := []
		var count := 18
		for ci in count:
			var u := float(ci) / (count - 1)
			var ang := ci * 2.39996 + rng.randf_range(-0.35, 0.35)
			var prof := sin(PI * (0.1 + 0.8 * pow(u, 0.8))) * 1.42
			var rr := prof * rng.randf_range(0.5, 1.0)
			var cpos := Vector3(tp.x * 0.7 + cos(ang) * rr, tp.y + 0.45 - u * 4.9 + rng.randf_range(-0.2, 0.2), tp.z * 0.7 + sin(ang) * rr)
			var sz := rng.randf_range(0.5, 0.8) * lerpf(0.78, 1.0, sin(PI * u))
			var radii := Vector3(sz, sz * rng.randf_range(0.7, 0.9), sz * rng.randf_range(0.85, 1.1))
			var colb: Color = palette[rng.randi() % palette.size()]
			colb = colb.darkened(rng.randf_range(0.0, 0.14))
			clumps.append([cpos, radii, colb])
			k.sphere(cpos, radii, 5, 3, _c(colb.lightened(0.06), 1.0), _c(colb.lerp(gold_d, 0.65), 0.85),
				Basis.from_euler(Vector3(rng.randf_range(-0.4, 0.4), rng.randf() * TAU, rng.randf_range(-0.4, 0.4))), 0.3, seed_v + ci)
		# loose leaves round every clump break up the silhouette
		for li in 72:
			var b: Array = clumps[li % clumps.size()]
			var dirv := Vector3(rng.randf_range(-1, 1), rng.randf_range(-0.8, 1), rng.randf_range(-1, 1)).normalized()
			var rad: Vector3 = b[1]
			var cpos := (b[0] as Vector3) + Vector3(dirv.x * rad.x, dirv.y * rad.y, dirv.z * rad.z) * rng.randf_range(0.9, 1.25)
			var u := dirv.cross(Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1))).normalized()
			var w := dirv.cross(u).normalized().lerp(dirv, 0.35).normalized()
			var sz := rng.randf_range(0.13, 0.25)
			var lc: Color = (b[2] as Color).lerp(palette[rng.randi() % palette.size()], 0.5)
			lc = _c(lc.lightened(rng.randf_range(0.0, 0.14)), 1.0)
			var i0 := k.vert(cpos - u * sz, dirv, lc)
			var i1 := k.vert(cpos + w * sz * 0.9, dirv, lc)
			var i2 := k.vert(cpos + u * sz, dirv, lc)
			var i3 := k.vert(cpos - w * sz * 0.9, dirv, _c(lc.darkened(0.2), 1.0))
			k.quad(i0, i1, i2, i3)
			k.quad(i3, i2, i1, i0)
		# a few slender branches reaching out to the lower clumps
		for bi2 in [6, 9, 11, 13, 15, 17]:
			var target: Vector3 = clumps[bi2][0]
			var from_i := clampi(int(remap(target.y, 0.0, tp.y, 0.0, centers.size() - 1.0)) - 1, 2, centers.size() - 2)
			k.cyl(centers[from_i], target, 0.035, 0.01, 3, _c(white.darkened(0.3), 0.3))
	else:
		var centers := _trunk(k, [-0.4, 4.5, 9.0], 0.17, 0.04, 3, func(u: float, _j: int, _i: int) -> Color: return _c(white.darkened(0.12), u * u * 0.6), 0.5, seed_v)
		var tp: Vector3 = centers[-1]
		k.sphere(tp + Vector3(0.0, -0.5, 0.0), Vector3(1.35, 1.5, 1.35), 5, 3, _c(gold, 1.0), _c(gold_d, 0.85), Basis.IDENTITY, 0.2, seed_v)
		k.sphere(tp + Vector3(0.3, -2.4, 0.2), Vector3(1.7, 1.2, 1.6), 5, 3, _c(gold.lerp(lime, 0.5), 1.0), _c(gold_d, 0.85), Basis.from_euler(Vector3(0, 0.7, 0)), 0.2, seed_v + 1)
		k.sphere(tp + Vector3(-0.3, -3.9, -0.2), Vector3(1.4, 0.95, 1.45), 5, 2, _c(gold.lerp(orange, 0.5), 1.0), _c(gold_d, 0.85), Basis.from_euler(Vector3(0, 1.4, 0)), 0.2, seed_v + 2)
	return k.commit()

# ------------------------------------------------------- trees with foliage
static func _two_surfaces(solid: MeshKit, cards: MeshKit) -> ArrayMesh:
	var mesh := solid.commit()
	cards.commit(null, mesh)
	return mesh

## Card vertex: `at` is the position inside the tile (0..1, v down).
static func _cv(k: MeshKit, p: Vector3, nrm: Vector3, col: Color, tile: Rect2, at: Vector2) -> int:
	return k.vert(p, nrm, col, tile.position + at * tile.size)

## A spruce bough: a tongue of foliage that leaves the trunk, sags under its own
## weight and hangs lower along both edges than down its spine.
## Mark the vertices from `from` on as fine detail (limbs, dead twigs): only a
## pixel or two wide further out, so the foliage shader drops them beyond a few
## tens of metres (see foliage.gdshader).
static func _mark_fine(k: MeshKit, from: int) -> void:
	for i in range(from, k.count()):
		k.uv[i] = Vector2(k.uv[i].x, k.uv[i].y + 1000.0)

## Where a bough is at `s` (0 at the trunk .. 1 at its tip): out along `dirv`,
## rising at first (`rise`), sagging under its weight (`sag`) and turning its
## tip up again (`up`).
static func _bough_at(origin: Vector3, dirv: Vector3, ln: float, rise: float, sag: float, up: float, s: float) -> Vector3:
	return origin + dirv * (ln * s) + Vector3.UP * (ln * (rise * s - sag * s * s + up * s * s * s))

## The spray of twigs on top of a bough: a strip along it, tented so its edges
## hang lower than its spine. One segment: the bough droops and then turns its tip
## up, so its middle lies within a percent or two of its length from the straight
## line between its ends. `trap` gives the strip's half-widths in u at the trunk
## end (x) and at the tip (y), just wide enough for the picture (FloraTextures.spray_trap).
## `flip` mirrors the picture.
static func _bough(k: MeshKit, tile: Rect2, origin: Vector3, az: float, ln: float, wd: float, rise: float, sag: float,
		roll: float, hang: float, col_in: Color, col_tip: Color, sway: float, up := 0.0, flip := false, trap := Vector2(0.5, 0.5)) -> void:
	var dirv := Vector3(cos(az), 0, sin(az))
	var side0 := Vector3(-dirv.z, 0, dirv.x)
	var prev := []
	for r in 2:
		var s := float(r)
		var p := _bough_at(origin, dirv, ln, rise, sag, up, s)
		# the strip's slope: the chord's, so both rows lie in the same tent
		var tang := (dirv + Vector3.UP * (rise - sag + up)).normalized()
		var side := side0.rotated(tang, roll)
		var up_l := side.cross(tang).normalized()
		if up_l.y < 0.0:
			up_l = -up_l
		var half := wd * 0.5
		var w: float = trap.x if r == 0 else trap.y
		var f := w / 0.5
		var uL := 0.5 + w if flip else 0.5 - w
		var uR := 1.0 - uL
		var col := col_in.lerp(col_tip, s)
		var nc := (up_l * 0.55 + dirv * 0.75).normalized()
		var cur := [
			_cv(k, p - (side * half * 0.74 + up_l * half * hang) * f, (nc - side * 0.5).normalized(), _c(col.darkened(0.1), sway * s), tile, Vector2(uL, 1.0 - s)),
			_cv(k, p, nc, _c(col, sway * s), tile, Vector2(0.5, 1.0 - s)),
			_cv(k, p + (side * half * 0.74 - up_l * half * hang) * f, (nc + side * 0.5).normalized(), _c(col.darkened(0.1), sway * s), tile, Vector2(uR, 1.0 - s)),
		]
		if not prev.is_empty():
			k.quad(prev[0], prev[1], cur[1], cur[0])
			k.quad(prev[1], prev[2], cur[2], cur[1])
		prev = cur

## A curtain of twigs hanging under a bough, from `s0` to `s1` along it and
## `depth` deep, turned `swing` radians about the upright so that a second one
## gives the curtain some body. Its foot sways freely in the wind.
static func _curtain(k: MeshKit, tile: Rect2, origin: Vector3, dirv: Vector3, ln: float, rise: float, sag: float, up: float,
		s0: float, s1: float, depth: float, swing: float, col_top: Color, col_bottom: Color, sway: float, bottom := PackedFloat32Array()) -> void:
	var pivot := _bough_at(origin, dirv, ln, rise, sag, up, (s0 + s1) * 0.5)
	var rot := Basis(Vector3.UP, swing)
	var outv := (dirv * 0.75 + Vector3.UP * 0.3).normalized()
	# its lower edge follows the longest twigs (`bottom`: v under evenly spaced columns)
	var nodes := bottom.size() if bottom.size() >= 2 else 3
	var tops := []
	var bots := []
	for ci in nodes:
		var t := ci / float(nodes - 1)
		var s := lerpf(s0, s1, t)
		# the picture's branch runs a little below its top edge: line it up with the bough
		var p := _bough_at(origin, dirv, ln, rise, sag, up, s) + Vector3.UP * depth * 0.07
		var vb: float = bottom[ci] if bottom.size() >= 2 else 0.97
		var k_down := (vb - 0.03) / 0.94
		var q := p + (Vector3.DOWN * depth + dirv * depth * 0.12) * k_down
		tops.append(_cv(k, pivot + rot * (p - pivot), outv, _c(col_top, sway), tile, Vector2(t, 0.03)))
		bots.append(_cv(k, pivot + rot * (q - pivot), outv, _c(col_top.lerp(col_bottom, k_down), lerpf(sway, 1.0, k_down)), tile, Vector2(t, vb)))
	for ci in nodes - 1:
		k.quad(bots[ci], bots[ci + 1], tops[ci + 1], tops[ci])

## A flat card through a rounded clump of foliage (corners: bottom-left, bottom-right,
## top-right, top-left), shaded as part of the clump's ball.
static func _clump_card(k: MeshKit, tile: Rect2, corners: Array, ctr: Vector3, radii: Vector3, col_low: Color, col_high: Color, sway: float) -> void:
	var uvs := [Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0)]
	var ids := []
	for i in 4:
		var p: Vector3 = corners[i]
		var rel := (p - ctr) / radii
		var nrm := (rel + Vector3(0, 0.4, 0)).normalized()
		var col := col_low.lerp(col_high, clampf(rel.y * 0.4 + 0.55, 0.0, 1.0))
		ids.append(_cv(k, p, nrm, _c(col, sway), tile, uvs[i]))
	k.quad(ids[0], ids[1], ids[2], ids[3])

## A Norway spruce. `form` 0: grown in the open, boughs down to the ground;
## 1: a narrow "comb" spruce with long curtains of hanging twigs; 2: grown in
## dense forest, its lower trunk bare but for dead grey twigs.
static func spruce(lod: int, seed_v := 11, form := 0) -> ArrayMesh:
	var base_y: float = [1.2, 1.0, 5.0][form]      # the lowest living bough
	var width: float = [1.0, 0.8, 0.84][form]
	if lod != 0:
		return _plain_spruce(lod, seed_v, base_y, width)
	var solid := MeshKit.new()
	var cards := MeshKit.new()
	var rng := _rng(seed_v)
	var hgt := 13.0 if form == 2 else 12.0
	var bark := Color(0.36, 0.29, 0.24)
	var deep := Color(0.20, 0.28, 0.23)
	var under := Color(0.24, 0.24, 0.20)      # dead inner twigs: dull grey-brown rather than black
	var c_in := Color(0.24, 0.34, 0.28)
	var c_tip := Color(0.34, 0.47, 0.38)
	var c_new := Color(0.41, 0.54, 0.43)
	var limb_c := Color(0.30, 0.25, 0.21)
	var dead_c := Color(0.37, 0.35, 0.32)
	solid.cyl(Vector3(0, -0.5, 0), Vector3(0, hgt * 0.93, 0), 0.25, 0.035, 7, _c(bark, 0.0), _c(bark, 0.4))
	# dead grey twigs on the lower trunk: a few by the ground, a whole bare stretch in the forest
	var fine_from := solid.count()
	var dead_top := base_y - 0.3 if form == 2 else 1.9
	var dy := 0.5
	while dy < dead_top:
		var n := (4 if form == 2 else 1) + rng.randi() % 3
		for i in n:
			var a := rng.randf() * TAU
			var out := Vector3(cos(a), rng.randf_range(-0.45, 0.05), sin(a))
			var dl := rng.randf_range(0.3, 1.25) * (1.0 if rng.randf() > 0.25 else 0.4)
			solid.cyl(Vector3(0, dy, 0) + out * 0.1, Vector3(0, dy, 0) + out * dl, 0.024, 0.005, 3, _c(dead_c.darkened(rng.randf() * 0.2), 0.0))
		dy += rng.randf_range(0.35, 0.6) if form == 2 else rng.randf_range(0.4, 0.8)
	_mark_fine(solid, fine_from)
	# the heart: a slim jagged cone close round the trunk, in the shade of the boughs
	var tiers := 7
	for t in tiers:
		var u := float(t) / (tiers - 1)
		var heart := deep.lerp(c_in, smoothstep(0.6, 1.0, u) * 0.6)
		_tier(solid, lerpf(base_y + 0.5, hgt - 2.5, u), lerpf(0.6, 0.22, pow(u, 0.9)) * width, lerpf(3.0, 2.0, u), 8, rng, heart.lightened(0.02), heart, under, 0.3 + 0.6 * u, t == 0)
	# boughs in whorls, a few missing: long and drooping below, their tips turned up, short
	# and lifted at the top. Each is a woody limb, a spray of twigs on top of it and, in the
	# lower crown, a curtain of twigs hanging from it
	var t_a := FloraTextures.tile_rect(FloraTextures.SPRUCE)
	var t_b := FloraTextures.tile_rect(FloraTextures.SPRUCE_B)
	var t_hang := FloraTextures.tile_rect(FloraTextures.SPRUCE_HANG)
	var trim_a := FloraTextures.spray_trap(FloraTextures.SPRUCE)
	var trim_b := FloraTextures.spray_trap(FloraTextures.SPRUCE_B)
	var hang_foot := FloraTextures.curtain_bottom(FloraTextures.SPRUCE_HANG, 2)
	var levels: int = [14, 15, 11][form]
	var curtain_k: float = [0.42, 0.58, 0.4][form]
	var twist := rng.randf() * TAU
	for lv in levels:
		# whorls crowd together towards the top, so the spire stays dense
		var u := 1.0 - pow(1.0 - float(lv) / (levels - 1), 1.4)
		var y := lerpf(base_y, hgt - 1.25, u) + rng.randf_range(-0.08, 0.08)
		var n_b := 5
		if form == 0 and rng.randf() < 0.6:
			n_b = 6
		elif form == 1 and rng.randf() < 0.5:
			n_b = 4
		twist += 2.4 + rng.randf_range(-0.3, 0.3)
		for b in n_b:
			if u < 0.85 and rng.randf() < 0.1:
				continue
			var a := twist + TAU * b / n_b + rng.randf_range(-0.25, 0.25)
			var ln := lerpf(2.9, 0.62, pow(u, 0.86)) * width * rng.randf_range(0.75, 1.2)
			var rise := lerpf(-0.06, 0.62, u) + rng.randf_range(-0.06, 0.06)
			var sag := lerpf(0.78 if form == 1 else 0.68, 0.2, u) * rng.randf_range(0.85, 1.15)
			var up := lerpf(0.42, 0.08, u) * rng.randf_range(0.7, 1.2)
			var dirv := Vector3(cos(a), 0, sin(a))
			var origin := Vector3(0, y, 0)
			var tipc := c_tip.lerp(c_new, u * 0.6).darkened(rng.randf_range(0.0, 0.12))
			var l0 := _bough_at(origin, dirv, ln, rise, sag, up, 0.0)
			var l2 := l0.lerp(_bough_at(origin, dirv, ln, rise, sag, up, 1.0), 0.88)
			var lr := 0.02 + 0.03 * ln / 2.9
			# the woody limb is only ever seen from below, under the lower crown. It runs
			# straight under the (straight) spray, a few centimetres below it
			if u < 0.5:
				var limb_from := solid.count()
				solid.cyl(l0, l2 + Vector3.DOWN * 0.035, lr, 0.008, 3, _c(limb_c, 0.2), _c(limb_c, 0.6))
				_mark_fine(solid, limb_from)
			var use_a := rng.randf() < 0.5
			_bough(cards, t_a if use_a else t_b, origin, a, ln, ln * rng.randf_range(0.72, 0.9), rise, sag,
				rng.randf_range(-0.25, 0.25), rng.randf_range(0.45, 0.7), c_in, tipc, 0.3 + 0.5 * u, up, rng.randf() < 0.5, trim_a if use_a else trim_b)
			if u < 0.72:
				var depth := ln * curtain_k * rng.randf_range(0.75, 1.2)
				var col_hang := c_in.lerp(tipc, 0.45)
				_curtain(cards, t_hang, origin, dirv, ln, rise, sag, up, 0.12, 0.95, depth, rng.randf_range(-0.2, 0.2), c_in, col_hang, 0.3 + 0.5 * u, hang_foot)
				if ln > 1.7:
					var swing := rng.randf_range(0.45, 0.7) * (1.0 if rng.randf() < 0.5 else -1.0)
					_curtain(cards, t_hang, origin, dirv, ln, rise, sag, up, 0.3, 0.92, depth * 0.8, swing, c_in, col_hang, 0.3 + 0.5 * u, hang_foot)
		# short branches between the whorls fill the crown in near the trunk
		if lv < levels - 2:
			for k in 3:
				var a := rng.randf() * TAU
				var ln := lerpf(2.9, 0.62, pow(u, 0.86)) * width * rng.randf_range(0.4, 0.58)
				var use_b := rng.randf() < 0.5
				_bough(cards, t_b if use_b else t_a, Vector3(0, y + rng.randf_range(0.15, 0.45), 0), a, ln, ln * 0.8,
					lerpf(0.1, 0.6, u), lerpf(0.5, 0.2, u), rng.randf_range(-0.3, 0.3), 0.55, c_in, c_tip.lerp(c_in, 0.3), 0.3 + 0.5 * u, 0.2, rng.randf() < 0.5, trim_b if use_b else trim_a)
	# the top: ever shorter shoots reaching upwards, closing to a slender point
	var top_whorls := [[hgt - 0.98, 0.46], [hgt - 0.68, 0.34], [hgt - 0.4, 0.24], [hgt - 0.16, 0.16]]
	for tw in top_whorls:
		twist += 2.4 + rng.randf_range(-0.3, 0.3)
		for b in 3:
			var a := twist + TAU * b / 3.0 + rng.randf_range(-0.2, 0.2)
			var ln: float = tw[1] * rng.randf_range(0.9, 1.1)
			_bough(cards, t_a, Vector3(0, tw[0], 0), a, ln, ln * 0.85, rng.randf_range(0.75, 1.0), 0.15,
				rng.randf_range(-0.2, 0.2), 0.6, c_in.lerp(c_tip, 0.4), c_new, 0.9, 0.0, false, trim_a)
	# the leader itself: only the pointed end of the bough picture, kept narrow
	solid.cyl(Vector3(0, hgt * 0.93, 0), Vector3(0, hgt + 0.3, 0), 0.03, 0.008, 3, _c(bark, 0.5), _c(bark, 1.0))
	for i in 2:
		var a := twist + PI * i / 2.0
		var side := Vector3(cos(a), 0, sin(a)) * 0.085
		var foot := Vector3(0, hgt - 0.25, 0)
		var top := Vector3(0, hgt + 0.55, 0)
		var nrm := Vector3(0, 0.8, 0)
		var i0 := _cv(cards, foot - side, (nrm - side).normalized(), _c(c_tip, 0.9), t_a, Vector2(0.36, 0.16))
		var i1 := _cv(cards, foot + side, (nrm + side).normalized(), _c(c_tip, 0.9), t_a, Vector2(0.64, 0.16))
		var i2 := _cv(cards, top + side, (nrm + side).normalized(), _c(c_new, 1.0), t_a, Vector2(0.64, 0.0))
		var i3 := _cv(cards, top - side, (nrm - side).normalized(), _c(c_new, 1.0), t_a, Vector2(0.36, 0.0))
		cards.quad(i0, i1, i2, i3)
	return _two_surfaces(solid, cards)

static func pine(lod: int, seed_v := 31) -> ArrayMesh:
	if lod != 0:
		return _plain_pine(lod, seed_v)
	var solid := MeshKit.new()
	var cards := MeshKit.new()
	var rng := _rng(seed_v)
	var low := Color(0.40, 0.33, 0.28)
	var high := Color(0.70, 0.44, 0.27)
	var col_fn := func(u: float, _j: int, _i: int) -> Color:
		return _c(low.lerp(high, smoothstep(0.25, 0.6, u)), u * u * 0.5)
	var ys := [-0.5, 1.8, 4.2, 6.8, 8.6, 10.2, 11.5, 12.6]
	var centers := _trunk(solid, ys, 0.27, 0.07, 6, col_fn, 0.45, seed_v)
	var tp: Vector3 = centers[-1]
	# Scots pine: a muted grey-blue-green, lighter than spruce, lighter on top of each layer
	var c_top := Color(0.50, 0.59, 0.47)
	var c_bot := Color(0.29, 0.37, 0.31)
	var tile := FloraTextures.tile_rect(FloraTextures.PINE)
	var crown := Vector3(tp.x, 11.0, tp.z)
	# crooked limbs in the top third, longer below; each kinks up and then levels
	# out, carrying a flat, ragged layer of shoots at its end
	var az := rng.randf() * TAU
	var limbs := 12
	for i in limbs:
		var f := float(i) / (limbs - 1)
		var y := lerpf(7.2, 12.3, pow(f, 0.85)) + rng.randf_range(-0.2, 0.2)
		var from := _on_trunk(centers, ys, y)
		az += 2.39996 + rng.randf_range(-0.45, 0.45)
		var reach := lerpf(3.0, 1.2, f) * rng.randf_range(0.8, 1.15)
		var rise := lerpf(0.22, 0.5, f) + rng.randf_range(-0.08, 0.12)
		var out := Vector3(cos(az), 0, sin(az))
		var elbow := from + out * reach * 0.5 + Vector3(rng.randf_range(-0.2, 0.2), reach * rise, rng.randf_range(-0.2, 0.2))
		var end := elbow + out.rotated(Vector3.UP, rng.randf_range(-0.45, 0.45)) * reach * 0.5 + Vector3(0, reach * rise * 0.2, 0)
		var thick := lerpf(0.085, 0.055, f)
		solid.cyl(from, elbow, thick, thick * 0.7, 4, _c(high, 0.15), _c(high, 0.3))
		solid.cyl(elbow, end, thick * 0.7, 0.022, 4, _c(high, 0.3), _c(high.darkened(0.2), 0.5))
		var width := lerpf(2.7, 1.8, f) * rng.randf_range(0.85, 1.15)
		_needle_layer(cards, tile, end + Vector3(0, 0.1, 0), width, crown, c_top, c_bot, rng)
		# now and then a side branch with a smaller layer of its own
		if rng.randf() < 0.75:
			var sd := out.rotated(Vector3.UP, (1.0 if rng.randf() < 0.5 else -1.0) * rng.randf_range(0.7, 1.2))
			var s0 := from.lerp(elbow, 0.7)
			var s1 := s0 + sd * reach * 0.5 + Vector3(0, reach * rise * 0.45, 0)
			solid.cyl(s0, s1, thick * 0.55, 0.018, 3, _c(high, 0.3), _c(high.darkened(0.2), 0.5))
			_needle_layer(cards, tile, s1 + Vector3(0, 0.08, 0), width * 0.75, crown, c_top, c_bot, rng)
	# the leader ends in a spread of shoots of its own, keeping the top flat-ish
	_needle_layer(cards, tile, tp + Vector3(0, 0.3, 0), 2.2, crown, c_top, c_bot, rng)
	for i in 2:
		var a := az + PI * i + rng.randf_range(-0.5, 0.5)
		_needle_layer(cards, tile, tp + Vector3(cos(a) * 0.9, -0.15, sin(a) * 0.9), 1.8, crown, c_top, c_bot, rng)
	# dead stubs lower down the bole
	for i in 4:
		var from := _on_trunk(centers, ys, rng.randf_range(3.5, 7.0))
		az += 2.1
		solid.cyl(from, from + Vector3(cos(az), rng.randf_range(-0.15, 0.3), sin(az)) * rng.randf_range(0.4, 1.0), 0.04, 0.012, 3, _c(low, 0.1))
	return _two_surfaces(solid, cards)

## A flat, ragged layer of pine shoots around `centre`, `width` across and about
## a third as deep: three cards lying nearly flat and two standing steeply, each
## turned at random, so it reads as a layer from below, from the side and in the
## pictures of distant trees, never as a ball.
static func _needle_layer(k: MeshKit, tile: Rect2, centre: Vector3, width: float, crown: Vector3, c_top: Color, c_bot: Color, rng: RandomNumberGenerator) -> void:
	var thick := width * 0.42
	var out := centre - crown
	out.y *= 0.4
	out = out.normalized() if out.length() > 0.05 else Vector3.UP
	var lit := (out + Vector3(0, 0.6, 0)).normalized()
	for i in 7:
		var steep := i >= 4
		var yaw := rng.randf() * TAU
		var pitch := rng.randf_range(0.95, 1.35) if steep else rng.randf_range(0.15, 0.6)
		var w := width * rng.randf_range(0.78, 1.0)
		var h := thick * rng.randf_range(1.4, 1.8) if steep else width * rng.randf_range(0.62, 0.85)
		var u := Vector3(cos(yaw), 0, sin(yaw))
		var v := (Vector3(-sin(yaw), 0, cos(yaw)) * cos(pitch) + Vector3.UP * sin(pitch)).normalized()
		var c := centre + Vector3(rng.randf_range(-0.15, 0.15) * width, rng.randf_range(-0.3, 0.3) * thick, rng.randf_range(-0.15, 0.15) * width)
		var pts := [c - u * w * 0.5 - v * h * 0.5, c + u * w * 0.5 - v * h * 0.5, c + u * w * 0.5 + v * h * 0.5, c - u * w * 0.5 + v * h * 0.5]
		var uvs := [Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0)]
		var ids := []
		for j in 4:
			var p: Vector3 = pts[j]
			var col := c_bot.lerp(c_top, clampf((p.y - centre.y) / thick * 0.7 + 0.55, 0.0, 1.0))
			ids.append(_cv(k, p, lit, _c(col, 0.9), tile, uvs[j]))
		k.quad(ids[0], ids[1], ids[2], ids[3])

static func birch(lod: int, seed_v := 41) -> ArrayMesh:
	if lod != 0:
		return _plain_birch(lod, seed_v)
	var solid := MeshKit.new()
	var cards := MeshKit.new()
	var rng := _rng(seed_v + 9)
	var white := Color(0.88, 0.87, 0.82)
	var dark := Color(0.17, 0.16, 0.15)
	var col_fn := func(u: float, j: int, _i: int) -> Color:
		return _c(white.darkened(G.hash2(j, 0, seed_v + 3) * 0.07), u * u * 0.6)
	var ys := [-0.4, 0.4, 1.0, 1.6, 2.3, 3.0, 3.8, 4.6, 5.4, 6.2, 7.0, 7.8, 8.6, 9.4]
	var centers := _trunk(solid, ys, 0.165, 0.025, 7, col_fn, 0.5, seed_v)
	var tp: Vector3 = centers[-1]
	# gold, varied only a little from clump to clump: the texture tints leaf by leaf
	var gold := Color(0.93, 0.75, 0.21)
	var shades := [Color(0.93, 0.75, 0.21), Color(0.92, 0.70, 0.19), Color(0.86, 0.78, 0.26), Color(0.95, 0.80, 0.27)]
	var twig_c := Color(0.31, 0.26, 0.25)
	var clump := FloraTextures.tile_rect(FloraTextures.BIRCH)
	var spray := FloraTextures.tile_rect(FloraTextures.BIRCH_SPRAY)
	# the crown: an airy, ragged oval round the upper trunk
	var cc := Vector3(tp.x * 0.55, 6.35, tp.z * 0.55)
	var cr := Vector3(1.75, 3.05, 1.75)
	var az := rng.randf() * TAU
	var n_br := 16
	for i in n_br:
		var f := float(i) / (n_br - 1)
		var y := lerpf(3.0, 8.9, f) + rng.randf_range(-0.15, 0.15)
		var from := _on_trunk(centers, ys, y)
		az += 2.39996 + rng.randf_range(-0.35, 0.35)
		var hh := clampf((y + 0.4 - cc.y) / cr.y, -0.95, 0.95)
		var reach := cr.x * sqrt(1.0 - hh * hh) * rng.randf_range(0.75, 1.05)
		var end := Vector3(cc.x + cos(az) * reach, y + rng.randf_range(0.25, 0.7), cc.z + sin(az) * reach)
		solid.cyl(from, end, 0.034, 0.008, 3, _c(twig_c, 0.2), _c(twig_c, 0.6))
		for t in [0.35, 0.55, 0.75, 0.95]:
			var p: Vector3 = from.lerp(end, t) + Vector3(rng.randf_range(-0.25, 0.25), rng.randf_range(-0.1, 0.3), rng.randf_range(-0.25, 0.25))
			_clump(cards, clump, p, rng.randf_range(0.85, 1.2), cc, shades[rng.randi() % shades.size()], rng)
	# more clumps over the crown's surface, so its outline is full but ragged
	for i in 56:
		var u := rng.randf() * TAU
		var v := rng.randf_range(-0.8, 0.95)
		var ring := sqrt(1.0 - v * v)
		var p := cc + Vector3(cos(u) * ring * cr.x, v * cr.y, sin(u) * ring * cr.z) * rng.randf_range(0.72, 1.0)
		_clump(cards, clump, p, rng.randf_range(0.8, 1.15), cc, shades[rng.randi() % shades.size()], rng)
	# a weeping fringe: a few sprays hanging from the crown's lower edge
	for i in 9:
		var u := TAU * (i + rng.randf_range(-0.3, 0.3)) / 9.0
		var top := cc + Vector3(cos(u) * cr.x * 0.85, -cr.y * 0.42 + rng.randf_range(-0.35, 0.35), sin(u) * cr.z * 0.85)
		_spray(cards, spray, top, u + PI * 0.5 + rng.randf_range(-0.4, 0.4), rng.randf_range(0.6, 0.85), rng.randf_range(0.75, 1.05),
			rng.randf_range(0.1, 0.45), cc, gold.darkened(rng.randf_range(0.0, 0.08)))
	return _two_surfaces(solid, cards)

## A clump of leaves: one card through `centre`, facing roughly out of the crown
## and turned at random, so no two show the same outline.
static func _clump(k: MeshKit, tile: Rect2, centre: Vector3, size: float, crown_c: Vector3, col: Color, rng: RandomNumberGenerator) -> void:
	var out := centre - crown_c
	out.y *= 0.5
	out = out.normalized() if out.length() > 0.05 else Vector3.FORWARD
	var face := (out + Vector3(rng.randf_range(-0.7, 0.7), rng.randf_range(-0.3, 0.7), rng.randf_range(-0.7, 0.7))).normalized()
	var a := face.cross(Vector3.UP)
	if a.length_squared() < 0.01:
		a = Vector3.RIGHT
	a = a.normalized()
	var b := face.cross(a).normalized()
	var spin := rng.randf() * TAU
	var u := (a * cos(spin) + b * sin(spin)) * size * 0.5
	var v := (b * cos(spin) - a * sin(spin)) * size * 0.5
	var lit := (out + Vector3(0, 0.35, 0)).normalized()
	var c0 := _c(col, 1.0)
	var i0 := _cv(k, centre - u - v, lit, c0, tile, Vector2(0, 1))
	var i1 := _cv(k, centre + u - v, lit, c0, tile, Vector2(1, 1))
	var i2 := _cv(k, centre + u + v, lit, c0, tile, Vector2(1, 0))
	var i3 := _cv(k, centre - u + v, lit, c0, tile, Vector2(0, 0))
	k.quad(i0, i1, i2, i3)

## The point on a (bent) trunk at height `y`.
static func _on_trunk(centers: Array, ys: Array, y: float) -> Vector3:
	for i in range(ys.size() - 1):
		if y <= ys[i + 1]:
			return (centers[i] as Vector3).lerp(centers[i + 1], clampf((y - ys[i]) / (ys[i + 1] - ys[i]), 0.0, 1.0))
	return centers[-1]

## A spray of leafy twigs hanging from `top`, swinging a little outwards. It is
## folded down the middle like an open book, so it never vanishes edge-on.
static func _spray(k: MeshKit, tile: Rect2, top: Vector3, az: float, wd: float, hgt: float, tilt: float, crown_mid: Vector3, col: Color) -> void:
	var hd := Vector3(cos(az), 0, sin(az))
	var fold := Vector3(-hd.z, 0, hd.x) * (wd * 0.5 * 0.55)
	var h := hd * (wd * 0.5 * 0.84)
	var out := Vector3(top.x - crown_mid.x, 0, top.z - crown_mid.z)
	out = out.normalized() if out.length() > 0.05 else Vector3(cos(az + 1.57), 0, sin(az + 1.57))
	if fold.dot(out) > 0.0:
		fold = -fold       # the spine of the fold faces outwards
	var bottom := top + Vector3.DOWN * (hgt * cos(tilt)) + out * (hgt * sin(tilt))
	# three columns (left edge, spine, right edge), top and bottom
	var cols := [[-h + fold, 0.0], [Vector3.ZERO, 0.5], [h + fold, 1.0]]
	var ids := []
	for row in 2:
		var base: Vector3 = top if row == 0 else bottom
		var spread := 1.0 if row == 0 else 1.06
		for cdef in cols:
			var p: Vector3 = base + (cdef[0] as Vector3) * spread
			var nrm := ((p - crown_mid) * Vector3(1.0, 0.5, 1.0)).normalized() + Vector3(0, 0.35, 0)
			var c2 := col.darkened(0.06) if row == 0 else col.lightened(0.05)
			ids.append(_cv(k, p, nrm.normalized(), _c(c2, 0.5 if row == 0 else 1.0), tile, Vector2(cdef[1], float(row))))
	k.quad(ids[3], ids[4], ids[1], ids[0])
	k.quad(ids[4], ids[5], ids[2], ids[1])

static func snag(lod: int, seed_v := 51) -> ArrayMesh:
	var k := MeshKit.new()
	var grey := Color(0.52, 0.50, 0.46)
	var col_fn := func(u: float, j: int, i: int) -> Color:
		return _c(grey.darkened(G.hash2(i, j, seed_v) * 0.3), 0.0)
	if lod == 0:
		var centers := _trunk(k, [-0.4, 1.5, 3.2, 5.0, 6.4, 7.2], 0.24, 0.09, 6, col_fn, 0.3, seed_v)
		k.cyl(centers[2], centers[2] + Vector3(1.3, 0.7, 0.2), 0.06, 0.015, 3, _c(grey, 0.0))
		k.cyl(centers[3], centers[3] + Vector3(-1.0, 0.9, -0.6), 0.055, 0.012, 3, _c(grey, 0.0))
		k.cyl(centers[4], centers[4] + Vector3(0.3, 0.8, 1.0), 0.045, 0.01, 3, _c(grey, 0.0))
	else:
		_trunk(k, [-0.4, 3.5, 7.2], 0.24, 0.09, 3, col_fn, 0.3, seed_v)
	return k.commit()

## Juniper (einer): a few stems rising from one root, leaning apart and clothed in
## upright, blue-green sprays - taller than wide, ragged at the top. Built like the
## young spruce: thin solid stems, foliage cards from the spruce tiles.
static func juniper(seed_v := 61) -> ArrayMesh:
	var solid := MeshKit.new()
	var cards := MeshKit.new()
	var rng := _rng(seed_v)
	var bark := Color(0.33, 0.27, 0.22)
	var c_in := Color(0.16, 0.24, 0.17)
	var c_tip := Color(0.31, 0.40, 0.30)
	var t_a := FloraTextures.tile_rect(FloraTextures.SPRUCE)
	var t_b := FloraTextures.tile_rect(FloraTextures.SPRUCE_B)
	var trim_a := FloraTextures.spray_trap(FloraTextures.SPRUCE)
	var trim_b := FloraTextures.spray_trap(FloraTextures.SPRUCE_B)
	var a0 := rng.randf() * TAU
	for st in 4:
		var a := a0 + TAU * st / 4.0 + rng.randf_range(-0.4, 0.4)
		var h := rng.randf_range(0.8, 1.15) * (1.0 if st == 0 else 0.75)
		var top := Vector3(cos(a), 0, sin(a)) * rng.randf_range(0.15, 0.3) + Vector3(0, h, 0)
		solid.cyl(Vector3(0, -0.1, 0), top, 0.035, 0.01, 3, _c(bark, 0.0), _c(bark, 0.4))
		var n := 8
		for i in n:
			var u := (i + rng.randf_range(0.2, 0.8)) / n
			var o := Vector3(0, -0.05, 0).lerp(top, lerpf(0.05, 0.95, u))
			var ln := lerpf(0.62, 0.3, u) * rng.randf_range(0.8, 1.2)
			var use_a := rng.randf() < 0.5
			# sprays fanning up and out all round, densest low down: a rounded, bushy cone
			_bough(cards, t_a if use_a else t_b, o, a + rng.randf_range(-1.8, 1.8), ln, ln * 1.05, rng.randf_range(0.25, 0.75), 0.1,
				rng.randf_range(-0.6, 0.6), 0.45, c_in, c_tip, 0.35 + 0.4 * u, 0.12, rng.randf() < 0.5, trim_a if use_a else trim_b)
	return _two_surfaces(solid, cards)

## Dwarf birch (dvergbjørk): a low, dense mound of small leaves gone red, orange and
## gold in autumn over a few wiry twigs, knee high and wider than tall.
static func dwarf_birch(seed_v := 63) -> ArrayMesh:
	var solid := MeshKit.new()
	var cards := MeshKit.new()
	var rng := _rng(seed_v)
	var twig_c := Color(0.30, 0.22, 0.18)
	var shades := [Color(0.80, 0.30, 0.12), Color(0.86, 0.46, 0.15), Color(0.70, 0.22, 0.13), Color(0.88, 0.63, 0.20), Color(0.62, 0.30, 0.14)]
	var clump := FloraTextures.tile_rect(FloraTextures.BIRCH)
	var cc := Vector3(0, 0.12, 0)
	var cr := Vector3(0.7, 0.42, 0.62)
	for i in 6:
		var a := TAU * i / 6.0 + rng.randf_range(-0.3, 0.3)
		var end := Vector3(cos(a) * cr.x * 0.9, rng.randf_range(0.18, 0.4), sin(a) * cr.z * 0.9)
		solid.cyl(Vector3(0, -0.05, 0), end, 0.018, 0.006, 3, _c(twig_c, 0.1), _c(twig_c, 0.5))
	for i in 36:
		var u := rng.randf() * TAU
		var v := rng.randf_range(-0.1, 0.95)
		var ring := sqrt(1.0 - v * v)
		var p := cc + Vector3(cos(u) * ring * cr.x, v * cr.y, sin(u) * ring * cr.z) * rng.randf_range(0.6, 1.0)
		_clump(cards, clump, p, rng.randf_range(0.36, 0.5), cc - Vector3(0, 0.2, 0), shades[rng.randi() % shades.size()], rng)
	return _two_surfaces(solid, cards)

## A boulder, ice-rounded with a few flat faces where it once split. `detail` is the
## icosphere level: 2 (320 triangles, smooth) up close, 1 (80) further out - the same
## shape sampled more coarsely, so the switch does not show. The surface (grain,
## lichen, moss, the damp foot) is drawn by rock.gdshader; vertex colour only darkens
## the hollows, vertex alpha 0 keeps it out of the wind.
static func rock(seed_v := 71, detail := 2) -> ArrayMesh:
	var k := MeshKit.new()
	var rng := _rng(seed_v)
	var ico := _icosphere(detail)
	var dirs: Array = ico[0]
	var tris: PackedInt32Array = ico[1]
	var nz := FastNoiseLite.new()
	nz.seed = seed_v
	nz.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	nz.fractal_type = FastNoiseLite.FRACTAL_NONE
	nz.frequency = 1.0
	var radii := Vector3(1.0, 0.72, 0.86)
	# fracture faces, mostly round the sides and over the top
	var cuts: Array = []
	for i in 3:
		var a := rng.randf() * TAU
		cuts.append([Vector3(cos(a), rng.randf_range(-0.1, 0.8), sin(a)).normalized(), rng.randf_range(0.58, 0.74)])
	var basis := Basis.from_euler(Vector3(rng.randf_range(-0.2, 0.2), rng.randf() * TAU, rng.randf_range(-0.2, 0.2)))
	var base := k.count()
	var i_start := k.idx.size()
	for d: Vector3 in dirs:
		var bump := nz.get_noise_3dv(d * 1.2) * 0.15 + nz.get_noise_3dv(d * 2.9 + Vector3(5.1, 1.7, 3.3)) * 0.06
		var p := Vector3(d.x * radii.x, d.y * radii.y, d.z * radii.z) * (1.0 + bump)
		for cu in cuts:
			var cn: Vector3 = cu[0]
			var s := p.dot(cn) - float(cu[1])
			if s > 0.0:
				p -= cn * s * 0.9
		if p.y < -0.42:                       # sits flat in the ground
			p.y = lerpf(p.y, -0.42, 0.8)
		var hollow := lerpf(0.74, 1.0, clampf(0.55 + bump * 3.5, 0.0, 1.0))
		k.vert(Vector3(0, 0.25, 0) + basis * p, basis * d, Color(hollow, hollow, hollow, 0.0))
	for t in range(0, tris.size(), 3):
		k.tri(base + tris[t], base + tris[t + 1], base + tris[t + 2])
	k.smooth_normals(base, i_start)
	return k.commit()

## Unit icosphere: [Array of Vector3 points, triangle indices CCW from outside].
static func _icosphere(detail: int) -> Array:
	var g := (1.0 + sqrt(5.0)) * 0.5
	var pts: Array = []
	for q in [Vector3(-1, g, 0), Vector3(1, g, 0), Vector3(-1, -g, 0), Vector3(1, -g, 0),
			Vector3(0, -1, g), Vector3(0, 1, g), Vector3(0, -1, -g), Vector3(0, 1, -g),
			Vector3(g, 0, -1), Vector3(g, 0, 1), Vector3(-g, 0, -1), Vector3(-g, 0, 1)]:
		pts.append((q as Vector3).normalized())
	var f := PackedInt32Array([0, 11, 5, 0, 5, 1, 0, 1, 7, 0, 7, 10, 0, 10, 11, 1, 5, 9, 5, 11, 4,
		11, 10, 2, 10, 7, 6, 7, 1, 8, 3, 9, 4, 3, 4, 2, 3, 2, 6, 3, 6, 8, 3, 8, 9, 4, 9, 5,
		2, 4, 11, 6, 2, 10, 8, 6, 7, 9, 8, 1])
	for level in detail:
		var mids := {}
		var nf := PackedInt32Array()
		for i in range(0, f.size(), 3):
			var m := PackedInt32Array()
			for e in 3:
				var a := f[i + e]
				var b := f[i + (e + 1) % 3]
				var key := mini(a, b) * 100000 + maxi(a, b)
				if not mids.has(key):
					mids[key] = pts.size()
					pts.append(((pts[a] as Vector3) + (pts[b] as Vector3)).normalized())
				m.append(mids[key])
			nf.append_array([f[i], m[0], m[2], f[i + 1], m[1], m[0], f[i + 2], m[2], m[1], m[0], m[1], m[2]])
		f = nf
	for i in range(0, f.size(), 3):
		var p0: Vector3 = pts[f[i]]
		if (pts[f[i + 1]] - p0).cross(pts[f[i + 2]] - p0).dot(p0) < 0.0:
			var tmp := f[i + 1]
			f[i + 1] = f[i + 2]
			f[i + 2] = tmp
	return [pts, f]

static func log_mesh(seed_v := 81) -> ArrayMesh:
	var k := MeshKit.new()
	var bark := Color(0.37, 0.30, 0.24, 0.0)
	k.cyl(Vector3(-2.6, 0.16, 0), Vector3(2.6, 0.2, 0.15), 0.24, 0.17, 7, bark, bark, true, true)
	k.cyl(Vector3(0.6, 0.25, 0.05), Vector3(1.0, 0.85, 0.5), 0.05, 0.02, 3, bark)
	var moss := Color(0.36, 0.45, 0.20)
	k.recolor(0, func(_p: Vector3, nrm: Vector3, col: Color) -> Color:
		var c2 := col.lerp(moss, smoothstep(0.5, 0.9, nrm.y) * 0.85)
		return Color(c2.r, c2.g, c2.b, 0.0))
	return k.commit()

# ----------------------------------------------------------- ground cover
static func grass_tuft(seed_v := 91) -> ArrayMesh:
	var k := MeshKit.new()
	var rng := _rng(seed_v)
	for i in 12:
		var a := rng.randf() * TAU
		var dirv := Vector3(cos(a), 0, sin(a))
		var side := Vector3(-dirv.z, 0, dirv.x)
		var root := dirv * rng.randf_range(0.02, 0.24) + side * rng.randf_range(-0.09, 0.09)
		var hgt := rng.randf_range(0.22, 0.56) * (0.7 if i % 3 == 0 else 1.0)
		var w := rng.randf_range(0.014, 0.025)
		var lean := rng.randf_range(0.05, 0.3)
		var base_c := Color(0.36, 0.38, 0.30, 0.0)
		var tip_c := Color(0.92, 0.90, 0.76, 1.0)
		var mid := root + dirv * lean * 0.38 + Vector3(0, hgt * 0.58, 0)
		var i0 := k.vert(root - side * w, Vector3.UP, base_c)
		var i1 := k.vert(root + side * w, Vector3.UP, base_c)
		var i2 := k.vert(mid - side * w * 0.72, Vector3.UP, base_c.lerp(tip_c, 0.62))
		var i3 := k.vert(mid + side * w * 0.72, Vector3.UP, base_c.lerp(tip_c, 0.62))
		var i4 := k.vert(root + dirv * lean + Vector3(0, hgt, 0), Vector3.UP, tip_c)
		k.quad(i0, i1, i3, i2)
		k.tri(i2, i3, i4)
	return k.commit()

static func fern(seed_v := 101) -> ArrayMesh:
	var k := MeshKit.new()
	var rng := _rng(seed_v)
	for i in 6:
		var a := TAU * i / 6.0 + rng.randf_range(-0.3, 0.3)
		var dirv := Vector3(cos(a), 0, sin(a))
		var side := Vector3(-dirv.z, 0, dirv.x)
		var length := rng.randf_range(0.55, 0.85)
		var base_c := Color(0.5, 0.5, 0.4, 0.0)
		var tip_c := Color(1.0, 0.95, 0.8, 1.0)
		var pts := [
			[Vector3(0, 0.02, 0), 0.03, 0.0],
			[dirv * length * 0.4 + Vector3(0, 0.34, 0), 0.15, 0.5],
			[dirv * length * 0.78 + Vector3(0, 0.36, 0), 0.10, 0.85],
			[dirv * length + Vector3(0, 0.22, 0), 0.0, 1.0],
		]
		var prev := []
		for p in pts:
			var col: Color = base_c.lerp(tip_c, p[2])
			var cur := [k.vert(p[0] - side * p[1], Vector3.UP, col), k.vert(p[0] + side * p[1], Vector3.UP, col)]
			if prev.size() > 0:
				k.quad(prev[0], prev[1], cur[1], cur[0])
			prev = cur
	return k.commit()

## Low leafy clump: blueberry, lingonberry, heather.
static func shrub(seed_v := 111) -> ArrayMesh:
	var k := MeshKit.new()
	var rng := _rng(seed_v)
	var base_c := Color(0.42, 0.42, 0.36, 0.0)
	var tip_c := Color(1.0, 1.0, 0.92, 1.0)
	for ring_i in 2:
		var count := 8 if ring_i == 0 else 5
		for i in count:
			var a := TAU * i / count + rng.randf_range(-0.3, 0.3)
			var dirv := Vector3(cos(a), 0, sin(a))
			var side := Vector3(-dirv.z, 0, dirv.x)
			var reach := rng.randf_range(0.2, 0.34) * (1.0 if ring_i == 0 else 0.55)
			var lift := rng.randf_range(0.1, 0.2) * (1.0 if ring_i == 0 else 1.7)
			var w := rng.randf_range(0.07, 0.11)
			var root := dirv * 0.03
			var mid := dirv * reach * 0.6 + Vector3(0, lift, 0)
			var tip := dirv * reach + Vector3(0, lift * 0.8, 0)
			var i0 := k.vert(root, Vector3.UP, base_c)
			var i1 := k.vert(mid - side * w, Vector3.UP, base_c.lerp(tip_c, 0.7))
			var i2 := k.vert(mid + side * w, Vector3.UP, base_c.lerp(tip_c, 0.7))
			var i3 := k.vert(tip, Vector3.UP, tip_c)
			k.tri(i0, i2, i1)
			k.tri(i1, i2, i3)
	return k.commit()

static func reed(seed_v := 121) -> ArrayMesh:
	var k := MeshKit.new()
	var rng := _rng(seed_v)
	for i in 7:
		var a := rng.randf() * TAU
		var dirv := Vector3(cos(a), 0, sin(a))
		var side := Vector3(-dirv.z, 0, dirv.x)
		var root := Vector3(rng.randf_range(-0.25, 0.25), -0.3, rng.randf_range(-0.25, 0.25))
		var hgt := rng.randf_range(1.2, 1.9)
		var w := 0.022
		var base_c := Color(0.5, 0.55, 0.4, 0.0)
		var tip_c := Color(1.0, 1.0, 0.85, 1.0)
		var top := root + dirv * rng.randf_range(0.05, 0.3) + Vector3(0, hgt, 0)
		var i0 := k.vert(root - side * w, Vector3.UP, base_c)
		var i1 := k.vert(root + side * w, Vector3.UP, base_c)
		var i2 := k.vert(top, Vector3.UP, tip_c)
		k.tri(i0, i1, i2)
		if i % 3 == 0:
			var head := Color(0.34, 0.2, 0.12, 0.9)
			k.cyl(top - Vector3(0, 0.36, 0), top - Vector3(0, 0.12, 0), 0.028, 0.028, 4, head, head, true, true)
	return k.commit()
