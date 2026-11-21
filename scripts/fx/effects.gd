class_name Effects
extends Node3D
## Pooled particle bursts (blood, dust, bark, spray, smoke) and ejected brass.

const POOL := 6

var _pools := {}
var _next := {}
var _mat: StandardMaterial3D
var _quad: QuadMesh
var _casings: Array = []      ## [{node, vel, spin, life, bounced}]
var _casing_mesh: ArrayMesh
var _ripples: Array = []
var _ripple_mat: StandardMaterial3D

func _ready() -> void:
	_mat = StandardMaterial3D.new()
	_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mat.vertex_color_use_as_albedo = true
	_mat.albedo_texture = WorldUtil.blob_texture(64, 1.6)
	_mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	_mat.billboard_keep_scale = true
	_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_quad = QuadMesh.new()
	_quad.size = Vector2(1, 1)
	_quad.material = _mat
	for kind in ["blood", "mist", "dust", "debris", "splash", "spark", "smoke"]:
		_pools[kind] = []
		_next[kind] = 0
		for i in POOL:
			var p := _make(kind)
			add_child(p)
			_pools[kind].append(p)
	# brass
	var k := MeshKit.new()
	var brass := Color(0.83, 0.62, 0.26)
	k.cyl(Vector3(0, 0, 0.028), Vector3(0, 0, -0.028), 0.0062, 0.0058, 7, brass, brass, true, true)
	var cm := StandardMaterial3D.new()
	cm.vertex_color_use_as_albedo = true
	cm.metallic = 0.9
	cm.roughness = 0.28
	_casing_mesh = k.commit(cm, null, true)
	_ripple_mat = StandardMaterial3D.new()
	_ripple_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_ripple_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_ripple_mat.albedo_texture = _ring_texture()
	_ripple_mat.cull_mode = BaseMaterial3D.CULL_DISABLED

static func _ring_texture() -> ImageTexture:
	var size := 96
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	for y in size:
		for x in size:
			var d := Vector2(x + 0.5 - size * 0.5, y + 0.5 - size * 0.5).length() / (size * 0.5)
			var a := exp(-pow((d - 0.82) / 0.07, 2.0)) * 0.8 + exp(-pow((d - 0.5) / 0.06, 2.0)) * 0.35
			img.set_pixel(x, y, Color(1, 1, 1, clampf(a, 0.0, 1.0)))
	return ImageTexture.create_from_image(img)

func _grad(c0: Color, c1: Color) -> Gradient:
	var g := Gradient.new()
	g.set_color(0, c0)
	g.set_color(1, c1)
	return g

func _curve(a: float, b: float) -> Curve:
	var c := Curve.new()
	c.add_point(Vector2(0, a))
	c.add_point(Vector2(1, b))
	return c

func _make(kind: String) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.mesh = _quad
	p.one_shot = true
	p.emitting = false
	p.explosiveness = 0.94
	p.local_coords = false
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.visibility_aabb = AABB(Vector3(-6, -6, -6), Vector3(12, 12, 12))
	match kind:
		"blood":
			p.amount = 30
			p.lifetime = 0.8
			p.spread = 30.0
			p.initial_velocity_min = 2.0
			p.initial_velocity_max = 7.5
			p.gravity = Vector3(0, -9.8, 0)
			p.scale_amount_min = 0.03
			p.scale_amount_max = 0.1
			p.color_ramp = _grad(Color(0.45, 0.02, 0.02, 1.0), Color(0.3, 0.01, 0.01, 0.0))
		"mist":
			p.amount = 10
			p.lifetime = 1.0
			p.spread = 50.0
			p.initial_velocity_min = 0.3
			p.initial_velocity_max = 1.6
			p.gravity = Vector3(0, -0.5, 0)
			p.damping_min = 1.5
			p.damping_max = 2.5
			p.scale_amount_min = 0.25
			p.scale_amount_max = 0.6
			p.scale_amount_curve = _curve(0.5, 1.4)
			p.color_ramp = _grad(Color(0.5, 0.04, 0.04, 0.5), Color(0.4, 0.03, 0.03, 0.0))
		"dust":
			p.amount = 16
			p.lifetime = 1.5
			p.spread = 45.0
			p.initial_velocity_min = 0.8
			p.initial_velocity_max = 4.0
			p.gravity = Vector3(0, -0.8, 0)
			p.damping_min = 2.0
			p.damping_max = 3.5
			p.scale_amount_min = 0.25
			p.scale_amount_max = 0.7
			p.scale_amount_curve = _curve(0.4, 1.6)
			p.color_ramp = _grad(Color(1, 1, 1, 0.6), Color(1, 1, 1, 0.0))
		"debris":
			p.amount = 16
			p.lifetime = 1.0
			p.spread = 38.0
			p.initial_velocity_min = 2.5
			p.initial_velocity_max = 8.0
			p.gravity = Vector3(0, -9.8, 0)
			p.scale_amount_min = 0.03
			p.scale_amount_max = 0.08
			p.color_ramp = _grad(Color(1, 1, 1, 1.0), Color(1, 1, 1, 0.0))
		"splash":
			p.amount = 34
			p.lifetime = 1.0
			p.spread = 16.0
			p.direction = Vector3.UP
			p.initial_velocity_min = 3.0
			p.initial_velocity_max = 9.5
			p.gravity = Vector3(0, -9.8, 0)
			p.scale_amount_min = 0.05
			p.scale_amount_max = 0.14
			p.color_ramp = _grad(Color(0.88, 0.93, 0.96, 0.9), Color(0.88, 0.93, 0.96, 0.0))
		"spark":
			p.amount = 10
			p.lifetime = 0.3
			p.spread = 50.0
			p.initial_velocity_min = 4.0
			p.initial_velocity_max = 11.0
			p.gravity = Vector3(0, -9.8, 0)
			p.scale_amount_min = 0.02
			p.scale_amount_max = 0.045
			p.color_ramp = _grad(Color(1.0, 0.85, 0.5, 1.0), Color(1.0, 0.5, 0.1, 0.0))
		"smoke":
			p.amount = 9
			p.lifetime = 1.2
			p.explosiveness = 0.8
			p.spread = 14.0
			p.initial_velocity_min = 1.2
			p.initial_velocity_max = 4.5
			p.gravity = Vector3(0, 0.35, 0)
			p.damping_min = 3.0
			p.damping_max = 5.0
			p.scale_amount_min = 0.1
			p.scale_amount_max = 0.24
			p.scale_amount_curve = _curve(0.5, 2.4)
			p.color_ramp = _grad(Color(0.85, 0.85, 0.85, 0.26), Color(0.85, 0.85, 0.85, 0.0))
	return p

func _daylight() -> float:
	if G.sky == null:
		return 1.0
	return 0.5 + 0.5 * sin(PI * clampf(G.sky.time, 0.03, 0.97))

func _burst(kind: String, pos: Vector3, dir: Vector3, color := Color.WHITE, scale_mul := 1.0) -> void:
	var pool: Array = _pools[kind]
	var p: CPUParticles3D = pool[_next[kind]]
	_next[kind] = (_next[kind] + 1) % pool.size()
	p.global_position = pos
	if dir != Vector3.ZERO:
		p.direction = dir.normalized()
	var l := _daylight()
	p.color = Color(color.r * l, color.g * l, color.b * l, color.a)
	p.scale = Vector3.ONE * scale_mul
	p.restart()
	p.emitting = true

## Fire every emitter once out of sight so their shaders are compiled before play.
func prewarm(at: Vector3) -> void:
	for kind in _pools:
		_burst(kind, at, Vector3.UP)
	eject_casing(at, Vector3.ZERO)

# ---------------------------------------------------------------- impacts
func blood_hit(pos: Vector3, bullet_dir: Vector3, heavy: bool) -> void:
	if not Settings.get_v("blood"):
		_burst("dust", pos, -bullet_dir, Color(0.5, 0.42, 0.35), 0.5)
		return
	_burst("blood", pos, (-bullet_dir + Vector3(0, 0.35, 0)), Color.WHITE, 0.8)
	_burst("mist", pos, -bullet_dir)
	if heavy:
		_burst("blood", pos + bullet_dir * 0.5, (bullet_dir + Vector3(0, 0.2, 0)), Color.WHITE, 1.3)
		_burst("mist", pos + bullet_dir * 0.55, bullet_dir, Color.WHITE, 1.3)

func impact_dirt(pos: Vector3, normal: Vector3, ground: Color) -> void:
	var c := Color(ground.r * 1.5 + 0.12, ground.g * 1.5 + 0.11, ground.b * 1.5 + 0.09, 1.0)
	_burst("dust", pos + normal * 0.1, normal, c)
	_burst("debris", pos + normal * 0.05, normal + Vector3(0, 0.4, 0), Color(ground.r * 0.7, ground.g * 0.7, ground.b * 0.7))

func impact_wood(pos: Vector3, normal: Vector3) -> void:
	_burst("debris", pos + normal * 0.05, normal + Vector3(0, 0.2, 0), Color(0.72, 0.56, 0.36))
	_burst("dust", pos + normal * 0.1, normal, Color(0.7, 0.62, 0.5), 0.55)

func impact_rock(pos: Vector3, normal: Vector3) -> void:
	_burst("spark", pos + normal * 0.03, normal)
	_burst("dust", pos + normal * 0.1, normal, Color(0.8, 0.8, 0.78), 0.6)
	_burst("debris", pos + normal * 0.05, normal, Color(0.5, 0.5, 0.48), 0.8)

func impact_water(pos: Vector3) -> void:
	_burst("splash", pos + Vector3(0, 0.02, 0), Vector3.UP)
	ripple(pos, 2.6)

func dust_puff(pos: Vector3, color: Color, scale_mul := 1.0) -> void:
	_burst("dust", pos + Vector3(0, 0.15, 0), Vector3.UP, color, scale_mul)

func muzzle_smoke(pos: Vector3, dir: Vector3, _base_vel: Vector3) -> void:
	_burst("smoke", pos, dir)

func ripple(pos: Vector3, size: float) -> void:
	var mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(1, 1)
	mi.mesh = pm
	var m: StandardMaterial3D = _ripple_mat.duplicate()
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	mi.global_position = Vector3(pos.x, 0.03, pos.z)
	mi.scale = Vector3(0.3, 1, 0.3)
	var tw := create_tween().set_parallel(true)
	tw.tween_property(mi, "scale", Vector3(size, 1, size), 1.6).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	tw.tween_property(m, "albedo_color", Color(1, 1, 1, 0), 1.6)
	tw.chain().tween_callback(mi.queue_free)

# ------------------------------------------------------------------ brass
func eject_casing(pos: Vector3, velocity: Vector3) -> void:
	var entry: Dictionary
	if _casings.size() < 10:
		var mi := MeshInstance3D.new()
		mi.mesh = _casing_mesh
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
		entry = {"node": mi}
		_casings.append(entry)
	else:
		entry = _casings[0]
		for c in _casings:
			if c["life"] < entry["life"]:
				entry = c
	entry["vel"] = velocity
	entry["spin"] = Vector3(randf_range(-20, 20), randf_range(-20, 20), randf_range(-20, 20))
	entry["life"] = 6.0
	entry["bounced"] = 0
	var node: MeshInstance3D = entry["node"]
	node.global_position = pos
	node.visible = true

func _process(dt: float) -> void:
	for c in _casings:
		if c["life"] <= 0.0:
			continue
		c["life"] -= dt
		var node: MeshInstance3D = c["node"]
		if c["life"] <= 0.0:
			node.visible = false
			continue
		if c["bounced"] >= 4:
			continue
		var v: Vector3 = c["vel"]
		v.y -= 9.8 * dt
		var p := node.global_position + v * dt
		var ground: float = maxf(G.terrain.height(p.x, p.z), 0.0) + 0.012
		if p.y < ground:
			p.y = ground
			v = Vector3(v.x * 0.45, -v.y * 0.32, v.z * 0.45)
			c["spin"] = (c["spin"] as Vector3) * 0.4
			c["bounced"] += 1
			if c["bounced"] == 1 and G.terrain.height(p.x, p.z) > 0.0:
				Sfx.play_at("casing", p, -12.0, randf_range(0.9, 1.15), 3.0)
			if absf(v.y) < 0.4:
				c["bounced"] = 4
		c["vel"] = v
		node.global_position = p
		var sp: Vector3 = c["spin"]
		node.rotation += sp * dt
