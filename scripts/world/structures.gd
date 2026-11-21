class_name Structures
extends Node3D
## The red lakeside cabin and its yard (deck and porch, woodshed, outhouse), the
## pier with its rowing boat, and the hunting towers. All built in code:
## structure.gdshader draws the surfaces, picking a pattern (paint, weathered
## wood, stone, turf...) from the vertex alpha; window_glass.gdshader the windows.

const TOWER_H := 4.3
const PIER_Y := 0.55
const FLOOR_H := 0.45

# The cabin, in cabin space: +Z faces the lake (the door side), +X is the woodshed end.
const CW := 7.2                  ## outside length of the walls (x)
const CD := 5.0                  ## outside depth of the walls (z)
const EAVE := FLOOR_H + 2.35     ## top of the walls
const PITCH := 0.4712            ## roof pitch, 27 degrees
const RAFTER_UP := 0.1           ## the roof plane sits this far above the walls at the wall line
const OVER_EAVE := 0.55          ## roof overhang past the long walls
const OVER_GABLE := 0.4          ## ... and past the gable walls
const DOOR_X := -0.9
const DECK_Z := CD * 0.5 + 2.1   ## front edge of the deck
const BIS_W := 0.95              ## the porch roof's posts stand this far either side of the door...
const BIS_Z := CD * 0.5 + 1.55   ## ... and this far out from the wall
const BIS_Y := FLOOR_H + 2.25    ## top of the porch roof's beams
const BIS_PITCH := 0.6632        ## porch roof pitch, 38 degrees
const OUTHOUSE := Vector3(-6.3, 0.0, -4.4)

# surface patterns, stored in the vertex alpha (see structure.gdshader)
const PLAIN := 0
const PAINT := 1
const WOOD := 2
const STONE := 3
const TURF := 4
const BARK := 5
const GRAIN := 6
const IRON := 7

# colours, as albedo (the cabin is committed without sRGB conversion)
const FALU := Color(0.27, 0.1, 0.072)
const TRIM := Color(0.46, 0.45, 0.42)
const DOOR_GREEN := Color(0.07, 0.115, 0.09)
const STONE_C := Color(0.23, 0.23, 0.22)
const WOOD_C := Color(0.20, 0.17, 0.135)
const WOOD_D := Color(0.11, 0.09, 0.075)
const BARK_C := Color(0.10, 0.075, 0.055)
const GRAIN_C := Color(0.44, 0.35, 0.23)
const IRON_C := Color(0.035, 0.035, 0.04)
const BONE := Color(0.5, 0.41, 0.27)
const BONE_D := Color(0.24, 0.17, 0.1)
const SOIL := Color(0.08, 0.06, 0.04)
const STRAW := Color(0.36, 0.31, 0.14)
const GRASS := Color(0.15, 0.19, 0.07)

var data: TerrainData
var cabin: Node3D
var cabin_inv := Transform3D.IDENTITY
var solids: Array = []          ## [AABB, impact kind] in cabin space: keep the player out, stop bullets
var floors: Array = []          ## [Rect2 over (x, z), top] in cabin space: the deck and its steps
var bare: Array = []            ## [Rect2 over (x, z)] in cabin space: no ground cover grows here
var pier_xf := Transform3D.IDENTITY
var pier_inv := Transform3D.IDENTITY
var pier_len := 12.0
var towers: Array = []          ## [Vector3 base, float yaw]
var mat: ShaderMaterial
var glass_mat: ShaderMaterial
var glow_mat: StandardMaterial3D
var lantern: OmniLight3D
var smoke: CPUParticles3D
var _xf := Transform3D.IDENTITY
var _rng := RandomNumberGenerator.new()
var _lumps := FastNoiseLite.new()
var _lit := -1.0

func build(p_data: TerrainData) -> void:
	data = p_data
	_rng.seed = 1905
	_lumps.seed = 77
	_lumps.frequency = 1.0
	var noise := WorldUtil.noise_texture(256, 4711, [0.045, 0.09, 0.07])
	mat = ShaderMaterial.new()
	mat.shader = load("res://shaders/structure.gdshader")
	mat.set_shader_parameter("noise_tex", noise)
	glass_mat = ShaderMaterial.new()
	glass_mat.shader = load("res://shaders/window_glass.gdshader")
	glass_mat.set_shader_parameter("noise_tex", noise)
	glow_mat = StandardMaterial3D.new()
	glow_mat.albedo_color = Color(0.85, 0.8, 0.66)
	glow_mat.emission_enabled = true
	glow_mat.emission = Color(1.0, 0.66, 0.3)
	glow_mat.emission_energy_multiplier = 0.0
	_build_cabin()
	_build_pier()
	for site in data.tower_sites:
		_build_tower(site[0], site[1])
	update_lights(0.0)
	# ground cover grown before the cabin stood would come up through its floor
	if G.flora:
		G.flora.clear_cover_near(data.cabin_pos, 30.0)

# ---------------------------------------------------------------- helpers
static func _c(col: Color, kind: int, shade := 1.0) -> Color:
	return Color(col.r * shade, col.g * shade, col.b * shade, kind * 0.1)

## A box with its sides along `ax`, `ay`, `az` (unit vectors; `size` measured along them).
static func _box(k: MeshKit, center: Vector3, size: Vector3, ax: Vector3, ay: Vector3, az: Vector3, col: Color) -> void:
	if ax.dot(ay.cross(az)) < 0.0:
		ax = -ax
	k.box(size, Transform3D(Basis(ax, ay, az), center), col)

## A beam of cross-section w x h from `a` to `b`, its h side as upright as the beam allows.
static func _beam(k: MeshKit, a: Vector3, b: Vector3, w: float, h: float, col: Color) -> void:
	var az := (b - a).normalized()
	var ref := Vector3.UP if absf(az.y) < 0.95 else Vector3.BACK
	var ax := ref.cross(az).normalized()
	var ay := az.cross(ax).normalized()
	_box(k, (a + b) * 0.5, Vector3(w, h, a.distance_to(b)), ax, ay, az, col)

## A quad facing `facing`, whichever way round the corners come.
static func _quad(k: MeshKit, p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, facing: Vector3, col: Color) -> void:
	if (p1 - p0).cross(p2 - p0).dot(facing) < 0.0:
		k.face4(p3, p2, p1, p0, col)
	else:
		k.face4(p0, p1, p2, p3, col)

## A flat polygon (star-shaped round its centroid) facing `facing`; the colour
## runs from `centre_col` in the middle to `rim_col` at the edge.
static func _fan(k: MeshKit, pts: Array, facing: Vector3, centre_col: Color, rim_col: Color) -> void:
	var ctr := Vector3.ZERO
	for p in pts:
		ctr += p
	ctr /= pts.size()
	var ci := k.vert(ctr, facing, centre_col)
	var first := k.count()
	for p in pts:
		k.vert(p, facing, rim_col)
	var m := pts.size()
	for i in m:
		var a: Vector3 = pts[i]
		var b: Vector3 = pts[(i + 1) % m]
		if (a - ctr).cross(b - ctr).dot(facing) > 0.0:
			k.tri(ci, first + i, first + (i + 1) % m)
		else:
			k.tri(ci, first + (i + 1) % m, first + i)

func _stone(k: MeshKit, centre: Vector3, radii: Vector3, col: Color) -> void:
	var i0 := k.idx.size()
	k.sphere(centre, radii, 7, 4, _c(col, STONE), _c(col.darkened(0.2), STONE), Basis(Vector3.UP, _rng.randf() * TAU), 0.22, _rng.randi() % 997)
	k.facet(i0)

## Ground height at a point given in cabin space, relative to the cabin.
func _ground(x: float, z: float) -> float:
	var w := _xf * Vector3(x, 0.0, z)
	return data.height(w.x, w.z) - data.cabin_pos.y

static func _top_at(tops: Array, s: float) -> float:
	for i in tops.size() - 1:
		var a: Array = tops[i]
		var b: Array = tops[i + 1]
		if s <= float(b[0]) + 0.0001:
			var t := clampf((s - float(a[0])) / maxf(float(b[0]) - float(a[0]), 0.0001), 0.0, 1.0)
			return lerpf(float(a[1]), float(b[1]), t)
	return float(tops[-1][1])

## Parts of [y0, y1] not covered by the openings that the upright at `s` passes through.
static func _free_spans(y0: float, y1: float, s: float, holes: Array) -> Array:
	var spans := [[y0, y1]]
	for h in holes:
		if s < float(h[0]) or s > float(h[1]):
			continue
		var next := []
		for sp in spans:
			if float(h[3]) <= float(sp[0]) or float(h[2]) >= float(sp[1]):
				next.append(sp)
				continue
			if float(h[2]) > float(sp[0]):
				next.append([sp[0], h[2]])
			if float(h[3]) < float(sp[1]):
				next.append([h[3], sp[1]])
		spans = next
	return spans

# ------------------------------------------------------------------ cabin
func _build_cabin() -> void:
	_xf = Transform3D(Basis(Vector3.UP, data.cabin_yaw), data.cabin_pos)
	solids.clear()
	floors.clear()
	bare.clear()
	var k := MeshKit.new()        # everything solid
	var gl := MeshKit.new()       # window glass
	var lamp := MeshKit.new()     # the lantern's glass
	_cabin_body(k, gl)
	_main_roof(k)
	var smoke_at := _chimney(k)
	_porch(k, gl)
	var lamp_at := Vector3(DOOR_X + 0.8, FLOOR_H + 1.95, CD * 0.5)
	_lantern(k, lamp, lamp_at)
	# moose antlers over the window in the west gable, facing the evening light
	k.xf = Transform3D(Basis(Vector3.UP, -PI * 0.5), Vector3(-CW * 0.5 - 0.035, EAVE + 0.06, 0.0))
	_trophy(k)
	k.xf = Transform3D.IDENTITY
	_ladder(k)
	_woodshed(k)
	_chopping_block(k, Vector3(CW * 0.5 + 2.3, 0.0, 2.9))
	_outhouse(k)
	_path(k)
	cabin = Node3D.new()
	cabin.name = "Cabin"
	add_child(cabin)
	cabin.transform = _xf
	var mesh := k.commit(mat)
	gl.commit(glass_mat, mesh)
	lamp.commit(glow_mat, mesh)
	var mi := MeshInstance3D.new()
	mi.name = "CabinMesh"
	mi.mesh = mesh
	cabin.add_child(mi)
	lantern = OmniLight3D.new()
	lantern.position = lamp_at + Vector3(0, -0.12, 0.26)
	lantern.light_color = Color(1.0, 0.72, 0.4)
	lantern.omni_range = 7.5
	lantern.omni_attenuation = 1.4
	lantern.shadow_enabled = false
	cabin.add_child(lantern)
	_add_smoke(smoke_at)
	cabin_inv = _xf.affine_inverse()

## Foundation, the four walls with their windows and door, corner boards.
func _cabin_body(k: MeshKit, gl: MeshKit) -> void:
	var hw := CW * 0.5
	var hd := CD * 0.5
	var y0 := FLOOR_H - 0.12
	var gable_top := EAVE + RAFTER_UP + tan(PITCH) * hd
	# a dry-stone foundation showing a hand's breadth above the ground
	var plinth := FLOOR_H - 0.06
	k.box_at(Vector3(0, (plinth - 0.6) * 0.5, 0), Vector3(CW + 0.08, plinth + 0.6, CD + 0.08), _c(STONE_C, STONE))
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			_stone(k, Vector3(sx * (hw + 0.03), plinth * 0.42, sz * (hd + 0.03)), Vector3(0.34, plinth * 0.62, 0.3), STONE_C.darkened(0.08))
	var eave_line := [[0.0, EAVE], [CW, EAVE]]
	var gable_line := [[0.0, EAVE + RAFTER_UP], [hd, gable_top], [CD, EAVE + RAFTER_UP]]
	# [origin, along, out, length, top line, openings: [what, s, y centre, w, h, panes across, panes up]]
	var walls := [
		[Vector3(-hw, 0, hd), Vector3.RIGHT, Vector3.BACK, CW, eave_line, [
			["win", -2.75 + hw, FLOOR_H + 1.45, 0.85, 1.0, 2, 2],
			["door", DOOR_X + hw, FLOOR_H + 1.0, 0.9, 2.0, 0, 0],
			["win", 1.75 + hw, FLOOR_H + 1.45, 1.3, 1.0, 3, 2]]],
		[Vector3(hw, 0, -hd), Vector3.LEFT, Vector3.FORWARD, CW, eave_line, [
			["win", hw - 1.0, FLOOR_H + 1.55, 0.75, 0.75, 2, 2]]],
		[Vector3(-hw, 0, -hd), Vector3.BACK, Vector3.LEFT, CD, gable_line, [
			["win", hd - 0.1, FLOOR_H + 1.45, 0.95, 1.05, 2, 2],
			["attic", hd, EAVE + 0.76, 0.38, 0.42, 1, 2]]],
		[Vector3(hw, 0, hd), Vector3.FORWARD, Vector3.RIGHT, CD, gable_line, [
			["attic", hd, EAVE + 0.76, 0.38, 0.42, 1, 2]]],
	]
	for wall in walls:
		var o: Vector3 = wall[0]
		var along: Vector3 = wall[1]
		var out: Vector3 = wall[2]
		var length: float = wall[3]
		var holes := []
		for op in wall[5]:
			var s: float = op[1]
			var yc: float = op[2]
			var w: float = op[3]
			var h: float = op[4]
			holes.append([s - w * 0.5 - 0.12, s + w * 0.5 + 0.12, yc - h * 0.5 - 0.18, yc + h * 0.5 + 0.32])
		_wall(k, o, along, out, length, y0, wall[4], holes, FALU, true)
		for op in wall[5]:
			match op[0]:
				"door":
					_door(k, gl, o, along, out, op[1], op[3], op[4])
				"attic":
					_window(k, gl, o, along, out, op[1], op[2], op[3], op[4], op[5], op[6], false)
				_:
					_window(k, gl, o, along, out, op[1], op[2], op[3], op[4], op[5], op[6], true)
		# white corner boards; on the long walls they lap over the gable walls' boards
		var long_wall := length > CD + 0.1
		var top_y: float = EAVE if long_wall else EAVE + RAFTER_UP
		var lap := 0.03 if long_wall else 0.0
		for e in [[-lap, 0.13], [length - 0.13, length + lap]]:
			var s0: float = e[0]
			var s1: float = e[1]
			_box(k, o + along * ((s0 + s1) * 0.5) + out * 0.015 + Vector3(0, (y0 + top_y) * 0.5, 0),
				Vector3(s1 - s0, top_y - y0, 0.03), along, Vector3.UP, out, _c(TRIM, PAINT))
		if long_wall:
			# a frieze board closes the gap up to the roof between the rafters
			_box(k, o + along * (length * 0.5) + out * 0.0125 + Vector3(0, EAVE + 0.04, 0),
				Vector3(length + 0.06, 0.16, 0.025), along, Vector3.UP, out, _c(FALU, PAINT, 0.85))
	solids.append([AABB(Vector3(-hw - 0.05, -0.6, -hd - 0.05), Vector3(CW + 0.1, gable_top + 0.9, CD + 0.1)), "house"])
	# the roof overhang stops bullets but not the hunter walking under it
	solids.append([AABB(Vector3(-hw - OVER_GABLE, EAVE - 0.2, -hd - OVER_EAVE), Vector3(CW + OVER_GABLE * 2.0, gable_top - EAVE + 0.6, CD + OVER_EAVE * 2.0)), "wood"])
	bare.append(Rect2(-hw - 0.5, -hd - 0.35, CW + 1.0, DECK_Z + 0.85 + hd + 0.35))

## Board-and-batten wall seen from outside: it runs from `o` along `along` for
## `length` m, faces `out`, and stands from `y0` up to the line `tops` ([s, y]
## pairs). Battens stop short of the `holes` ([s0, s1, y0, y1]).
func _wall(k: MeshKit, o: Vector3, along: Vector3, out: Vector3, length: float, y0: float, tops: Array, holes: Array, col: Color, battens: bool) -> void:
	var n := maxi(2, int(round(length / 0.225)))
	if n % 2 == 1:
		n += 1
	var bw := length / n
	for i in n:
		var s0 := i * bw
		var s1 := s0 + bw
		var shade := 0.93 + _rng.randf() * 0.1
		_quad(k, o + along * s0 + Vector3(0, y0, 0), o + along * s1 + Vector3(0, y0, 0),
			o + along * s1 + Vector3(0, _top_at(tops, s1), 0), o + along * s0 + Vector3(0, _top_at(tops, s0), 0), out, _c(col, PAINT, shade))
	if not battens:
		return
	for i in range(1, n):
		var s := i * bw
		if s < 0.15 or s > length - 0.15:
			continue
		for sp in _free_spans(y0 + 0.02, _top_at(tops, s) - 0.005, s, holes):
			var a: float = sp[0]
			var b: float = sp[1]
			if b - a < 0.03:
				continue
			_box(k, o + along * s + out * 0.011 + Vector3(0, (a + b) * 0.5, 0), Vector3(0.05, b - a, 0.022), along, Vector3.UP, out, _c(col, PAINT, 0.97))

## A window: glass (painted by the glass shader), sash and glazing bars, white
## casing, and for the big ones a crown with a drip cap above and a sill below.
func _window(k: MeshKit, gl: MeshKit, o: Vector3, along: Vector3, out: Vector3, s: float, yc: float, w: float, h: float, cols: int, rows: int, crown: bool) -> void:
	var trim := _c(TRIM, PAINT)
	var up := Vector3.UP
	var at := func(ss: float, yy: float, off: float) -> Vector3: return o + along * ss + Vector3(0, yy, 0) + out * off
	var gcol := Color(w / 4.0, h / 4.0, _rng.randf(), 1.0)
	var g0 := gl.vert(at.call(s - w * 0.5, yc - h * 0.5, 0.012), out, gcol, Vector2(0, h))
	var g1 := gl.vert(at.call(s + w * 0.5, yc - h * 0.5, 0.012), out, gcol, Vector2(w, h))
	var g2 := gl.vert(at.call(s + w * 0.5, yc + h * 0.5, 0.012), out, gcol, Vector2(w, 0))
	var g3 := gl.vert(at.call(s - w * 0.5, yc + h * 0.5, 0.012), out, gcol, Vector2(0, 0))
	gl.quad(g0, g1, g2, g3)
	# sash and glazing bars
	var fw := 0.05
	_box(k, at.call(s - w * 0.5 + fw * 0.5, yc, 0.022), Vector3(fw, h, 0.03), along, up, out, trim)
	_box(k, at.call(s + w * 0.5 - fw * 0.5, yc, 0.022), Vector3(fw, h, 0.03), along, up, out, trim)
	_box(k, at.call(s, yc - h * 0.5 + fw * 0.5, 0.022), Vector3(w - fw * 2.0, fw, 0.03), along, up, out, trim)
	_box(k, at.call(s, yc + h * 0.5 - fw * 0.5, 0.022), Vector3(w - fw * 2.0, fw, 0.03), along, up, out, trim)
	for c in range(1, cols):
		_box(k, at.call(s - w * 0.5 + w * c / cols, yc, 0.02), Vector3(0.028, h - fw * 2.0, 0.022), along, up, out, trim)
	for r in range(1, rows):
		_box(k, at.call(s, yc - h * 0.5 + h * r / rows, 0.02), Vector3(w - fw * 2.0, 0.028, 0.022), along, up, out, trim)
	# casing
	var cw := 0.1
	_box(k, at.call(s - w * 0.5 - cw * 0.5, yc, 0.017), Vector3(cw, h + cw * 2.0, 0.034), along, up, out, trim)
	_box(k, at.call(s + w * 0.5 + cw * 0.5, yc, 0.017), Vector3(cw, h + cw * 2.0, 0.034), along, up, out, trim)
	_box(k, at.call(s, yc + h * 0.5 + cw * 0.5, 0.017), Vector3(w, cw, 0.034), along, up, out, trim)
	_box(k, at.call(s, yc - h * 0.5 - cw * 0.5, 0.017), Vector3(w, cw, 0.034), along, up, out, trim)
	if crown:
		_box(k, at.call(s, yc + h * 0.5 + cw + 0.06, 0.02), Vector3(w + cw * 2.0 + 0.06, 0.12, 0.04), along, up, out, trim)
		_box(k, at.call(s, yc + h * 0.5 + cw + 0.135, 0.045), Vector3(w + cw * 2.0 + 0.14, 0.03, 0.09), along, up, out, trim)
		_box(k, at.call(s, yc - h * 0.5 - cw - 0.018, 0.05), Vector3(w + cw * 2.0 + 0.1, 0.035, 0.1), along, up, out, trim)

## A door of upright boards with a little window, white casing and an iron latch.
func _door(k: MeshKit, gl: MeshKit, o: Vector3, along: Vector3, out: Vector3, s: float, w: float, h: float) -> void:
	var up := Vector3.UP
	var y0 := FLOOR_H
	var at := func(ss: float, yy: float, off: float) -> Vector3: return o + along * ss + Vector3(0, yy, 0) + out * off
	var nb := 5
	var bw := w / nb
	for i in nb:
		var sc := s - w * 0.5 + (i + 0.5) * bw
		_box(k, at.call(sc, y0 + h * 0.5, 0.015), Vector3(bw - 0.008, h, 0.03), along, up, out, _c(DOOR_GREEN, PAINT, 0.92 + _rng.randf() * 0.14))
	# rails across the boards, below and above the window
	for yy in [y0 + 0.3, y0 + 1.2]:
		_box(k, at.call(s, yy, 0.038), Vector3(w - 0.12, 0.1, 0.018), along, up, out, _c(DOOR_GREEN, PAINT, 1.05))
	# the window in the door
	var wy := y0 + 1.62
	var ww := 0.42
	var wh := 0.38
	var gcol := Color(ww / 4.0, wh / 4.0, _rng.randf(), 1.0)
	var g0 := gl.vert(at.call(s - ww * 0.5, wy - wh * 0.5, 0.033), out, gcol, Vector2(0, wh))
	var g1 := gl.vert(at.call(s + ww * 0.5, wy - wh * 0.5, 0.033), out, gcol, Vector2(ww, wh))
	var g2 := gl.vert(at.call(s + ww * 0.5, wy + wh * 0.5, 0.033), out, gcol, Vector2(ww, 0))
	var g3 := gl.vert(at.call(s - ww * 0.5, wy + wh * 0.5, 0.033), out, gcol, Vector2(0, 0))
	gl.quad(g0, g1, g2, g3)
	var trim := _c(TRIM, PAINT)
	for e in [[s - ww * 0.5 - 0.02, wy, 0.04, wh + 0.08], [s + ww * 0.5 + 0.02, wy, 0.04, wh + 0.08], [s, wy - wh * 0.5 - 0.02, ww, 0.04], [s, wy + wh * 0.5 + 0.02, ww, 0.04], [s, wy, 0.025, wh], [s, wy, ww, 0.025]]:
		_box(k, at.call(e[0], e[1], 0.042), Vector3(e[2], e[3], 0.02), along, up, out, trim)
	# casing, crown, threshold
	var cw := 0.1
	_box(k, at.call(s - w * 0.5 - cw * 0.5, y0 + (h + cw) * 0.5, 0.017), Vector3(cw, h + cw, 0.034), along, up, out, trim)
	_box(k, at.call(s + w * 0.5 + cw * 0.5, y0 + (h + cw) * 0.5, 0.017), Vector3(cw, h + cw, 0.034), along, up, out, trim)
	_box(k, at.call(s, y0 + h + cw * 0.5, 0.017), Vector3(w, cw, 0.034), along, up, out, trim)
	_box(k, at.call(s, y0 + h + cw + 0.06, 0.02), Vector3(w + cw * 2.0 + 0.06, 0.12, 0.04), along, up, out, trim)
	_box(k, at.call(s, y0 + h + cw + 0.135, 0.045), Vector3(w + cw * 2.0 + 0.14, 0.03, 0.09), along, up, out, trim)
	_box(k, at.call(s, y0 + 0.015, 0.06), Vector3(w + cw * 2.0, 0.03, 0.14), along, up, out, _c(WOOD_C, WOOD))
	# iron latch
	var iron := _c(IRON_C, IRON)
	_box(k, at.call(s + w * 0.5 - 0.13, y0 + 1.0, 0.036), Vector3(0.05, 0.2, 0.012), along, up, out, iron)
	_box(k, at.call(s + w * 0.5 - 0.17, y0 + 1.0, 0.07), Vector3(0.11, 0.024, 0.024), along, up, out, iron)

# ------------------------------------------------------------------- roofs
## One slope of a turf roof, in roof space: the ridge runs along x at height
## `ridge_y`; the slope falls towards +z (side 1) or -z (side -1) at `pitch`,
## from the ridge out to `s_end` metres along the slope. Roof boards and a lumpy
## layer of turf that closes over the ridge; and, as asked in `opt`:
##   "log"       a turf log along the eave        "tails"   rafter tails from there out
##   "fringe"    grass hanging over the eave      "edge0"/"edge1" turf closed at x0 / x1
##   "end_face"  a board closing the turf at s_end
##   "mono"      a lean-to: no ridge to close over ("top_log" holds the turf at the top)
func _slope(k: MeshKit, side: float, ridge_y: float, pitch: float, x0: float, x1: float, s_end: float, opt: Dictionary) -> void:
	var cs := cos(pitch)
	var sn := sin(pitch)
	var d := Vector3(0, -sn, side * cs)
	var nrm := Vector3(0, cs, side * sn)
	var base := Vector3(0, ridge_y, 0)
	var mono: bool = opt.get("mono", false)
	var has_log: bool = opt.get("log", false)
	var top_log: bool = opt.get("top_log", false)
	var bt := 0.045      # board thickness
	var under := _c(WOOD_D, WOOD)
	var at := func(x: float, s: float, u: float) -> Vector3: return base + Vector3(x, 0, 0) + d * s + nrm * u
	# roof boards; their underside is what you see from below the eaves
	_quad(k, at.call(x0, 0.0, 0.0), at.call(x1, 0.0, 0.0), at.call(x1, s_end, 0.0), at.call(x0, s_end, 0.0), -nrm, under)
	_quad(k, at.call(x0, s_end, 0.0), at.call(x1, s_end, 0.0), at.call(x1, s_end, bt), at.call(x0, s_end, bt), d, under)
	if mono:
		_quad(k, at.call(x0, 0.0, 0.0), at.call(x1, 0.0, 0.0), at.call(x1, 0.0, bt), at.call(x0, 0.0, bt), -d, under)
	# turf, on a grid so it can be lumpy
	var t0 := 0.13 if top_log else 0.0
	var t1 := s_end - (0.13 if has_log else 0.0)
	var xa := x0 + 0.06
	var xb := x1 - 0.06
	var nx := maxi(2, int(ceil((xb - xa) / 0.32)))
	var ns := maxi(2, int(ceil((t1 - t0) / 0.28)))
	var row := nx + 1
	var first := k.count()
	var i_start := k.idx.size()
	var grid: Array[Vector3] = []
	for j in ns + 1:
		var s := lerpf(t0, t1, float(j) / ns)
		for i in nx + 1:
			var x := lerpf(xa, xb, float(i) / nx)
			var th := bt + _turf_depth(x, s, side, t1, mono)
			var p: Vector3 = Vector3(x, ridge_y + th / cs, 0.0) if (j == 0 and not mono) else at.call(x, s, th)
			grid.append(p)
			k.vert(p, nrm, _c(Color.WHITE, TURF, 0.86 + 0.14 * G.hash2(i, j, int(side) + 7)))
	for j in ns:
		for i in nx:
			var a := first + j * row + i
			if side > 0.0:
				k.quad(a, a + row, a + row + 1, a + 1)
			else:
				k.quad(a, a + 1, a + row + 1, a + row)
	k.smooth_normals(first, i_start)
	# the turf's cut edges
	var soil := _c(SOIL, PLAIN)
	if opt.get("edge0", false) or opt.get("edge1", false):
		for e in 2:
			if not opt.get("edge0" if e == 0 else "edge1", false):
				continue
			var i := 0 if e == 0 else nx
			var x := xa if e == 0 else xb
			for j in ns:
				var s_a := lerpf(t0, t1, float(j) / ns)
				var s_b := lerpf(t0, t1, float(j + 1) / ns)
				_quad(k, at.call(x, s_a, bt), at.call(x, s_b, bt), grid[(j + 1) * row + i], grid[j * row + i], Vector3(-1.0 if e == 0 else 1.0, 0, 0), soil)
	var end_col := under if opt.get("end_face", false) else soil
	for i in nx:
		var xl := lerpf(xa, xb, float(i) / nx)
		var xr := lerpf(xa, xb, float(i + 1) / nx)
		_quad(k, at.call(xl, t1, bt), at.call(xr, t1, bt), grid[ns * row + i + 1], grid[ns * row + i], d, end_col)
	# the turf logs that hold it in place
	if has_log:
		k.cyl(at.call(x0 + 0.05, s_end - 0.075, bt + 0.075), at.call(x1 - 0.05, s_end - 0.075, bt + 0.075), 0.075, 0.075, 7, _c(BARK_C, BARK), _c(BARK_C, BARK), true, true)
	if top_log:
		k.cyl(at.call(x0 + 0.05, 0.07, bt + 0.07), at.call(x1 - 0.05, 0.07, bt + 0.07), 0.07, 0.07, 7, _c(BARK_C, BARK), _c(BARK_C, BARK), true, true)
	# rafter tails under the overhang
	var tails: float = opt.get("tails", -1.0)
	if tails >= 0.0:
		var x := x0 + 0.42
		while x < x1 - 0.35:
			_box(k, at.call(x, (tails + s_end) * 0.5, -0.065), Vector3(0.055, 0.13, s_end - tails), Vector3.RIGHT, nrm, d, _c(WOOD_D, WOOD, 0.9))
			x += 0.6
	# grass: hanging over the eave, along the ridge, and here and there
	if opt.get("fringe", false):
		var x := xa
		while x < xb:
			var th := bt + _turf_depth(x, t1, side, t1, mono)
			_blades(k, at.call(x, t1 - 0.04, th), (d * 0.75 + nrm * 0.45).normalized(), 0.17, 3)
			x += 0.1 + _rng.randf() * 0.05
		if not mono:
			x = xa
			while x < xb:
				_blades(k, Vector3(x, ridge_y + (bt + _turf_depth(x, 0.0, side, t1, mono)) / cs, 0.0), (Vector3.UP + d * 0.3).normalized(), 0.15, 2)
				x += 0.16 + _rng.randf() * 0.08
		for t in int((xb - xa) * (t1 - t0) * 2.2):
			var xx := _rng.randf_range(xa, xb)
			var ss := _rng.randf_range(t0 + 0.2, t1 - 0.1)
			_blades(k, at.call(xx, ss, bt + _turf_depth(xx, ss, side, t1, mono) - 0.01), (nrm + d * 0.25).normalized(), 0.13, 3)

## How deep the turf lies: lumpy, heaped over the ridge, thinning out to the eave.
func _turf_depth(x: float, s: float, side: float, t1: float, mono: bool) -> float:
	var t := 0.15 + _lumps.get_noise_2d(x * 2.6, s * side * 2.6) * 0.035
	if not mono:
		t += 0.06 * (1.0 - smoothstep(0.0, 0.55, s))
	return t * lerpf(1.0, 0.72, smoothstep(t1 - 0.35, t1, s))

## A tuft of grass blades (two-sided thin triangles) from `at` towards `dir`.
func _blades(k: MeshKit, at: Vector3, dir: Vector3, length: float, count: int) -> void:
	for b in count:
		var bd := (dir + Vector3(_rng.randf_range(-0.35, 0.35), _rng.randf_range(-0.1, 0.25), _rng.randf_range(-0.35, 0.35))).normalized()
		var side := bd.cross(Vector3.UP)
		if side.length_squared() < 0.01:
			side = Vector3.RIGHT
		side = side.normalized() * 0.013
		var tip := at + bd * length * _rng.randf_range(0.65, 1.15)
		var col := _c(STRAW.lerp(GRASS, _rng.randf() * 0.7), PLAIN)
		var i0 := k.vert(at - side, Vector3.UP, col)
		var i1 := k.vert(at + side, Vector3.UP, col)
		var i2 := k.vert(tip, Vector3.UP, _c(STRAW.lightened(0.12), PLAIN))
		k.tri(i0, i1, i2)
		k.tri(i0, i2, i1)

## A barge board along the gable edge of one slope, standing proud of the turf.
## With `cross` it runs on past the ridge and crosses its partner from the other
## slope; `outward` (+1 or -1) says which way is out of the roof at this end.
func _barge(k: MeshKit, x: float, side: float, ridge_y: float, pitch: float, run: float, cross: bool, col: Color, outward: float, width := 0.36) -> void:
	var cs := cos(pitch)
	var sn := sin(pitch)
	var d := Vector3(0, -sn, side * cs)
	var nrm := Vector3(0, cs, side * sn)
	var s_a := run + 0.08
	var s_b := -0.42 if cross else 0.0
	var off := outward * (0.018 if side > 0.0 else -0.018)
	var c := Vector3(x + off, ridge_y, 0) + d * ((s_a + s_b) * 0.5) + nrm * (0.28 - width * 0.5)
	_box(k, c, Vector3(0.035, width, s_a - s_b), Vector3.RIGHT, nrm, d, _c(col, PAINT if col == TRIM or col == FALU else WOOD))

func _main_roof(k: MeshKit) -> void:
	var hd := CD * 0.5
	var ridge := EAVE + RAFTER_UP + tan(PITCH) * hd
	var run := (hd + OVER_EAVE) / cos(PITCH)
	var wall_s := hd / cos(PITCH)
	var x0 := -CW * 0.5 - OVER_GABLE
	var x1 := CW * 0.5 + OVER_GABLE
	_slope(k, -1.0, ridge, PITCH, x0, x1, run, {"log": true, "tails": wall_s, "fringe": true})
	# where the porch roof joins the front slope the eave stops at the wall
	var g0 := DOOR_X - 0.8
	var g1 := DOOR_X + 0.8
	_slope(k, 1.0, ridge, PITCH, x0, g0, run, {"log": true, "tails": wall_s, "fringe": true, "edge1": true})
	_slope(k, 1.0, ridge, PITCH, g1, x1, run, {"log": true, "tails": wall_s, "fringe": true, "edge0": true})
	_slope(k, 1.0, ridge, PITCH, g0, g1, wall_s, {"end_face": true})
	for e in [[x0, -1.0], [x1, 1.0]]:
		for side in [-1.0, 1.0]:
			_barge(k, e[0], side, ridge, PITCH, run, true, TRIM, e[1])

## A stone chimney through the ridge with a slab on top. Returns where its smoke starts.
func _chimney(k: MeshKit) -> Vector3:
	var ridge := EAVE + RAFTER_UP + tan(PITCH) * CD * 0.5
	var top := ridge + 1.05
	var cx := -1.5
	var bottom := EAVE - 0.2
	k.box_at(Vector3(cx, (bottom + top) * 0.5, 0), Vector3(0.62, top - bottom, 0.62), _c(STONE_C.lightened(0.06), STONE))
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			k.box_at(Vector3(cx + sx * 0.22, top + 0.07, sz * 0.22), Vector3(0.14, 0.14, 0.14), _c(STONE_C, STONE, 0.85))
	k.box_at(Vector3(cx, top + 0.17, 0), Vector3(0.84, 0.06, 0.84), _c(Color(0.11, 0.11, 0.12), STONE))
	return Vector3(cx, top + 0.12, 0)

# ------------------------------------------------------------------- porch
## The front deck with its railing and steps, and the little turf-roofed porch
## (bislag) over the door.
func _porch(k: MeshKit, gl: MeshKit) -> void:
	var hd := CD * 0.5
	var dx0 := -CW * 0.5 - 0.3
	var dx1 := CW * 0.5 + 0.3
	var dz0 := hd + 0.005
	var depth := DECK_Z - dz0
	# planks running along the wall, each weathered a little differently
	var n := 14
	var pz := depth / n
	for i in n:
		k.box_at(Vector3((dx0 + dx1) * 0.5, FLOOR_H - 0.018, dz0 + (i + 0.5) * pz), Vector3(dx1 - dx0, 0.036, pz - 0.012), _c(WOOD_C, WOOD, 0.85 + _rng.randf() * 0.28))
	k.box_at(Vector3((dx0 + dx1) * 0.5, FLOOR_H - 0.07, dz0 + depth * 0.5), Vector3(dx1 - dx0, 0.02, depth), _c(Color(0.015, 0.012, 0.01), PLAIN))
	var fascia := _c(WOOD_C, WOOD, 0.72)
	k.box_at(Vector3((dx0 + dx1) * 0.5, FLOOR_H - 0.17, DECK_Z + 0.015), Vector3(dx1 - dx0 + 0.06, 0.3, 0.03), fascia)
	for x in [dx0 - 0.015, dx1 + 0.015]:
		k.box_at(Vector3(x, FLOOR_H - 0.17, dz0 + depth * 0.5), Vector3(0.03, 0.3, depth), fascia)
	for x in [dx0 + 0.2, -2.2, 0.6, 2.4, dx1 - 0.2]:
		_stone(k, Vector3(x, _ground(x, DECK_Z - 0.15) + 0.02, DECK_Z - 0.15), Vector3(0.2, 0.13, 0.17), STONE_C)
	# steps down to a flat stone
	var step := _c(WOOD_C, WOOD, 0.95)
	k.box_at(Vector3(DOOR_X, 0.15 - 0.05, DECK_Z + 0.18), Vector3(1.4, 0.3 + 0.1, 0.3), step)
	k.box_at(Vector3(DOOR_X, 0.075 - 0.05, DECK_Z + 0.48), Vector3(1.4, 0.15 + 0.1, 0.3), step)
	_stone(k, Vector3(DOOR_X, _ground(DOOR_X, DECK_Z + 0.95) - 0.02, DECK_Z + 0.95), Vector3(0.62, 0.07, 0.38), STONE_C.lightened(0.05))
	floors.append([Rect2(dx0, hd, dx1 - dx0, DECK_Z - hd), FLOOR_H])
	floors.append([Rect2(DOOR_X - 0.7, DECK_Z, 1.4, 0.33), 0.3])
	floors.append([Rect2(DOOR_X - 0.7, DECK_Z + 0.33, 1.4, 0.3), 0.15])
	# railing: posts, rails and narrow upright boards, gapped for the steps
	var zr := DECK_Z - 0.06
	for sg in [
			[Vector3(dx0 + 0.05, 0, zr), Vector3(DOOR_X - 0.74, 0, zr)],
			[Vector3(DOOR_X + 0.74, 0, zr), Vector3(dx1 - 0.05, 0, zr)],
			[Vector3(dx0 + 0.05, 0, hd + 0.06), Vector3(dx0 + 0.05, 0, zr)],
			[Vector3(dx1 - 0.05, 0, hd + 0.06), Vector3(dx1 - 0.05, 0, zr)]]:
		_railing(k, sg[0], sg[1])
	# the porch: two posts with knee braces, beams back to the wall, a boarded gable
	var white := _c(TRIM, PAINT)
	for sx in [-1.0, 1.0]:
		var px: float = DOOR_X + sx * BIS_W
		_box(k, Vector3(px, (FLOOR_H + BIS_Y) * 0.5, BIS_Z), Vector3(0.12, BIS_Y - FLOOR_H, 0.12), Vector3.RIGHT, Vector3.UP, Vector3.BACK, white)
		_beam(k, Vector3(px, BIS_Y - 0.07, hd), Vector3(px, BIS_Y - 0.07, BIS_Z + 0.08), 0.09, 0.14, white)
		_beam(k, Vector3(px, BIS_Y - 0.5, BIS_Z), Vector3(px - sx * 0.4, BIS_Y - 0.12, BIS_Z), 0.07, 0.07, white)
		_beam(k, Vector3(px, BIS_Y - 0.5, BIS_Z), Vector3(px, BIS_Y - 0.12, BIS_Z - 0.4), 0.07, 0.07, white)
		solids.append([AABB(Vector3(px - 0.09, FLOOR_H, BIS_Z - 0.09), Vector3(0.18, BIS_Y - FLOOR_H, 0.18)), "wood"])
	_beam(k, Vector3(DOOR_X - BIS_W - 0.08, BIS_Y - 0.07, BIS_Z), Vector3(DOOR_X + BIS_W + 0.08, BIS_Y - 0.07, BIS_Z), 0.1, 0.14, white)
	var b_ridge := BIS_Y + tan(BIS_PITCH) * BIS_W
	var tri := [[0.0, BIS_Y], [BIS_W, b_ridge], [BIS_W * 2.0, BIS_Y]]
	_wall(k, Vector3(DOOR_X - BIS_W, 0, BIS_Z), Vector3.RIGHT, Vector3.BACK, BIS_W * 2.0, BIS_Y, tri, [], FALU, true)
	_wall(k, Vector3(DOOR_X + BIS_W, 0, BIS_Z - 0.02), Vector3.LEFT, Vector3.FORWARD, BIS_W * 2.0, BIS_Y, tri, [], FALU, false)
	# its roof runs back into the main roof
	var b_run := (BIS_W + 0.28) / cos(BIS_PITCH)
	var bx1 := BIS_Z + 0.3
	k.xf = Transform3D(Basis(Vector3.UP, -PI * 0.5), Vector3(DOOR_X, 0, 0))
	for side in [-1.0, 1.0]:
		_slope(k, side, b_ridge, BIS_PITCH, 0.9, bx1, b_run, {"log": true, "fringe": true})
		_barge(k, bx1, side, b_ridge, BIS_PITCH, b_run, true, TRIM, 1.0)
	k.xf = Transform3D.IDENTITY

## A railing from `a` to `b` on the deck: posts, top and bottom rails and narrow boards.
func _railing(k: MeshKit, a: Vector3, b: Vector3) -> void:
	var white := _c(TRIM, PAINT)
	var along := b - a
	var length := along.length()
	along /= length
	var out := Vector3.UP.cross(along)
	var np := maxi(1, int(ceil(length / 1.3)))
	for i in np + 1:
		_box(k, a + along * (length * i / np) + Vector3(0, FLOOR_H + 0.5, 0), Vector3(0.09, 1.0, 0.09), along, Vector3.UP, out, white)
	_box(k, (a + b) * 0.5 + Vector3(0, FLOOR_H + 0.97, 0), Vector3(length + 0.1, 0.045, 0.12), along, Vector3.UP, out, white)
	_box(k, (a + b) * 0.5 + Vector3(0, FLOOR_H + 0.13, 0), Vector3(length, 0.05, 0.06), along, Vector3.UP, out, white)
	var nb := int(length / 0.13)
	for i in nb:
		_box(k, a + along * ((i + 0.5) * length / nb) + Vector3(0, FLOOR_H + 0.55, 0), Vector3(0.065, 0.79, 0.02), along, Vector3.UP, out, white)
	var lo := Vector3(minf(a.x, b.x) - 0.07, FLOOR_H, minf(a.z, b.z) - 0.07)
	var hi := Vector3(maxf(a.x, b.x) + 0.07, FLOOR_H + 1.0, maxf(a.z, b.z) + 0.07)
	solids.append([AABB(lo, hi - lo), "wood"])

## An iron lantern hanging from a bracket on the front wall at `at`.
func _lantern(k: MeshKit, lamp: MeshKit, at: Vector3) -> void:
	var iron := _c(IRON_C, IRON)
	var x := Vector3.RIGHT
	var y := Vector3.UP
	var z := Vector3.BACK
	_box(k, at + Vector3(0, 0, 0.012), Vector3(0.07, 0.17, 0.024), x, y, z, iron)
	_beam(k, at + Vector3(0, 0.05, 0.02), at + Vector3(0, 0.05, 0.27), 0.022, 0.022, iron)
	_beam(k, at + Vector3(0, -0.06, 0.02), at + Vector3(0, 0.04, 0.16), 0.016, 0.016, iron)
	var c := at + Vector3(0, -0.12, 0.26)
	_beam(k, at + Vector3(0, 0.05, 0.26), c + Vector3(0, 0.15, 0), 0.012, 0.012, iron)
	_box(k, c + Vector3(0, 0.105, 0), Vector3(0.17, 0.03, 0.17), x, y, z, iron)
	_box(k, c + Vector3(0, 0.135, 0), Vector3(0.09, 0.04, 0.09), x, y, z, iron)
	_box(k, c + Vector3(0, -0.095, 0), Vector3(0.14, 0.03, 0.14), x, y, z, iron)
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			_box(k, c + Vector3(sx * 0.058, 0, sz * 0.058), Vector3(0.016, 0.18, 0.016), x, y, z, iron)
	lamp.box_at(c, Vector3(0.11, 0.17, 0.11), Color.WHITE)

## A mounted pair of palmate moose antlers on a wooden shield, built facing +Z
## around the origin of the kit's current transform.
func _trophy(k: MeshKit) -> void:
	var base := k.xf
	# the shield: a slab whose outline lies in its local (-z, y) plane, turned to face +Z
	var to_front := Basis(Vector3(0, 0, 1), Vector3(0, 1, 0), Vector3(-1, 0, 0))
	k.xf = base * Transform3D(to_front, Vector3(0, 0, 0.016))
	k.slab(PackedVector2Array([Vector2(-0.17, 0.2), Vector2(0.17, 0.2), Vector2(0.185, 0.04), Vector2(0.14, -0.1), Vector2(0.0, -0.2), Vector2(-0.14, -0.1), Vector2(-0.185, 0.04)]),
		0.016, 0.008, _c(Color(0.13, 0.08, 0.05), WOOD))
	k.xf = base
	# the skull plate
	k.sphere(Vector3(0, 0.03, 0.045), Vector3(0.085, 0.06, 0.028), 7, 4, _c(BONE.lightened(0.05), PLAIN), _c(BONE, PLAIN))
	for side in [-1.0, 1.0]:
		var burr := Vector3(side * 0.055, 0.06, 0.075)
		# the palm's plane: out from the skull and up, leaning forward a little
		var b := Basis(Vector3(0, 0, side), Vector3(0, 1, 0), Vector3(-side, 0, 0))
		k.xf = base * Transform3D(Basis(Vector3.RIGHT, 0.5) * Basis(Vector3.BACK, side * 0.12) * b, burr)
		var v0 := k.count()
		k.slab(_antler_outline(side), 0.016, 0.007, _c(BONE, PLAIN))
		# the round beam out to the palm, and a short brow tine pointing forward
		k.cyl(Vector3.ZERO, Vector3(0, 0.02, -0.16), 0.032, 0.027, 6, _c(BONE_D, PLAIN), _c(BONE, PLAIN))
		k.cyl(Vector3(0, 0.01, -0.09), Vector3(0.09, 0.07, -0.11), 0.02, 0.006, 5, _c(BONE, PLAIN))
		var burr_at: Vector3 = k.xf * Vector3.ZERO
		k.recolor(v0, func(p: Vector3, _n: Vector3, col: Color) -> Color:
			var t := clampf(p.distance_to(burr_at) / 0.6, 0.0, 1.0)
			var c2 := BONE_D.lerp(BONE.lightened(0.08), smoothstep(0.0, 0.85, t))
			return Color(c2.r, c2.g, c2.b, col.a))
		k.xf = base

## One palmate antler, in its own plane: u runs out from the skull, v up. A
## short beam widens into a long, shallow blade whose upper edge breaks into tines.
func _antler_outline(side: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	# underside: the beam, then the blade's lower edge sweeping out and up to its tip
	for p in [Vector2(0.0, -0.022), Vector2(0.1, -0.03), Vector2(0.2, -0.045), Vector2(0.32, -0.05), Vector2(0.44, -0.03), Vector2(0.53, 0.01), Vector2(0.6, 0.07)]:
		pts.append(p)
	# the upper edge, from the outer tip back towards the skull, broken into tines
	var tines := 7
	for i in tines:
		var t := float(i) / (tines - 1)
		var root := Vector2(lerpf(0.58, 0.2, t), lerpf(0.1, 0.075, t) + 0.05 * sin(t * PI))
		var lean := lerpf(-0.55, 0.35, t)                 # the outer tines rake outwards
		var reach := (0.07 + 0.05 * sin(t * PI * 0.9)) * (0.85 + 0.3 * G.hash2(i, int(side) + 3, 11))
		var dir := Vector2(sin(-lean), cos(lean)).normalized()
		var half := 0.022
		var along := Vector2(-1.0, 0.0)
		pts.append(root - along * half)
		pts.append(root + dir * reach)
		pts.append(root + along * half)
	# the top of the beam back to the burr
	pts.append(Vector2(0.12, 0.06))
	pts.append(Vector2(0.0, 0.028))
	return pts

## A wooden ladder left leaning against the back eave.
func _ladder(k: MeshKit) -> void:
	var x := 2.3
	var foot_z := -CD * 0.5 - 1.15
	var top := Vector3(0, EAVE + 0.05, -CD * 0.5 - 0.42)
	var wood := _c(WOOD_C, WOOD, 1.05)
	var g := _ground(x, foot_z)
	for sx in [-0.22, 0.22]:
		_beam(k, Vector3(x + sx, g - 0.05, foot_z), Vector3(x + sx, top.y, top.z), 0.045, 0.07, wood)
	var steps := 9
	for i in steps:
		var t := (i + 0.6) / (steps + 0.5)
		var p := Vector3(x, lerpf(g, top.y, t), lerpf(foot_z, top.z, t))
		k.cyl(p - Vector3(0.22, 0, 0), p + Vector3(0.22, 0, 0), 0.018, 0.018, 5, wood)
	solids.append([AABB(Vector3(x - 0.3, g, foot_z - 0.1), Vector3(0.6, top.y - g, top.z - foot_z + 0.2)), "wood"])

# ---------------------------------------------------------------- the yard
## A lean-to woodshed against the east gable, full of split birch.
func _woodshed(k: MeshKit) -> void:
	var wx := CW * 0.5
	var depth := 1.45
	var hz := 2.3
	var top_y := FLOOR_H + 2.08
	var pitch := 0.32
	var post_top := top_y - tan(pitch) * depth
	var wood := _c(WOOD_C, WOOD)
	for z in [-hz + 0.08, 0.0, hz - 0.08]:
		_box(k, Vector3(wx + depth, (post_top - 0.12 - 0.05) * 0.5, z), Vector3(0.11, post_top - 0.12 + 0.05, 0.11), Vector3.RIGHT, Vector3.UP, Vector3.BACK, wood)
		_stone(k, Vector3(wx + depth, _ground(wx + depth, z) - 0.02, z), Vector3(0.16, 0.08, 0.15), STONE_C)
	_beam(k, Vector3(wx + depth, post_top - 0.06, -hz - 0.05), Vector3(wx + depth, post_top - 0.06, hz + 0.05), 0.11, 0.12, wood)
	# a flashing board where the lean-to meets the wall
	k.box_at(Vector3(wx + 0.02, top_y + 0.17, 0), Vector3(0.04, 0.34, hz * 2.0 + 0.3), _c(WOOD_D, WOOD))
	k.xf = Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(wx, 0, 0))
	var run := (depth + 0.3) / cos(pitch)
	_slope(k, 1.0, top_y, pitch, -hz - 0.15, hz + 0.15, run, {"mono": true, "log": true, "fringe": true})
	_barge(k, -hz - 0.15, 1.0, top_y, pitch, run, false, WOOD_D, -1.0)
	_barge(k, hz + 0.15, 1.0, top_y, pitch, run, false, WOOD_D, 1.0)
	k.xf = Transform3D.IDENTITY
	# the woodpile: a dark body of stacked logs on two poles, cut ends to the front
	var face := wx + depth - 0.1
	var y_lo := 0.12
	var y_hi := FLOOR_H + 1.2
	k.box_at(Vector3((wx + 0.06 + face - 0.03) * 0.5, (y_lo + y_hi) * 0.5, 0), Vector3(face - 0.03 - wx - 0.06, y_hi - y_lo, hz * 2.0 - 0.36), _c(BARK_C, BARK, 0.7))
	for px in [wx + 0.25, face - 0.12]:
		k.cyl(Vector3(px, 0.06, -hz + 0.1), Vector3(px, 0.06, hz - 0.1), 0.055, 0.055, 6, _c(BARK_C, BARK))
	var y := y_lo + 0.075
	var row := 0
	while y < y_hi - 0.06:
		var z := -hz + 0.2 + (0.065 if row % 2 == 1 else 0.0)
		while z < hz - 0.2:
			var r := _rng.randf_range(0.055, 0.085)
			_log_end(k, Vector3(face + _rng.randf_range(0.0, 0.035), y + _rng.randf_range(-0.012, 0.012), z), r)
			z += r * 2.0 + _rng.randf_range(0.004, 0.03)
		y += 0.135 + _rng.randf_range(-0.008, 0.01)
		row += 1
	for i in 4:
		var z := _rng.randf_range(-hz + 0.4, hz - 0.4)
		k.cyl(Vector3(face - 0.45, y_hi + 0.06, z), Vector3(face + 0.02, y_hi + 0.07, z + _rng.randf_range(-0.08, 0.08)), 0.07, 0.065, 6, _c(BARK_C, BARK), _c(BARK_C, BARK), false, true)
	# the stack's ends: the outermost logs, bark side out
	for e in [-1.0, 1.0]:
		var ze: float = e * (hz - 0.15)
		var yy := y_lo + 0.075
		while yy < y_hi - 0.06:
			var xx := wx + 0.14
			while xx < face - 0.05:
				var r := _rng.randf_range(0.055, 0.08)
				k.cyl(Vector3(xx, yy, ze - e * 0.42), Vector3(xx + _rng.randf_range(-0.02, 0.02), yy + _rng.randf_range(-0.01, 0.01), ze + e * _rng.randf_range(0.0, 0.03)),
					r, r * 0.95, 6, _c(BARK_C, BARK, _rng.randf_range(0.8, 1.35)), _c(BARK_C, BARK, _rng.randf_range(0.8, 1.35)))
				xx += r * 2.0 + _rng.randf_range(0.004, 0.02)
			yy += 0.13
	solids.append([AABB(Vector3(wx, -0.2, -hz - 0.12), Vector3(depth + 0.12, FLOOR_H + 2.3, hz * 2.0 + 0.24)), "wood"])
	bare.append(Rect2(wx - 0.1, -hz - 0.35, depth + 0.55, hz * 2.0 + 0.7))

## The cut end of one log, facing +X: whole, halved or quartered by the axe.
func _log_end(k: MeshKit, c: Vector3, r: float) -> void:
	var split := _rng.randi() % 3
	var rot := _rng.randf() * TAU
	var pts := []
	var arc := TAU
	var steps := 7
	var rr := r
	if split == 1:
		arc = PI
		steps = 5
		rr = r * 1.3
	elif split == 2:
		arc = PI * 0.5
		steps = 3
		rr = r * 1.6
	if split != 0:
		pts.append(c + Vector3(0, sin(rot + arc * 0.5), cos(rot + arc * 0.5)) * rr * -0.28)
	for i in steps + (0 if split == 0 else 1):
		var a := rot + arc * i / steps
		pts.append(c + Vector3(0, sin(a), cos(a)) * rr * _rng.randf_range(0.9, 1.05))
	var tone := _rng.randf_range(0.8, 1.12)
	var col := GRAIN_C.lerp(Color(0.3, 0.29, 0.26), _rng.randf() * 0.35)
	_fan(k, pts, Vector3.RIGHT, _c(col, GRAIN, tone), _c(col, GRAIN, tone * 0.62))

## A chopping block with an axe left in it, and chips round about.
func _chopping_block(k: MeshKit, at: Vector3) -> void:
	at.y = _ground(at.x, at.z)
	var top := at.y + 0.46
	k.cyl(at + Vector3(0, -0.08, 0), Vector3(at.x, top, at.z), 0.25, 0.235, 9, _c(BARK_C, BARK), _c(BARK_C, BARK))
	var pts := []
	for i in 11:
		var a := TAU * i / 11.0
		pts.append(Vector3(at.x + cos(a) * 0.232, top + 0.002, at.z + sin(a) * 0.232))
	_fan(k, pts, Vector3.UP, _c(GRAIN_C, GRAIN, 1.02), _c(GRAIN_C, GRAIN, 0.55))
	# the axe: its blade sunk in the top, the haft leaning out
	var tilt := Basis(Vector3.UP, 0.6) * Basis(Vector3.BACK, -0.5)
	var head := Vector3(at.x + 0.04, top + 0.025, at.z - 0.02)
	k.cyl(head, head + tilt * Vector3.UP * 0.68, 0.019, 0.016, 6, _c(Color(0.42, 0.32, 0.2), WOOD))
	_box(k, head, Vector3(0.17, 0.075, 0.026), tilt * Vector3.RIGHT, tilt * Vector3.UP, tilt * Vector3.BACK, _c(IRON_C, IRON))
	for i in 14:
		var a := _rng.randf() * TAU
		var dd := _rng.randf_range(0.35, 1.1)
		var p := Vector3(at.x + cos(a) * dd, 0.0, at.z + sin(a) * dd)
		p.y = _ground(p.x, p.z) + 0.006
		var yaw := Basis(Vector3.UP, _rng.randf() * TAU)
		_box(k, p, Vector3(_rng.randf_range(0.04, 0.09), 0.012, _rng.randf_range(0.02, 0.04)), yaw * Vector3.RIGHT, Vector3.UP, yaw * Vector3.BACK, _c(GRAIN_C, GRAIN, _rng.randf_range(0.8, 1.1)))
	solids.append([AABB(Vector3(at.x - 0.27, at.y, at.z - 0.27), Vector3(0.54, 0.5, 0.54)), "wood"])
	bare.append(Rect2(at.x - 0.6, at.z - 0.6, 1.2, 1.2))

## The outhouse (utedo) behind the cabin, with a heart cut in the door.
func _outhouse(k: MeshKit) -> void:
	var c := OUTHOUSE
	c.y = _ground(c.x, c.z)
	var oxf := Transform3D(Basis(Vector3.UP, 0.4), c)
	k.xf = oxf
	var hw := 0.62
	var front_h := 2.12
	var back_h := 1.86
	var y0 := 0.12
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			_stone(k, Vector3(sx * (hw - 0.04), 0.04, sz * (hw - 0.04)), Vector3(0.2, 0.15, 0.18), STONE_C)
	k.box_at(Vector3(0, y0 + 0.04, 0), Vector3(hw * 2.0 + 0.04, 0.08, hw * 2.0 + 0.04), _c(WOOD_D, WOOD))
	var slope := (front_h - back_h) / (hw * 2.0)
	var walls := [
		[Vector3(-hw, 0, hw), Vector3.RIGHT, Vector3.BACK, [[0.0, front_h], [hw * 2.0, front_h]]],
		[Vector3(hw, 0, -hw), Vector3.LEFT, Vector3.FORWARD, [[0.0, back_h], [hw * 2.0, back_h]]],
		[Vector3(-hw, 0, -hw), Vector3.BACK, Vector3.LEFT, [[0.0, back_h], [hw * 2.0, front_h]]],
		[Vector3(hw, 0, hw), Vector3.FORWARD, Vector3.RIGHT, [[0.0, front_h], [hw * 2.0, back_h]]],
	]
	var door_w := 0.64
	var door_h := 1.74
	for wall in walls:
		var holes := []
		if wall[2] == Vector3.BACK:
			holes.append([hw - door_w * 0.5 - 0.1, hw + door_w * 0.5 + 0.1, 0.0, y0 + door_h + 0.12])
		_wall(k, wall[0], wall[1], wall[2], hw * 2.0, y0, wall[3], holes, FALU, true)
		var o: Vector3 = wall[0]
		var along: Vector3 = wall[1]
		var out: Vector3 = wall[2]
		for e in [[0.0, 0.11], [hw * 2.0 - 0.11, hw * 2.0]]:
			var s0: float = e[0]
			var s1: float = e[1]
			var t := minf(_top_at(wall[3], s0), _top_at(wall[3], s1)) - 0.02
			_box(k, o + along * ((s0 + s1) * 0.5) + out * 0.015 + Vector3(0, (y0 + t) * 0.5, 0), Vector3(s1 - s0, t - y0, 0.03), along, Vector3.UP, out, _c(TRIM, PAINT))
	# the door: red boards in a white frame, a wooden turn-button, the heart
	var trim := _c(TRIM, PAINT)
	for i in 4:
		var x := -door_w * 0.5 + (i + 0.5) * door_w / 4.0
		k.box_at(Vector3(x, y0 + door_h * 0.5, hw + 0.016), Vector3(door_w / 4.0 - 0.008, door_h, 0.03), _c(FALU, PAINT, 0.85 + _rng.randf() * 0.12))
	k.box_at(Vector3(-door_w * 0.5 - 0.05, y0 + (door_h + 0.1) * 0.5, hw + 0.017), Vector3(0.1, door_h + 0.1, 0.034), trim)
	k.box_at(Vector3(door_w * 0.5 + 0.05, y0 + (door_h + 0.1) * 0.5, hw + 0.017), Vector3(0.1, door_h + 0.1, 0.034), trim)
	k.box_at(Vector3(0, y0 + door_h + 0.05, hw + 0.017), Vector3(door_w, 0.1, 0.034), trim)
	k.box_at(Vector3(door_w * 0.5 - 0.08, y0 + 0.95, hw + 0.045), Vector3(0.03, 0.11, 0.025), _c(WOOD_C, WOOD))
	var heart := []
	for i in 18:
		var t := TAU * i / 18.0
		var hx := 16.0 * pow(sin(t), 3.0)
		var hy := 13.0 * cos(t) - 5.0 * cos(2.0 * t) - 2.0 * cos(3.0 * t) - cos(4.0 * t)
		heart.append(Vector3(hx * 0.0058, y0 + 1.45 + hy * 0.0058, hw + 0.0325))
	_fan(k, heart, Vector3.BACK, _c(Color(0.012, 0.01, 0.01), PLAIN), _c(Color(0.012, 0.01, 0.01), PLAIN))
	# a lean-to turf roof, higher over the door
	var over := 0.22
	var pitch := atan(slope)
	var ridge := back_h + (hw * 2.0 + over) * slope
	var run := (hw * 2.0 + over * 2.0) / cos(pitch)
	k.xf = oxf * Transform3D(Basis(Vector3.UP, PI), Vector3(0, 0, hw + over))
	_slope(k, 1.0, ridge, pitch, -hw - 0.2, hw + 0.2, run, {"mono": true, "log": true, "top_log": true, "fringe": true})
	_barge(k, -hw - 0.2, 1.0, ridge, pitch, run, false, WOOD_D, -1.0, 0.24)
	_barge(k, hw + 0.2, 1.0, ridge, pitch, run, false, WOOD_D, 1.0, 0.24)
	k.xf = Transform3D.IDENTITY
	solids.append([AABB(Vector3(c.x - 0.88, c.y - 0.2, c.z - 0.88), Vector3(1.76, 2.6, 1.76)), "wood"])
	bare.append(Rect2(c.x - 1.0, c.z - 1.0, 2.0, 2.0))

## Stepping stones from the steps down towards the lake.
func _path(k: MeshKit) -> void:
	var z := DECK_Z + 1.75
	var x := DOOR_X + 0.25
	for i in 5:
		var at := Vector3(x + _rng.randf_range(-0.12, 0.12), 0.0, z)
		at.y = _ground(at.x, at.z) - 0.025
		_stone(k, at, Vector3(_rng.randf_range(0.28, 0.36), 0.06, _rng.randf_range(0.24, 0.31)), STONE_C.lightened(0.08))
		z += 0.85 + _rng.randf_range(-0.05, 0.1)
		x += 0.5

## Wood smoke from the chimney, drifting with the breeze.
func _add_smoke(at: Vector3) -> void:
	smoke = CPUParticles3D.new()
	smoke.name = "ChimneySmoke"
	smoke.amount = 26
	smoke.lifetime = 8.0
	smoke.preprocess = 8.0
	smoke.local_coords = false
	var quad := QuadMesh.new()
	var m := StandardMaterial3D.new()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.vertex_color_use_as_albedo = true
	m.albedo_texture = WorldUtil.blob_texture(64, 1.6)
	quad.material = m
	smoke.mesh = quad
	smoke.direction = Vector3.UP
	smoke.spread = 7.0
	smoke.initial_velocity_min = 0.45
	smoke.initial_velocity_max = 0.7
	smoke.gravity = Vector3(0.14, 0.05, 0.1)
	smoke.angle_min = -180.0
	smoke.angle_max = 180.0
	smoke.scale_amount_min = 0.35
	smoke.scale_amount_max = 0.55
	var grow := Curve.new()
	grow.max_value = 4.0
	grow.add_point(Vector2(0.0, 0.5))
	grow.add_point(Vector2(1.0, 3.4))
	smoke.scale_amount_curve = grow
	var ramp := Gradient.new()
	ramp.offsets = PackedFloat32Array([0.0, 0.12, 0.55, 1.0])
	ramp.colors = PackedColorArray([Color(1, 1, 1, 0), Color(1, 1, 1, 0.3), Color(1, 1, 1, 0.14), Color(1, 1, 1, 0)])
	smoke.color_ramp = ramp
	smoke.position = at
	cabin.add_child(smoke)

# ------------------------------------------------------------------- pier
func _build_pier() -> void:
	var fwd := Vector3(sin(data.cabin_yaw), 0, cos(data.cabin_yaw))
	var right := Vector3(fwd.z, 0, -fwd.x)
	var start := data.cabin_pos + fwd * 6.0 + right * 5.0
	var p := start
	for i in 80:
		if data.height(p.x, p.z) < 0.35:
			break
		p += fwd * 1.0
	var origin := Vector3(p.x, 0.0, p.z) - fwd * 2.0
	var k := MeshKit.new()
	var plank := Color(0.42, 0.34, 0.25)
	var post := Color(0.26, 0.21, 0.16, WOOD * 0.1)
	pier_len = 13.0
	for i in int(pier_len / 0.25):
		var z := i * 0.25 + 0.12
		var shade := 0.9 + G.hash2(i, 3, 5) * 0.2
		k.box_at(Vector3(0, PIER_Y - 0.03, z), Vector3(1.5, 0.05, 0.22), Color(plank.r * shade, plank.g * shade, plank.b * shade, WOOD * 0.1))
	for i in 5:
		var z := 0.3 + i * 3.1
		for sx in [-0.72, 0.72]:
			k.cyl(Vector3(sx, -3.0, z), Vector3(sx, PIER_Y + 0.25, z), 0.07, 0.07, 6, post, post, false, true)
		k.box_at(Vector3(0, PIER_Y - 0.12, z), Vector3(1.5, 0.1, 0.1), post)
	k.box_at(Vector3(-0.68, PIER_Y - 0.1, pier_len * 0.5), Vector3(0.08, 0.12, pier_len), post)
	k.box_at(Vector3(0.68, PIER_Y - 0.1, pier_len * 0.5), Vector3(0.08, 0.12, pier_len), post)
	# rowing boat moored at the end
	var bk := MeshKit.new()
	bk.xf = Transform3D(Basis.from_euler(Vector3(0.0, 0.25, 0.04)), Vector3(1.75, -0.16, pier_len - 3.2))
	var rings := []
	var cols := []
	var outer_c := Color(0.36, 0.13, 0.09, PAINT * 0.1)
	var inner_c := Color(0.55, 0.45, 0.32, WOOD * 0.1)
	for st in [[-1.7, 0.72, 0.0], [-0.9, 0.95, 0.0], [0.0, 1.0, 0.0], [0.9, 0.86, 0.02], [1.6, 0.5, 0.08], [2.05, 0.1, 0.2]]:
		var z: float = st[0]
		var s: float = st[1]
		var lift: float = st[2]
		var bw := 0.68 * s
		var bh := 0.5
		var t := 0.05
		var pts := PackedVector3Array([
			Vector3(-bw, bh, z), Vector3(-bw * 0.8, bh * 0.3 + lift, z), Vector3(0, lift, z),
			Vector3(bw * 0.8, bh * 0.3 + lift, z), Vector3(bw, bh, z),
			Vector3(maxf(bw - t, 0.01), bh, z), Vector3(maxf(bw * 0.8 - t, 0.008), bh * 0.3 + t + lift, z), Vector3(0, t + lift, z),
			Vector3(-maxf(bw * 0.8 - t, 0.008), bh * 0.3 + t + lift, z), Vector3(-maxf(bw - t, 0.01), bh, z),
		])
		rings.append(pts)
		cols.append([outer_c, outer_c, outer_c, outer_c, outer_c, inner_c, inner_c, inner_c, inner_c, inner_c])
	bk.loft(rings, cols, true, true)
	bk.box_at(Vector3(0, 0.3, -0.6), Vector3(1.25, 0.04, 0.24), inner_c.lightened(0.1))
	bk.box_at(Vector3(0, 0.3, 0.7), Vector3(1.1, 0.04, 0.24), inner_c.lightened(0.1))
	k.append_kit(bk)
	var node := MeshInstance3D.new()
	node.name = "Pier"
	node.mesh = k.commit(mat, null, true)
	add_child(node)
	node.position = origin
	node.rotation.y = data.cabin_yaw
	pier_xf = node.global_transform
	pier_inv = pier_xf.affine_inverse()

# ------------------------------------------------------------------ tower
func _build_tower(base: Vector3, yaw: float) -> void:
	var k := MeshKit.new()
	var wood := Color(0.40, 0.33, 0.26, WOOD * 0.1)
	var wood_d := Color(0.30, 0.25, 0.20, WOOD * 0.1)
	var h := TOWER_H
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			k.cyl(Vector3(sx * 1.3, -1.2, sz * 1.3), Vector3(sx * 0.95, h, sz * 0.95), 0.09, 0.08, 6, wood_d)
			k.box_at(Vector3(sx * 0.95, h + 1.05, sz * 0.95), Vector3(0.09, 2.1, 0.09), wood)
	# cross braces
	for side in 4:
		var rot := Basis.from_euler(Vector3(0, side * PI * 0.5, 0))
		k.cyl(rot * Vector3(-1.22, 0.4, 1.22), rot * Vector3(1.0, h - 0.5, 1.0), 0.045, 0.045, 4, wood)
		k.cyl(rot * Vector3(1.22, 0.4, 1.22), rot * Vector3(-1.0, h - 0.5, 1.0), 0.045, 0.045, 4, wood)
		# rail boards (front has a lower shooting rest)
		var top := 0.95 if side == 0 else 1.1
		for by in [0.3, 0.62, top]:
			k.box(Vector3(2.0, 0.2 if by < top else 0.1, 0.035), Transform3D(rot, rot * Vector3(0, h + by, 0.98)), wood.darkened(G.hash2(side, int(by * 10.0), 2) * 0.2))
	k.box_at(Vector3(0, h - 0.05, 0), Vector3(2.1, 0.1, 2.1), wood)
	k.box(Vector3(2.7, 0.07, 2.7), Transform3D(Basis.from_euler(Vector3(0.12, 0, 0)), Vector3(0, h + 2.2, 0.1)), Color(0.16, 0.16, 0.17, IRON * 0.1))
	# ladder at the back
	for sx in [-0.28, 0.28]:
		k.cyl(Vector3(sx, -0.3, -1.75), Vector3(sx, h + 0.9, -1.02), 0.035, 0.035, 5, wood_d)
	for i in 11:
		var u := (i + 0.5) / 11.0
		var c := Vector3(0, lerpf(0.1, h, u), lerpf(-1.7, -1.06, u))
		k.cyl(c - Vector3(0.28, 0, 0), c + Vector3(0.28, 0, 0), 0.025, 0.025, 4, wood)
	var node := MeshInstance3D.new()
	node.name = "Tower"
	node.mesh = k.commit(mat, null, true)
	add_child(node)
	node.position = base
	node.rotation.y = yaw
	towers.append([base, yaw])

# ---------------------------------------------------------------- queries
## Walkable surface above the terrain (deck, steps, pier), or `base_h`.
func surface_height(x: float, z: float, base_h: float, feet_y: float) -> float:
	var lp := pier_inv * Vector3(x, 0.0, z)
	if absf(lp.x) < 0.8 and lp.z > -0.2 and lp.z < pier_len and feet_y > PIER_Y - 0.7:
		return maxf(base_h, PIER_Y)
	var lc := cabin_inv * Vector3(x, data.cabin_pos.y, z)
	if lc.x * lc.x + lc.z * lc.z > 100.0:
		return base_h
	var p := Vector2(lc.x, lc.z)
	for f in floors:
		if (f[0] as Rect2).has_point(p):
			return maxf(base_h, data.cabin_pos.y + float(f[1]))
	return base_h

## Keep a circle of `radius` (feet at pos.y) out of the cabin, its railings and
## outbuildings. Returns the corrected position.
func push_out(pos: Vector3, radius: float) -> Vector3:
	var l := cabin_inv * pos
	if l.x * l.x + l.z * l.z > 196.0:
		return pos
	var moved := false
	for s in solids:
		var b: AABB = s[0]
		if l.y + 1.7 < b.position.y or l.y > b.end.y - 0.05:
			continue
		var cx := clampf(l.x, b.position.x, b.end.x)
		var cz := clampf(l.z, b.position.z, b.end.z)
		var dx := l.x - cx
		var dz := l.z - cz
		var d2 := dx * dx + dz * dz
		if d2 >= radius * radius:
			continue
		if d2 > 1e-8:
			var dd := sqrt(d2)
			l.x = cx + dx / dd * radius
			l.z = cz + dz / dd * radius
		else:
			# inside: out through the nearest side
			var to_x0 := l.x - b.position.x
			var to_x1 := b.end.x - l.x
			var to_z0 := l.z - b.position.z
			var to_z1 := b.end.z - l.z
			var m := minf(minf(to_x0, to_x1), minf(to_z0, to_z1))
			if m == to_x0:
				l.x = b.position.x - radius
			elif m == to_x1:
				l.x = b.end.x + radius
			elif m == to_z0:
				l.z = b.position.z - radius
			else:
				l.z = b.end.z + radius
		moved = true
	if not moved:
		return pos
	var w := _xf * l
	return Vector3(w.x, pos.y, w.z)

## Steering push away from the cabin and its outbuildings, for animals (world x, z).
func avoid_vector(pos: Vector3, reach: float) -> Vector2:
	var l := cabin_inv * pos
	if l.x * l.x + l.z * l.z > 400.0:
		return Vector2.ZERO
	var push := Vector2.ZERO
	for s in solids:
		var b: AABB = s[0]
		var cx := clampf(l.x, b.position.x, b.end.x)
		var cz := clampf(l.z, b.position.z, b.end.z)
		var dv := Vector2(l.x - cx, l.z - cz)
		var dist := dv.length()
		if dist >= reach:
			continue
		if dist < 0.001:
			var ctr := b.get_center()
			dv = Vector2(l.x - ctr.x, l.z - ctr.z)
		push += dv.normalized() * (1.0 - dist / reach)
	if push == Vector2.ZERO:
		return push
	var w := _xf.basis * Vector3(push.x, 0, push.y)
	return Vector2(w.x, w.z)

## True where no ground cover should grow: under the cabin, deck and outbuildings, on the pier.
func covers(x: float, z: float) -> bool:
	var lp := pier_inv * Vector3(x, 0.0, z)
	if absf(lp.x) < 0.95 and lp.z > -0.4 and lp.z < pier_len + 0.3:
		return true
	var lc := cabin_inv * Vector3(x, data.cabin_pos.y, z)
	if lc.x * lc.x + lc.z * lc.z > 144.0:
		return false
	var p := Vector2(lc.x, lc.z)
	for r in bare:
		if (r as Rect2).has_point(p):
			return true
	return false

## Segment vs the cabin and its outbuildings. Returns {pos, normal, kind} or {}.
func ray(from: Vector3, to: Vector3) -> Dictionary:
	if from.distance_squared_to(data.cabin_pos) > 250000.0 and to.distance_squared_to(data.cabin_pos) > 250000.0:
		return {}
	var a := cabin_inv * from
	var b := cabin_inv * to
	var best := INF
	var hit := Vector3.ZERO
	var kind := ""
	for s in solids:
		var box: AABB = s[0]
		var h = box.intersects_segment(a, b)
		if h == null:
			continue
		var dd := a.distance_squared_to(h)
		if dd < best:
			best = dd
			hit = h
			kind = s[1]
	if kind == "":
		return {}
	if kind == "house":
		kind = "rock" if hit.y < FLOOR_H - 0.07 else "wood"
	return {"pos": _xf * hit, "normal": (from - to).normalized(), "kind": kind}

## Where the menu camera stands at time `t` (seconds) and what it looks at: on the
## slope in front of the cabin with the morning sun behind it, the cabin in the
## right half of the picture (the menu itself sits on the left), drifting slowly.
func menu_view(t: float) -> Array:
	var x := 10.0 + sin(t * 0.045) * 1.2
	var z := 13.0 + sin(t * 0.033) * 0.5
	var eye := _xf * Vector3(x, _ground(x, z) + 2.6 + sin(t * 0.06) * 0.15, z)
	var target := _xf * Vector3(-5.9, 1.7, 0.9)
	return [eye, target]

func tower_near(pos: Vector3, reach := 3.2) -> int:
	for i in towers.size():
		var base: Vector3 = towers[i][0]
		if Vector2(pos.x - base.x, pos.z - base.z).length() < reach:
			return i
	return -1

func tower_top(index: int) -> Vector3:
	var base: Vector3 = towers[index][0]
	return base + Vector3(0, TOWER_H, 0)

func tower_yaw(index: int) -> float:
	return towers[index][1]

## 0 by day .. 1 at dusk: the lantern, lamplight in the windows, the colour of the smoke.
func update_lights(twilight: float) -> void:
	var t := clampf(twilight, 0.0, 1.0)
	if absf(t - _lit) < 0.004:
		return
	_lit = t
	if lantern:
		lantern.visible = t > 0.06
		lantern.light_energy = lerpf(0.0, 1.7, t)
	glow_mat.emission_energy_multiplier = lerpf(0.0, 2.4, t)
	glass_mat.set_shader_parameter("glow", t)
	if smoke:
		smoke.color = Color(0.82, 0.82, 0.84).lerp(Color(0.48, 0.43, 0.45), t * 0.85)
