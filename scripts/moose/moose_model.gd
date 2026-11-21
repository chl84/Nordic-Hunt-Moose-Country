class_name MooseModel
extends RefCounted
## Procedural moose: skeleton, skinned mesh, hit zones and ragdoll layout.
## Model space: nose towards -Z, +Y up, hooves on y = 0. All bones rest
## un-rotated, so a bone's pose rotation is simply "rotation in model axes".

enum B { ROOT, HIPS, CHEST, NECK, HEAD, FL_U, FL_L, FR_U, FR_L, HL_T, HL_S, HL_C, HR_T, HR_S, HR_C }

## name, parent, rest position (model space)
const BONES := [
	["root", -1, Vector3(0, 0, 0)],
	["hips", 0, Vector3(0, 1.32, 0.62)],
	["chest", 1, Vector3(0, 1.38, -0.30)],
	["neck", 2, Vector3(0, 1.55, -0.92)],
	["head", 3, Vector3(0, 1.93, -1.52)],
	["fl_upper", 2, Vector3(-0.21, 1.22, -0.72)],
	["fl_lower", 5, Vector3(-0.20, 0.62, -0.70)],
	["fr_upper", 2, Vector3(0.21, 1.22, -0.72)],
	["fr_lower", 7, Vector3(0.20, 0.62, -0.70)],
	["hl_thigh", 1, Vector3(-0.20, 1.28, 0.78)],
	["hl_shin", 9, Vector3(-0.21, 0.92, 0.64)],
	["hl_cannon", 10, Vector3(-0.20, 0.62, 0.9)],
	["hr_thigh", 1, Vector3(0.20, 1.28, 0.78)],
	["hr_shin", 12, Vector3(0.21, 0.92, 0.64)],
	["hr_cannon", 13, Vector3(0.20, 0.62, 0.9)],
]

const KINDS := {
	"cow": {"label": "cow", "title": "Moose Cow", "scale": 0.90, "points": 220, "health": 100.0, "antlers": 0, "weight": [330, 420], "speed": 10.0},
	"young": {"label": "young bull", "title": "Young Bull", "scale": 0.94, "points": 330, "health": 110.0, "antlers": 1, "weight": [360, 470], "speed": 10.4},
	"bull": {"label": "bull", "title": "Bull Moose", "scale": 1.0, "points": 540, "health": 125.0, "antlers": 2, "weight": [470, 600], "speed": 9.8},
	"trophy": {"label": "trophy bull", "title": "Trophy Bull", "scale": 1.09, "points": 980, "health": 140.0, "antlers": 3, "weight": [600, 760], "speed": 9.4},
}

## Outer hit volumes: zone, bone, capsule a, capsule b (model space), radius
const SHAPES := [
	["head", B.HEAD, Vector3(0, 1.89, -1.62), Vector3(0, 1.68, -2.2), 0.15],
	["neck", B.NECK, Vector3(0, 1.50, -1.00), Vector3(0, 1.80, -1.44), 0.19],
	["chest", B.CHEST, Vector3(0, 1.54, -0.78), Vector3(0, 1.5, -0.05), 0.37],
	["chest", B.CHEST, Vector3(0, 1.80, -0.88), Vector3(0, 1.74, -0.30), 0.2],      # the hump over the shoulders
	["rear", B.HIPS, Vector3(0, 1.42, 0.0), Vector3(0, 1.42, 0.80), 0.33],
	["leg", B.FL_U, Vector3(-0.21, 1.05, -0.71), Vector3(-0.20, 0.62, -0.70), 0.085],
	["leg", B.FL_L, Vector3(-0.20, 0.60, -0.70), Vector3(-0.20, 0.05, -0.72), 0.06],
	["leg", B.FR_U, Vector3(0.21, 1.05, -0.71), Vector3(0.20, 0.62, -0.70), 0.085],
	["leg", B.FR_L, Vector3(0.20, 0.60, -0.70), Vector3(0.20, 0.05, -0.72), 0.06],
	["leg", B.HL_T, Vector3(-0.20, 1.12, 0.70), Vector3(-0.21, 0.92, 0.64), 0.12],
	["leg", B.HL_S, Vector3(-0.21, 0.92, 0.64), Vector3(-0.20, 0.62, 0.9), 0.08],
	["leg", B.HL_C, Vector3(-0.20, 0.62, 0.9), Vector3(-0.20, 0.05, 0.86), 0.06],
	["leg", B.HR_T, Vector3(0.20, 1.12, 0.70), Vector3(0.21, 0.92, 0.64), 0.12],
	["leg", B.HR_S, Vector3(0.21, 0.92, 0.64), Vector3(0.20, 0.62, 0.9), 0.08],
	["leg", B.HR_C, Vector3(0.20, 0.62, 0.9), Vector3(0.20, 0.05, 0.86), 0.06],
]

## Organs inside the body; the most vital one the bullet path crosses decides the hit.
const ORGANS := [
	["brain", B.HEAD, Vector3(0, 1.97, -1.62), Vector3(0, 1.93, -1.76), 0.08],
	["spine", B.NECK, Vector3(0, 1.62, -0.98), Vector3(0, 1.92, -1.48), 0.055],
	["spine", B.CHEST, Vector3(0, 1.74, -0.85), Vector3(0, 1.62, -0.05), 0.065],
	["spine", B.HIPS, Vector3(0, 1.60, 0.0), Vector3(0, 1.56, 0.85), 0.065],
	["heart", B.CHEST, Vector3(0, 1.3, -0.58), Vector3(0, 1.33, -0.50), 0.12],
	["lungs", B.CHEST, Vector3(0, 1.42, -0.66), Vector3(0, 1.42, -0.28), 0.25],
]
const ORGAN_RANK := {"brain": 6, "spine": 5, "heart": 4, "lungs": 3}

## Ragdoll particles: bone, model-space point, radius, mass
const RAG := [
	[B.HL_T, Vector3(-0.20, 1.28, 0.78), 0.17, 7.0],    # 0 hip L
	[B.HR_T, Vector3(0.20, 1.28, 0.78), 0.17, 7.0],     # 1 hip R
	[B.FL_U, Vector3(-0.21, 1.22, -0.72), 0.17, 7.0],   # 2 shoulder L
	[B.FR_U, Vector3(0.21, 1.22, -0.72), 0.17, 7.0],    # 3 shoulder R
	[B.CHEST, Vector3(0, 1.92, -0.58), 0.1, 5.0],       # 4 withers
	[B.HIPS, Vector3(0, 1.64, 0.80), 0.1, 5.0],         # 5 rump
	[B.CHEST, Vector3(0, 0.95, -0.05), 0.14, 6.0],      # 6 belly
	[B.NECK, Vector3(0, 1.55, -0.92), 0.16, 4.0],       # 7 neck base
	[B.HEAD, Vector3(0, 1.93, -1.52), 0.13, 2.5],       # 8 head
	[B.HEAD, Vector3(0, 1.63, -2.28), 0.1, 1.5],        # 9 nose
	[B.HEAD, Vector3(-0.2, 2.1, -1.52), 0.06, 0.8],     # 10 antler / ear L
	[B.HEAD, Vector3(0.2, 2.1, -1.52), 0.06, 0.8],      # 11 antler / ear R
	[B.FL_L, Vector3(-0.20, 0.62, -0.70), 0.065, 1.2],  # 12 knee FL
	[B.FL_L, Vector3(-0.20, 0.04, -0.72), 0.05, 1.0],   # 13 hoof FL
	[B.FR_L, Vector3(0.20, 0.62, -0.70), 0.065, 1.2],   # 14 knee FR
	[B.FR_L, Vector3(0.20, 0.04, -0.72), 0.05, 1.0],    # 15 hoof FR
	[B.HL_S, Vector3(-0.21, 0.92, 0.64), 0.1, 1.8],     # 16 stifle L
	[B.HL_C, Vector3(-0.20, 0.62, 0.9), 0.06, 1.2],    # 17 hock L
	[B.HL_C, Vector3(-0.20, 0.04, 0.86), 0.05, 1.0],    # 18 hoof HL
	[B.HR_S, Vector3(0.21, 0.92, 0.64), 0.1, 1.8],      # 19 stifle R
	[B.HR_C, Vector3(0.20, 0.62, 0.9), 0.06, 1.2],     # 20 hock R
	[B.HR_C, Vector3(0.20, 0.04, 0.86), 0.05, 1.0],     # 21 hoof HR
]

static var _meshes := {}
static var _material: ShaderMaterial

## Vertex alpha tells the shader what a surface is (see moose.gdshader).
const FUR := 1.0
const ANTLER := 0.6
const HOOF := 0.4
const NOSE := 0.3
const EYE := 0.2

static func rest(b: int) -> Vector3:
	return BONES[b][2]

static func material() -> ShaderMaterial:
	if _material == null:
		_material = ShaderMaterial.new()
		_material.shader = load("res://shaders/moose.gdshader")
		_material.set_shader_parameter("noise_tex", WorldUtil.noise_texture(256, 977, [0.07, 0.13, 0.1]))
	return _material

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

static func mesh_for(kind: String) -> ArrayMesh:
	if not _meshes.has(kind):
		_meshes[kind] = _build(int(KINDS[kind]["antlers"]))
	return _meshes[kind]

## A cross-section of the torso, neck or head at `z`, from `bot` up to `top`: narrow
## over the spine, full through the belly, with an optional crest of mane along the top.
static func _torso_ring(z: float, top: float, bot: float, hw: float, sides: int, pinch: float, crest: float, sq := 2.0, bulge := 0.0) -> PackedVector3Array:
	var out := PackedVector3Array()
	out.resize(sides)
	var c := (top + bot) * 0.5
	var ry := (top - bot) * 0.5
	for i in sides:
		var a := TAU * float(i) / sides
		var sn := sin(a)
		var cs := cos(a)
		# sq > 2 squares the section off (a superellipse); 2 is a plain ellipse
		var e := 2.0 / sq
		var sx := signf(cs) * pow(absf(cs), e)
		var sy := signf(sn) * pow(absf(sn), e)
		var w := hw * (1.0 - pinch * pow(maxf(sn, 0.0), 1.5)) * (1.0 - 0.08 * maxf(-sn, 0.0))
		w *= 1.0 + bulge * exp(-pow((sn - 0.05) / 0.38, 2.0))   # shoulder and haunch muscle along the side
		var y := c + sy * ry + crest * pow(maxf(sn, 0.0), 3.0)
		out[i] = Vector3(-sx * w, y, z)     # u = -X, w = +Y -> travels towards -Z
	return out

static func _leg_ring(c: Vector3, rx: float, rz: float, sides: int) -> PackedVector3Array:
	var out := PackedVector3Array()
	out.resize(sides)
	for i in sides:
		var a := TAU * float(i) / sides
		out[i] = c + Vector3(cos(a) * rx, 0.0, sin(a) * rz)  # u = +X, w = +Z -> travels towards -Y
	return out

static func _build(antlers: int) -> ArrayMesh:
	var k := MeshKit.new(true)
	var cow := antlers == 0
	# Scandinavian moose in autumn: grey-brown over the back and hump, darker flanks,
	# near-black belly and upper legs, pale grey-white lower legs, a brown face with a
	# greyer muzzle (cows lighter and greyer in the face)
	# (perceived colours: the shader squares them into linear light)
	var back := Color(0.43, 0.33, 0.235)
	var flank := Color(0.32, 0.27, 0.22)
	var belly := Color(0.33, 0.28, 0.23)
	var mane := Color(0.17, 0.13, 0.1)
	var face := Color(0.28, 0.215, 0.165) if not cow else Color(0.35, 0.27, 0.205)
	var muzzle := Color(0.48, 0.43, 0.38) if not cow else Color(0.53, 0.48, 0.42)
	var saddle := Color(0.47, 0.4, 0.32)
	var sides := 20
	# ---- torso, neck and head as one skin
	# z, top y, bottom y, half width, bones, muzzle tint 0..1, mane crest (m), pinch
	var st := [
		[1.07, 1.54, 1.42, 0.05, [B.HIPS, 1.0], 0.0, 0.0, 0.2, 2.1],
		[1.04, 1.645, 1.3, 0.15, [B.HIPS, 1.0], 0.0, 0.0, 0.2, 2.2],
		[0.99, 1.72, 1.22, 0.23, [B.HIPS, 1.0], 0.0, 0.0, 0.22, 2.3, 0.1],
		[0.9, 1.755, 1.23, 0.29, [B.HIPS, 1.0], 0.0, 0.0, 0.24, 2.2, 0.18],
		[0.79, 1.77, 1.26, 0.325, [B.HIPS, 1.0], 0.0, 0.0, 0.25, 2.0, 0.22],
		[0.67, 1.78, 1.31, 0.335, [B.HIPS, 1.0], 0.0, 0.0, 0.25, 2.0, 0.1],
		[0.555, 1.785, 1.26, 0.35, [B.HIPS, 1.0], 0.0, 0.0, 0.25],
		[0.385, 1.795, 1.2, 0.365, [B.HIPS, 0.6, B.CHEST, 0.4], 0.0, 0.0, 0.25],
		[0.12, 1.82, 1.18, 0.38, [B.HIPS, 0.3, B.CHEST, 0.7], 0.0, 0.0, 0.25],
		[-0.18, 1.87, 1.17, 0.385, [B.CHEST, 1.0], 0.0, 0.01, 0.27],
		[-0.48, 2.02, 1.15, 0.37, [B.CHEST, 1.0], 0.0, 0.02, 0.32, 2.0, 0.12],
		[-0.72, 2.11, 1.18, 0.335, [B.CHEST, 1.0], 0.0, 0.025, 0.34, 2.0, 0.2],
		[-0.88, 2.09, 1.22, 0.295, [B.CHEST, 1.0], 0.0, 0.03, 0.32, 2.0, 0.15],
		[-1.00, 2.065, 1.25, 0.245, [B.CHEST, 0.55, B.NECK, 0.45], 0.0, 0.03, 0.28],
		[-1.13, 2.055, 1.31, 0.235, [B.NECK, 1.0], 0.0, 0.03, 0.22],
		[-1.28, 2.065, 1.43, 0.21, [B.NECK, 1.0], 0.0, 0.025, 0.18],
		[-1.40, 2.09, 1.59, 0.16, [B.NECK, 0.5, B.HEAD, 0.5], 0.0, 0.012, 0.15],
		[-1.48, 2.115, 1.71, 0.15, [B.NECK, 0.2, B.HEAD, 0.8], 0.02, 0.0, 0.12],
		[-1.56, 2.11, 1.62, 0.145, [B.HEAD, 1.0], 0.06, 0.0, 0.14, 2.4, 0.1],
		[-1.64, 2.085, 1.585, 0.133, [B.HEAD, 1.0], 0.11, 0.0, 0.15, 2.6, 0.12],
		[-1.73, 2.05, 1.6, 0.115, [B.HEAD, 1.0], 0.18, 0.0, 0.15, 2.6, 0.05],
		[-1.82, 2.01, 1.62, 0.1, [B.HEAD, 1.0], 0.27, 0.0, 0.14, 2.6],
		[-1.91, 1.97, 1.635, 0.088, [B.HEAD, 1.0], 0.38, 0.0, 0.12, 2.6],
		[-1.99, 1.945, 1.635, 0.09, [B.HEAD, 1.0], 0.52, 0.0, 0.1, 2.6],
		[-2.06, 1.935, 1.615, 0.105, [B.HEAD, 1.0], 0.68, 0.0, 0.12, 2.7],
		[-2.13, 1.93, 1.578, 0.117, [B.HEAD, 1.0], 0.82, 0.0, 0.16, 2.8],
		[-2.19, 1.905, 1.555, 0.122, [B.HEAD, 1.0], 0.93, 0.0, 0.2, 2.9],
		[-2.24, 1.858, 1.54, 0.118, [B.HEAD, 1.0], 1.0, 0.0, 0.2, 2.9],
		[-2.275, 1.79, 1.54, 0.1, [B.HEAD, 1.0], 1.0, 0.0, 0.18, 2.7],
		[-2.295, 1.715, 1.555, 0.076, [B.HEAD, 1.0], 1.0, 0.0, 0.14, 2.5],
		[-2.305, 1.645, 1.58, 0.04, [B.HEAD, 1.0], 1.0, 0.0, 0.1, 2.2],
	]
	var rings := []
	var cols := []
	var bw := []
	for s in st:
		var z: float = s[0]
		var crest: float = s[6]
		rings.append(_torso_ring(z, s[1], s[2], s[3], sides, s[7], crest, s[8] if s.size() > 8 else 2.0, s[9] if s.size() > 9 else 0.0))
		var rc := []
		var head_k := smoothstep(-1.35, -1.55, z)          # 0 on the body .. 1 on the head
		for i in sides:
			var up := sin(TAU * float(i) / sides)
			var c := belly.lerp(flank, smoothstep(-0.85, -0.1, up)).lerp(back, smoothstep(0.15, 0.85, up))
			# the mane: a dark crest along the top of the neck and over the hump
			c = c.lerp(mane, smoothstep(0.82, 0.97, up) * smoothstep(-0.3, -0.75, z) * (1.0 - head_k) * 0.85)
			# a lighter, greyer saddle over the back behind the hump
			c = c.lerp(saddle, smoothstep(0.45, 0.9, up) * smoothstep(-0.6, -0.2, z) * smoothstep(1.05, 0.7, z) * 0.75)
			# the neck darker than the body, below the mane
			c = c.lerp(mane, smoothstep(-0.92, -1.12, z) * (1.0 - head_k) * smoothstep(0.6, -0.2, up) * 0.45)
			# rump and the backs of the thighs a little darker
			c = c.lerp(flank, smoothstep(0.7, 1.05, z) * 0.5)
			var fc := face.lerp(face.darkened(0.3), smoothstep(0.2, -0.9, up))
			c = c.lerp(fc, head_k).lerp(muzzle, float(s[5]) * 0.85)
			c = c.lerp(Color(0.08, 0.065, 0.055), (1.0 - smoothstep(0.1, 0.3, absf(up + 0.85))) * smoothstep(-1.92, -2.04, z) * 0.9)
			rc.append(c)
		cols.append(rc)
		bw.append(s[4])
	k.loft(rings, cols, true, true, bw)
	# ---- legs: dark and muscular above, pale and slender below, big dark hooves
	var pale := Color(0.58, 0.54, 0.48)
	var leg_d := Color(0.3, 0.24, 0.19)
	var hoof := Color(0.2, 0.18, 0.16, HOOF)
	for side in [-1.0, 1.0]:
		var up_b := B.FL_U if side < 0 else B.FR_U
		var lo_b := B.FL_L if side < 0 else B.FR_L
		var x: float = side * 0.205
		var fl := [
			[1.42, -0.70, 0.12, 0.24, [B.CHEST, 1.0], side * 0.15],
			[1.22, -0.71, 0.13, 0.22, [up_b, 1.0], side * 0.165],
			[1.00, -0.72, 0.12, 0.17, [up_b, 1.0], side * 0.19],
			[0.86, -0.715, 0.1, 0.14, [up_b, 1.0]],
			[0.75, -0.705, 0.08, 0.1, [up_b, 1.0]],
			[0.665, -0.69, 0.09, 0.1, [up_b, 0.5, lo_b, 0.5]],
			[0.60, -0.70, 0.076, 0.084, [lo_b, 1.0]],
			[0.50, -0.70, 0.052, 0.06, [lo_b, 1.0]],
			[0.22, -0.705, 0.046, 0.053, [lo_b, 1.0]],
			[0.14, -0.71, 0.048, 0.055, [lo_b, 1.0]],
			[0.09, -0.725, 0.05, 0.062, [lo_b, 1.0]],
			[0.065, -0.735, 0.05, 0.06, [lo_b, 1.0]],
		]
		_leg(k, x, fl, leg_d, pale, hoof, 8, 0.3, 0.95, belly)
		_hoof(k, Vector3(x, 0.0, -0.75), lo_b, hoof)
		var th := B.HL_T if side < 0 else B.HR_T
		var sh := B.HL_S if side < 0 else B.HR_S
		var cn := B.HL_C if side < 0 else B.HR_C
		var hl := [
			[1.40, 0.80, 0.13, 0.24, [B.HIPS, 1.0], side * 0.13],
			[1.25, 0.76, 0.15, 0.25, [th, 1.0], side * 0.18],
			[1.06, 0.7, 0.125, 0.19, [th, 1.0], side * 0.2],
			[0.92, 0.66, 0.11, 0.15, [th, 0.5, sh, 0.5]],
			[0.78, 0.77, 0.09, 0.115, [sh, 1.0]],
			[0.66, 0.89, 0.078, 0.11, [sh, 0.5, cn, 0.5]],
			[0.6, 0.925, 0.072, 0.1, [cn, 1.0]],
			[0.5, 0.9, 0.051, 0.06, [cn, 1.0]],
			[0.20, 0.875, 0.046, 0.053, [cn, 1.0]],
			[0.13, 0.875, 0.048, 0.055, [cn, 1.0]],
			[0.085, 0.865, 0.05, 0.062, [cn, 1.0]],
			[0.065, 0.855, 0.05, 0.06, [cn, 1.0]],
		]
		_leg(k, x, hl, leg_d, pale, hoof, 8, 0.3, 0.95, flank)
		_hoof(k, Vector3(x, 0.0, 0.84), cn, hoof)
	# ---- the bell: a flap of skin and long hair hanging from the throat
	k.set_bone(B.NECK, 0.6, B.HEAD, 0.4)
	var bell_c := Color(0.25, 0.2, 0.16)
	var bl := 0.45 if cow else (0.85 if antlers == 1 else 1.3)
	# (it hangs from the throat behind the jaw: a flat flap of skin ending in a tassel of hair)
	var bell := [[1.72, -1.53, 0.028, 0.12], [1.65, -1.54, 0.022, 0.085], [1.58, -1.55, 0.02, 0.06], [1.52, -1.555, 0.026, 0.055], [1.47, -1.56, 0.03, 0.06], [1.43, -1.565, 0.022, 0.045], [1.405, -1.565, 0.008, 0.015]]
	var b_rings := []
	var b_cols := []
	for bs in bell:
		var y := 1.72 - (1.72 - float(bs[0])) * bl
		b_rings.append(_leg_ring(Vector3(0, y, bs[1]), bs[2], bs[3], 8))
		b_cols.append(bell_c)
	k.loft(b_rings, b_cols, false, true)
	# ---- a soft chin, set back under the overhanging upper lip
	k.set_bone(B.HEAD)
	k.sphere(Vector3(0, 1.6, -2.1), Vector3(0.048, 0.03, 0.06), 8, 4, muzzle.darkened(0.12), muzzle.darkened(0.22))
	# ---- ears, eyes, nostrils, tail
	for side in [-1.0, 1.0]:
		# long ears held out and up, a cupped leaf with the hollow facing forward
		var along := Vector3(side * 0.78, 0.36, 0.5).normalized()
		var hollow := Vector3(side * 0.55, 0.2, -1.0)
		hollow = (hollow - along * hollow.dot(along)).normalized()
		_leaf(k, Vector3(side * 0.12, 1.99, -1.44), along, hollow, 0.4, 0.14, 0.055, 0.016,
			Color(0.52, 0.45, 0.38), face.lerp(back, 0.65), back.lerp(face, 0.5))
		# the eye in its socket: a brow over it, a ring of dark skin round it
		var eye := Vector3(side * 0.1, 1.965, -1.72)
		k.sphere(eye + Vector3(side * -0.006, 0.022, 0.004), Vector3(0.026, 0.012, 0.036), 8, 4, face, face.darkened(0.1))
		k.sphere(eye + Vector3(side * -0.006, 0.0, 0.0), Vector3(0.024, 0.024, 0.032), 8, 5, Color(0.1, 0.075, 0.06))
		k.sphere(eye, Vector3(0.03, 0.028, 0.036), 8, 5, Color(0.06, 0.045, 0.035, EYE))
		# big nostrils, slanting slits on the front of the muzzle
		var nb := Basis(Vector3(0, 1, 0), side * 0.7) * Basis(Vector3(1, 0, 0), 0.75)
		k.sphere(Vector3(side * 0.09, 1.745, -2.25), Vector3(0.013, 0.075, 0.026), 8, 4, Color(0.1, 0.08, 0.07, NOSE), null, nb)
		k.sphere(Vector3(side * 0.093, 1.79, -2.23), Vector3(0.022, 0.05, 0.03), 8, 4, muzzle.darkened(0.05), muzzle.darkened(0.12), nb)
	k.set_bone(B.HIPS)
	k.cyl(Vector3(0, 1.56, 1.04), Vector3(0, 1.4, 1.14), 0.05, 0.03, 6, back.darkened(0.25), back.darkened(0.45), false, true)
	if antlers > 0:
		for side in [-1.0, 1.0]:
			_antler(k, side, antlers)
	# rest-pose position for the shader's hair (the skinned vertex moves with the bones)
	k.uv2.resize(k.count())
	for i in k.count():
		k.uv[i] = Vector2(k.v[i].z, k.v[i].y)
		k.uv2[i] = Vector2(k.v[i].x, 0.0)
	return k.commit(material())

## A thin, cupped leaf of a surface (an ear, a brow palm): from `base` along `along` for
## `length`, `width` either side at its widest, the hollow (depth `cup`) facing `hollow`.
## Both faces are built; `col_in` lines the hollow, `col_out` the back, `col_base` the root.
static func _leaf(k: MeshKit, base: Vector3, along: Vector3, hollow: Vector3, length: float, width: float, cup: float, thick: float,
		col_in: Color, col_out: Color, col_base: Color, nu := 6, nv := 4) -> void:
	var across := along.cross(hollow).normalized()
	var grid := []
	for iu in nu + 1:
		var u := float(iu) / nu
		var hw := width * pow(sin(PI * clampf(u * 0.9 + 0.1, 0.0, 1.0)), 0.75) * (1.0 - 0.55 * u * u) + width * 0.25 * (1.0 - u)
		for iv in nv + 1:
			var v := float(iv) / nv * 2.0 - 1.0
			grid.append([base + along * (length * u) + across * (v * hw) - hollow * (cup * (1.0 - v * v) * sin(PI * minf(u * 1.2, 1.0))), u, absf(v)])
	for face_i in 2:
		var sgn := 1.0 if face_i == 0 else -1.0
		var first := k.count()
		var t0 := k.idx.size()
		for g in grid:
			var u: float = g[1]
			var c: Color = (col_in.lerp(col_in.darkened(0.35), smoothstep(0.3, 1.0, g[2])) if face_i == 0 else col_out)
			c = col_base.lerp(c, smoothstep(0.0, 0.3, u))
			k.vert(g[0] + hollow * (thick * 0.5 * sgn), hollow * sgn, c)
		for iu in nu:
			for iv in nv:
				var a := first + iu * (nv + 1) + iv
				if face_i == 0:
					k.quad(a, a + 1, a + nv + 2, a + nv + 1)
				else:
					k.quad(a, a + nv + 1, a + nv + 2, a + 1)
		k.smooth_normals(first, t0)
		# (keep the normals on their own side, however the winding came out)
		for i in range(first, k.count()):
			if k.n[i].dot(hollow * sgn) < 0.0:
				k.n[i] = -k.n[i]

## Tilt the normals along a grid's free edges outwards, so a thin plate reads as rounded
## at its rim instead of cut from card. `centre` is roughly the plate's middle.
static func _round_edges(k: MeshKit, first: int, nu: int, nv: int, centre: Vector3, amount: float) -> void:
	for iu in nu + 1:
		for iv in nv + 1:
			if iu == 0 or (iv > 0 and iv < nv and iu < nu):
				continue
			var i := first + iu * (nv + 1) + iv
			var out := k.v[i] - centre
			out = (out - k.n[i] * out.dot(k.n[i])).normalized()
			k.n[i] = (k.n[i] + out * amount).normalized()

## A cloven hoof under a leg ending at `at` (ground level): two splayed toes and the dewclaws behind.
static func _hoof(k: MeshKit, at: Vector3, bone: int, col: Color) -> void:
	k.set_bone(bone)
	for t in [-1.0, 1.0]:
		var tb := Basis(Vector3.UP, t * 0.14)
		k.sphere(at + Vector3(t * 0.032, 0.04, -0.03), Vector3(0.036, 0.042, 0.07), 8, 4, col, col.darkened(0.3), tb)
		k.sphere(at + Vector3(t * 0.028, 0.12, 0.055), Vector3(0.016, 0.018, 0.022), 6, 3, col, col)

## A leg from the shoulder or hip down: the colour turns from the dark upper leg to the
## pale stocking between `pale_y` and `dark_y`; the bottom rings are the hoof.
static func _leg(k: MeshKit, x: float, stations: Array, dark: Color, pale: Color, hoof: Color, sides: int, pale_y: float, dark_y: float, body: Color) -> void:
	var rings := []
	var cols := []
	var bw := []
	for s in stations:
		var lx: float = s[5] if s.size() > 5 else x
		rings.append(_leg_ring(Vector3(lx, s[0], s[1]), s[2], s[3], sides))
		var y: float = s[0]
		var c := pale.lerp(dark, smoothstep(pale_y, dark_y, y))
		c = c.lerp(body, smoothstep(1.0, 1.22, y))      # where the leg runs up into the body
		if y < 0.15:
			c = c.darkened(0.12)                  # dirt round the fetlocks
		if y < 0.07:
			c = hoof
		cols.append(c)
		bw.append(s[4])
	k.loft(rings, cols, false, true, bw)

## A moose antler: from the pedicle a short beam sweeps out to the side into a broad,
## cupped palm edged with tines; a brow palm with a few points reaches forward.
## level 1 = a young bull's fork, 2 = a bull, 3 = a trophy bull.
static func _antler(k: MeshKit, side: float, level: int) -> void:
	k.set_bone(B.HEAD)
	var base_c := Color(0.25, 0.19, 0.13, ANTLER)
	var mid_c := Color(0.38, 0.3, 0.215, ANTLER)
	var tip_c := Color(0.8, 0.74, 0.62, ANTLER)
	var base := Vector3(side * 0.085, 2.12, -1.6)
	var rng := RandomNumberGenerator.new()
	rng.seed = level * 31 + (7 if side > 0 else 0)
	if level == 1:
		# young bull: a short beam forking into a few points
		var tip := base + Vector3(side * 0.28, 0.17, 0.03)
		k.cyl(base, tip, 0.026, 0.02, 6, base_c, mid_c)
		for t in [Vector3(side * 0.15, 0.2, -0.09), Vector3(side * 0.12, 0.15, 0.13), Vector3(side * 0.05, 0.19, 0.02)]:
			k.cyl(tip, tip + t, 0.019, 0.004, 5, mid_c, tip_c)
		var m := base.lerp(tip, 0.5)
		k.cyl(m, m + Vector3(side * 0.03, 0.11, -0.15), 0.016, 0.004, 5, mid_c, tip_c)
		return
	var size := 1.15 if level == 2 else 1.3
	var n_tines := 5 if level == 2 else 8
	# frame of the palm: out to the side (and a little up and back), forwards, and its face
	var beam_dir := Vector3(side, 0.08, 0.14).normalized()
	var out := Vector3(side, 0.3, 0.3).normalized()
	var fwd := Vector3(0, 0.25, -1.0)
	fwd = (fwd - out * fwd.dot(out)).normalized()
	var face := out.cross(fwd).normalized()
	if face.y < 0.0:
		fwd = -fwd
		face = -face
	var root := base + beam_dir * 0.3 * size
	# the burr round the pedicle, then a stout beam running straight out from the side of the skull
	k.cyl(base - beam_dir * 0.01, base + beam_dir * 0.025, 0.05, 0.048, 8, base_c.darkened(0.15), base_c)
	k.cyl(base, root, 0.044, 0.05 * size, 8, base_c, base_c.lerp(mid_c, 0.5))
	# the palm as a grid: u out along it, v across it (front edge -1 .. back edge +1)
	var nu := 6
	var nv := 6
	var L := 0.6 * size
	var W := 0.14 * size
	var wob := []                 # an irregular outline: each row a little wider or narrower
	for iu in nu + 1:
		wob.append(rng.randf_range(0.94, 1.06))
	var grid := []          # [pos, thickness] per (iu, iv)
	for iu in nu + 1:
		var u := float(iu) / nu
		var hw := W * (0.3 + 0.7 * pow(sin(PI * clampf(u * 0.62 + 0.12, 0.0, 1.0)), 0.6)) * float(wob[iu])
		for iv in nv + 1:
			var v := float(iv) / nv * 2.0 - 1.0
			# the back half of the palm reaches further out than the front
			var reach := L * u * (0.9 + 0.12 * v)
			var cup := (0.6 * v * v + 0.45 * u * u) * 0.14 * size
			var p := root + out * reach + fwd * (-v * hw) + face * cup
			grid.append([p, (0.032 * (1.0 - u) + 0.014) * size])
	var top_first := k.count()
	var t_start := k.idx.size()
	for g in grid:
		var p: Vector3 = g[0]
		var u: float = (p - root).dot(out) / L
		k.vert(p + face * float(g[1]) * 0.5, face, base_c.lerp(mid_c, smoothstep(0.0, 0.35, u)).lerp(tip_c, smoothstep(0.85, 1.0, u) * 0.2))
	for iu in nu:
		for iv in nv:
			var a := top_first + iu * (nv + 1) + iv
			k.quad(a, a + nv + 1, a + nv + 2, a + 1)
	k.smooth_normals(top_first, t_start)
	_round_edges(k, top_first, nu, nv, root + out * L * 0.5, 0.75)
	var bot_first := k.count()
	t_start = k.idx.size()
	for g in grid:
		var p: Vector3 = g[0]
		var u: float = (p - root).dot(out) / L
		k.vert(p - face * float(g[1]) * 0.5, -face, base_c.lerp(mid_c, smoothstep(0.0, 0.35, u)))
	for iu in nu:
		for iv in nv:
			var a := bot_first + iu * (nv + 1) + iv
			k.quad(a, a + 1, a + nv + 2, a + nv + 1)
	k.smooth_normals(bot_first, t_start)
	_round_edges(k, bot_first, nu, nv, root + out * L * 0.5, 0.75)
	# the rim round the three free edges: front, outer end, back
	var rim := []
	for iu in range(1, nu + 1):
		rim.append(iu * (nv + 1))                  # front edge (v = -1)
	for iv in range(1, nv + 1):
		rim.append(nu * (nv + 1) + iv)             # outer end
	for iu in range(nu - 1, 0, -1):
		rim.append(iu * (nv + 1) + nv)             # back edge (v = +1), back towards the beam
	for i in rim.size() - 1:
		var a: int = rim[i]
		var b: int = rim[i + 1]
		var p0: Vector3 = grid[a][0]
		var p1: Vector3 = grid[b][0]
		var n := (p1 - p0).cross(face).normalized()
		var c := mid_c.lerp(tip_c, 0.3)
		var i0 := k.vert(k.v[top_first + a], n, c)
		var i1 := k.vert(k.v[top_first + b], n, c)
		var i2 := k.vert(k.v[bot_first + b], n, c)
		var i3 := k.vert(k.v[bot_first + a], n, c)
		if n.dot((p0 + p1) * 0.5 - (root + out * L * 0.5)) < 0.0:
			k.quad(i0, i3, i2, i1)
		else:
			k.quad(i0, i1, i2, i3)
	# tines: points along the outer end and the back edge, rising from the palm
	var spots := []
	for iv in range(1, nv + 1):
		spots.append(nu * (nv + 1) + iv)
	for iu in range(nu - 1, 2, -1):
		spots.append(iu * (nv + 1) + nv)
	for i in n_tines:
		var f := float(i) / maxf(n_tines - 1, 1)
		var fj := clampf(f + rng.randf_range(-0.04, 0.04), 0.0, 1.0)
		var gi: int = spots[int(round(fj * (spots.size() - 1)))]
		var p: Vector3 = grid[gi][0]
		var away := (p - (root + out * L * 0.45))
		away = (away - face * away.dot(face)).normalized()
		var dirv := (away * 0.85 + face * 0.4 + out * 0.1).normalized()
		var ln := rng.randf_range(0.06, 0.17) * size * (1.25 if rng.randf() < 0.3 else 1.0)
		dirv = (dirv + Vector3(rng.randf_range(-0.15, 0.15), 0.0, rng.randf_range(-0.15, 0.15))).normalized()
		# a tine: a flat, tapering finger growing out of the palm's edge, curving up a little
		var t_dir := (dirv + face * 0.25).normalized()
		var t_flat := (face - t_dir * face.dot(t_dir)).normalized()
		_leaf(k, p - t_dir * 0.05 * size, t_dir, t_flat, ln + 0.05 * size, 0.05 * size, -0.01 * size, 0.018 * size, mid_c.lerp(tip_c, 0.7), mid_c.lerp(tip_c, 0.45), mid_c, 4, 2)
	# brow palm: a small palm of its own reaching forward from the beam, ending in points
	var brow := base + beam_dir * 0.07 * size
	var b_along := (fwd * 1.0 + out * 0.55 + face * 0.25).normalized()
	var b_hollow := (face - b_along * face.dot(b_along)).normalized()
	var bl := 0.2 * size
	_leaf(k, brow, b_along, -b_hollow, bl, 0.05 * size, 0.012, 0.022, mid_c, base_c.lerp(mid_c, 0.5), base_c, 4, 2)
	var n_brow := 3 if level == 2 else 4
	var b_side := b_along.cross(b_hollow).normalized()
	for i in n_brow:
		var f := (float(i) / (n_brow - 1)) * 2.0 - 1.0
		var p := brow + b_along * bl * (0.82 + 0.1 * (1.0 - absf(f))) + b_side * f * 0.04 * size
		var dirv := (b_along * 0.7 + b_side * f * 0.35 + face * 0.45).normalized()
		k.cyl(p, p + dirv * rng.randf_range(0.06, 0.11) * size, 0.016 * size, 0.004, 5, mid_c, tip_c)
