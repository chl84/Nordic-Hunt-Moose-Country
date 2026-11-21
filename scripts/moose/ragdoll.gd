class_name MooseRagdoll
extends RefCounted
## Position-based (Verlet) ragdoll for a moose: 22 particles joined by rigid
## sticks plus one-sided "keep apart" constraints, colliding with the terrain
## and tree trunks. The solved particle cloud drives the skeleton.

const GRAV := Vector3(0, -12.5, 0)
const B := MooseModel.B

var skel: Skeleton3D
var owner_xf: Transform3D
var scale := 1.0
var p := PackedVector3Array()
var pp := PackedVector3Array()
var radius := PackedFloat32Array()
var inv_mass := PackedFloat32Array()
var sticks: Array = []        ## [i, j, length]
var mins: Array = []          ## [i, j, min length]
var rest_pts: Array = []      ## model-space rest points of the particles
var asleep := false
var age := 0.0
var _still := 0.0
var _thumped := false
var _f_torso_rest: Transform3D
var _f_head_rest: Transform3D

func setup(p_skel: Skeleton3D, p_scale: float, velocity: Vector3, hit_pos: Vector3, impulse: Vector3, wide_antlers: float) -> void:
	skel = p_skel
	scale = p_scale
	owner_xf = skel.global_transform
	var n := MooseModel.RAG.size()
	p.resize(n)
	pp.resize(n)
	radius.resize(n)
	inv_mass.resize(n)
	var h := 1.0 / 120.0
	for i in n:
		var r: Array = MooseModel.RAG[i]
		var pt: Vector3 = r[1]
		if i == 10 or i == 11:
			pt = Vector3(signf(pt.x) * wide_antlers, pt.y + (0.12 if wide_antlers > 0.3 else 0.0), pt.z)
		rest_pts.append(pt)
		var bone: int = r[0]
		var world := owner_xf * (skel.get_bone_global_pose(bone) * (pt - MooseModel.rest(bone)))
		p[i] = world
		radius[i] = float(r[2]) * scale
		inv_mass[i] = 1.0 / float(r[3])
		var v := velocity
		var d := world.distance_to(hit_pos)
		if d < 1.3 * scale:
			v += impulse * (1.0 - d / (1.3 * scale)) * inv_mass[i] * 4.0
		pp[i] = world - v * h
	# rigid torso (fully braced) and rigid head
	for group in [[0, 1, 2, 3, 4, 5, 6, 7], [8, 9, 10, 11]]:
		for a in group.size():
			for b in range(a + 1, group.size()):
				_stick(group[a], group[b])
	# neck and legs
	for pair in [[7, 8], [2, 12], [12, 13], [3, 14], [14, 15], [0, 16], [16, 17], [17, 18], [1, 19], [19, 20], [20, 21]]:
		_stick(pair[0], pair[1])
	# anatomical limits: joints that must not fold through each other
	for m in [
		[8, 4, 0.72], [8, 6, 0.8], [9, 7, 0.72], [8, 2, 0.74], [8, 3, 0.74], [9, 4, 0.6],
		[13, 2, 0.5], [15, 3, 0.5], [13, 3, 0.45], [15, 2, 0.45], [12, 4, 0.75], [14, 4, 0.75],
		[12, 6, 0.55], [14, 6, 0.55], [12, 14, 0.6], [13, 15, 0.35], [13, 6, 0.5], [15, 6, 0.5],
		[17, 0, 0.6], [20, 1, 0.6], [18, 16, 0.6], [21, 19, 0.6], [18, 0, 0.42], [21, 1, 0.42],
		[16, 5, 0.75], [19, 5, 0.75], [17, 5, 0.7], [20, 5, 0.7], [16, 19, 0.7], [17, 20, 0.4], [18, 21, 0.35],
		[16, 6, 0.6], [19, 6, 0.6], [18, 6, 0.5], [21, 6, 0.5], [13, 18, 0.3], [15, 21, 0.3],
	]:
		mins.append([m[0], m[1], (rest_pts[m[0]] as Vector3).distance_to(rest_pts[m[1]]) * scale * float(m[2])])
	_f_torso_rest = _torso_frame_from(rest_pts)
	_f_head_rest = _head_frame_from(rest_pts)

func _stick(a: int, b: int) -> void:
	sticks.append([a, b, (rest_pts[a] as Vector3).distance_to(rest_pts[b]) * scale])

func push(at: Vector3, impulse: Vector3) -> void:
	asleep = false
	_still = 0.0
	age = minf(age, 1.0)
	var h := 1.0 / 120.0
	for i in p.size():
		var d := p[i].distance_to(at)
		if d < 1.0 * scale:
			pp[i] -= impulse * (1.0 - d / (1.0 * scale)) * inv_mass[i] * 3.0 * h

func step(dt: float) -> void:
	if asleep:
		return
	age += dt
	var sub := 2
	var h := dt / sub
	var t: TerrainData = G.terrain
	var moved := 0.0
	for s in sub:
		for i in p.size():
			var v := (p[i] - pp[i]) * 0.992
			pp[i] = p[i]
			p[i] += v + GRAV * h * h
		for it in 6:
			for c in sticks:
				var a: int = c[0]
				var b: int = c[1]
				var d := p[b] - p[a]
				var len := d.length()
				if len < 0.0001:
					continue
				var w := inv_mass[a] + inv_mass[b]
				var corr := d * ((len - float(c[2])) / len / w)
				p[a] += corr * inv_mass[a]
				p[b] -= corr * inv_mass[b]
			for c in mins:
				var a: int = c[0]
				var b: int = c[1]
				var d := p[b] - p[a]
				var len := d.length()
				if len >= float(c[2]) or len < 0.0001:
					continue
				var w := inv_mass[a] + inv_mass[b]
				var corr := d * ((len - float(c[2])) / len / w)
				p[a] += corr * inv_mass[a]
				p[b] -= corr * inv_mass[b]
		# ground (lakes: the carcass floats low in the water)
		for i in p.size():
			var q := p[i]
			var ground := maxf(t.height(q.x, q.z), -0.45) + radius[i]
			if q.y < ground:
				var depth := ground - q.y
				q.y = ground
				var fr := 0.55 if t.height(q.x, q.z) > -0.3 else 0.12
				var prev := pp[i]
				prev.x = lerpf(prev.x, q.x, fr)
				prev.z = lerpf(prev.z, q.z, fr)
				pp[i] = prev
				p[i] = q
				if not _thumped and i < 8 and depth > 0.004 and age > 0.15:
					_thumped = true
					Sfx.play_at_delayed("body_fall", q, G.player.cam.global_position if G.player else q, 2.0, randf_range(0.9, 1.05), 30.0)
					if G.fx:
						G.fx.dust_puff(q, Color(0.6, 0.55, 0.45), 1.6)
		if G.flora:
			for i in 8:
				var q: Vector3 = G.flora.push_out(p[i], radius[i] * 0.8)
				p[i] = q
	for i in p.size():
		moved = maxf(moved, (p[i] - pp[i]).length())
	if moved < 0.0016 and age > 1.2:
		_still += dt
	else:
		_still = 0.0
	if _still > 0.7 or age > 12.0:
		asleep = true

# ----------------------------------------------------- particles -> bones
static func _frame(origin: Vector3, y_dir: Vector3, x_hint: Vector3) -> Transform3D:
	var y := y_dir.normalized()
	var x := (x_hint - y * x_hint.dot(y))
	if x.length_squared() < 1e-6:
		x = y.cross(Vector3.FORWARD)
	x = x.normalized()
	return Transform3D(Basis(x, y, x.cross(y)), origin)

static func _torso_frame_from(pts: Array) -> Transform3D:
	var hips: Vector3 = ((pts[0] as Vector3) + pts[1]) * 0.5
	var sh: Vector3 = ((pts[2] as Vector3) + pts[3]) * 0.5
	var right: Vector3 = ((pts[1] as Vector3) - pts[0]) + ((pts[3] as Vector3) - pts[2])
	return _frame((hips + sh) * 0.5, sh - hips, right)

static func _head_frame_from(pts: Array) -> Transform3D:
	return _frame(pts[8], (pts[9] as Vector3) - pts[8], (pts[11] as Vector3) - pts[10])

func _arr() -> Array:
	var a := []
	for i in p.size():
		a.append(p[i])
	return a

func apply() -> void:
	var inv := skel.global_transform.affine_inverse()
	var pts := _arr()
	var sc := Basis.IDENTITY.scaled(Vector3(scale, scale, scale))
	var torso := _torso_frame_from(pts)
	var torso_map := torso * Transform3D(sc, Vector3.ZERO) * _f_torso_rest.affine_inverse()
	var right := torso.basis.x
	_set_rigid(B.ROOT, inv, torso_map)
	_set_rigid(B.HIPS, inv, torso_map)
	_set_rigid(B.CHEST, inv, torso_map)
	_set_chain(B.NECK, inv, 7, 8, right, Vector3.RIGHT)
	var head := _head_frame_from(pts)
	var head_map := head * Transform3D(sc, Vector3.ZERO) * _f_head_rest.affine_inverse()
	_set_rigid(B.HEAD, inv, head_map)
	_set_chain(B.FL_U, inv, 2, 12, right, Vector3.RIGHT)
	_set_chain(B.FL_L, inv, 12, 13, right, Vector3.RIGHT)
	_set_chain(B.FR_U, inv, 3, 14, right, Vector3.RIGHT)
	_set_chain(B.FR_L, inv, 14, 15, right, Vector3.RIGHT)
	_set_chain(B.HL_T, inv, 0, 16, right, Vector3.RIGHT)
	_set_chain(B.HL_S, inv, 16, 17, right, Vector3.RIGHT)
	_set_chain(B.HL_C, inv, 17, 18, right, Vector3.RIGHT)
	_set_chain(B.HR_T, inv, 1, 19, right, Vector3.RIGHT)
	_set_chain(B.HR_S, inv, 19, 20, right, Vector3.RIGHT)
	_set_chain(B.HR_C, inv, 20, 21, right, Vector3.RIGHT)

## Bone carried rigidly by a frame map (model space -> world).
func _set_rigid(bone: int, inv: Transform3D, map: Transform3D) -> void:
	var world := map * Transform3D(Basis.IDENTITY, MooseModel.rest(bone))
	var local := inv * world
	skel.set_bone_global_pose(bone, Transform3D(local.basis.orthonormalized(), local.origin))

## Bone that runs from particle `a` to particle `b`.
func _set_chain(bone: int, inv: Transform3D, a: int, b: int, x_hint: Vector3, x_hint_rest: Vector3) -> void:
	var cur := _frame(p[a], p[b] - p[a], x_hint)
	var rest_f := _frame(rest_pts[a], (rest_pts[b] as Vector3) - rest_pts[a], x_hint_rest)
	var basis := cur.basis * rest_f.basis.inverse()
	var local := inv * Transform3D(basis, p[a])
	skel.set_bone_global_pose(bone, Transform3D(local.basis.orthonormalized(), local.origin))

func centre() -> Vector3:
	return (p[0] + p[1] + p[2] + p[3]) * 0.25
