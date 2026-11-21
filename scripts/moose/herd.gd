class_name Herd
extends Node3D
## Owns every moose: spawning, respawning, alarms, hit queries, ambient calls.

const POPULATION := {"cow": 5, "young": 4, "bull": 4, "trophy": 2}
const SOUND_SPEED := 343.0

var moose: Array[Moose] = []
var _next_id := 1
var _respawn_t := 8.0
var _call_t := 14.0
var _rng := RandomNumberGenerator.new()
var active := false
var _winded_t := 0.0
var _winded_told := false

func _ready() -> void:
	G.herd = self
	_rng.randomize()

## A moose has caught the hunter's scent and is leaving. Say so now and then - that is
## how one learns to hunt into the wind.
func winded_by(m: Moose) -> void:
	if G.player == null or G.hud == null or _winded_t > 0.0:
		return
	var d: float = m.global_position.distance_to(G.player.global_position)
	if d > 280.0:
		return
	_winded_t = 30.0
	var where := "%d m off" % int(round(d / 10.0) * 10.0)
	if not _winded_told:
		_winded_told = true
		G.hud.show_message("A moose %s caught your scent and is leaving. Keep the wind in your face." % where, 6.0)
	else:
		G.hud.show_message("A moose %s winded you." % where, 4.0)

func clear() -> void:
	_winded_t = 0.0
	_winded_told = false
	for m in moose:
		m.queue_free()
	moose.clear()

func populate(seed_v := 0) -> void:
	clear()
	if seed_v != 0:
		_rng.seed = seed_v
	else:
		_rng.randomize()
	var avoid: Vector3 = G.terrain.spawn_pos
	for kind in POPULATION:
		for i in int(POPULATION[kind]):
			var p := _find_spot(avoid, 150.0)
			spawn(kind, p, true)
	# cows like company: nudge some next to bulls
	for m in moose:
		if m.kind == "cow" and _rng.randf() < 0.5:
			var buddy: Moose = moose[_rng.randi() % moose.size()]
			if buddy != m:
				var q := buddy.position + Vector3(_rng.randf_range(-22, 22), 0, _rng.randf_range(-22, 22))
				if G.terrain.height(q.x, q.z) > 0.8:
					m.position = Vector3(q.x, G.terrain.height(q.x, q.z), q.z)
	_respawn_t = 10.0

func _find_spot(avoid: Vector3, min_dist: float) -> Vector3:
	var t: TerrainData = G.terrain
	for attempt in 200:
		var ang := _rng.randf() * TAU
		var r := sqrt(_rng.randf()) * 385.0
		var p := Vector3(cos(ang) * r, 0, sin(ang) * r)
		var h := t.height(p.x, p.z)
		if h < 1.0 or h > 95.0 or t.slope(p.x, p.z) > 0.2:
			continue
		if p.distance_to(Vector3(avoid.x, 0, avoid.z)) < min_dist:
			continue
		var ok := true
		for m in moose:
			if not m.dead and Vector2(m.position.x - p.x, m.position.z - p.z).length() < 34.0:
				ok = false
				break
		if not ok:
			continue
		if G.flora and G.flora.avoid_vector(p, 2.5).length() > 0.2:
			continue
		p.y = h
		return p
	return Vector3(120, t.height(120, -160), -160)

func spawn(kind: String, pos: Vector3, back_trail: bool) -> Moose:
	var m := Moose.new()
	m.name = "Moose_%d" % _next_id
	add_child(m)
	m.setup(kind, _next_id, pos, _rng.randf() * TAU)
	_next_id += 1
	moose.append(m)
	if back_trail and G.tracks:
		_lay_back_trail(m)
	return m

## Tracks leading up to where the animal stands now, so there is something to follow.
func _lay_back_trail(m: Moose) -> void:
	var p := m.position
	var dir := -m.forward()
	var ang := atan2(dir.x, dir.z)
	var pts := []
	for i in 46:
		ang += _rng.randf_range(-0.28, 0.28)
		p += Vector3(sin(ang), 0, cos(ang)) * 2.3
		if G.terrain.height(p.x, p.z) < 0.3 or Vector2(p.x, p.z).length() > 420.0:
			ang += 1.2
			continue
		pts.append([p, Vector2(-sin(ang), -cos(ang)), 20.0 + i * 9.0])
	pts.reverse()
	for e in pts:
		G.tracks.add_print(e[0], e[1], m.id, m.label(), e[2])

func alive_count() -> int:
	var n := 0
	for m in moose:
		if not m.dead:
			n += 1
	return n

# ---------------------------------------------------------------- queries
## First moose hit along the segment. Also startles animals the bullet passes close to.
func ray(from: Vector3, to: Vector3, near: Dictionary, shooter: Vector3) -> Dictionary:
	var best := {}
	var seg_mid := (from + to) * 0.5
	var reach := from.distance_to(to) * 0.5 + 4.0
	for m in moose:
		var c := m.centre()
		if c.distance_to(seg_mid) > reach:
			continue
		var closest := Geometry3D.get_closest_point_to_segment(c, from, to)
		var d := closest.distance_to(c)
		if d > 3.2 * m.size:
			if d < 7.0 and not m.dead and not near.has(m.id):
				near[m.id] = true
				m.alarm_later(0.05, "flee", shooter)
			continue
		var h := m.ray_test(from, to)
		if not h.is_empty() and (best.is_empty() or h["t"] < best["t"]):
			best = h
		elif h.is_empty() and not m.dead and not near.has(m.id):
			near[m.id] = true
			m.alarm_later(0.05, "flee", shooter)
	return best

## Side-effect-free distance query (rangefinder). Returns metres or -1.
func probe(from: Vector3, to: Vector3) -> float:
	var best := -1.0
	var length := from.distance_to(to)
	for m in moose:
		var c := m.centre()
		if Geometry3D.get_closest_point_to_segment(c, from, to).distance_to(c) > 3.2 * m.size:
			continue
		var h := m.ray_test(from, to)
		if not h.is_empty():
			var d: float = float(h["t"]) * length
			if best < 0.0 or d < best:
				best = d
	return best

func gunshot(from: Vector3) -> void:
	for m in moose:
		if m.dead:
			continue
		var d := m.global_position.distance_to(from)
		if d < 170.0:
			m.alarm_later(d / SOUND_SPEED, "flee", from)
		elif d < 430.0:
			m.alarm_later(d / SOUND_SPEED, "alert", from)

func bullet_landed(pos: Vector3, shooter: Vector3) -> void:
	for m in moose:
		if not m.dead and m.global_position.distance_to(pos) < 14.0:
			m.alarm_later(0.05, "flee", shooter)

## A moose was hit: the others nearby bolt.
func alarm(pos: Vector3, radius: float, threat: Vector3, except: Moose) -> void:
	for m in moose:
		if m == except or m.dead:
			continue
		var d := m.global_position.distance_to(pos)
		if d < radius:
			m.alarm_later(_rng.randf_range(0.1, 0.5), "flee", threat)

func nearest_carcass(p: Vector3, radius: float):
	var best = null
	var bd := radius
	for m in moose:
		if m.dead and not m.tagged:
			var d := m.centre().distance_to(p + Vector3(0, 1.0, 0))
			if d < bd:
				bd = d
				best = m
	return best

## Bulls within earshot wander in to investigate. Returns how many respond.
func call_from(pos: Vector3) -> int:
	var n := 0
	for m in moose:
		if m.dead or m.kind == "cow":
			continue
		var d := m.global_position.distance_to(pos)
		if d < 330.0 and d > 50.0 and _rng.randf() < 0.8:
			if m.lure(pos):
				n += 1
	return n

## Nearest living moose to a point (for dev tools / tips).
func nearest_alive(p: Vector3) -> Moose:
	var best: Moose = null
	var bd := INF
	for m in moose:
		if not m.dead:
			var d := m.global_position.distance_to(p)
			if d < bd:
				bd = d
				best = m
	return best

func _process(dt: float) -> void:
	if not active or get_tree().paused:
		return
	_winded_t = maxf(_winded_t - dt, 0.0)
	_respawn_t -= dt
	if _respawn_t <= 0.0:
		_respawn_t = 9.0
		_respawn()
	_call_t -= dt
	if _call_t <= 0.0:
		_call_t = _rng.randf_range(22.0, 48.0)
		_ambient_call()

func _respawn() -> void:
	# keep the valley stocked: replace harvested animals well away from the hunter
	var want := {}
	for kind in POPULATION:
		want[kind] = int(POPULATION[kind])
	for m in moose:
		if not m.dead:
			want[m.kind] = int(want[m.kind]) - 1
	var player_pos: Vector3 = G.player.global_position if G.player else Vector3.ZERO
	for kind in want:
		if int(want[kind]) > 0:
			spawn(kind, _find_spot(player_pos, 260.0), true)
			break
	# forget carcasses that were tagged long ago and are far away
	var i := 0
	while i < moose.size():
		var m := moose[i]
		if m.dead and m.tagged and m.centre().distance_to(player_pos) > 220.0:
			m.queue_free()
			moose.remove_at(i)
		else:
			i += 1

func _ambient_call() -> void:
	if G.player == null:
		return
	var pp: Vector3 = G.player.global_position
	var options: Array[Moose] = []
	for m in moose:
		if not m.dead and m.state in [Moose.State.GRAZE, Moose.State.WANDER]:
			var d := m.global_position.distance_to(pp)
			if d > 40.0 and d < 380.0:
				options.append(m)
	if options.is_empty():
		return
	var m: Moose = options[_rng.randi() % options.size()]
	var sound := "moose_bull" if m.kind != "cow" else ("moose_cow_1" if _rng.randf() < 0.5 else "moose_cow_2")
	Sfx.play_at(sound, m.head_pos(), 5.0, _rng.randf_range(0.92, 1.06), 60.0, 0.0, "Ambience")
