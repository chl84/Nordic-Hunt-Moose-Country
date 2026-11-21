class_name WeaponModels
extends RefCounted
## Procedural first-person rifles. Model space: muzzle towards -Z, +Y up,
## origin at the chamber. `f` below means "metres forward of the origin".

const VIEW_FOV := 54.0

static var _mats := {}

class Kits:
	var k := {}
	func m(mat_name: String) -> MeshKit:
		if not k.has(mat_name):
			k[mat_name] = MeshKit.new()
		return k[mat_name]
	func mesh() -> ArrayMesh:
		var out := ArrayMesh.new()
		for mat_name in k:
			(k[mat_name] as MeshKit).commit(WeaponModels.mat(mat_name), out, true)
		return out

static func P(f: float, y: float, x := 0.0) -> Vector3:
	return Vector3(x, y, -f)

static func _std(color: Color, metallic: float, rough: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.albedo_color = color
	m.metallic = metallic
	m.roughness = rough
	m.use_fov_override = true
	m.fov_override = VIEW_FOV
	m.use_z_clip_scale = true
	m.z_clip_scale = 0.35
	return m

static func mat(mat_name: String) -> Material:
	if _mats.has(mat_name):
		return _mats[mat_name]
	var m: StandardMaterial3D
	match mat_name:
		"wood":
			m = _std(Color.WHITE, 0.0, 0.78)
			m.albedo_texture = _grain_texture()
			m.uv1_triplanar = true
			m.uv1_scale = Vector3(26.0, 26.0, 1.6)
			m.metallic_specular = 0.18
		"metal":
			m = _std(Color.WHITE, 0.62, 0.44)
		"black":
			m = _std(Color.WHITE, 0.15, 0.58)
		"brass":
			m = _std(Color.WHITE, 0.92, 0.34)
		"glass":
			m = _std(Color.WHITE, 0.95, 0.04)
		"cloth":
			m = _std(Color.WHITE, 0.0, 0.95)
		"dot":
			m = _std(Color(1.0, 0.1, 0.05), 0.0, 1.0)
			m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			m.albedo_color = Color(1.0, 0.12, 0.06)
			m.vertex_color_use_as_albedo = false
		_:
			m = _std(Color.WHITE, 0.0, 0.7)
	_mats[mat_name] = m
	return m

static func _grain_texture() -> ImageTexture:
	var size := 256
	var nz := FastNoiseLite.new()
	nz.seed = 77
	nz.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	nz.frequency = 0.02
	nz.fractal_octaves = 4
	var img := Image.create(size, size, true, Image.FORMAT_RGB8)
	for y in size:
		for x in size:
			var v := nz.get_noise_2d(x * 0.6, y * 7.0) * 0.5 + 0.5
			var ring := absf(sin((nz.get_noise_2d(x * 0.3 + 90.0, y * 1.2) * 6.0 + y * 0.12)))
			var g := clampf(0.62 + 0.3 * v + 0.16 * ring, 0.0, 1.0)
			img.set_pixel(x, y, Color(g, g * 0.94, g * 0.86))
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)

static func _node(parent: Node3D, node_name: String, pos := Vector3.ZERO) -> Node3D:
	var n := Node3D.new()
	n.name = node_name
	n.position = pos
	parent.add_child(n)
	return n

static func _mesh_node(parent: Node3D, kits: Kits, node_name := "mesh") -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = node_name
	mi.mesh = kits.mesh()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	mi.extra_cull_margin = 4.0
	parent.add_child(mi)
	return mi

const STEEL := Color(0.20, 0.21, 0.235)
const BRIGHT := Color(0.60, 0.61, 0.63)
const BLACK := Color(0.10, 0.10, 0.11)
const WALNUT := Color(0.54, 0.40, 0.29)
const WALNUT_D := Color(0.45, 0.32, 0.23)
const LAMINATE := Color(0.36, 0.40, 0.33)
const BRASS := Color(0.87, 0.73, 0.40)
const GLOVE := Color(0.37, 0.27, 0.20)
const SLEEVE := Color(0.40, 0.45, 0.29)
const LENS := Color(0.10, 0.16, 0.24)

static func build(id: String) -> Dictionary:
	var w: Dictionary = WeaponDB.get_weapon(id)
	match w["type"]:
		"lever":
			return _lever()
		"semi":
			return _semi()
		"double":
			return _double()
	return _bolt(w.get("variant", "standard") == "magnum")

# ------------------------------------------------------------------ hands
static func _hand_r(parent: Node3D, at: Vector3) -> Node3D:
	var n := _node(parent, "hand_r", at)
	var kits := Kits.new()
	var g := kits.m("cloth")
	g.sphere(Vector3(0.016, -0.012, 0.0), Vector3(0.037, 0.05, 0.043), 8, 6, GLOVE.lightened(0.06), GLOVE.darkened(0.2))
	g.cyl(Vector3(0.028, 0.022, 0.005), Vector3(-0.018, 0.034, -0.03), 0.0125, 0.0105, 6, GLOVE, GLOVE, true, true)   # thumb over the wrist
	g.cyl(Vector3(0.034, 0.004, -0.03), Vector3(0.026, -0.004, -0.085), 0.0105, 0.009, 6, GLOVE, GLOVE, true, true)   # trigger finger
	g.sphere(Vector3(-0.012, -0.03, -0.012), Vector3(0.022, 0.04, 0.036), 6, 4, GLOVE.darkened(0.1), GLOVE.darkened(0.3))  # curled fingers
	g.cyl(Vector3(0.024, -0.03, 0.035), Vector3(0.20, -0.25, 0.42), 0.043, 0.064, 9, SLEEVE.lightened(0.04), SLEEVE.darkened(0.15), true, true)
	g.cyl(Vector3(0.022, -0.028, 0.03), Vector3(0.036, -0.045, 0.06), 0.047, 0.047, 9, SLEEVE.darkened(0.3))
	_mesh_node(n, kits)
	return n

static func _hand_l(parent: Node3D, at: Vector3) -> Node3D:
	var n := _node(parent, "hand_l", at)
	var kits := Kits.new()
	var g := kits.m("cloth")
	g.sphere(Vector3(0.0, -0.016, 0.0), Vector3(0.043, 0.026, 0.058), 8, 5, GLOVE.lightened(0.05), GLOVE.darkened(0.2))   # palm cupping the forend
	g.sphere(Vector3(-0.036, 0.012, -0.004), Vector3(0.016, 0.03, 0.05), 6, 4, GLOVE, GLOVE.darkened(0.2))                # fingers up the left side
	g.cyl(Vector3(0.03, -0.006, 0.02), Vector3(0.036, 0.022, -0.02), 0.0125, 0.0105, 6, GLOVE, GLOVE, true, true)         # thumb on the right
	g.cyl(Vector3(-0.006, -0.03, 0.045), Vector3(-0.21, -0.25, 0.46), 0.043, 0.064, 9, SLEEVE.lightened(0.04), SLEEVE.darkened(0.15), true, true)
	g.cyl(Vector3(-0.004, -0.028, 0.04), Vector3(-0.018, -0.044, 0.07), 0.047, 0.047, 9, SLEEVE.darkened(0.3))
	_mesh_node(n, kits)
	return n

## (commit the kit with the "brass" material)
static func _cartridge(k: MeshKit, base: Vector3, length := 0.07, r := 0.006) -> void:
	k.cyl(base, base + Vector3(0, 0, -length * 0.68), r, r, 8, BRASS, BRASS, true, false)
	k.cyl(base + Vector3(0, 0, -length * 0.68), base + Vector3(0, 0, -length), r * 0.92, r * 0.3, 8, Color(0.62, 0.4, 0.26), null, false, true)

# ----------------------------------------------------------------- scopes
static func _scope(kits: Kits, sy: float, big: bool) -> void:
	var b := kits.m("black")
	var gl := kits.m("glass")
	var tube_r := 0.0168 if big else 0.0135
	var obj_r := 0.031 if big else 0.0235
	var f0 := -0.118 if big else -0.105
	var f1 := 0.30 if big else 0.245
	var bell0 := f1 - (0.115 if big else 0.095)
	var matte := BLACK.lightened(0.03)
	b.tube(P(f0, sy), P(f0 + 0.052, sy), 0.0215, 0.0175, 16, matte, BLACK)          # eyepiece
	b.cyl(P(f0 + 0.052, sy), P(f0 + 0.072, sy), 0.0215, tube_r, 16, matte)
	b.cyl(P(f0 + 0.012, sy), P(f0 + 0.022, sy), 0.0228, 0.0228, 16, BLACK.lightened(0.08))   # zoom ring
	b.cyl(P(f0 + 0.072, sy), P(bell0, sy), tube_r, tube_r, 14, matte)
	b.cyl(P(bell0, sy), P(bell0 + 0.045, sy), tube_r, obj_r, 16, matte)
	b.tube(P(bell0 + 0.045, sy), P(f1, sy), obj_r, obj_r - 0.004, 16, matte, BLACK)
	gl.cyl(P(f0 + 0.006, sy), P(f0 + 0.008, sy), 0.0175, 0.0175, 16, LENS, LENS, true, false)
	gl.cyl(P(f1 - 0.012, sy), P(f1 - 0.01, sy), obj_r - 0.004, obj_r - 0.004, 16, LENS, LENS, false, true)
	# turret saddle
	var tf := 0.05 if big else 0.045
	b.box_at(P(tf, sy), Vector3(0.03, 0.03, 0.03), matte)
	b.cyl(P(tf, sy + 0.014), P(tf, sy + 0.033), 0.0105, 0.0105, 12, BLACK.lightened(0.07), null, false, true)
	b.cyl(P(tf, sy, 0.014), P(tf, sy, 0.033), 0.0105, 0.0105, 12, BLACK.lightened(0.07), null, false, true)
	if big:
		b.cyl(P(tf, sy, -0.015), P(tf, sy, -0.036), 0.012, 0.012, 12, BLACK.lightened(0.07), null, false, true)
	# rings
	var m := kits.m("metal")
	for rf in [-0.03, 0.105 if big else 0.092]:
		b.cyl(P(rf - 0.009, sy), P(rf + 0.009, sy), tube_r + 0.004, tube_r + 0.004, 14, BLACK.lightened(0.05), null, true, true)
		m.box_at(P(rf, sy - tube_r - 0.012), Vector3(0.02, 0.022, 0.018), STEEL)

# ------------------------------------------------------------ bolt action
static func _bolt(magnum: bool) -> Dictionary:
	var root := Node3D.new()
	root.name = "BoltRifle"
	var kits := Kits.new()
	var wood := kits.m("wood")
	var metal := kits.m("metal")
	var black := kits.m("black")
	var bore := 0.014
	var stock_col := LAMINATE if magnum else WALNUT
	var outline := PackedVector2Array([
		Vector2(0.40, -0.008), Vector2(0.10, -0.008), Vector2(-0.02, -0.008), Vector2(-0.10, -0.027),
		Vector2(-0.16, -0.046), Vector2(-0.22, -0.02), Vector2(-0.30, 0.0), Vector2(-0.47, -0.006),
		Vector2(-0.485, -0.06), Vector2(-0.47, -0.155), Vector2(-0.30, -0.125), Vector2(-0.20, -0.10),
		Vector2(-0.165, -0.13), Vector2(-0.14, -0.142), Vector2(-0.115, -0.117), Vector2(-0.09, -0.076),
		Vector2(-0.05, -0.062), Vector2(0.10, -0.058), Vector2(0.25, -0.055), Vector2(0.40, -0.046),
		Vector2(0.416, -0.028),
	])
	wood.slab(outline, 0.0225, 0.0105, stock_col)
	black.box_at(P(-0.49, -0.082), Vector3(0.043, 0.152, 0.016), BLACK)                  # recoil pad
	black.box_at(P(0.412, -0.027), Vector3(0.044, 0.04, 0.012), BLACK.lightened(0.02))   # forend tip
	if magnum:
		wood.box_at(P(-0.33, 0.012), Vector3(0.034, 0.03, 0.14), LAMINATE.darkened(0.25))   # cheek riser
	var barrel_end := 0.74 if magnum else 0.66
	metal.cyl(P(0.08, bore), P(barrel_end, bore), 0.0165 if magnum else 0.0135, 0.0125 if magnum else 0.0088, 14, STEEL)
	if magnum:
		metal.tube(P(barrel_end - 0.005, bore), P(barrel_end + 0.055, bore), 0.0155, 0.005, 12, STEEL.lightened(0.04), BLACK)
		for i in 3:
			black.box_at(P(barrel_end + 0.012 + i * 0.014, bore), Vector3(0.033, 0.007, 0.006), BLACK)
		# folded bipod
		for sx in [-1.0, 1.0]:
			black.cyl(P(0.37, -0.05, sx * 0.014), P(0.60, -0.035, sx * 0.02), 0.006, 0.005, 6, BLACK.lightened(0.04), null, true, true)
		black.box_at(P(0.37, -0.05), Vector3(0.04, 0.016, 0.03), BLACK.lightened(0.04))
	else:
		metal.tube(P(barrel_end - 0.004, bore), P(barrel_end, bore), 0.0088, 0.0042, 12, STEEL, BLACK)
	metal.cyl(P(-0.118, bore), P(0.10, bore), 0.0174, 0.0174, 14, STEEL, STEEL, true, true)   # receiver
	black.box_at(P(0.015, bore + 0.003, 0.0125), Vector3(0.012, 0.014, 0.072), BLACK)       # ejection port
	# trigger group
	metal.box_at(P(-0.052, -0.099), Vector3(0.012, 0.004, 0.07), STEEL)
	metal.box_at(P(-0.018, -0.081), Vector3(0.012, 0.038, 0.004), STEEL)
	metal.box(Vector3(0.012, 0.03, 0.004), Transform3D(Basis.from_euler(Vector3(0.6, 0, 0)), P(-0.092, -0.088)), STEEL)
	metal.box(Vector3(0.005, 0.024, 0.006), Transform3D(Basis.from_euler(Vector3(-0.3, 0, 0)), P(-0.056, -0.076)), STEEL.lightened(0.1))
	metal.cyl(P(-0.40, -0.146), P(-0.40, -0.16), 0.005, 0.005, 6, STEEL)
	metal.cyl(P(0.30, -0.052), P(0.30, -0.066), 0.005, 0.005, 6, STEEL)
	var sy := bore + (0.052 if magnum else 0.047)
	_scope(kits, sy, magnum)
	_mesh_node(root, kits, "body")

	# bolt
	var bolt := _node(root, "bolt", P(-0.09, bore))
	var bk := Kits.new()
	bk.m("metal").cyl(Vector3(0, 0, 0.035), Vector3(0, 0, -0.13), 0.0098, 0.0098, 10, BRIGHT, BRIGHT, true, true)
	bk.m("black").cyl(Vector3(0, 0, 0.058), Vector3(0, 0, 0.03), 0.0138, 0.0138, 10, BLACK.lightened(0.04), null, true, true)
	bk.m("metal").cyl(Vector3(0.012, -0.004, 0.012), Vector3(0.05, -0.03, 0.02), 0.0048, 0.0044, 6, STEEL.lightened(0.05))
	bk.m("black" if magnum else "metal").sphere(Vector3(0.054, -0.033, 0.021), Vector3(0.0115, 0.0115, 0.0115), 8, 6, BLACK.lightened(0.05) if magnum else STEEL.lightened(0.08))
	_mesh_node(bolt, bk)
	_node(bolt, "knob", Vector3(0.054, -0.033, 0.021))

	# magazine
	var mag := _node(root, "mag", P(0.043, -0.066))
	var mk := Kits.new()
	mk.m("black").box_at(Vector3.ZERO, Vector3(0.027, 0.04, 0.084), BLACK.lightened(0.03))
	mk.m("black").box_at(Vector3(0, -0.02, 0), Vector3(0.03, 0.006, 0.09), BLACK.lightened(0.06))
	_mesh_node(mag, mk)

	_hand_r(root, P(-0.135, -0.062))
	_hand_l(root, P(0.2, -0.062))
	_node(root, "muzzle", P(barrel_end + (0.06 if magnum else 0.0), bore))
	_node(root, "eject", P(0.02, bore + 0.004, 0.02))
	return {
		"root": root, "sight_y": sy, "eye_f": -0.20 if magnum else -0.185,
		"hip_pos": Vector3(0.118, -0.158, -0.4), "hip_rot": Vector3(0.5, 3.6, -1.5),
		"hand_r_parent": "", "grab_r": "bolt/knob", "grab_l": "mag",
	}

# ----------------------------------------------------------- lever action
static func _lever() -> Dictionary:
	var root := Node3D.new()
	root.name = "LeverRifle"
	var kits := Kits.new()
	var wood := kits.m("wood")
	var metal := kits.m("metal")
	var black := kits.m("black")
	var bore := 0.014
	wood.slab(PackedVector2Array([
		Vector2(-0.105, 0.016), Vector2(-0.20, 0.006), Vector2(-0.46, -0.03), Vector2(-0.475, -0.072),
		Vector2(-0.46, -0.152), Vector2(-0.20, -0.078), Vector2(-0.105, -0.048),
	]), 0.019, 0.009, WALNUT_D)
	var brass := kits.m("brass")
	brass.box_at(P(-0.474, -0.092), Vector3(0.036, 0.125, 0.006), BRASS)                  # butt plate
	# brass receiver
	brass.box_at(P(-0.01, -0.012), Vector3(0.034, 0.078, 0.2), BRASS)
	brass.box_at(P(-0.01, 0.03), Vector3(0.026, 0.008, 0.2), BRASS.darkened(0.08))
	black.box_at(P(0.02, -0.006, 0.0172), Vector3(0.002, 0.016, 0.04), BLACK)             # loading gate
	metal.box(Vector3(0.008, 0.02, 0.012), Transform3D(Basis.from_euler(Vector3(0.6, 0, 0)), P(-0.108, 0.028)), STEEL)   # hammer
	# barrel + magazine tube
	metal.cyl(P(0.09, bore), P(0.60, bore), 0.0118, 0.0105, 8, STEEL)
	metal.tube(P(0.596, bore), P(0.60, bore), 0.0105, 0.0055, 8, STEEL, BLACK)
	metal.cyl(P(0.09, bore - 0.024), P(0.565, bore - 0.024), 0.0085, 0.0085, 10, STEEL, null, false, true)
	metal.box_at(P(0.535, bore - 0.012), Vector3(0.012, 0.045, 0.012), STEEL)
	wood.slab(PackedVector2Array([
		Vector2(0.09, 0.004), Vector2(0.32, 0.004), Vector2(0.332, -0.012), Vector2(0.32, -0.036), Vector2(0.09, -0.04),
	]), 0.0205, 0.009, WALNUT_D)
	metal.box_at(P(0.322, -0.014), Vector3(0.044, 0.05, 0.012), STEEL)                     # barrel band
	# buckhorn rear sight + brass bead front sight
	var sy := 0.054
	metal.box_at(P(0.125, bore + 0.014), Vector3(0.012, 0.006, 0.04), STEEL)
	metal.box_at(P(0.11, bore + 0.024), Vector3(0.014, 0.02, 0.004), STEEL)
	metal.box_at(P(0.11, sy - 0.002, 0.0056), Vector3(0.0045, 0.014, 0.003), STEEL)
	metal.box_at(P(0.11, sy - 0.002, -0.0056), Vector3(0.0045, 0.014, 0.003), STEEL)
	metal.box_at(P(0.11, sy - 0.0085), Vector3(0.0125, 0.003, 0.003), STEEL)
	metal.box_at(P(0.585, sy - 0.016), Vector3(0.0028, 0.03, 0.012), STEEL)
	brass.sphere(P(0.585, sy - 0.0012), Vector3(0.0024, 0.0024, 0.0024), 6, 4, BRASS.lightened(0.2))
	_mesh_node(root, kits, "body")

	# lever (pivot just ahead of the trigger)
	var lever := _node(root, "lever", P(0.005, -0.05))
	var lk := Kits.new()
	var lm := lk.m("metal")
	lm.box_at(Vector3(0, -0.03, 0.0), Vector3(0.01, 0.058, 0.006), STEEL)
	lm.box_at(Vector3(0, -0.058, 0.035), Vector3(0.01, 0.005, 0.075), STEEL)
	lm.box(Vector3(0.01, 0.005, 0.11), Transform3D(Basis.from_euler(Vector3(-0.12, 0, 0)), Vector3(0, -0.064, 0.125)), STEEL)
	lm.box(Vector3(0.01, 0.005, 0.05), Transform3D(Basis.from_euler(Vector3(0.95, 0, 0)), Vector3(0, -0.052, 0.19)), STEEL)
	lm.box(Vector3(0.01, 0.005, 0.085), Transform3D(Basis.from_euler(Vector3(0.24, 0, 0)), Vector3(0, -0.026, 0.165)), STEEL)
	lm.box(Vector3(0.005, 0.022, 0.006), Transform3D(Basis.from_euler(Vector3(-0.3, 0, 0)), Vector3(0, -0.034, 0.045)), STEEL.lightened(0.1))
	_mesh_node(lever, lk)
	_hand_r(lever, Vector3(0.0, -0.022, 0.13))

	var rnd := _node(root, "round", P(0.02, -0.004, 0.03))
	var rk := Kits.new()
	_cartridge(rk.m("brass"), Vector3(0, 0, 0.03), 0.062, 0.0062)
	_mesh_node(rnd, rk)
	rnd.visible = false

	_hand_l(root, P(0.21, -0.06))
	_node(root, "muzzle", P(0.60, bore))
	_node(root, "eject", P(0.0, 0.04, 0.012))
	return {
		"root": root, "sight_y": sy - 0.001, "eye_f": -0.29,
		"hip_pos": Vector3(0.112, -0.146, -0.4), "hip_rot": Vector3(0.5, 3.6, -1.5),
		"grab_l": "round",
	}

# -------------------------------------------------------------- semi-auto
static func _semi() -> Dictionary:
	var root := Node3D.new()
	root.name = "SemiAuto"
	var kits := Kits.new()
	var wood := kits.m("wood")
	var metal := kits.m("metal")
	var black := kits.m("black")
	var bore := 0.014
	wood.slab(PackedVector2Array([
		Vector2(-0.10, 0.012), Vector2(-0.16, -0.03), Vector2(-0.215, -0.012), Vector2(-0.30, 0.008), Vector2(-0.47, 0.002),
		Vector2(-0.485, -0.055), Vector2(-0.47, -0.15), Vector2(-0.30, -0.122), Vector2(-0.205, -0.10),
		Vector2(-0.17, -0.132), Vector2(-0.145, -0.142), Vector2(-0.12, -0.116), Vector2(-0.10, -0.05),
	]), 0.021, 0.0105, WALNUT)
	black.box_at(P(-0.49, -0.076), Vector3(0.04, 0.15, 0.016), BLACK)
	metal.box_at(P(0.0, -0.008), Vector3(0.036, 0.076, 0.21), STEEL.lightened(0.03))        # receiver
	metal.cyl(P(-0.105, 0.03), P(0.105, 0.03), 0.018, 0.018, 12, STEEL.lightened(0.03))
	black.box_at(P(0.03, 0.02, 0.0185), Vector3(0.002, 0.016, 0.07), BLACK)                 # ejection port
	wood.slab(PackedVector2Array([
		Vector2(0.105, 0.004), Vector2(0.36, 0.004), Vector2(0.375, -0.014), Vector2(0.36, -0.042), Vector2(0.105, -0.046),
	]), 0.0225, 0.0105, WALNUT)
	metal.cyl(P(0.1, bore + 0.01), P(0.61, bore + 0.01), 0.013, 0.0095, 12, STEEL)
	metal.tube(P(0.606, bore + 0.01), P(0.61, bore + 0.01), 0.0095, 0.0048, 12, STEEL, BLACK)
	metal.cyl(P(0.36, bore - 0.012), P(0.42, bore - 0.012), 0.008, 0.008, 8, STEEL, null, false, true)   # gas block
	metal.box_at(P(0.56, bore + 0.03), Vector3(0.004, 0.02, 0.014), STEEL)                    # front sight blade
	# trigger guard
	metal.box_at(P(-0.045, -0.087), Vector3(0.012, 0.004, 0.07), STEEL)
	metal.box_at(P(-0.01, -0.066), Vector3(0.012, 0.042, 0.004), STEEL)
	metal.box(Vector3(0.012, 0.03, 0.004), Transform3D(Basis.from_euler(Vector3(0.6, 0, 0)), P(-0.085, -0.076)), STEEL)
	metal.box(Vector3(0.005, 0.024, 0.006), Transform3D(Basis.from_euler(Vector3(-0.3, 0, 0)), P(-0.05, -0.064)), STEEL.lightened(0.1))
	# red dot on a rail
	var sy := 0.03 + 0.018 + 0.027
	black.box_at(P(0.0, 0.051), Vector3(0.022, 0.008, 0.16), BLACK.lightened(0.03))
	black.box_at(P(0.005, 0.058), Vector3(0.026, 0.012, 0.05), BLACK.lightened(0.04))
	black.tube(P(-0.03, sy), P(0.045, sy), 0.021, 0.0178, 18, BLACK.lightened(0.04), BLACK)
	black.cyl(P(0.008, sy + 0.02), P(0.008, sy + 0.032), 0.007, 0.007, 8, BLACK.lightened(0.08), null, false, true)
	black.cyl(P(0.008, sy, 0.02), P(0.008, sy, 0.034), 0.0085, 0.0085, 8, BLACK.lightened(0.08), null, false, true)
	_mesh_node(root, kits, "body")
	# the dot itself (tiny, unshaded, sits on the sight axis)
	var dot := MeshInstance3D.new()
	dot.name = "dot"
	var sm := SphereMesh.new()
	sm.radius = 0.0011
	sm.height = 0.0022
	sm.radial_segments = 8
	sm.rings = 4
	dot.mesh = sm
	dot.material_override = mat("dot")
	dot.position = P(0.03, sy)
	dot.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(dot)

	var bolt := _node(root, "bolt", P(0.03, 0.022, 0.012))
	var bk := Kits.new()
	bk.m("metal").box_at(Vector3(0.0, 0.0, 0.0), Vector3(0.014, 0.015, 0.075), BRIGHT)
	bk.m("metal").cyl(Vector3(0.006, 0.0, -0.02), Vector3(0.026, 0.0, -0.02), 0.0045, 0.0045, 6, STEEL, null, false, true)
	_mesh_node(bolt, bk)
	_node(bolt, "knob", Vector3(0.026, 0.0, -0.02))

	var mag := _node(root, "mag", P(0.03, -0.068))
	var mk := Kits.new()
	mk.m("black").box_at(Vector3.ZERO, Vector3(0.026, 0.058, 0.078), BLACK.lightened(0.04))
	mk.m("black").box_at(Vector3(0, -0.03, 0), Vector3(0.029, 0.007, 0.084), BLACK.lightened(0.07))
	_mesh_node(mag, mk)

	_hand_r(root, P(-0.14, -0.06))
	_hand_l(root, P(0.22, -0.062))
	_node(root, "muzzle", P(0.61, bore + 0.01))
	_node(root, "eject", P(0.03, 0.022, 0.025))
	return {
		"root": root, "sight_y": sy, "eye_f": -0.25,
		"hip_pos": Vector3(0.118, -0.156, -0.4), "hip_rot": Vector3(0.5, 3.6, -1.5),
		"grab_l": "mag",
	}

# ------------------------------------------------------------ double rifle
static func _double() -> Dictionary:
	var root := Node3D.new()
	root.name = "DoubleRifle"
	var kits := Kits.new()
	var wood := kits.m("wood")
	var metal := kits.m("metal")
	var bore := 0.014
	var coin := Color(0.58, 0.58, 0.56)
	wood.slab(PackedVector2Array([
		Vector2(-0.085, 0.012), Vector2(-0.15, -0.024), Vector2(-0.21, -0.012), Vector2(-0.30, 0.004), Vector2(-0.47, -0.012),
		Vector2(-0.485, -0.065), Vector2(-0.47, -0.158), Vector2(-0.30, -0.118), Vector2(-0.20, -0.094),
		Vector2(-0.165, -0.124), Vector2(-0.14, -0.134), Vector2(-0.118, -0.108), Vector2(-0.085, -0.046),
	]), 0.0215, 0.0105, WALNUT.lerp(Color(0.55, 0.24, 0.10), 0.5))
	metal.box_at(P(-0.488, -0.086), Vector3(0.04, 0.15, 0.012), Color(0.45, 0.14, 0.1))      # red recoil pad
	# action body, coin finish
	metal.box_at(P(-0.01, -0.012), Vector3(0.046, 0.066, 0.15), coin)
	metal.sphere(P(-0.085, 0.004), Vector3(0.023, 0.03, 0.03), 8, 5, coin, coin.darkened(0.1))
	metal.box(Vector3(0.008, 0.008, 0.05), Transform3D(Basis.from_euler(Vector3(0, 0.25, 0)), P(-0.075, 0.026)), STEEL)    # top lever
	metal.box_at(P(-0.045, -0.084), Vector3(0.012, 0.004, 0.085), STEEL)
	metal.box_at(P(-0.002, -0.064), Vector3(0.012, 0.04, 0.004), STEEL)
	metal.box(Vector3(0.012, 0.03, 0.004), Transform3D(Basis.from_euler(Vector3(0.6, 0, 0)), P(-0.092, -0.072)), STEEL)
	metal.box(Vector3(0.004, 0.022, 0.006), Transform3D(Basis.from_euler(Vector3(-0.3, 0, 0)), P(-0.035, -0.06, 0.003)), BRASS)
	metal.box(Vector3(0.004, 0.022, 0.006), Transform3D(Basis.from_euler(Vector3(-0.3, 0, 0)), P(-0.06, -0.06, -0.003)), BRASS)
	_mesh_node(root, kits, "body")

	# barrels hinge down around the knuckle
	var hinge := P(0.065, -0.03)
	var barrels := _node(root, "barrels", hinge)
	var bk := Kits.new()
	var bm := bk.m("metal")
	var bw := bk.m("wood")
	var sy := bore + 0.0125 + 0.025
	for sx in [-1.0, 1.0]:
		bm.cyl(P(0.065, bore, sx * 0.0128) - hinge, P(0.66, bore, sx * 0.0112) - hinge, 0.0132, 0.0108, 12, STEEL)
		bm.tube(P(0.656, bore, sx * 0.0112) - hinge, P(0.66, bore, sx * 0.0112) - hinge, 0.0108, 0.006, 12, STEEL, BLACK)
		bm.tube(P(0.063, bore, sx * 0.0128) - hinge, P(0.066, bore, sx * 0.0128) - hinge, 0.0132, 0.0078, 12, STEEL, BLACK)
	bm.box_at(P(0.36, bore + 0.0105) - hinge, Vector3(0.007, 0.006, 0.6), STEEL.lightened(0.03))            # rib
	bm.box_at(P(0.12, bore + 0.021) - hinge, Vector3(0.016, 0.018, 0.07), STEEL)                              # quarter rib
	bm.box_at(P(0.13, sy - 0.004, 0.0048) - hinge, Vector3(0.006, 0.01, 0.003), STEEL)                        # express V
	bm.box_at(P(0.13, sy - 0.004, -0.0048) - hinge, Vector3(0.006, 0.01, 0.003), STEEL)
	bm.box_at(P(0.645, sy - 0.014) - hinge, Vector3(0.0028, 0.026, 0.01), STEEL)
	bm.sphere(P(0.645, sy - 0.001) - hinge, Vector3(0.0024, 0.0024, 0.0024), 6, 4, Color(0.95, 0.93, 0.85))
	bw.xf = Transform3D(Basis.IDENTITY, -hinge)
	bw.slab(PackedVector2Array([
		Vector2(0.09, 0.004), Vector2(0.31, 0.006), Vector2(0.325, -0.008), Vector2(0.31, -0.028), Vector2(0.09, -0.036),
	]), 0.024, 0.0105, WALNUT.lerp(Color(0.55, 0.24, 0.10), 0.5))
	bw.xf = Transform3D.IDENTITY
	_mesh_node(barrels, bk)
	_hand_l(barrels, P(0.2, -0.056) - hinge)

	var rnd := _node(root, "round", P(0.03, bore))
	var rk := Kits.new()
	_cartridge(rk.m("brass"), Vector3(0.0128, 0, 0.04), 0.082, 0.0076)
	_cartridge(rk.m("brass"), Vector3(-0.0128, 0, 0.04), 0.082, 0.0076)
	_mesh_node(rnd, rk)
	rnd.visible = false

	_hand_r(root, P(-0.132, -0.056))
	_node(barrels, "muzzle", P(0.66, bore) - hinge)
	_node(root, "eject", P(0.04, bore + 0.01, 0.0))
	return {
		"root": root, "sight_y": sy - 0.001, "eye_f": -0.27,
		"hip_pos": Vector3(0.116, -0.15, -0.41), "hip_rot": Vector3(0.5, 3.6, -1.5),
		"grab_l": "",
	}
