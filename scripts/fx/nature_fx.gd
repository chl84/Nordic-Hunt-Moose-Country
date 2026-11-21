class_name NatureFx
extends Node3D
## Small living touches round the hunter: mist lying over the lakes and bogs at dawn
## (thinner at dusk), breath smoking in the cold air - the hunter's and that of moose
## nearby - and birch leaves coming down on the wind.

# ------------------------------------------------------------------- mist
var _mist: MultiMeshInstance3D
var _mist_mat: ShaderMaterial
var mist_scale := 1.0           ## 0 hides the mist (dev A/B)

# ----------------------------------------------------------------- breath
var _breath_mat: StandardMaterial3D
var _player_breath: CPUParticles3D
var _moose_breath: Array[CPUParticles3D] = []
var _moose_next := 0
var _breath_t := 1.5
var _exert := 0.0               ## 0..1, built up by sprinting: quicker, bigger breaths
var _moose_t := {}              ## moose instance id -> seconds to its next breath

# ----------------------------------------------------------------- leaves
const LEAVES := 90
const LEAF_RANGE := 28.0        ## leaves come off birches this close to the camera
const LEAF_COLOURS := [Color(0.93, 0.75, 0.21), Color(0.90, 0.56, 0.16), Color(0.95, 0.84, 0.34), Color(0.62, 0.42, 0.17), Color(0.86, 0.66, 0.19)]
var _leaf_mm: MultiMesh
var _leaf_buf := PackedFloat32Array()
var _leaves: Array = []         ## per leaf: {on, lying, pos, basis, spin_axis, spin, phase, freq, life, col}
var _crowns := PackedFloat32Array()
var _crown_t := 0.0
var _spawn_acc := 0.0
var _noise_img: Image
var _rng := RandomNumberGenerator.new()

func _ready() -> void:
	_rng.seed = 4711
	_build_mist()
	_build_breath()
	_build_leaves()

func _process(dt: float) -> void:
	var t: float = G.sky.time if G.sky else 0.5
	var a := mist_amount(t) * mist_scale
	_mist.visible = a > 0.01
	if _mist.visible:
		_mist_mat.set_shader_parameter("amount", a)
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	_update_breath(dt, t, cam)
	_update_leaves(dt, cam)

## How thick the mist lies: all there at first light, lifting from about 07:30 and gone by
## 08:15 (the hunt runs 06:30 -> 18:30 as t 0 -> 1); a faint trace again in the last of the dusk.
static func mist_amount(t: float) -> float:
	return (1.0 - smoothstep(0.083, 0.146, t)) + smoothstep(0.92, 0.99, t) * 0.3

## How cold the air is for breath to show: the frosty early morning (gone by about 08:30),
## and again from about 17:30.
static func cold_at(t: float) -> float:
	return clampf((1.0 - smoothstep(0.1, 0.167, t)) + smoothstep(0.917, 0.98, t) * 0.8, 0.0, 1.0)

# ------------------------------------------------------------------- mist
func _build_mist() -> void:
	var d: TerrainData = G.terrain
	var items: Array = []       # [centre, width, height, thickness]
	for L in d.lakes:
		var n := int(clampf(float(L[2]) * float(L[3]) / 900.0, 6.0, 26.0))
		for i in n:
			var ang := _rng.randf() * TAU
			var r := sqrt(_rng.randf()) * 0.85
			var p := Vector3(float(L[0]) + cos(ang) * r * float(L[2]), 0.0, float(L[1]) + sin(ang) * r * float(L[3]))
			items.append([p, _rng.randf_range(22.0, 40.0), _rng.randf_range(1.8, 3.5), _rng.randf_range(0.7, 1.0)])
	# and over the bogs: low, open, wet ground
	var bogs := 0
	var tries := 0
	while bogs < 40 and tries < 4000:
		tries += 1
		var x := _rng.randf_range(-470.0, 470.0)
		var z := _rng.randf_range(-470.0, 470.0)
		var h := d.height(x, z)
		if h < 0.2 or h > 2.4 or d.forest_at(x, z) > 0.3:
			continue
		items.append([Vector3(x, h, z), _rng.randf_range(16.0, 30.0), _rng.randf_range(1.5, 2.5), _rng.randf_range(0.4, 0.8)])
		bogs += 1
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	mm.mesh = quad
	mm.instance_count = items.size()
	for i in items.size():
		var it: Array = items[i]
		var hgt: float = it[2]
		var c: Vector3 = it[0] + Vector3(0, hgt * 0.5 - 0.25, 0)     # the bottom just under the surface
		mm.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3(it[1], hgt, 1.0)), c))
		mm.set_instance_color(i, Color(_rng.randf(), 0.0, 0.0, it[3]))
	_mist_mat = ShaderMaterial.new()
	_mist_mat.shader = load("res://shaders/mist.gdshader")
	_mist_mat.set_shader_parameter("noise_tex", G.world.noise_tex)
	_mist = MultiMeshInstance3D.new()
	_mist.name = "Mist"
	_mist.multimesh = mm
	_mist.material_override = _mist_mat
	_mist.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_mist.custom_aabb = AABB(Vector3(-560, -10, -560), Vector3(1120, 40, 1120))
	add_child(_mist)

# ----------------------------------------------------------------- breath
func _build_breath() -> void:
	_breath_mat = StandardMaterial3D.new()
	_breath_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_breath_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_breath_mat.vertex_color_use_as_albedo = true
	_breath_mat.albedo_texture = WorldUtil.blob_texture(64, 1.6)
	_breath_mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	_breath_mat.billboard_keep_scale = true
	_breath_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	# (fades out right at the lens instead of filling the screen as you walk into it)
	_breath_mat.distance_fade_mode = BaseMaterial3D.DISTANCE_FADE_PIXEL_ALPHA
	_breath_mat.distance_fade_min_distance = 0.12
	_breath_mat.distance_fade_max_distance = 0.6
	_player_breath = _breath_emitter(10, 1.2, 0.04, 0.065, 0.22, 3.4)
	for i in 5:
		_moose_breath.append(_breath_emitter(14, 1.8, 0.14, 0.24, 0.22, 3.6))

func _breath_emitter(count: int, life: float, s0: float, s1: float, peak: float, grow: float) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	var q := QuadMesh.new()
	q.size = Vector2.ONE
	q.material = _breath_mat
	p.mesh = q
	p.one_shot = true
	p.emitting = false
	p.explosiveness = 0.75
	p.local_coords = false
	p.amount = count
	p.lifetime = life
	p.spread = 16.0
	p.damping_min = 0.9
	p.damping_max = 1.4
	p.gravity = Vector3(0, 0.1, 0)
	p.scale_amount_min = s0
	p.scale_amount_max = s1
	var c := Curve.new()
	c.max_value = 5.0
	c.add_point(Vector2(0, 0.6))
	c.add_point(Vector2(1, grow))
	p.scale_amount_curve = c
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.18, 1.0])
	g.colors = PackedColorArray([Color(1, 1, 1, 0.0), Color(1, 1, 1, peak), Color(1, 1, 1, 0.0)])
	p.color_ramp = g
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.visibility_aabb = AABB(Vector3(-4, -4, -4), Vector3(8, 8, 8))
	add_child(p)
	return p

func _breath_tint(t: float, strength: float) -> Color:
	var light := 0.6 + 0.3 * sin(PI * clampf(t, 0.03, 0.97))
	return Color(0.88 * light, 0.9 * light, 0.93 * light, clampf(strength, 0.0, 1.0))

func _update_breath(dt: float, t: float, cam: Camera3D) -> void:
	var cold := cold_at(t)
	var pl = G.player
	if pl and cam == pl.cam:
		if pl.sprinting:
			_exert = minf(_exert + dt * 0.3, 1.0)
		else:
			_exert = maxf(_exert - dt * 0.05, 0.0)
		_breath_t -= dt
		if _breath_t <= 0.0:
			_breath_t = lerpf(5.0, 1.6, _exert) * _rng.randf_range(0.8, 1.2)
			# (no breath while aiming or glassing: the hunter holds it)
			if cold > 0.05 and pl.weapon.ads < 0.5 and not pl.binoc:
				var fwd := -cam.global_basis.z
				# out and down from the mouth, so it drifts away under the line of sight
				var v: Vector3 = fwd * 0.5 + Vector3(pl.vel.x, 0.0, pl.vel.z) * 0.9 + Vector3(0, -0.25, 0)
				_player_breath.global_position = cam.global_position + fwd * 0.45 + Vector3(0, -0.26, 0)
				_puff(_player_breath, v, _breath_tint(t, cold * (0.55 + 0.75 * _exert)))
	if G.herd == null or cold <= 0.05:
		return
	for m in G.herd.moose:
		if not is_instance_valid(m) or m.dead:
			continue
		if m.global_position.distance_squared_to(cam.global_position) > 90.0 * 90.0:
			continue
		var id: int = m.get_instance_id()
		var left := float(_moose_t.get(id, _rng.randf_range(0.0, 3.0))) - dt
		if left <= 0.0:
			var fleeing: bool = m.state == Moose.State.FLEE
			left = (1.2 if fleeing else 3.2) * _rng.randf_range(0.8, 1.2)
			var fwd: Vector3 = m.forward()
			# the nostrils, wherever the head is (grazing, looking round, running)
			var hb := MooseModel.B.HEAD
			var nose: Vector3 = m.skel.global_transform * (m.skel.get_bone_global_pose(hb) * (Vector3(0, 1.6, -2.36) - MooseModel.rest(hb)))
			var p: CPUParticles3D = _moose_breath[_moose_next]
			_moose_next = (_moose_next + 1) % _moose_breath.size()
			p.global_position = nose
			_puff(p, fwd * (1.4 if fleeing else 0.9) + Vector3(0, -0.35, 0), _breath_tint(t, cold * (1.0 if fleeing else 0.8)))
		_moose_t[id] = left

func _puff(p: CPUParticles3D, v: Vector3, tint: Color) -> void:
	# the breath rises a little and goes off with the wind
	if G.wind:
		var wd: Vector2 = G.wind.dir
		var ws: float = clampf(float(G.wind.speed) / 3.3, 0.2, 1.8)
		p.gravity = Vector3(wd.x * 0.45 * ws, 0.1, wd.y * 0.45 * ws)
	p.direction = v.normalized()
	p.initial_velocity_min = v.length() * 0.85
	p.initial_velocity_max = v.length() * 1.15
	p.color = tint
	p.restart()
	p.emitting = true

# ----------------------------------------------------------------- leaves
func _build_leaves() -> void:
	var q := QuadMesh.new()
	q.size = Vector2(0.09, 0.12)       # (a little over life size, or they vanish beyond a few metres)
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/leaf.gdshader")
	q.material = mat
	_leaf_mm = MultiMesh.new()
	_leaf_mm.transform_format = MultiMesh.TRANSFORM_3D
	_leaf_mm.use_colors = true
	_leaf_mm.mesh = q
	_leaf_mm.instance_count = LEAVES
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "Leaves"
	mmi.multimesh = _leaf_mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.custom_aabb = AABB(Vector3(-600, -20, -600), Vector3(1200, 400, 1200))
	add_child(mmi)
	_leaf_buf.resize(LEAVES * 16)
	_leaf_buf.fill(0.0)
	for i in LEAVES:
		_leaves.append({"on": false})
	_leaf_mm.buffer = _leaf_buf
	_noise_img = G.world.noise_tex.get_image()
	if _noise_img.is_compressed():
		_noise_img.decompress()

## The gust passing over `p` (0..1): atmo_gust() in atmo.gdshaderinc, on the CPU, so the
## leaves come off and blow about when the grass leans.
func gust_at(p: Vector3) -> float:
	var time := fmod(Time.get_ticks_msec() * 0.001, 3600.0)
	var wd: Vector2 = G.wind.dir if G.wind else Vector2(0.8, 0.6)
	var xz := Vector2(p.x, p.z)
	var uv := Vector2(xz.dot(wd) * 0.014 - time * 0.1, xz.dot(Vector2(-wd.y, wd.x)) * 0.006)
	var w := _noise_img.get_width()
	var h := _noise_img.get_height()
	var x := uv.x * w - 0.5
	var y := uv.y * h - 0.5
	var x0 := floori(x)
	var y0 := floori(y)
	var a := lerpf(_noise_img.get_pixel(posmod(x0, w), posmod(y0, h)).r, _noise_img.get_pixel(posmod(x0 + 1, w), posmod(y0, h)).r, x - x0)
	var b := lerpf(_noise_img.get_pixel(posmod(x0, w), posmod(y0 + 1, h)).r, _noise_img.get_pixel(posmod(x0 + 1, w), posmod(y0 + 1, h)).r, x - x0)
	return smoothstep(0.45, 0.78, lerpf(a, b, y - y0))

func _spawn_leaf() -> void:
	var n := _crowns.size() / 4
	if n == 0:
		return
	for lf in _leaves:
		if lf["on"]:
			continue
		# (of two birches picked at random, the nearer: most leaves come down close by)
		var i := _rng.randi() % n
		var j := _rng.randi() % n
		var cam := get_viewport().get_camera_3d()
		if cam:
			var cp := cam.global_position
			if Vector2(_crowns[j * 4] - cp.x, _crowns[j * 4 + 2] - cp.z).length() < Vector2(_crowns[i * 4] - cp.x, _crowns[i * 4 + 2] - cp.z).length():
				i = j
		var r := _crowns[i * 4 + 3]
		var c := Vector3(_crowns[i * 4], _crowns[i * 4 + 1], _crowns[i * 4 + 2])
		lf["on"] = true
		lf["lying"] = false
		lf["pos"] = c + Vector3(_rng.randf_range(-r, r) * 0.8, _rng.randf_range(-1.8, 1.0), _rng.randf_range(-r, r) * 0.8)
		lf["basis"] = Basis.from_euler(Vector3(_rng.randf() * TAU, _rng.randf() * TAU, _rng.randf() * TAU))
		lf["spin_axis"] = Vector3(_rng.randf_range(-1, 1), _rng.randf_range(-1, 1), _rng.randf_range(-1, 1)).normalized()
		lf["spin"] = _rng.randf_range(3.0, 7.0)
		lf["phase"] = _rng.randf() * TAU
		lf["freq"] = _rng.randf_range(2.4, 4.0)
		lf["life"] = 9.0
		var col: Color = LEAF_COLOURS[_rng.randi() % LEAF_COLOURS.size()]
		lf["col"] = col.darkened(_rng.randf_range(0.0, 0.12))
		return

func _update_leaves(dt: float, cam: Camera3D) -> void:
	var cp := cam.global_position
	_crown_t -= dt
	if _crown_t <= 0.0:
		_crown_t = 0.5
		_crowns = G.flora.birches_near(cp, LEAF_RANGE) if G.flora else PackedFloat32Array()
	var gust := gust_at(cp)
	var wd: Vector2 = G.wind.dir if G.wind else Vector2(0.8, 0.6)
	var ws: float = G.wind.strength() if G.wind else 1.0
	var wind := Vector3(wd.x, 0.0, wd.y) * (0.5 + gust * 2.6) * ws
	var side := Vector3(-wd.y, 0.0, wd.x)
	var n_crowns := _crowns.size() / 4
	if n_crowns > 0:
		# a few leaves at any time, a flurry when a gust comes through
		_spawn_acc += dt * (0.2 + gust * 1.4) * minf(n_crowns, 12.0)
		while _spawn_acc >= 1.0:
			_spawn_acc -= 1.0
			_spawn_leaf()
	for i in LEAVES:
		var lf: Dictionary = _leaves[i]
		var o := i * 16
		if not lf["on"]:
			if _leaf_buf[o] != 0.0 or _leaf_buf[o + 5] != 0.0:
				for k in 12:
					_leaf_buf[o + k] = 0.0
			continue
		var pos: Vector3 = lf["pos"]
		var basis: Basis = lf["basis"]
		var fade := 1.0
		if lf["lying"]:
			lf["life"] = float(lf["life"]) - dt
			fade = clampf(float(lf["life"]), 0.0, 1.0)
			if lf["life"] <= 0.0:
				lf["on"] = false
		else:
			lf["phase"] = float(lf["phase"]) + dt * float(lf["freq"])
			var ph: float = lf["phase"]
			# fluttering down: swinging side to side, dropping fastest edge-on at the bottom of each swing
			var fall := 0.55 + 0.5 * absf(cos(ph))
			pos += (wind + side * sin(ph) * 0.8 + Vector3(0, -fall, 0)) * dt
			basis = basis.rotated(lf["spin_axis"], float(lf["spin"]) * dt).orthonormalized()
			var ground: float = maxf(G.terrain.height(pos.x, pos.z), 0.0)
			if pos.y <= ground + 0.012:
				pos.y = ground + 0.012
				lf["lying"] = true
				basis = Basis(Vector3.UP, _rng.randf() * TAU) * Basis(Vector3.RIGHT, -PI * 0.5)
			if pos.distance_squared_to(cp) > 50.0 * 50.0:
				lf["on"] = false
		lf["pos"] = pos
		lf["basis"] = basis
		var b := basis.scaled(Vector3.ONE * fade) if fade < 1.0 else basis
		var col: Color = lf["col"]
		_leaf_buf[o] = b.x.x
		_leaf_buf[o + 1] = b.y.x
		_leaf_buf[o + 2] = b.z.x
		_leaf_buf[o + 3] = pos.x
		_leaf_buf[o + 4] = b.x.y
		_leaf_buf[o + 5] = b.y.y
		_leaf_buf[o + 6] = b.z.y
		_leaf_buf[o + 7] = pos.y
		_leaf_buf[o + 8] = b.x.z
		_leaf_buf[o + 9] = b.y.z
		_leaf_buf[o + 10] = b.z.z
		_leaf_buf[o + 11] = pos.z
		_leaf_buf[o + 12] = col.r
		_leaf_buf[o + 13] = col.g
		_leaf_buf[o + 14] = col.b
		_leaf_buf[o + 15] = 1.0
	_leaf_mm.buffer = _leaf_buf

## Active leaves (falling, lying): for tests.
func leaf_count() -> Vector2i:
	var falling := 0
	var lying := 0
	for lf in _leaves:
		if lf["on"]:
			if lf["lying"]:
				lying += 1
			else:
				falling += 1
	return Vector2i(falling, lying)
