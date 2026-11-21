class_name DogModel
extends RefCounted
## Procedural grey Norwegian elkhound: skeleton and skinned mesh, built like the moose
## (MooseModel) and drawn with the same coat shader. Model space as the moose's: nose
## towards -Z, +Y up, paws on y = 0; all bones rest un-rotated.
## About 52 cm at the withers: square and compact, a thick grey coat with a darker
## saddle, pale legs, chest and belly, a dark mask, erect pointed ears, and the tail
## curled tight over the back.

enum B { ROOT, HIPS, CHEST, NECK, HEAD, JAW, TAIL, FL_U, FL_L, FR_U, FR_L, HL_T, HL_S, HL_C, HR_T, HR_S, HR_C }

## name, parent, rest position (model space)
const BONES := [
	["root", -1, Vector3(0, 0, 0)],
	["hips", 0, Vector3(0, 0.46, 0.2)],
	["chest", 1, Vector3(0, 0.46, -0.12)],
	["neck", 2, Vector3(0, 0.5, -0.27)],
	["head", 3, Vector3(0, 0.665, -0.37)],
	["jaw", 4, Vector3(0, 0.612, -0.425)],
	["tail", 1, Vector3(0, 0.52, 0.31)],
	["fl_upper", 2, Vector3(-0.07, 0.42, -0.19)],
	["fl_lower", 7, Vector3(-0.07, 0.265, -0.2)],
	["fr_upper", 2, Vector3(0.07, 0.42, -0.19)],
	["fr_lower", 9, Vector3(0.07, 0.265, -0.2)],
	["hl_thigh", 1, Vector3(-0.076, 0.43, 0.235)],
	["hl_shin", 11, Vector3(-0.076, 0.27, 0.185)],
	["hl_hock", 12, Vector3(-0.076, 0.145, 0.285)],
	["hr_thigh", 1, Vector3(0.076, 0.43, 0.235)],
	["hr_shin", 14, Vector3(0.076, 0.27, 0.185)],
	["hr_hock", 15, Vector3(0.076, 0.145, 0.285)],
]

## The coat shader reads the rest position from UV/UV2 at moose scale (its hair, the
## leg/body split and the rim light are laid out for an animal 2 m tall).
const SHADER_SCALE := 2.4

const GREY := Color(0.5, 0.5, 0.48)
const SADDLE := Color(0.24, 0.24, 0.235)
const PALE := Color(0.64, 0.635, 0.605)
const RUFF := Color(0.57, 0.565, 0.545)
const MASK := Color(0.16, 0.155, 0.15)

static var _mesh: ArrayMesh
static var _material: ShaderMaterial

static func rest(b: int) -> Vector3:
	return BONES[b][2]

static func make_skeleton() -> Skeleton3D:
	var skel := Skeleton3D.new()
	skel.name = "Skeleton"
	for i in BONES.size():
		var b: Array = BONES[i]
		skel.add_bone(b[0])
		var parent: int = b[1]
		if parent >= 0:
			skel.set_bone_parent(i, parent)
			skel.set_bone_rest(i, Transform3D(Basis.IDENTITY, (b[2] as Vector3) - (BONES[parent][2] as Vector3)))
		else:
			skel.set_bone_rest(i, Transform3D(Basis.IDENTITY, b[2]))
	skel.reset_bone_poses()
	return skel

static func material() -> ShaderMaterial:
	if _material == null:
		_material = MooseModel.material().duplicate()
		_material.set_shader_parameter("tint", Vector3(1.0, 1.0, 1.0))
	return _material

static func mesh() -> ArrayMesh:
	if _mesh == null:
		_mesh = _build()
	return _mesh

static func _build() -> ArrayMesh:
	var k := MeshKit.new(true)
	var sides := 16
	# ---- body, neck and head as one skin
	# z, top y, bottom y, half width, bones, mask 0..1, pinch, squareness
	var st := [
		[0.35, 0.505, 0.425, 0.026, [B.HIPS, 1.0], 0.0, 0.2, 2.0],
		[0.336, 0.537, 0.362, 0.078, [B.HIPS, 1.0], 0.0, 0.22, 2.1],
		[0.305, 0.556, 0.322, 0.11, [B.HIPS, 1.0], 0.0, 0.22, 2.2],
		[0.25, 0.562, 0.302, 0.122, [B.HIPS, 1.0], 0.0, 0.2, 2.2],
		[0.175, 0.556, 0.313, 0.114, [B.HIPS, 1.0], 0.0, 0.2, 2.1],
		[0.095, 0.55, 0.322, 0.108, [B.HIPS, 1.0], 0.0, 0.18, 2.0],
		[0.01, 0.552, 0.288, 0.114, [B.HIPS, 0.5, B.CHEST, 0.5], 0.0, 0.16, 2.0],
		[-0.07, 0.561, 0.252, 0.126, [B.CHEST, 1.0], 0.0, 0.16, 2.0],
		[-0.145, 0.572, 0.236, 0.132, [B.CHEST, 1.0], 0.0, 0.18, 2.0],
		[-0.21, 0.584, 0.25, 0.126, [B.CHEST, 1.0], 0.0, 0.2, 2.0],
		[-0.255, 0.61, 0.29, 0.114, [B.CHEST, 0.6, B.NECK, 0.4], 0.0, 0.2, 2.0],
		[-0.292, 0.656, 0.372, 0.104, [B.NECK, 1.0], 0.0, 0.16, 2.0],
		[-0.322, 0.698, 0.455, 0.094, [B.NECK, 0.6, B.HEAD, 0.4], 0.0, 0.14, 2.0],
		[-0.348, 0.73, 0.54, 0.082, [B.NECK, 0.2, B.HEAD, 0.8], 0.0, 0.14, 2.0],
		[-0.372, 0.752, 0.568, 0.08, [B.HEAD, 1.0], 0.0, 0.16, 2.1],
		[-0.4, 0.758, 0.58, 0.078, [B.HEAD, 1.0], 0.0, 0.16, 2.2],
		[-0.425, 0.748, 0.59, 0.07, [B.HEAD, 1.0], 0.1, 0.14, 2.2],
		[-0.447, 0.725, 0.598, 0.058, [B.HEAD, 1.0], 0.35, 0.12, 2.3],
		[-0.472, 0.712, 0.603, 0.05, [B.HEAD, 1.0], 0.6, 0.1, 2.4],
		[-0.5, 0.702, 0.608, 0.044, [B.HEAD, 1.0], 0.85, 0.08, 2.4],
		[-0.527, 0.694, 0.613, 0.038, [B.HEAD, 1.0], 1.0, 0.06, 2.4],
		[-0.548, 0.686, 0.62, 0.031, [B.HEAD, 1.0], 1.0, 0.05, 2.3],
		[-0.562, 0.677, 0.63, 0.02, [B.HEAD, 1.0], 1.0, 0.04, 2.0],
	]
	var rings := []
	var cols := []
	var bw := []
	for s in st:
		var z: float = s[0]
		rings.append(MooseModel._torso_ring(z, s[1], s[2], s[3], sides, s[6], 0.0, s[7]))
		var head_k := smoothstep(-0.33, -0.37, z)
		var rc := []
		for i in sides:
			var up := sin(TAU * float(i) / sides)
			# pale under the body, grey on the sides, the dark saddle over the back
			var c := PALE.lerp(GREY, smoothstep(-0.7, -0.15, up))
			c = c.lerp(SADDLE, smoothstep(0.35, 0.9, up) * smoothstep(-0.27, -0.12, z) * smoothstep(0.36, 0.28, z))
			# a thick, lighter ruff round the neck; the chest in front pale
			c = c.lerp(RUFF, smoothstep(-0.24, -0.3, z) * (1.0 - head_k) * smoothstep(-0.3, 0.4, up) * 0.8)
			c = c.lerp(PALE, smoothstep(-0.22, -0.28, z) * (1.0 - head_k) * smoothstep(0.1, -0.6, up))
			# head grey with paler cheeks and throat, the muzzle in a dark mask
			var hc := GREY.lerp(PALE, smoothstep(-0.1, -0.7, up) * 0.6)
			c = c.lerp(hc, head_k).lerp(MASK.lerp(GREY, 0.3 * smoothstep(0.6, 1.0, up)), float(s[5]) * (0.55 + 0.45 * smoothstep(-0.5, 0.2, up)))
			rc.append(c)
		cols.append(rc)
		bw.append(s[4])
	k.loft(rings, cols, true, true, bw)
	# ---- the lower jaw (opens to bark)
	var jr := []
	var jc := []
	var jb := []
	for js in [[-0.43, 0.608, 0.588, 0.04], [-0.47, 0.612, 0.594, 0.033], [-0.505, 0.615, 0.6, 0.026], [-0.53, 0.618, 0.606, 0.017], [-0.542, 0.619, 0.611, 0.008]]:
		jr.append(MooseModel._torso_ring(js[0], js[1], js[2], js[3], 10, 0.0, 0.0, 2.0))
		jc.append(MASK.lerp(GREY, 0.55))
		jb.append([B.JAW, 1.0])
	k.loft(jr, jc, true, true, jb)
	# ---- legs: pale, slim and straight, with tight round paws
	for side in [-1.0, 1.0]:
		var up_b := B.FL_U if side < 0 else B.FR_U
		var lo_b := B.FL_L if side < 0 else B.FR_L
		var x: float = side * 0.07
		var fl := [
			[0.45, -0.188, 0.056, 0.084, [B.CHEST, 1.0], side * 0.064],
			[0.385, -0.193, 0.053, 0.074, [up_b, 1.0], side * 0.068],
			[0.315, -0.198, 0.044, 0.057, [up_b, 1.0]],
			[0.268, -0.2, 0.037, 0.045, [up_b, 0.5, lo_b, 0.5]],
			[0.22, -0.2, 0.031, 0.036, [lo_b, 1.0]],
			[0.12, -0.2, 0.026, 0.029, [lo_b, 1.0]],
			[0.072, -0.203, 0.025, 0.027, [lo_b, 1.0]],
			[0.045, -0.208, 0.027, 0.032, [lo_b, 1.0]],
		]
		_leg(k, x, fl, 0.36)
		_paw(k, Vector3(x, 0.0, -0.218), lo_b)
		var th := B.HL_T if side < 0 else B.HR_T
		var sh := B.HL_S if side < 0 else B.HR_S
		var hk := B.HL_C if side < 0 else B.HR_C
		var hl := [
			[0.46, 0.23, 0.062, 0.102, [B.HIPS, 1.0], side * 0.07],
			[0.385, 0.218, 0.061, 0.092, [th, 1.0], side * 0.078],
			[0.315, 0.198, 0.049, 0.067, [th, 1.0]],
			[0.27, 0.188, 0.039, 0.049, [th, 0.5, sh, 0.5]],
			[0.21, 0.226, 0.033, 0.041, [sh, 1.0]],
			[0.152, 0.272, 0.028, 0.035, [sh, 0.5, hk, 0.5]],
			[0.11, 0.282, 0.024, 0.028, [hk, 1.0]],
			[0.062, 0.279, 0.024, 0.026, [hk, 1.0]],
			[0.04, 0.276, 0.026, 0.031, [hk, 1.0]],
		]
		_leg(k, x * 1.08, hl, 0.38)
		_paw(k, Vector3(x * 1.08, 0.0, 0.272), hk)
	# ---- ears: erect, pointed, set high
	for side in [-1.0, 1.0]:
		k.set_bone(B.HEAD)
		var base := Vector3(side * 0.043, 0.744, -0.39)
		var along := Vector3(side * 0.22, 1.0, 0.08).normalized()
		var hollow := Vector3(side * 0.2, 0.0, -1.0)
		hollow = (hollow - along * hollow.dot(along)).normalized()
		_ear(k, base, along, hollow, 0.088, 0.032, 0.008, 0.008)
		# almond eyes, dark brown
		var eb := Basis(Vector3.UP, side * 0.5)
		k.sphere(Vector3(side * 0.043, 0.714, -0.432), Vector3(0.0105, 0.0085, 0.008), 8, 4, Color(0.07, 0.05, 0.04, MooseModel.EYE), null, eb)
	# a black, wet nose
	k.sphere(Vector3(0, 0.672, -0.559), Vector3(0.016, 0.013, 0.012), 8, 4, Color(0.05, 0.05, 0.05, MooseModel.HOOF))
	# ---- the tail, curled tight over the back
	_tail(k)
	# rest-pose position for the coat shader, at moose scale
	k.uv2.resize(k.count())
	for i in k.count():
		var p := k.v[i] * SHADER_SCALE
		k.uv[i] = Vector2(p.z, p.y)
		k.uv2[i] = Vector2(p.x, 0.0)
	return k.commit(material())

static func _leg(k: MeshKit, x: float, stations: Array, body_y: float) -> void:
	var rings := []
	var cols := []
	var bw := []
	for s in stations:
		var lx: float = s[5] if s.size() > 5 else x
		rings.append(MooseModel._leg_ring(Vector3(lx, s[0], s[1]), s[2], s[3], 8))
		var y: float = s[0]
		cols.append(PALE.lerp(GREY.lerp(PALE, 0.35), smoothstep(body_y, body_y + 0.08, y)))
		bw.append(s[4])
	k.loft(rings, cols, false, true, bw)

static func _paw(k: MeshKit, at: Vector3, bone: int) -> void:
	k.set_bone(bone)
	k.sphere(at + Vector3(0, 0.022, -0.006), Vector3(0.029, 0.024, 0.038), 8, 4, PALE, PALE.darkened(0.3))

## A pointed, cupped ear: widest at the root, the hollow facing `hollow`.
static func _ear(k: MeshKit, base: Vector3, along: Vector3, hollow: Vector3, length: float, width: float, cup: float, thick: float) -> void:
	var across := along.cross(hollow).normalized()
	var nu := 4
	var nv := 4
	var grid := []
	for iu in nu + 1:
		var u := float(iu) / nu
		var hw := width * pow(1.0 - u, 0.85) + 0.002
		for iv in nv + 1:
			var v := float(iv) / nv * 2.0 - 1.0
			grid.append([base + along * (length * u) + across * (v * hw) - hollow * (cup * (1.0 - v * v) * (1.0 - u)), u, absf(v)])
	for face_i in 2:
		var sgn := 1.0 if face_i == 0 else -1.0
		var first := k.count()
		var t0 := k.idx.size()
		for g in grid:
			var c: Color = MASK.lerp(GREY, 0.25) if face_i == 1 else PALE.lerp(GREY, 0.4).lerp(MASK, smoothstep(0.5, 1.0, g[2]))
			k.vert(g[0] + hollow * (thick * 0.5 * sgn), hollow * sgn, c)
		for iu in nu:
			for iv in nv:
				var a := first + iu * (nv + 1) + iv
				if face_i == 0:
					k.quad(a, a + 1, a + nv + 2, a + nv + 1)
				else:
					k.quad(a, a + nv + 1, a + nv + 2, a + 1)
		k.smooth_normals(first, t0)
		for i in range(first, k.count()):
			if k.n[i].dot(hollow * sgn) < 0.0:
				k.n[i] = -k.n[i]

## The tail: up from the rump, over and forward, lying in a tight ring on the back.
## A bushy tube along a curve, grey on top with dark tips, pale underneath.
static func _tail(k: MeshKit) -> void:
	var pts := [Vector3(0, 0.5, 0.315), Vector3(0, 0.575, 0.352), Vector3(0, 0.648, 0.338), Vector3(0.006, 0.686, 0.288),
		Vector3(0.016, 0.679, 0.232), Vector3(0.03, 0.648, 0.198), Vector3(0.042, 0.612, 0.19), Vector3(0.05, 0.586, 0.207)]
	var radii := [0.042, 0.052, 0.058, 0.058, 0.053, 0.046, 0.035, 0.014]
	var curl_c := Vector3(0.02, 0.6, 0.275)
	var rings := []
	var cols := []
	var bw := []
	var u := Vector3.RIGHT
	for i in pts.size():
		var p: Vector3 = pts[i]
		var t: Vector3 = ((pts[mini(i + 1, pts.size() - 1)] as Vector3) - (pts[maxi(i - 1, 0)] as Vector3)).normalized()
		# carry the frame along the curve so the rings don't twist
		u = (u - t * u.dot(t)).normalized()
		var w := t.cross(u).normalized()
		var r: float = radii[i]
		var ring := MeshKit.ring_uw(p, u, w, r * 1.15, r, 8)
		rings.append(ring)
		var rc := []
		var inward := (curl_c - p).normalized()
		for q in ring:
			var o: Vector3 = (q - p).normalized()
			var c := GREY.lerp(PALE, smoothstep(-0.1, 0.6, o.dot(inward)))
			c = c.lerp(SADDLE, smoothstep(0.55, 1.0, float(i) / (pts.size() - 1)) * smoothstep(0.3, -0.4, o.dot(inward)))
			rc.append(c)
		cols.append(rc)
		bw.append([B.HIPS, 1.0] if i == 0 else [B.TAIL, 1.0])
	k.loft(rings, cols, true, true, bw)
