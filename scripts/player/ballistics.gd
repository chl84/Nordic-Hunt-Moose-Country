class_name Ballistics
extends Node3D
## Simulated bullets: gravity, drag, travel time. Hits are resolved against
## moose, trunks and boulders, the cabin, terrain and water.

const GRAVITY := 9.81
const MAX_LIFE := 3.2

var bullets: Array = []
var _tracers: Array[MeshInstance3D] = []
var _tracer_mat: StandardMaterial3D

func _ready() -> void:
	_tracer_mat = StandardMaterial3D.new()
	_tracer_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_tracer_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_tracer_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_tracer_mat.albedo_color = Color(1.0, 0.9, 0.7, 0.35)
	_tracer_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	for i in 4:
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.014, 0.014, 1.0)
		mi.mesh = bm
		mi.material_override = _tracer_mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.visible = false
		add_child(mi)
		_tracers.append(mi)

# ------------------------------------------------------------ trajectory math
## Height of the bullet relative to a flat line of fire after `dist` metres,
## when launched `angle` radians above that line.
static func _fly(v0: float, drag: float, angle: float, dist: float) -> float:
	var x := 0.0
	var y := 0.0
	var vx := v0 * cos(angle)
	var vy := v0 * sin(angle)
	var dt := 1.0 / 240.0
	while x < dist:
		var sp := sqrt(vx * vx + vy * vy)
		var k := drag * sp
		vx -= vx * k * dt
		vy -= (vy * k + GRAVITY) * dt
		var nx := x + vx * dt
		if nx >= dist:
			return y + vy * dt * ((dist - x) / maxf(nx - x, 0.0001))
		x = nx
		y += vy * dt
		if vx < 20.0:
			break
	return y

static func zero_angle(v0: float, drag: float, zero_dist: float) -> float:
	var angle := 0.0
	for i in 4:
		var miss := _fly(v0, drag, angle, zero_dist)
		angle -= atan2(miss, zero_dist)
	return angle

## Metres above (+) or below (-) the line of sight at `dist`.
static func drop_at(v0: float, drag: float, angle: float, dist: float) -> float:
	return _fly(v0, drag, angle, dist)

# ---------------------------------------------------------------- firing
func fire(origin: Vector3, dir: Vector3, stats: Dictionary, weapon_id: String) -> void:
	var tracer: MeshInstance3D = null
	for t in _tracers:
		if not t.visible:
			tracer = t
			break
	bullets.append({
		"pos": origin, "vel": dir * float(stats["velocity"]), "drag": float(stats["drag"]),
		"damage": float(stats["damage"]), "weapon": weapon_id, "origin": origin, "life": 0.0,
		"tracer": tracer, "near": {},
	})

func _physics_process(dt: float) -> void:
	if bullets.is_empty():
		return
	var i := 0
	while i < bullets.size():
		if _step(bullets[i], dt):
			var tr = bullets[i]["tracer"]
			if tr:
				tr.visible = false
			bullets.remove_at(i)
		else:
			i += 1

## Advances one bullet; returns true when it is spent.
func _step(b: Dictionary, dt: float) -> bool:
	var from: Vector3 = b["pos"]
	var vel: Vector3 = b["vel"]
	var sp := vel.length()
	vel -= vel * (float(b["drag"]) * sp * dt)
	vel.y -= GRAVITY * dt
	var to := from + vel * dt
	b["vel"] = vel
	b["life"] += dt
	var best_t := 2.0
	var hit := {}
	# moose
	if G.herd:
		var mh: Dictionary = G.herd.ray(from, to, b["near"], b["origin"])
		if not mh.is_empty() and mh["t"] < best_t:
			best_t = mh["t"]
			hit = mh
			hit["kind"] = "moose"
	# trunks and boulders
	if G.flora:
		var fh: Dictionary = G.flora.ray(from, to)
		if not fh.is_empty():
			var t := from.distance_to(fh["pos"]) / maxf(from.distance_to(to), 0.0001)
			if t < best_t:
				best_t = t
				hit = fh
	if G.world and G.world.structures:
		var sh: Dictionary = G.world.structures.ray(from, to)
		if not sh.is_empty():
			var t := from.distance_to(sh["pos"]) / maxf(from.distance_to(to), 0.0001)
			if t < best_t:
				best_t = t
				hit = sh
	# ground / water
	var gh = G.terrain.ray(from, to)
	if gh != null:
		var gp: Vector3 = gh
		var t := from.distance_to(gp) / maxf(from.distance_to(to), 0.0001)
		if t < best_t:
			best_t = t
			var wet := gp.y < 0.0
			if wet:
				# stop at the lake surface instead of the lake bed
				var k := from.y / maxf(from.y - gp.y, 0.0001)
				gp = from.lerp(gp, clampf(k, 0.0, 1.0))
				gp.y = 0.0
			hit = {"pos": gp, "normal": Vector3.UP if wet else G.terrain.normal(gp.x, gp.z), "kind": "water" if wet else "dirt"}
	# the dog: never hit, but a shot close past it is a fault (once per bullet)
	if G.dog and G.dog.active and not (b["near"] as Dictionary).has("dog"):
		var end := to if hit.is_empty() else from.lerp(to, clampf(best_t, 0.0, 1.0))
		if G.dog.near_segment(from, end, 1.0):
			b["near"]["dog"] = true
			G.dog.shot_close()
			if G.main and G.main.has_method("dog_endangered"):
				G.main.dog_endangered()
	if hit.is_empty():
		b["pos"] = to
		_update_tracer(b, from, to)
		return b["life"] > MAX_LIFE or absf(to.x) > 1900.0 or absf(to.z) > 1900.0 or to.y < -20.0
	_impact(b, hit, vel.normalized())
	return true

func _update_tracer(b: Dictionary, from: Vector3, to: Vector3) -> void:
	var tr = b["tracer"]
	if tr == null:
		return
	var travelled: float = (to - (b["origin"] as Vector3)).length()
	if travelled < 14.0:
		return
	var mid := (from + to) * 0.5
	var mi: MeshInstance3D = tr
	mi.visible = true
	mi.global_position = mid
	if (to - from).length_squared() > 0.001:
		mi.look_at(to, Vector3.UP if absf((to - from).normalized().y) < 0.99 else Vector3.RIGHT)
	var w := 1.0 + travelled * 0.012
	mi.scale = Vector3(w, w, (to - from).length() * 0.6)

func _impact(b: Dictionary, hit: Dictionary, dir: Vector3) -> void:
	var pos: Vector3 = hit["pos"]
	var shooter: Vector3 = b["origin"]
	var dist := shooter.distance_to(pos)
	var listener: Vector3 = G.player.cam.global_position if G.player else shooter
	match hit["kind"]:
		"moose":
			var moose = hit["moose"]
			moose.take_hit(hit["zone"], pos, dir, float(b["damage"]), dist, b["weapon"], hit.get("part", -1))
			Sfx.play_at_delayed("hit_flesh", pos, listener, 4.0, randf_range(0.92, 1.05), 55.0)
			if G.main and G.main.has_method("on_hit"):
				G.main.on_hit()
		"wood":
			G.fx.impact_wood(pos, hit["normal"])
			Sfx.play_at_delayed("hit_wood", pos, listener, 2.0, randf_range(0.9, 1.1), 40.0)
		"rock":
			G.fx.impact_rock(pos, hit["normal"])
			Sfx.play_at_delayed("hit_rock", pos, listener, 0.0, randf_range(0.9, 1.15), 45.0)
		"water":
			G.fx.impact_water(pos)
			Sfx.play_at_delayed("hit_water", pos, listener, 2.0, randf_range(0.9, 1.1), 40.0)
		_:
			G.fx.impact_dirt(pos, hit["normal"], G.terrain.ground_color(pos.x, pos.z))
			Sfx.play_at_delayed("hit_dirt", pos, listener, 1.0, randf_range(0.9, 1.1), 40.0)
	if hit["kind"] != "moose" and G.herd:
		G.herd.bullet_landed(pos, shooter)
