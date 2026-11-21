class_name FloraTextures
extends RefCounted
## Painted-in-code textures for the trees' foliage, in one atlas of 4 x 2 tiles:
## two spruce boughs seen from above, a curtain of spruce twigs hanging under a
## bough, a cluster of pine shoots, a clump of birch leaves and a hanging spray
## of birch twigs. Alpha is the shape; red and green hold light and dark; blue
## is each leaf's own tint (128 = none), so a crown is mottled leaf by leaf
## rather than card by card. The hue itself comes from the mesh.
##
## The smaller copies (mipmaps) are made here rather than by the engine: they
## keep the share of each tile that passes the alpha cut-off, so the gaps
## between leaves stay open with distance instead of silting up until each card
## reads as one big solid leaf. Painting and shrinking take a couple of seconds,
## so the result is cached under user://.

const TILE := 512
const COLS := 4
const ROWS := 2
const VERSION := 9
const CUT := 0.5               ## the cards' alpha cut-off (foliage_card.gdshader)
const SPRUCE := 0              ## a spruce bough seen from above, the trunk end at the bottom
const PINE := 1
const BIRCH := 2               ## a round clump of leaves
const BIRCH_SPRAY := 3         ## twigs hanging from the top of the tile
const SPRUCE_B := 4            ## a second spruce bough, denser, its twigs swept further forward
const SPRUCE_HANG := 5         ## spruce twigs hanging from a branch along the top, the trunk end on the left
const TILES := 6

static var _atlas: ImageTexture
static var _img: Image          ## the atlas with its mipmaps, kept for measuring the tiles' shapes
static var _shapes := {}

## UV rectangle of a tile in the atlas.
static func tile_rect(tile: int) -> Rect2:
	return Rect2(float(tile % COLS) / COLS, float(tile / COLS) / ROWS, 1.0 / COLS, 1.0 / ROWS)

static func atlas() -> ImageTexture:
	if _atlas:
		return _atlas
	var path := "user://flora_cards_v%d.bin" % VERSION
	var w := TILE * COLS
	var h := TILE * ROWS
	var img: Image = null
	if FileAccess.file_exists(path) and not G.args.has("nocache"):
		var f := FileAccess.open_compressed(path, FileAccess.READ, FileAccess.COMPRESSION_ZSTD)
		if f:
			var fw := f.get_32()
			var fh := f.get_32()
			var bytes := f.get_buffer(f.get_32())
			if fw == w and fh == h and bytes.size() == _chain_bytes(w, h):
				img = Image.create_from_data(w, h, true, Image.FORMAT_RGBA8, bytes)
	if img == null:
		var cover := PackedFloat32Array()
		img = _coverage_mips(build_image(cover), cover)
		var f := FileAccess.open_compressed(path, FileAccess.WRITE, FileAccess.COMPRESSION_ZSTD)
		if f:
			var bytes := img.get_data()
			f.store_32(w)
			f.store_32(h)
			f.store_32(bytes.size())
			f.store_buffer(bytes)
			f.close()
		for old in range(1, VERSION):
			for ext in ["png", "bin"]:
				var p := "user://flora_cards_v%d.%s" % [old, ext]
				if FileAccess.file_exists(p):
					DirAccess.remove_absolute(ProjectSettings.globalize_path(p))
	_img = img
	_atlas = ImageTexture.create_from_image(img)
	return _atlas

# ------------------------------------------------------------------ shapes
## Cards are cut to the shape of what is painted on them, so the graphics card
## does not shade (and throw away) the empty corners. The shapes are measured
## on the atlas's quarter-size copy, where a painted pixel anywhere in a 4 x 4
## block still shows: the cut can never clip a needle.
static func _solid_rows(tile: int) -> Array:
	var key := "rows_%d" % tile
	if _shapes.has(key):
		return _shapes[key]
	atlas()
	var level := 2
	var ts := TILE >> level
	var w := (TILE * COLS) >> level
	var off := _img.get_mipmap_offset(level)
	var data := _img.get_data()
	var x0 := (tile % COLS) * ts
	var y0 := (tile / COLS) * ts
	# per row: leftmost and rightmost painted pixel (as u), or -1 if the row is empty;
	# per column: the lowest painted pixel (as v)
	var lo := PackedFloat32Array()
	var hi := PackedFloat32Array()
	var bottom := PackedFloat32Array()
	lo.resize(ts)
	hi.resize(ts)
	bottom.resize(ts)
	bottom.fill(-1.0)
	for y in ts:
		lo[y] = -1.0
		hi[y] = -1.0
		var row := off + ((y0 + y) * w + x0) * 4 + 3
		for x in ts:
			if data[row + x * 4] > 0:
				if lo[y] < 0.0:
					lo[y] = float(x) / ts
				hi[y] = float(x + 1) / ts
				bottom[x] = float(y + 1) / ts
	var out := [lo, hi, bottom, ts]
	_shapes[key] = out
	return out

## The narrowest trapezoid that holds everything painted on a bough tile: its
## half-widths in u at the trunk end (x) and at the tip (y), the edges straight
## between them. A bough strip of one segment uses it.
static func spray_trap(tile: int) -> Vector2:
	var key := "trap_%d" % tile
	if _shapes.has(key):
		return _shapes[key]
	var m: Array = _solid_rows(tile)
	var lo: PackedFloat32Array = m[0]
	var hi: PackedFloat32Array = m[1]
	var ts: int = m[3]
	var margin := 1.5 / ts
	var rows := []
	for y in ts:
		if lo[y] >= 0.0:
			# v runs from 0 at the tip (top of the tile) to 1 at the trunk end
			rows.append([(y + 0.5) / ts, minf(maxf(0.5 - lo[y], hi[y] - 0.5) + margin, 0.5)])
	var best := Vector2(0.5, 0.5)
	var best_sum := 1.0
	var wt := 0.0
	while wt <= 0.5001:
		var wb := 0.0
		for r in rows:
			var v: float = r[0]
			var need: float = r[1]
			if v > 0.001:
				wb = maxf(wb, (need - wt * (1.0 - v)) / v)
			elif need > wt:
				wb = 99.0
		if wb <= 0.5 and wt + wb < best_sum:
			best_sum = wt + wb
			best = Vector2(wb, wt)
		wt += 0.005
	_shapes[key] = best
	return best

## The lowest painted point of a hanging-twig tile under each of `nodes` evenly
## spaced columns, such that straight lines between them pass below everything.
static func curtain_bottom(tile: int, nodes: int) -> PackedFloat32Array:
	var m: Array = _solid_rows(tile)
	var bottom: PackedFloat32Array = m[2]
	var ts: int = m[3]
	var out := PackedFloat32Array()
	for i in nodes:
		# the deepest point over the neighbouring stretches
		var u0 := float(i - 1) / (nodes - 1)
		var u1 := float(i + 1) / (nodes - 1)
		var deepest := 0.0
		for x in ts:
			var u := (x + 0.5) / ts
			if u >= u0 - 1.0 / ts and u <= u1 + 1.0 / ts:
				deepest = maxf(deepest, bottom[x])
		out.append(clampf(deepest + 1.5 / ts, 0.05, 1.0))
	return out

## Bytes in an RGBA8 image of w x h with all its mipmaps.
static func _chain_bytes(w: int, h: int) -> int:
	var total := 0
	var lw := w
	var lh := h
	while true:
		total += lw * lh * 4
		if lw <= 1 and lh <= 1:
			break
		lw = maxi(lw / 2, 1)
		lh = maxi(lh / 2, 1)
	return total

## The full-size atlas. `cover` receives each tile's share of solid pixels.
static func build_image(cover := PackedFloat32Array()) -> Image:
	var out := Image.create(TILE * COLS, TILE * ROWS, false, Image.FORMAT_RGBA8)
	out.fill(Color(0.7, 0.7, 0.5, 0.0))
	cover.resize(COLS * ROWS)
	for tile in TILES:
		var c := Canvas.new(TILE)
		var rng := RandomNumberGenerator.new()
		rng.seed = 4100 + tile * 77
		match tile:
			SPRUCE: _paint_spruce(c, rng, 0)
			SPRUCE_B: _paint_spruce(c, rng, 1)
			SPRUCE_HANG: _paint_spruce_curtain(c, rng)
			PINE: _paint_pine(c, rng)
			BIRCH: _paint_birch_clump(c, rng)
			BIRCH_SPRAY: _paint_birch_spray(c, rng)
		var part := c.to_image()
		cover[tile] = c.cover
		out.blit_rect(part, Rect2i(0, 0, TILE, TILE), Vector2i((tile % COLS) * TILE, (tile / COLS) * TILE))
	return out

# ---------------------------------------------------------------- mipmaps
## A full mip chain in which every tile keeps the share of pixels at or above
## the cut-off (`cover`, per tile). Each level is a plain 2 x 2 average of the
## one above, then its alpha is raised just enough to bring the share back.
static func _coverage_mips(base: Image, cover: PackedFloat32Array) -> Image:
	var w := base.get_width()
	var h := base.get_height()
	var cut := int(CUT * 255.0)
	var out := base.get_data()
	var prev := base
	var lw := w
	var lh := h
	var ts := TILE
	while lw > 1 or lh > 1:
		lw = maxi(lw / 2, 1)
		lh = maxi(lh / 2, 1)
		ts = maxi(ts / 2, 1)
		var lvl: Image = prev.duplicate()
		lvl.resize(lw, lh, Image.INTERPOLATE_BILINEAR)
		prev = lvl
		var data := lvl.get_data()
		if ts >= 4:
			data = _boost(data, lw, ts, cut, cover)
		out.append_array(data)
	return Image.create_from_data(w, h, true, Image.FORMAT_RGBA8, out)

## Raise the alpha of each tile (ts x ts pixels at this level, in an image w wide).
static func _boost(data: PackedByteArray, w: int, ts: int, cut: int, cover: PackedFloat32Array) -> PackedByteArray:
	for tile in cover.size():
		if cover[tile] <= 0.0:
			continue
		var x0 := (tile % COLS) * ts
		var y0 := (tile / COLS) * ts
		var hist := PackedInt32Array()
		hist.resize(256)
		for y in range(y0, y0 + ts):
			var row := (y * w + x0) * 4 + 3
			for x in ts:
				hist[data[row + x * 4]] += 1
		# the alpha that the wanted share of pixels reach or pass
		var need := int(cover[tile] * ts * ts)
		var acc := 0
		var a := 255
		while a > 1:
			acc += hist[a]
			if acc >= need:
				break
			a -= 1
		var scale := clampf(float(cut) / float(maxi(a, 1)), 1.0, 8.0)
		if scale <= 1.001:
			continue
		for y in range(y0, y0 + ts):
			var row := (y * w + x0) * 4 + 3
			for x in ts:
				var i := row + x * 4
				data[i] = mini(255, int(data[i] * scale))
	return data

# ------------------------------------------------------------------ canvas
## Brightness, tint and alpha, with a few stamping tools.
class Canvas:
	var n: int
	var lum := PackedByteArray()
	var tint := PackedByteArray()
	var alpha := PackedByteArray()
	var cover := 0.0

	func _init(size: int) -> void:
		n = size
		lum.resize(n * n)
		tint.resize(n * n)
		tint.fill(128)
		alpha.resize(n * n)

	func px(x: int, y: int, l: int, h := 128) -> void:
		if x < 0 or y < 0 or x >= n or y >= n:
			return
		var i := y * n + x
		lum[i] = l
		tint[i] = h
		alpha[i] = 255

	func disc(cx: float, cy: float, r: float, l: int, h := 128) -> void:
		var r2 := r * r
		for y in range(int(floor(cy - r)), int(ceil(cy + r)) + 1):
			var dy := y + 0.5 - cy
			for x in range(int(floor(cx - r)), int(ceil(cx + r)) + 1):
				var dx := x + 0.5 - cx
				if dx * dx + dy * dy <= r2:
					px(x, y, l, h)

	## Tapered line from p0 (width w0, brightness l0) to p1.
	func stroke(p0: Vector2, p1: Vector2, w0: float, w1: float, l0: int, l1: int, h := 128) -> void:
		var dv := p1 - p0
		var steps := int(maxf(absf(dv.x), absf(dv.y))) + 1
		for s in steps + 1:
			var t := float(s) / steps
			var cx := p0.x + dv.x * t
			var cy := p0.y + dv.y * t
			var w := lerpf(w0, w1, t)
			var l := int(lerpf(l0, l1, t))
			if w < 1.4:
				px(int(cx), int(cy), l, h)
			elif w < 2.4:
				var x := int(cx)
				var y := int(cy)
				px(x, y, l, h)
				px(x + 1, y, l, h)
				px(x, y + 1, l, h)
				px(x + 1, y + 1, l, h)
			else:
				disc(cx, cy, w * 0.5, l, h)

	## RGBA: R and G the brightness, B the tint, A the shape. Empty pixels take the
	## average brightness, so the smaller copies don't grow pale or dark rims.
	func to_image() -> Image:
		var total := 0
		var count := 0
		for i in n * n:
			if alpha[i] > 0:
				total += lum[i]
				count += 1
		cover = float(count) / float(n * n)
		var mean := total / maxi(count, 1)
		var data := PackedByteArray()
		data.resize(n * n * 4)
		for i in n * n:
			var o := i * 4
			if alpha[i] > 0:
				data[o] = lum[i]
				data[o + 1] = lum[i]
				data[o + 2] = tint[i]
				data[o + 3] = 255
			else:
				data[o] = mean
				data[o + 1] = mean
				data[o + 2] = 128
		return Image.create_from_data(n, n, false, Image.FORMAT_RGBA8, data)

# ------------------------------------------------------------------ spruce
## A spruce bough seen from above: the trunk end at the bottom of the tile, the
## tip at the top. Side twigs of uneven length, now and then a gap, carry
## smaller twigs of their own; every twig bristles with short needles, lighter
## at its growing tip. `variant` 1 is denser, its twigs swept further forward.
static func _paint_spruce(c: Canvas, rng: RandomNumberGenerator, variant: int) -> void:
	var bend := rng.randf_range(-0.6, 0.6)
	var axis := PackedVector2Array()
	for i in 49:
		var t := i / 48.0
		axis.append(Vector2(256.0 + sin(t * PI * 0.9) * bend * 40.0, lerpf(504.0, 16.0, t)))
	for i in 48:
		var t := i / 48.0
		c.stroke(axis[i], axis[i + 1], lerpf(5.0, 1.6, t), lerpf(5.0, 1.6, t), 84, 104)
	var s := rng.randf_range(0.4, 1.0)
	var side := 1.0 if rng.randf() < 0.5 else -1.0
	while s < 46.5:
		var t := s / 48.0
		var i := int(s)
		var p := axis[i].lerp(axis[i + 1], s - i)
		var along := (axis[i + 1] - axis[i]).normalized()
		side = -side
		if rng.randf() > 0.1:
			var reach := lerpf(0.5, 1.0, smoothstep(0.0, 0.3, t)) * minf(1.0, (1.0 - t) * 1.9)
			var ln := 232.0 * reach * rng.randf_range(0.72, 1.12)
			var ang := deg_to_rad(rng.randf_range(44.0, 68.0) if variant == 0 else rng.randf_range(34.0, 54.0))
			_spruce_twig(c, rng, p, along.rotated(ang * side), ln, rng.randf_range(-0.35, 0.35) * side, 1, variant)
		s += rng.randf_range(0.95, 1.55) if variant == 0 else rng.randf_range(0.75, 1.2)
	_needles(c, rng, axis[1], axis[47], 10.0)

## One twig of a spruce bough, its smaller twigs branching off alternately.
static func _spruce_twig(c: Canvas, rng: RandomNumberGenerator, p: Vector2, dirv: Vector2, ln: float, bend: float, depth: int, variant: int) -> void:
	var heading := dirv.angle()
	var s := 0.0
	var since := 0.0
	var gap := rng.randf_range(16.0, 26.0) if variant == 0 else rng.randf_range(12.0, 19.0)
	var side := 1.0 if rng.randf() < 0.5 else -1.0
	var w0 := 2.4 if depth == 1 else 1.4
	var nl := 10.5 if depth == 1 else 9.0
	while s < ln:
		var step := 4.0
		heading += bend * step / maxf(ln, 1.0) + rng.randf_range(-0.03, 0.03)
		var d := Vector2(cos(heading), sin(heading))
		var q := p + d * step
		if q.x < 14.0 or q.x > TILE - 14.0 or q.y < 14.0 or q.y > TILE - 14.0:
			break
		var t := s / ln
		c.stroke(p, q, lerpf(w0, 1.0, t), lerpf(w0, 1.0, t), 88, 108)
		_needle_pair(c, rng, p + d * 2.0, heading, nl * lerpf(1.0, 0.78, t), t > 0.8, 48.0, 78.0)
		_needle_pair(c, rng, q, heading, nl * lerpf(1.0, 0.78, t), t > 0.8, 48.0, 78.0)
		s += step
		since += step
		if depth == 1 and since > gap and t > 0.1 and t < 0.86:
			since = 0.0
			gap = rng.randf_range(16.0, 26.0) if variant == 0 else rng.randf_range(12.0, 19.0)
			side = -side
			var sub_ln := (ln - s) * rng.randf_range(0.34, 0.55)
			if sub_ln > 14.0:
				_spruce_twig(c, rng, q, d.rotated(side * deg_to_rad(rng.randf_range(36.0, 56.0))), sub_ln, -bend * 0.5, 2, variant)
		p = q
	# the growing tip
	for k in 3:
		var a := heading + rng.randf_range(-0.35, 0.35)
		c.stroke(p, p + Vector2(cos(a), sin(a)) * nl * 0.8, 1.8, 1.0, 200, 245)

## Two needles from `at`, one each side of a twig heading `heading`, angled
## forwards by between `a0` and `a1` degrees; this year's needles are lighter.
static func _needle_pair(c: Canvas, rng: RandomNumberGenerator, at: Vector2, heading: float, length: float, fresh: bool, a0: float, a1: float) -> void:
	for side: float in [-1.0, 1.0]:
		var a: float = heading + side * deg_to_rad(rng.randf_range(a0, a1))
		var l := (200 + rng.randi() % 50) if fresh else (130 + rng.randi() % 85)
		c.stroke(at, at + Vector2(cos(a), sin(a)) * length * rng.randf_range(0.78, 1.15), 1.9, 1.0, l, mini(l + 34, 255))

## Short needles bristling from both sides of a twig, shorter towards its end.
static func _needles(c: Canvas, rng: RandomNumberGenerator, p0: Vector2, p1: Vector2, length: float) -> void:
	var dv := p1 - p0
	var total := dv.length()
	if total < 1.0:
		return
	var heading := dv.angle()
	var s := 0.0
	while s <= total:
		var t := s / total
		_needle_pair(c, rng, p0 + dv / total * s, heading, length * (1.0 - 0.3 * t), t > 0.9, 48.0, 72.0)
		s += 2.1

## Spruce twigs hanging in a curtain from a branch along the top of the tile,
## the trunk end on the left: short by the trunk and at the tip, longest in
## between, each bristling with needles and lighter at its end.
static func _paint_spruce_curtain(c: Canvas, rng: RandomNumberGenerator) -> void:
	var branch := PackedVector2Array()
	for i in 49:
		var t := i / 48.0
		branch.append(Vector2(lerpf(8.0, 504.0, t), 34.0 + 30.0 * sin(PI * t * 0.85) - 22.0 * smoothstep(0.78, 1.0, t)))
	for i in 48:
		var t := i / 48.0
		c.stroke(branch[i], branch[i + 1], lerpf(4.0, 1.6, t), lerpf(4.0, 1.6, t), 84, 104)
	_needles(c, rng, branch[2], branch[47], 9.0)
	var s := rng.randf_range(2.0, 4.0)
	while s < 46.0:
		var t := s / 48.0
		var i := int(s)
		var p := branch[i].lerp(branch[i + 1], s - i)
		if rng.randf() > 0.08:
			var env := pow(sin(PI * pow(t, 0.75)), 0.8)
			var ln := minf(440.0 * env * rng.randf_range(0.6, 1.08), TILE - 18.0 - p.y)
			if ln > 24.0:
				# hanging straight down, swept a little towards the tip
				_hanging_twig(c, rng, p, PI * 0.5 + rng.randf_range(-0.25, 0.08), ln, rng.randf_range(-0.25, 0.25), 1)
		s += rng.randf_range(0.7, 1.15)

## One twig hanging from the branch, now and then forking.
static func _hanging_twig(c: Canvas, rng: RandomNumberGenerator, p: Vector2, heading: float, ln: float, bend: float, depth: int) -> void:
	var s := 0.0
	var since := 0.0
	var gap := rng.randf_range(30.0, 55.0)
	while s < ln:
		var step := 4.0
		heading += bend * step / maxf(ln, 1.0) + rng.randf_range(-0.025, 0.025)
		var d := Vector2(cos(heading), sin(heading))
		var q := p + d * step
		if q.x < 12.0 or q.x > TILE - 12.0 or q.y > TILE - 12.0:
			break
		var t := s / ln
		c.stroke(p, q, lerpf(1.9, 1.0, t), lerpf(1.9, 1.0, t), 86, 104)
		var nl := lerpf(9.5, 7.0, t) * (1.0 if depth == 1 else 0.85)
		_needle_pair(c, rng, p + d * 2.0, heading, nl, t > 0.84, 30.0, 60.0)
		_needle_pair(c, rng, q, heading, nl, t > 0.84, 30.0, 60.0)
		s += step
		since += step
		if depth == 1 and since > gap and t > 0.25 and t < 0.7 and rng.randf() < 0.45:
			since = 0.0
			gap = rng.randf_range(30.0, 55.0)
			var side := 1.0 if rng.randf() < 0.5 else -1.0
			_hanging_twig(c, rng, q, heading + side * rng.randf_range(0.3, 0.5), (ln - s) * rng.randf_range(0.4, 0.65), -bend, 2)
		p = q
	for k in 3:
		var a := heading + rng.randf_range(-0.35, 0.35)
		c.stroke(p, p + Vector2(cos(a), sin(a)) * 7.0, 1.8, 1.0, 200, 245)

# -------------------------------------------------------------------- pine
## Pine shoots seen from above: crooked twigs fanning out from the branch, each
## clothed in long paired needles and ending in a dense brush. Sky shows between
## the shoots; there is no solid middle and no round outline.
static func _paint_pine(c: Canvas, rng: RandomNumberGenerator) -> void:
	var ctr := Vector2(256, 256)
	var shoots := 20
	for i in shoots:
		var heading := TAU * (i + rng.randf_range(-0.45, 0.45)) / shoots
		var p := ctr + Vector2(rng.randf_range(-50.0, 50.0), rng.randf_range(-50.0, 50.0))
		_pine_shoot(c, rng, p, heading, rng.randf_range(80.0, 180.0), rng.randf_range(-1.1, 1.1), 1)
	for i in 13:
		var p := ctr + Vector2(rng.randf_range(-90.0, 90.0), rng.randf_range(-90.0, 90.0))
		_pine_shoot(c, rng, p, rng.randf() * TAU, rng.randf_range(45.0, 95.0), rng.randf_range(-1.0, 1.0), 0)

## One pine shoot: a bare stretch near its base, then needles in pairs angled
## forwards, and a brush of needles at the tip. Forks now and then.
static func _pine_shoot(c: Canvas, rng: RandomNumberGenerator, p: Vector2, heading: float, length: float, bend: float, forks: int) -> void:
	var tint := 128 + rng.randi_range(-24, 24)
	var s := 0.0
	var since := 0.0
	var ctr := Vector2(TILE * 0.5, TILE * 0.5)
	while s < length:
		# stop short of the tile's edge, leaving room for the needles and the brush
		if p.distance_to(ctr) > 186.0:
			break
		var step := 4.0
		heading += bend * step / length + rng.randf_range(-0.04, 0.04)
		var dirv := Vector2(cos(heading), sin(heading))
		var q := p + dirv * step
		var t := s / length
		c.stroke(p, q, lerpf(2.6, 1.6, t), lerpf(2.6, 1.6, t), 92, 104)
		s += step
		since += step
		if t > 0.1 and since >= 2.6:
			since = 0.0
			for side in [-1.0, 1.0]:
				var nd := dirv.rotated(side * deg_to_rad(rng.randf_range(24.0, 58.0)))
				var nl := rng.randf_range(34.0, 54.0) * lerpf(0.8, 1.0, t)
				var l := 118 + rng.randi() % 70
				c.stroke(q, q + nd * nl, 1.8, 1.0, l, mini(l + 40, 255), tint)
		if forks > 0 and t > 0.3 and t < 0.75 and rng.randf() < 0.035 and q.distance_to(ctr) < 150.0:
			_pine_shoot(c, rng, q, heading + (1.0 if rng.randf() < 0.5 else -1.0) * rng.randf_range(0.45, 0.8), (length - s) * rng.randf_range(0.5, 0.8), -bend * 0.6, forks - 1)
		p = q
	# the brush at the tip, around this year's bud
	var dirv := Vector2(cos(heading), sin(heading))
	for k in 24:
		var nd := dirv.rotated(rng.randf_range(-1.35, 1.35))
		var l := 140 + rng.randi() % 80
		c.stroke(p, p + nd * rng.randf_range(34.0, 58.0), 2.0, 1.0, l, mini(l + 40, 255), tint)
	c.disc(p.x, p.y, 3.0, 120, tint)

# ------------------------------------------------------------------- birch
## A clump of birch leaves on short twigs that wander out from the middle, with
## open gaps between them and a ragged edge: no outline to read as one big leaf.
static func _paint_birch_clump(c: Canvas, rng: RandomNumberGenerator) -> void:
	var ctr := Vector2(256, 256)
	var twigs := 11
	for i in twigs:
		var heading := TAU * (i + rng.randf_range(-0.4, 0.4)) / twigs
		var length := rng.randf_range(110.0, 225.0)
		var bend := rng.randf_range(-1.5, 1.5)
		var p := ctr + Vector2(rng.randf_range(-50.0, 50.0), rng.randf_range(-50.0, 50.0))
		_twig(c, rng, p, heading, length, bend, 0.95, 2)
	# short twigs fill the middle, so it reads as a clump rather than a star
	for i in 9:
		var heading := rng.randf() * TAU
		var p := ctr + Vector2(rng.randf_range(-70.0, 70.0), rng.randf_range(-70.0, 70.0))
		_twig(c, rng, p, heading, rng.randf_range(50.0, 110.0), rng.randf_range(-1.5, 1.5), 0.95, 0)

## One wandering twig hung with leaves, alternately left and right; now and
## then it forks (`forks` more times at most).
static func _twig(c: Canvas, rng: RandomNumberGenerator, p: Vector2, heading: float, length: float, bend: float, leaf: float, forks: int) -> void:
	var s := 0.0
	var since := 0.0
	var gap := rng.randf_range(7.0, 10.0)
	var side := 1.0 if rng.randf() < 0.5 else -1.0
	while s < length:
		var step := 5.0
		heading += bend * step / length + rng.randf_range(-0.05, 0.05)
		var q := p + Vector2(cos(heading), sin(heading)) * step
		var t := s / length
		c.stroke(p, q, lerpf(2.2, 1.3, t), lerpf(2.2, 1.3, t), 70, 86)
		s += step
		since += step
		if since >= gap and s > 14.0:
			since = 0.0
			gap = rng.randf_range(7.0, 10.0)
			side = -side
			var la := heading + side * deg_to_rad(rng.randf_range(35.0, 75.0))
			# leaves hang a little under their own weight
			var ld := Vector2(cos(la), sin(la)).lerp(Vector2(0, 1), 0.22).normalized()
			_leaf(c, rng, q, ld, leaf)
			if rng.randf() < 0.6:
				var lb := heading - side * deg_to_rad(rng.randf_range(35.0, 70.0))
				_leaf(c, rng, q, Vector2(cos(lb), sin(lb)).lerp(Vector2(0, 1), 0.22).normalized(), leaf)
			if forks > 0 and t > 0.2 and rng.randf() < 0.2:
				_twig(c, rng, q, heading + side * rng.randf_range(0.5, 0.9), (length - s) * rng.randf_range(0.45, 0.7), -bend * 0.5, leaf, forks - 1)
		p = q
	_leaf(c, rng, p, Vector2(cos(heading), sin(heading)), leaf)

## A spray of thin twigs hanging from the top of the tile, hung with small leaves.
static func _paint_birch_spray(c: Canvas, rng: RandomNumberGenerator) -> void:
	var root := Vector2(256, 8)
	var twigs := 9
	for i in twigs:
		var fx := (i + 0.5) / twigs
		var end := Vector2(lerpf(34.0, 478.0, fx) + rng.randf_range(-14.0, 14.0), 0.0)
		end.y = 498.0 - absf(end.x - 256.0) * rng.randf_range(0.25, 0.5) - rng.randf_range(0.0, 60.0)
		var ctrl := Vector2(lerpf(root.x, end.x, 0.8), lerpf(root.y, end.y, rng.randf_range(0.12, 0.3)))
		var prev := root
		var since := 0.0
		var side := 1.0
		var next_sprig := rng.randf_range(60.0, 110.0)
		var run := 0.0
		for s in range(1, 41):
			var t := s / 40.0
			var p := root.lerp(ctrl, t).lerp(ctrl.lerp(end, t), t)
			var seg := p - prev
			var seg_len := seg.length()
			c.stroke(prev, p, lerpf(2.6, 1.2, t), lerpf(2.6, 1.2, t), 70, 92)
			since += seg_len
			run += seg_len
			if t > 0.1 and since > 12.0:
				since = 0.0
				side = -side
				var dirv := seg / maxf(seg_len, 0.001)
				_leaf(c, rng, p, dirv.rotated(deg_to_rad(rng.randf_range(35.0, 80.0)) * side).lerp(Vector2(0, 1), 0.35).normalized(), 0.8)
			if t > 0.15 and run > next_sprig:
				run = 0.0
				next_sprig = rng.randf_range(55.0, 100.0)
				# a short side twig, hanging straight down
				var q := p
				var hang := Vector2(rng.randf_range(-0.35, 0.35), 1.0).normalized()
				var sprig_len := rng.randf_range(46.0, 96.0)
				c.stroke(q, q + hang * sprig_len, 1.6, 1.0, 74, 92)
				var m := 10.0
				var sd := 1.0
				while m < sprig_len:
					_leaf(c, rng, q + hang * m, hang.rotated(deg_to_rad(rng.randf_range(30.0, 70.0)) * sd), 0.8)
					sd = -sd
					m += rng.randf_range(11.0, 16.0)
				_leaf(c, rng, q + hang * sprig_len, hang, 0.8)
			prev = p
		_leaf(c, rng, end, Vector2(0, 1), 0.8)

## One birch leaf: broad near the stalk, drawn out to a point, with a tint of its own.
static func _leaf(c: Canvas, rng: RandomNumberGenerator, p: Vector2, dirv: Vector2, size: float) -> void:
	var ln := rng.randf_range(23.0, 33.0) * size
	var wd := ln * rng.randf_range(0.6, 0.76)
	var l := 168 + rng.randi() % 88
	var h := 128 + rng.randi_range(-72, 72)
	var mid := p + dirv * ln * 0.4
	c.stroke(p + dirv * 2.0, mid, 4.0, wd, l - 14, l, h)
	c.stroke(mid, p + dirv * ln, wd, 1.6, l, mini(l + 16, 255), h)
