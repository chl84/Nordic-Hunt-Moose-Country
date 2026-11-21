class_name Dog
extends Node3D
## The hunter's grey elkhound. On the lead it keeps to heel; let loose (G) it ranges out
## into the wind and finds moose by scent or on fresh tracks. A moose that stands for it
## is held at bay - the dog circles it barking steadily while the hunter closes in under
## cover of the noise - and one that runs is followed, the dog giving tongue, until it
## stands again or gets away. It keeps watch over a fallen moose, and comes back when
## whistled in (G again). Its GPS collar shows on the compass and the map.

enum S { HEEL, SEARCH, TRAIL, BAY, FOLLOW, RETURN, GUARD }

const NAME := "Fant"
const B := DogModel.B
const GALLOP := 7.6
const LOPE := 5.4
const MAX_OUT := 560.0          ## ranges no further from the hunter than this
const SIT_TILT := 35.0          ## degrees the body tips back when it sits
const NAV_CELL := 5.0           ## the route grid: 5 m cells over the valley
const NAV_HALF := 450.0

## Where a dog can run: dry land that is not a cliff, inside the valley. Built once.
static var _nav: AStarGrid2D
const STATUS := ["at heel", "searching", "on a scent", "baying", "following a moose", "coming back", "by the moose"]

var state := S.HEEL
var state_t := 0.0
var target: Moose = null
var heading := 0.0
var speed := 0.0
var active := false
var skel: Skeleton3D

var _mesh: MeshInstance3D
var _goal := Vector3.ZERO
var _want := 0.0
var _turn := 4.0
var _think := 0.0
var _rng := RandomNumberGenerator.new()
var _phase := 0.0
var _bark_t := 0.0
var _bark_run := 0
var _jaw := 0.0
var _sit := 0.0
var _still := 0.0
var _circle := 1.0
var _bay_ang := 0.0
var _bay_move_t := 0.0          ## standing barking until this runs out, then a few steps round
var _wp_t := 0.0
var _lost_t := 0.0
var _guard_barks := 0
var _pitch := 0.0
var _neck := 0.0
var _head := 0.0
var _look := 0.0
var _neck_t := 0.0
var _head_t := 0.0
var _look_t := 0.0
var _wag := 0.0
var _wag_t := 0.0
var _sniff_t := 0.0
var _frame := 0
var _side := 1.0                ## which way it goes round water in its path
var _best_d := INF              ## closest it has got to the moose it is after...
var _best_t := 0.0              ## ...and how long ago
var _path := PackedVector2Array()   ## route round a lake (world x, z), when the way is not straight
var _path_i := 0
var _path_goal := Vector3(INF, 0, INF)
var _path_t := 0.0
var _cut_t := 0.0

func _ready() -> void:
	G.dog = self
	_rng.randomize()
	skel = DogModel.make_skeleton()
	add_child(skel)
	_mesh = MeshInstance3D.new()
	_mesh.mesh = DogModel.mesh()
	_mesh.skin = skel.create_skin_from_rest_transforms()
	skel.add_child(_mesh)
	_mesh.skeleton = _mesh.get_path_to(skel)
	_mesh.extra_cull_margin = 1.0
	visible = false
	if _nav == null and G.terrain:
		var t0 := Time.get_ticks_msec()
		_nav = _build_nav()
		print("[dog] route grid built in %d ms" % (Time.get_ticks_msec() - t0))

# ------------------------------------------------------------------ control
func begin_hunt(pos: Vector3, facing: float) -> void:
	active = true
	visible = true
	target = null
	speed = 0.0
	heading = facing
	_sit = 0.0
	position = Vector3(pos.x, G.terrain.height(pos.x, pos.z), pos.z)
	_enter(S.HEEL)

func end_hunt() -> void:
	active = false
	visible = false
	target = null

func out() -> bool:
	return active and state != S.HEEL

## G: let the dog loose, or whistle it in.
func toggle() -> void:
	if not active:
		return
	if state == S.HEEL:
		_enter(S.SEARCH)
		_new_waypoint()
		Sfx.play("rustle_1", -10.0)
		_say("%s is off, nose into the wind." % NAME, 3.0)
	else:
		recall("You whistle %s in." % NAME)

## Back to the hunter. `whistle`: the hunter called it (the dog giving up on its own
## just comes).
func recall(text := "", whistle := true) -> void:
	if state == S.HEEL or state == S.RETURN:
		return
	if whistle:
		Sfx.play("dog_whistle", -6.0, _rng.randf_range(0.97, 1.03))
	if target and is_instance_valid(target) and target.is_bayed():
		target.dog_left()
	target = null
	_enter(S.RETURN)
	if text != "":
		_say(text, 3.0)

## A bullet went close past the dog: it comes straight back to the hunter.
func shot_close() -> void:
	recall()

func status() -> String:
	return STATUS[state]

func centre() -> Vector3:
	return global_position + Vector3(0, 0.4, 0)

func nose() -> Vector3:
	return global_position + Vector3(0, 0.62, 0) + forward() * 0.55

func forward() -> Vector3:
	return Vector3(-sin(heading), 0, -cos(heading))

## Does the segment pass within `r` of the dog?
func near_segment(a: Vector3, b: Vector3, r: float) -> bool:
	var c := centre()
	return Geometry3D.get_closest_point_to_segment(c, a, b).distance_to(c) < r

func _enter(s: S) -> void:
	state = s
	state_t = 0.0
	_best_d = INF
	_best_t = 0.0
	_lost_t = 0.0
	_bark_t = 0.0
	_bark_run = 0

func _say(text: String, seconds: float) -> void:
	if G.hud:
		G.hud.show_message(text, seconds)

# -------------------------------------------------------------------- think
func _process(dt: float) -> void:
	if not active or dt <= 0.0 or G.player == null:
		return
	state_t += dt
	_think -= dt
	if _think <= 0.0:
		_think = 0.25
		_decide(0.25)
	_act(dt)
	_bark_tick(dt)
	_move(dt)
	_frame += 1
	var d: float = global_position.distance_to(G.player.global_position)
	var skip := 1 if d < 120.0 else (2 if d < 300.0 else 4)
	if _frame % skip == 0:
		_animate(dt * skip)

func _decide(dt: float) -> void:
	var pp: Vector3 = G.player.global_position
	match state:
		S.SEARCH:
			var m := _sniff()
			if m:
				target = m
				_enter(S.TRAIL)
				return
			_wp_t -= dt
			if _wp_t <= 0.0 or _flat_dist(_goal) < 6.0 or _flat_dist(pp) > MAX_OUT:
				_new_waypoint()
			if state_t > 210.0:
				recall("%s found nothing and is coming back." % NAME, false)
		S.TRAIL, S.BAY, S.FOLLOW:
			if target == null or not is_instance_valid(target):
				recall("", false)
				return
			if target.dead:
				_enter(S.GUARD)
				_guard_barks = _rng.randi_range(4, 7)
				return
			var d := _flat_dist(target.global_position)
			# no closer for half a minute (cut off by water or the valley's edge): give up
			_best_t += dt
			if d < _best_d - 4.0:
				_best_d = d
				_best_t = 0.0
			if _best_t > 30.0 and state != S.BAY:
				recall("%s lost the moose and is coming back." % NAME, false)
				return
			if state == S.TRAIL:
				if target.state == Moose.State.FLEE and d < 90.0:
					_enter(S.FOLLOW)
				elif d < 20.0:
					_meet()
				elif d > 650.0 or state_t > 160.0:
					recall("%s lost the scent and is coming back." % NAME, false)
			elif state == S.BAY:
				if not target.is_bayed():
					_enter(S.FOLLOW)
			else:   # FOLLOW
				if target.is_bayed():
					_enter(S.BAY)
					_bay_ang = _angle_from(target.global_position)
				elif target.state != Moose.State.FLEE and d < 24.0:
					_meet()
				if d > 170.0:
					_lost_t += dt
				else:
					_lost_t = 0.0
				if _lost_t > 10.0 or state_t > 170.0:
					recall("%s lost the moose and is coming back." % NAME, false)
		S.RETURN:
			if _flat_dist(pp) < 3.5:
				_enter(S.HEEL)
				_say("%s is back at heel." % NAME, 2.5)
		S.GUARD:
			if target == null or not is_instance_valid(target):
				recall("", false)
			elif _flat_dist(pp) < 9.0 and state_t > 2.0:
				_enter(S.HEEL)

## Up to the moose: it stands (bay) or runs (follow).
func _meet() -> void:
	if target.meet_dog(global_position):
		_enter(S.BAY)
		_bay_ang = _angle_from(target.global_position)
		_circle = 1.0 if _rng.randf() < 0.5 else -1.0
		_say("%s has a moose at bay - %s." % [NAME, _gps_text()], 4.0)
	elif state != S.FOLLOW:
		_enter(S.FOLLOW)
		_say("%s is after a moose." % NAME, 3.0)

## The best moose the dog can smell from here (wounded ones first), or one whose fresh
## tracks it has just crossed.
func _sniff() -> Moose:
	if G.herd == null or G.wind == null:
		return null
	var best: Moose = null
	var best_s := 0.2
	var nz := nose()
	for m in G.herd.moose:
		if m.dead:
			continue
		var d: float = m.global_position.distance_to(global_position)
		if d > 700.0:
			continue
		var s: float = G.wind.scent(m.centre(), nz, 3.2 if m.wounded else 2.2)
		if d < 45.0:
			s = maxf(s, 1.0 - d / 45.0)
		if m.wounded:
			s *= 1.6
		if s > best_s:
			best_s = s
			best = m
	if best == null and G.tracks:
		var tr: Dictionary = G.tracks.nearest(global_position, 2.6)
		if not tr.is_empty() and G.tracks.clock - float(tr["time"]) < 420.0:
			for m in G.herd.moose:
				if m.id == int(tr["id"]) and not m.dead:
					best = m
	return best

func _new_waypoint() -> void:
	var pp: Vector3 = G.player.global_position
	var up: Vector2 = -G.wind.dir if G.wind else Vector2(0, -1)
	var base_ang := atan2(up.y, up.x)
	var best := pp
	var best_s := -INF
	for i in 14:
		var ang := base_ang + _rng.randf_range(-1.4, 1.4)
		var r := _rng.randf_range(90.0, 320.0)
		var c := pp + Vector3(cos(ang) * r, 0.0, sin(ang) * r)
		if Vector2(c.x, c.z).length() > 392.0:
			continue
		var h: float = G.terrain.height(c.x, c.z)
		if h < 0.4 or G.terrain.slope(c.x, c.z) > 0.45:
			continue
		# somewhere new, more or less into the wind
		var s := _flat_dist(c) * 0.01 + _rng.randf() + cos(ang - base_ang)
		if s > best_s:
			best_s = s
			best = c
	_goal = best
	_wp_t = 45.0

# ---------------------------------------------------------------------- act
func _act(dt: float) -> void:
	var pl: Player = G.player
	var pp: Vector3 = pl.global_position
	_turn = 5.0
	match state:
		S.HEEL:
			var st: Structures = G.world.structures if G.world else null
			if pl.on_tower >= 0 and st:
				var base: Vector3 = st.towers[pl.on_tower][0]
				_goal = base + Basis(Vector3.UP, st.tower_yaw(pl.on_tower)) * Vector3(1.2, 0, -2.2)
			else:
				_goal = pp + Basis(Vector3.UP, pl.yaw) * Vector3(-0.85, 0.0, 1.25)
			var d := _flat_dist(_goal)
			_want = clampf((d - 0.35) * 1.8, 0.0, GALLOP)
			if d < 0.5:
				_want = 0.0
			_neck_t = 4.0
			_head_t = -6.0
			_look_t = sin(state_t * 0.37) * 25.0
		S.SEARCH:
			_want = LOPE
			# nose up into the wind, then down to the ground
			_sniff_t += dt
			_neck_t = 8.0 if sin(_sniff_t * 0.5) > 0.0 else -24.0
			_head_t = -10.0 if _neck_t > 0.0 else -28.0
			_look_t = sin(state_t * 1.3) * 18.0
		S.TRAIL:
			var tp := target.global_position
			var side := Vector3(-forward().z, 0, forward().x)
			_goal = tp + side * sin(state_t * 1.7) * 6.0
			_want = 6.4
			_neck_t = -30.0
			_head_t = -30.0
			_look_t = 0.0
		S.BAY:
			var mp := target.global_position
			target.dog_near(global_position)
			# it mostly stands its ground barking, now and then shifting a few steps round
			_bay_move_t -= dt
			if _bay_move_t <= 0.0:
				_bay_move_t = _rng.randf_range(4.0, 9.0)
				if _rng.randf() < 0.3:
					_circle = -_circle
				_bay_ang += _circle * _rng.randf_range(0.15, 0.45)
			var r := 12.0 + 3.0 * sin(state_t * 0.11)
			if target.is_lunging():
				r = 21.0
			_goal = mp + Vector3(cos(_bay_ang), 0.0, sin(_bay_ang)) * r
			var d := _flat_dist(_goal)
			_want = clampf(d * 1.4, 0.0, GALLOP if target.is_lunging() else 4.0)
			if d < 0.8:
				_want = 0.0
			_neck_t = 14.0
			_head_t = -12.0
			# eyes on the moose, even while it shifts round it
			var tm := mp - global_position
			_look_t = clampf(rad_to_deg(wrapf(atan2(-tm.x, -tm.z) - heading, -PI, PI)), -70.0, 70.0)
		S.FOLLOW:
			var tp := target.global_position
			var tf := target.forward()
			_goal = tp - tf * 14.0
			var d := _flat_dist(tp)
			if target.state == Moose.State.FLEE:
				_want = GALLOP + (1.0 if d > 40.0 else 0.0)
			else:
				_want = clampf((d - 14.0) * 0.6 + 1.6, 1.4, GALLOP)
			_neck_t = -6.0
			_head_t = -12.0
			_look_t = 0.0
		S.RETURN:
			_goal = pp
			_want = GALLOP * 0.85 if _flat_dist(pp) > 10.0 else 3.0
			_neck_t = -4.0
			_head_t = -10.0
			_look_t = 0.0
		S.GUARD:
			var c: Vector3 = target.centre() if target and is_instance_valid(target) else global_position
			_goal = c + (global_position - c).normalized() * 2.6
			var d := _flat_dist(_goal)
			_want = clampf(d * 1.5, 0.0, LOPE)
			if d < 0.6:
				_want = 0.0
			_neck_t = 10.0
			_head_t = -10.0
			_look_t = 0.0
	# sit at heel when the hunter stands still
	if state == S.HEEL and speed < 0.2 and _want < 0.1:
		_still += dt
	else:
		_still = 0.0
	_sit = move_toward(_sit, 1.0 if _still > 1.6 else 0.0, dt / (0.55 if _still > 1.6 else 0.3))

func _bark_tick(dt: float) -> void:
	_jaw = maxf(_jaw - dt * 7.0, 0.0)
	_bark_t -= dt
	if _bark_t > 0.0:
		return
	match state:
		S.BAY:
			# the steady stand-bark: runs of barks with short breaths between
			if _bark_run > 0:
				_bark()
				_bark_run -= 1
				_bark_t = _rng.randf_range(0.42, 0.78)
			else:
				_bark_run = _rng.randi_range(5, 14)
				_bark_t = _rng.randf_range(1.0, 3.0)
		S.FOLLOW:
			_bark()
			_bark_t = _rng.randf_range(1.1, 2.8)
		S.GUARD:
			if _guard_barks > 0:
				_guard_barks -= 1
				_bark()
				_bark_t = _rng.randf_range(0.8, 1.6)
			else:
				_bark_t = 999.0
		_:
			_bark_t = 0.5

func _bark() -> void:
	_jaw = 1.0
	var cam: Camera3D = G.player.cam
	var at := nose()
	Sfx.play_at_delayed("dog_bark_%d" % _rng.randi_range(1, 4), at, cam.global_position, 3.0, _rng.randf_range(0.95, 1.06), 32.0)

# --------------------------------------------------------------------- move
func _move(dt: float) -> void:
	var aim := _route(_goal, dt)
	var to := Vector2(aim.x - position.x, aim.z - position.z)
	var f := forward()
	if _want > 0.05 and to.length() > 0.2:
		var desired := to.normalized()
		# round water and cliffs: the straight way if it is clear, else the nearest clear
		# heading, keeping to one side so it follows a shore instead of dithering
		var look := 3.0 + speed * 0.7
		if not _clear(desired, look):
			var found := false
			for k in range(1, 11):
				for sgn in [_side, -_side]:
					var dd := desired.rotated(0.3 * k * sgn)
					if _clear(dd, look):
						desired = dd
						_side = sgn
						found = true
						break
				if found:
					break
		if G.flora:
			desired += G.flora.avoid_vector(position + f * (0.7 + speed * 0.2), 1.2) * 1.6
		var st: Structures = G.world.structures if G.world else null
		if st:
			desired += st.avoid_vector(position + f * (0.7 + speed * 0.2), 2.0) * 2.0
		var r := Vector2(position.x, position.z).length()
		if r > 398.0:
			desired += -Vector2(position.x, position.z).normalized() * ((r - 398.0) / 8.0)
		var want := atan2(-desired.x, -desired.y)
		var diff := wrapf(want - heading, -PI, PI)
		heading += clampf(diff, -_turn * dt, _turn * dt)
		if absf(diff) > 1.2:
			_want = minf(_want, 2.5)
	elif state in [S.BAY, S.GUARD] and target and is_instance_valid(target):
		# standing: face the moose
		var tm := target.global_position - global_position
		var diff := wrapf(atan2(-tm.x, -tm.z) - heading, -PI, PI)
		heading += clampf(diff, -3.0 * dt, 3.0 * dt)
	elif state == S.HEEL:
		var diff := wrapf(G.player.yaw - heading, -PI, PI)
		heading += clampf(diff, -1.5 * dt, 1.5 * dt)
	speed = move_toward(speed, _want, (10.0 if _want > speed else 14.0) * dt)
	if speed > 0.01:
		var np := position + forward() * speed * dt
		var h: float = G.terrain.height(np.x, np.z)
		if h < -0.55:
			speed = 0.0
		else:
			position = Vector3(np.x, h, np.z)
	else:
		position.y = G.terrain.height(position.x, position.z)

# -------------------------------------------------------------------- route
static func _build_nav() -> AStarGrid2D:
	var t: TerrainData = G.terrain
	var n := int(NAV_HALF * 2.0 / NAV_CELL)
	var g := AStarGrid2D.new()
	g.region = Rect2i(0, 0, n, n)
	g.cell_size = Vector2(1, 1)
	g.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	g.update()
	for y in n:
		for x in n:
			var wx := -NAV_HALF + (x + 0.5) * NAV_CELL
			var wz := -NAV_HALF + (y + 0.5) * NAV_CELL
			if Vector2(wx, wz).length() > 398.0 or t.height(wx, wz) < -0.3 or t.slope(wx, wz) > 0.6:
				g.set_point_solid(Vector2i(x, y), true)
	return g

static func _cell(p: Vector3) -> Vector2i:
	var n := int(NAV_HALF * 2.0 / NAV_CELL)
	return Vector2i(clampi(int((p.x + NAV_HALF) / NAV_CELL), 0, n - 1), clampi(int((p.z + NAV_HALF) / NAV_CELL), 0, n - 1))

## Where to head for on the way to `goal`: the goal itself when the straight line is dry
## land, else the next corner of a route round the water.
func _route(goal: Vector3, dt: float) -> Vector3:
	if _nav == null or state == S.HEEL:
		return goal
	_path_t -= dt
	if _path_t <= 0.0 or goal.distance_to(_path_goal) > 10.0:
		_path_t = 2.0
		_path_goal = goal
		_path = PackedVector2Array()
		_path_i = 0
		if not _straight_clear(goal):
			var ids := _nav.get_id_path(_cell(position), _cell(goal), true)
			for id in ids:
				_path.append(Vector2(-NAV_HALF + (id.x + 0.5) * NAV_CELL, -NAV_HALF + (id.y + 0.5) * NAV_CELL))
	if _path.is_empty():
		return goal
	while _path_i < _path.size() - 1 and Vector2(position.x, position.z).distance_to(_path[_path_i]) < 4.0:
		_path_i += 1
	# cut corners: aim at the furthest point of the route it can run to straight
	# (a few times a second; each look costs a row of height samples)
	_cut_t -= dt
	if _cut_t <= 0.0:
		_cut_t = 0.3
		for j in range(mini(_path_i + 10, _path.size() - 1), _path_i, -1):
			if _straight_clear(Vector3(_path[j].x, 0.0, _path[j].y)):
				_path_i = j
				break
	return Vector3(_path[_path_i].x, 0.0, _path[_path_i].y)

## Dry, gentle ground all the way from here to `p` in a straight line?
func _straight_clear(p: Vector3) -> bool:
	var a := Vector2(position.x, position.z)
	var b := Vector2(p.x, p.z)
	var n := int(a.distance_to(b) / 3.0) + 1
	for i in range(1, n + 1):
		var q := a.lerp(b, float(i) / n)
		if G.terrain.height(q.x, q.y) < -0.35 or G.terrain.slope(q.x, q.y) > 0.6:
			return false
	return true

## Dry, not too steep ground along `dir` for `look` metres?
func _clear(dir: Vector2, look: float) -> bool:
	for k in [0.4, 1.0]:
		var p: Vector3 = position + Vector3(dir.x, 0.0, dir.y) * look * float(k)
		if G.terrain.height(p.x, p.z) < -0.35 or G.terrain.slope(p.x, p.z) > 0.6:
			return false
		if Vector2(p.x, p.z).length() > 400.0:
			return false
	return true

func _flat_dist(p: Vector3) -> float:
	return Vector2(p.x - position.x, p.z - position.z).length()

func _angle_from(c: Vector3) -> float:
	return atan2(position.z - c.z, position.x - c.x)

## "240 m NE" from the hunter, as the collar's GPS shows it.
func _gps_text() -> String:
	var d: Vector3 = global_position - G.player.global_position
	var bearing := fposmod(rad_to_deg(atan2(d.x, -d.z)), 360.0)
	return "%d m %s" % [int(round(Vector2(d.x, d.z).length() / 10.0) * 10.0), Hud.POINTS[int(round(bearing / 45.0)) % 8]]

# ------------------------------------------------------------------ animate
func _animate(dt: float) -> void:
	var t: TerrainData = G.terrain
	var f := forward()
	var hf := t.height(position.x + f.x * 0.25, position.z + f.z * 0.25)
	var hr := t.height(position.x - f.x * 0.25, position.z - f.z * 0.25)
	_pitch = lerpf(_pitch, atan2(hf - hr, 0.5), 1.0 - exp(-8.0 * dt))
	rotation = Vector3(_pitch, heading, 0.0)

	var trot := smoothstep(1.3, 2.6, speed)
	var run := smoothstep(4.6, 6.4, speed)
	var amp := clampf(speed / 0.8, 0.0, 1.0)
	var stride := lerpf(lerpf(0.62, 1.35, trot), 2.5, run)
	_phase = fposmod(_phase + speed * dt / stride, 1.0)
	var a_up := lerpf(lerpf(17.0, 27.0, trot), 44.0, run) * amp
	var a_knee := lerpf(lerpf(32.0, 52.0, trot), 74.0, run) * amp
	# walk: lateral sequence; trot: diagonal pairs; gallop: the hind pair then the fore pair
	var walk := [0.25, 0.75, 0.0, 0.5]                # FL, FR, HL, HR
	var trot_o := [0.0, 0.5, 0.5, 0.0]
	var gallop := [0.58, 0.48, 0.0, 0.1]
	var sit := smoothstep(0.0, 1.0, _sit)
	for leg in 4:
		var o: float = lerpf(lerpf(walk[leg], trot_o[leg], trot), gallop[leg], run)
		var ph := fposmod(_phase + o, 1.0)
		var sw := sin(ph * TAU)
		var lift := maxf(cos(ph * TAU), 0.0)
		var up_a := sw * a_up
		var fl := lift * a_knee
		if leg < 2:
			var ub := B.FL_U if leg == 0 else B.FR_U
			var lb := B.FL_L if leg == 0 else B.FR_L
			# (sitting, the forelegs stay upright under the raised chest)
			_rx(ub, up_a + fl * 0.2 - SIT_TILT * sit)
			_rx(lb, -fl)
		else:
			var tb := B.HL_T if leg == 2 else B.HR_T
			var sb := B.HL_S if leg == 2 else B.HR_S
			var cb := B.HL_C if leg == 2 else B.HR_C
			# sitting: thigh forward, shank down to the ground, the hind foot flat
			_rx(tb, up_a * 0.85 + fl * 0.35 + 48.0 * sit)
			_rx(sb, -fl * 0.8 - 44.0 * sit)
			_rx(cb, fl * 0.9 + 45.0 * sit)
	# sitting: the body tips back about the shoulders, the rump down on the ground
	var pivot := DogModel.rest(B.FL_U) * Vector3(0, 1, 1)
	var rq := Quaternion(Vector3.RIGHT, deg_to_rad(SIT_TILT * sit))
	skel.set_bone_pose_rotation(B.ROOT, rq)
	skel.set_bone_pose_position(B.ROOT, pivot - rq * pivot)
	# the back flexes in the gallop, the body bobs
	var bob := absf(sin(_phase * TAU * 2.0)) * 0.012 * amp * (1.0 - run) + (sin(_phase * TAU) * 0.5 + 0.5) * 0.03 * run
	skel.set_bone_pose_position(B.HIPS, DogModel.rest(B.HIPS) + Vector3(0, -bob, 0))
	_rx(B.HIPS, sin(_phase * TAU + 0.5) * 9.0 * run)
	_rx(B.CHEST, -sin(_phase * TAU + 0.2) * 7.0 * run)
	# head and neck
	var k := 1.0 - exp(-5.0 * dt)
	var nt := _neck_t - 22.0 * sit
	if run > 0.3 and state != S.TRAIL:
		nt = minf(nt, -2.0)
	_neck = lerpf(_neck, nt, k)
	_head = lerpf(_head, _head_t, k)
	_look = lerpf(_look, _look_t, k)
	var jerk := _jaw * 7.0
	var nod := sin(_phase * TAU * 2.0) * 3.0 * amp
	skel.set_bone_pose_rotation(B.NECK, Quaternion.from_euler(Vector3(deg_to_rad(_neck + nod + jerk), deg_to_rad(_look * 0.5), 0)))
	skel.set_bone_pose_rotation(B.HEAD, Quaternion.from_euler(Vector3(deg_to_rad(_head - nod * 0.5 + jerk * 0.6), deg_to_rad(_look * 0.5), 0)))
	_rx(B.JAW, -26.0 * smoothstep(0.0, 0.5, _jaw))
	# the curled tail wags when the dog is pleased or excited
	var wag_amp := 0.0
	match state:
		S.HEEL, S.RETURN:
			wag_amp = 6.0
		S.BAY, S.GUARD, S.FOLLOW:
			wag_amp = 14.0
		_:
			wag_amp = 9.0
	_wag_t += dt * (9.0 if wag_amp > 10.0 else 5.0)
	_wag = lerpf(_wag, sin(_wag_t) * wag_amp, 1.0 - exp(-10.0 * dt))
	skel.set_bone_pose_rotation(B.TAIL, Quaternion(Vector3.UP, deg_to_rad(_wag)) * Quaternion(Vector3.FORWARD, deg_to_rad(_wag * 0.4)))

func _rx(bone: int, degrees: float) -> void:
	skel.set_bone_pose_rotation(bone, Quaternion(Vector3.RIGHT, deg_to_rad(degrees)))
