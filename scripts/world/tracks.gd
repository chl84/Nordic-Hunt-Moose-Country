class_name Tracks
extends Node3D
## Hoof prints and blood drops left by moose, stored in ring buffers and
## drawn as two MultiMeshes. Supports "examine" and trail highlighting.

const MAX_PRINTS := 3000
const MAX_BLOOD := 900
const DIRS := ["north", "north-east", "east", "south-east", "south", "south-west", "west", "north-west"]

var prints: Array = []        ## [pos, heading(Vector2), time, moose_id, kind_name]
var blood: Array = []         ## [pos, time, moose_id, kind_name]
var _pi := 0
var _bi := 0
var _mm_p: MultiMesh
var _mm_b: MultiMesh
var _mat_p: ShaderMaterial
var _mat_b: ShaderMaterial
var _sense_t := 0.0
var _trail_t := 0.0
var clock := 0.0

func _ready() -> void:
	G.tracks = self
	prints.resize(MAX_PRINTS)
	blood.resize(MAX_BLOOD)
	_mat_p = _material(_print_texture(), Color(0.045, 0.03, 0.02), Color(1.0, 0.62, 0.18))
	_mat_b = _material(_splat_texture(), Color(0.33, 0.012, 0.012), Color(1.0, 0.16, 0.1))
	_mm_p = _multimesh(MAX_PRINTS, Vector2(0.34, 0.3), _mat_p)
	_mm_b = _multimesh(MAX_BLOOD, Vector2(0.4, 0.4), _mat_b)

func _material(tex: Texture2D, base: Color, glow: Color) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/track.gdshader")
	m.set_shader_parameter("tex", tex)
	m.set_shader_parameter("base_color", base)
	m.set_shader_parameter("glow_color", glow)
	return m

func _multimesh(count: int, size: Vector2, mat: Material) -> MultiMesh:
	var pm := PlaneMesh.new()
	pm.size = size
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = pm
	mm.instance_count = count
	for i in count:
		mm.set_instance_transform(i, Transform3D(Basis.IDENTITY.scaled(Vector3.ZERO), Vector3(0, -500, 0)))
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = mat
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.custom_aabb = AABB(Vector3(-600, -50, -600), Vector3(1200, 500, 1200))
	add_child(mmi)
	return mm

## Two cloven hooves side by side with dew-claw dots.
static func _print_texture() -> ImageTexture:
	var w := 96
	var h := 84
	var img := Image.create(w, h, true, Image.FORMAT_RGBA8)
	for y in h:
		for x in w:
			var a := 0.0
			for hoof in 2:
				var cx := 0.27 + hoof * 0.46
				var u := (float(x) / w - cx) / 0.2
				var v := (float(y) / h - 0.5) / 0.44
				for toe in 2:
					var tx := u + (0.42 if toe == 0 else -0.42)
					var width := 0.36 * (1.0 - 0.55 * clampf(-v, 0.0, 1.0)) * (1.0 - 0.2 * clampf(v, 0.0, 1.0))
					var d := absf(tx) / maxf(width, 0.01)
					if absf(v) < 0.92 and d < 1.0:
						a = maxf(a, smoothstep(1.0, 0.6, d) * smoothstep(0.92, 0.7, absf(v)))
			img.set_pixel(x, y, Color(1, 1, 1, a))
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)

static func _splat_texture() -> ImageTexture:
	var s := 64
	var img := Image.create(s, s, true, Image.FORMAT_RGBA8)
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var blobs := []
	blobs.append([Vector2(0.5, 0.5), 0.2])
	for i in 9:
		blobs.append([Vector2(0.5, 0.5) + Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(0.12, 0.36), rng.randf_range(0.03, 0.09)])
	for y in s:
		for x in s:
			var p := Vector2((x + 0.5) / s, (y + 0.5) / s)
			var a := 0.0
			for b in blobs:
				a = maxf(a, smoothstep(b[1], b[1] * 0.6, p.distance_to(b[0])))
			img.set_pixel(x, y, Color(1, 1, 1, a))
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)

func clear() -> void:
	for i in MAX_PRINTS:
		prints[i] = null
		_mm_p.set_instance_transform(i, Transform3D(Basis.IDENTITY.scaled(Vector3.ZERO), Vector3(0, -500, 0)))
	for i in MAX_BLOOD:
		blood[i] = null
		_mm_b.set_instance_transform(i, Transform3D(Basis.IDENTITY.scaled(Vector3.ZERO), Vector3(0, -500, 0)))
	_pi = 0
	_bi = 0
	clock = 0.0

func _ground_xf(pos: Vector3, heading: Vector2, size: float) -> Transform3D:
	var n: Vector3 = G.terrain.normal(pos.x, pos.z)
	var fwd := Vector3(heading.x, 0, heading.y)
	if fwd.length_squared() < 0.001:
		fwd = Vector3.FORWARD
	var x := n.cross(fwd).normalized()
	var z := x.cross(n).normalized()
	var p := Vector3(pos.x, G.terrain.height(pos.x, pos.z), pos.z) + n * 0.035
	return Transform3D(Basis(x * size, n * size, z * size), p)

func add_print(pos: Vector3, heading: Vector2, moose_id: int, kind_name: String, age := 0.0) -> void:
	if G.terrain.height(pos.x, pos.z) < 0.05:
		return
	prints[_pi] = [pos, heading, clock - age, moose_id, kind_name]
	_mm_p.set_instance_transform(_pi, _ground_xf(pos, heading, 1.0))
	_mm_p.set_instance_custom_data(_pi, Color(float(moose_id) / 512.0, 1.0, 0, 0))
	_pi = (_pi + 1) % MAX_PRINTS

func add_blood(pos: Vector3, size: float, moose_id: int, kind_name: String) -> void:
	if not Settings.get_v("blood") or G.terrain.height(pos.x, pos.z) < 0.02:
		return
	blood[_bi] = [pos, clock, moose_id, kind_name]
	_mm_b.set_instance_transform(_bi, _ground_xf(pos, Vector2.from_angle(randf() * TAU), size))
	_mm_b.set_instance_custom_data(_bi, Color(float(moose_id) / 512.0, 1.0, 0, 0))
	_bi = (_bi + 1) % MAX_BLOOD

## Closest mark within `radius` (blood wins over prints). {} if none.
func nearest(p: Vector3, radius: float) -> Dictionary:
	var best := {}
	var bd := radius * radius
	for i in MAX_BLOOD:
		var b = blood[i]
		if b == null:
			continue
		var d := Vector2(b[0].x - p.x, b[0].z - p.z).length_squared()
		if d < bd:
			bd = d
			best = {"blood": true, "pos": b[0], "time": b[1], "id": b[2], "kind": b[3]}
	if not best.is_empty():
		return best
	for i in MAX_PRINTS:
		var t = prints[i]
		if t == null:
			continue
		var d := Vector2(t[0].x - p.x, t[0].z - p.z).length_squared()
		if d < bd:
			bd = d
			best = {"blood": false, "pos": t[0], "heading": t[1], "time": t[2], "id": t[3], "kind": t[4]}
	return best

static func compass(heading: Vector2) -> String:
	var deg := rad_to_deg(atan2(heading.x, -heading.y))
	return DIRS[posmod(int(round(deg / 45.0)), 8)]

func describe(info: Dictionary) -> String:
	var age: float = clock - float(info["time"])
	var age_s := "fresh" if age < 45.0 else ("%d min old" % int(ceil(age / 60.0)))
	if info["blood"]:
		return "Blood  -  wounded %s  -  %s" % [info["kind"], age_s]
	return "Moose tracks  -  %s  -  %s  -  heading %s" % [info["kind"], age_s, compass(info["heading"])]

## Light up every mark within `radius` for a while. Returns how many there are.
func highlight(center: Vector3, radius: float, seconds: float) -> int:
	var n := 0
	for i in MAX_PRINTS:
		var t = prints[i]
		if t != null and (t[0] as Vector3).distance_to(center) < radius:
			n += 1
	for i in MAX_BLOOD:
		var b = blood[i]
		if b != null and (b[0] as Vector3).distance_to(center) < radius:
			n += 1
	for m in [_mat_p, _mat_b]:
		m.set_shader_parameter("sense_center", center)
		m.set_shader_parameter("sense_radius", radius)
	_sense_t = seconds
	return n

func highlight_trail(info: Dictionary, seconds: float) -> void:
	for m in [_mat_p, _mat_b]:
		m.set_shader_parameter("trail_id", float(info["id"]) / 512.0)
	_trail_t = seconds

func _process(dt: float) -> void:
	if get_tree().paused:
		return
	clock += dt
	_sense_t = maxf(_sense_t - dt, 0.0)
	_trail_t = maxf(_trail_t - dt, 0.0)
	var day := 1.0
	if G.sky:
		day = 0.55 + 0.45 * sin(PI * clampf(G.sky.time, 0.03, 0.97))
	for m in [_mat_p, _mat_b]:
		m.set_shader_parameter("sense_strength", clampf(_sense_t, 0.0, 1.0))
		m.set_shader_parameter("trail_strength", clampf(_trail_t, 0.0, 1.0))
		m.set_shader_parameter("daylight", day)
