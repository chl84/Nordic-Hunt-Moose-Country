class_name Moose
extends Node3D
## One moose: wanders, grazes, notices the hunter (sees, hears and smells him), flees -
## never attacks. Stands for a baying dog. Movement is kinematic on the height field;
## animation is fully procedural.

enum State { GRAZE, WANDER, ALERT, FLEE, LURED, BAYED, DEAD }

const B := MooseModel.B

var id := 0
var kind := "bull"
var info := {}
var size := 1.0
var state := State.GRAZE
var state_t := 0.0
var heading := 0.0          ## yaw; the nose points along (-sin, -cos)
var speed := 0.0
var awareness := 0.0
var health := 100.0
var bleed := 0.0
var wounded := false
var limp := 0.0
var dead := false
var tagged := false
var hits := 0
var last_hit := {}
var kill := {}              ## filled in when it dies
var ragdoll: MooseRagdoll
var skel: Skeleton3D
var threat := Vector3.ZERO
var weight := 400.0
var winded := false         ## last alarm came from the hunter's scent
var dog_pos := Vector3.ZERO ## where the dog that holds it is
var bay_count := 0          ## times it has stood for the dog today

var _mesh: MeshInstance3D
var _target := Vector3.ZERO
var _graze_len := 10.0
var _flee_len := 8.0
var _dying_in := -1.0
var _think := 0.0
var _phase := 0.0
var _neck := 0.0
var _head := 0.0
var _look := 0.0
var _neck_t := 0.0
var _head_t := 0.0
var _look_t := 0.0
var _peek := 0.0
var _peek_next := 6.0
var _flinch := Vector2.ZERO
var _flinch_v := Vector2.ZERO
var _track_acc := 0.0
var _blood_acc := 0.0
var _hoof_acc := 0.0
var _side := 1.0
var _frame := 0
var _pending: Array = []     ## delayed alarms: [seconds, kind, position]
var _pitch := 0.0
var _lure_stop := 45.0
var _stuck := 0.0
var _bay_len := 0.0
var _dog_cool := 0.0        ## after breaking from the dog it keeps going a while
var _lunge := 0.0           ## > 0: rushing the dog
var _lunge_next := 6.0
var _rng := RandomNumberGenerator.new()

func setup(p_kind: String, p_id: int, pos: Vector3, facing: float) -> void:
	kind = p_kind
	id = p_id
	info = MooseModel.KINDS[kind]
	_rng.seed = hash(p_id * 7919 + 13)
	size = float(info["scale"]) * _rng.randf_range(0.96, 1.05)
	health = info["health"]
	var wr: Array = info["weight"]
	weight = _rng.randf_range(wr[0], wr[1])
	skel = MooseModel.make_skeleton()
	add_child(skel)
	_mesh = MeshInstance3D.new()
	_mesh.mesh = MooseModel.mesh_for(kind)
	_mesh.skin = skel.create_skin_from_rest_transforms()
	skel.add_child(_mesh)
	_mesh.skeleton = _mesh.get_path_to(skel)
	_mesh.extra_cull_margin = 3.0
	var tint := _rng.randf_range(0.82, 1.12)
	var m: ShaderMaterial = MooseModel.material().duplicate()
	m.set_shader_parameter("tint", Vector3(tint, tint * _rng.randf_range(0.94, 1.0), tint * _rng.randf_range(0.88, 1.0)))
	_mesh.material_override = m
	scale = Vector3(size, size, size)
	heading = facing
	position = Vector3(pos.x, G.terrain.height(pos.x, pos.z), pos.z)
	rotation = Vector3(0, heading, 0)
	_graze_len = _rng.randf_range(6.0, 22.0)
	_peek_next = _rng.randf_range(3.0, 10.0)
	_think = _rng.randf() * 0.25
	_neck = -55.0
	_neck_t = -55.0

func forward() -> Vector3:
	return Vector3(-sin(heading), 0, -cos(heading))

func head_pos() -> Vector3:
	return global_position + Vector3(0, 1.9 * size, 0) + forward() * 1.4 * size

func centre() -> Vector3:
	if ragdoll:
		return ragdoll.centre()
	return global_position + Vector3(0, 1.25 * size, 0)

func label() -> String:
	return info["label"]

# ------------------------------------------------------------------ think
func _set_state(s: State) -> void:
	state = s
	state_t = 0.0

func _process(dt: float) -> void:
	if dt <= 0.0:
		return
	if dead:
		if ragdoll and not ragdoll.asleep:
			ragdoll.step(minf(dt, 0.033))
			ragdoll.apply()
		return
	state_t += dt
	_dog_cool = maxf(_dog_cool - dt, 0.0)
	_update_pending(dt)
	_think -= dt
	if _think <= 0.0:
		_think = 0.2
		_sense(0.2)
	_behave(dt)
	if dead:
		return
	if wounded and _dying_in < 0.0:
		health -= bleed * dt
		if health <= 0.0:
			_die(forward() * 0.4, centre(), "bled out")
			return
	if _dying_in >= 0.0:
		_dying_in -= dt
		if _dying_in < 0.0:
			_die(forward() * 0.5, centre(), "")
			return
	_frame += 1
	var cam_d := 0.0
	if G.player:
		cam_d = global_position.distance_to(G.player.global_position)
	var skip := 1 if cam_d < 280.0 else (3 if cam_d < 600.0 else 6)
	if _frame % skip == 0:
		_animate(dt * skip)

func _update_pending(dt: float) -> void:
	var i := 0
	while i < _pending.size():
		_pending[i][0] -= dt
		if _pending[i][0] <= 0.0:
			var e: Array = _pending[i]
			_pending.remove_at(i)
			_react(e[1], e[2])
		else:
			i += 1

func alarm_later(delay: float, what: String, from: Vector3) -> void:
	_pending.append([delay, what, from])

func _react(what: String, from: Vector3) -> void:
	if dead:
		return
	threat = from
	winded = false
	match what:
		"flee":
			_start_flee(from)
		"alert":
			if state == State.ALERT and awareness > 0.75:
				_start_flee(from)
			elif state != State.FLEE:
				awareness = maxf(awareness, 0.78)
				_set_state(State.ALERT)

func _sense(dt: float) -> void:
	var pl: Player = G.player
	if pl == null or not pl.active:
		awareness = maxf(awareness - dt * 0.1, 0.0)
		return
	var to_p := pl.global_position - global_position
	var d := to_p.length()
	# the nose reaches furthest: downwind of the hunter it smells him long before it could
	# see or hear him (from a tower the scent mostly carries over the animals)
	var smell := 0.0
	if G.wind and d < 260.0:
		smell = G.wind.scent(pl.global_position + Vector3(0, 1.2, 0), head_pos()) * pl.scent
	if d > 190.0 and smell < 0.04:
		awareness = maxf(awareness - dt * 0.08, 0.0)
		return
	var alert_mul := 1.3 if state == State.ALERT else 1.0
	# held by a barking dog it hears little else and watches the dog
	var busy := state == State.BAYED
	var heard := d < pl.noise * alert_mul * (0.4 if busy else 1.0)
	var see_range := 80.0 * pl.visibility * alert_mul * (0.75 if busy else 1.0)
	if G.terrain.forest_at(pl.global_position.x, pl.global_position.z) > 0.55:
		see_range *= 0.68
	if G.sky and G.sky.is_twilight():
		see_range *= 0.8
	var facing := forward().dot(to_p / maxf(d, 0.01))
	var fov_ok := facing > (0.1 if (state == State.GRAZE and _peek <= 0.0) else -0.5)
	var seen: bool = d < see_range and fov_ok and G.terrain.line_clear(head_pos(), pl.cam.global_position)
	var gain := 0.0
	if heard or seen:
		var closeness := 1.0 - d / maxf(maxf(see_range, pl.noise * alert_mul), 1.0)
		gain = dt * (0.3 + 1.5 * clampf(closeness, 0.0, 1.0)) * (1.7 if (heard and seen) else 1.0)
	if smell > 0.04:
		gain += dt * (0.15 + 1.4 * smell)
	if gain > 0.0:
		awareness += gain
		threat = pl.global_position
		winded = smell > 0.04 and not (heard or seen)
	else:
		awareness -= dt * (0.1 if state == State.ALERT else 0.16)
	if d < 11.0:
		awareness = 1.3
		threat = pl.global_position
	awareness = clampf(awareness, 0.0, 1.3)
	match state:
		State.BAYED:
			if awareness >= 1.0:
				_start_flee(threat)
		State.GRAZE, State.WANDER, State.LURED:
			if awareness >= 1.0:
				_start_flee(threat)
			elif awareness > 0.45:
				_set_state(State.ALERT)
				if d < 130.0:
					Sfx.play_at("moose_snort", head_pos(), -4.0, _rng.randf_range(0.9, 1.1), 12.0)
		State.ALERT:
			if awareness >= 1.0:
				_start_flee(threat)
			elif awareness < 0.22 and state_t > 4.0:
				_set_state(State.WANDER)
				_pick_target(false)

func _start_flee(from: Vector3) -> void:
	if dead:
		return
	if winded and state != State.FLEE and G.herd:
		G.herd.winded_by(self)
	threat = from
	awareness = 1.2
	_flee_len = _rng.randf_range(7.0, 11.0) + (4.0 if wounded else 0.0)
	var away := global_position - from
	away.y = 0
	if away.length() < 0.5:
		away = forward()
	away = away.normalized().rotated(Vector3.UP, _rng.randf_range(-0.5, 0.5))
	_target = global_position + away * 160.0
	if state != State.FLEE:
		_set_state(State.FLEE)

func _pick_target(far: bool) -> void:
	var best := global_position
	var best_s := -INF
	for i in 6:
		var ang := _rng.randf() * TAU
		var dist := _rng.randf_range(60.0, 130.0) if far else _rng.randf_range(18.0, 70.0)
		var c := global_position + Vector3(cos(ang), 0, sin(ang)) * dist
		if Vector2(c.x, c.z).length() > 395.0:
			continue
		var h: float = G.terrain.height(c.x, c.z)
		if h < 0.5:
			continue
		var s: float = 1.0 - G.terrain.forest_at(c.x, c.z) * 0.7 - G.terrain.slope(c.x, c.z) * 3.0
		s += (0.5 if h < 4.0 else 0.0) + _rng.randf() * 0.5
		if s > best_s:
			best_s = s
			best = c
	_target = best

func lure(to: Vector3) -> bool:
	if dead or wounded or state == State.FLEE or state == State.ALERT or state == State.BAYED:
		return false
	_target = to
	_lure_stop = _rng.randf_range(28.0, 55.0)
	_set_state(State.LURED)
	return true

# -------------------------------------------------------------------- dog
## The dog has come up to it. Most bulls stand and face a baying dog, cows and young
## ones as often run; a wounded or tired animal stands more readily, one that already
## knows the hunter is near less. Returns true if it stands (BAYED).
func meet_dog(from: Vector3) -> bool:
	if dead:
		return false
	dog_pos = from
	if state == State.BAYED:
		return true
	if _dog_cool > 0.0 or state == State.FLEE:
		return false
	var p: float = {"cow": 0.5, "young": 0.45, "bull": 0.68, "trophy": 0.74}[kind]
	if wounded:
		p = 0.88
	p += 0.12 * bay_count - 0.35 * clampf(awareness - 0.45, 0.0, 0.8)
	if _rng.randf() < p:
		bay_count += 1
		_bay_len = _rng.randf_range(80.0, 170.0)
		_lunge_next = _rng.randf_range(4.0, 10.0)
		_lunge = 0.0
		awareness = minf(awareness, 0.6)
		_set_state(State.BAYED)
		Sfx.play_at("moose_snort", head_pos(), -2.0, _rng.randf_range(0.85, 1.0), 14.0)
		return true
	winded = false
	_start_flee(from)
	_flee_len = _rng.randf_range(6.0, 11.0)
	return false

## Where the baying dog is now (called by the dog while it holds the animal).
func dog_near(from: Vector3) -> void:
	dog_pos = from

## The dog was called off: the animal stays wary a while, then settles.
func dog_left() -> void:
	if state == State.BAYED:
		threat = dog_pos
		awareness = 0.6
		_set_state(State.ALERT)

func is_bayed() -> bool:
	return state == State.BAYED

func is_lunging() -> bool:
	return state == State.BAYED and _lunge > 0.0

# ----------------------------------------------------------------- behave
func _behave(dt: float) -> void:
	var want_speed := 0.0
	var turn_rate := 1.3
	var steer := false
	match state:
		State.GRAZE:
			_peek_next -= dt
			if _peek_next <= 0.0:
				_peek = _rng.randf_range(1.4, 3.2)
				_peek_next = _peek + _rng.randf_range(5.0, 13.0)
				_look_t = _rng.randf_range(-55.0, 55.0)
			_peek = maxf(_peek - dt, 0.0)
			if _peek > 0.0:
				_neck_t = 14.0
				_head_t = -20.0
			else:
				_neck_t = -46.0 + sin(state_t * 2.3) * 3.0
				_head_t = 6.0 + sin(state_t * 5.0) * 4.0
				_look_t = sin(state_t * 0.4 + id) * 12.0
			if state_t > _graze_len:
				_graze_len = _rng.randf_range(7.0, 24.0)
				_pick_target(_rng.randf() < 0.2)
				_set_state(State.WANDER)
		State.WANDER, State.LURED:
			want_speed = (1.25 if state == State.WANDER else 1.7) * (1.0 - limp * 0.4)
			steer = true
			_neck_t = -6.0 + sin(_phase * TAU * 2.0) * 3.0
			_head_t = -12.0
			_look_t = sin(state_t * 0.5 + id) * 14.0
			var dist := Vector2(_target.x - position.x, _target.z - position.z).length()
			var stop := _lure_stop if state == State.LURED else 3.5
			if dist < stop or state_t > 70.0:
				if state == State.LURED:
					_peek = 6.0
					_peek_next = 8.0
				_set_state(State.GRAZE)
		State.ALERT:
			_neck_t = 22.0
			_head_t = -22.0
			var to_t := threat - global_position
			var rel := wrapf(atan2(-to_t.x, -to_t.z) - heading, -PI, PI)
			_look_t = clampf(rad_to_deg(rel), -80.0, 80.0)
			if absf(rel) > 1.3:
				heading += signf(rel) * 0.7 * dt
		State.BAYED:
			# head to the dog, ears forward, now and then a rush at it; after a while it
			# has had enough and walks off (the dog follows, and it may stand again)
			var to_d := dog_pos - global_position
			var rel := wrapf(atan2(-to_d.x, -to_d.z) - heading, -PI, PI)
			heading += clampf(rel, -1.5 * dt, 1.5 * dt)
			_neck_t = 6.0
			_head_t = -12.0
			_look_t = clampf(rad_to_deg(rel), -60.0, 60.0)
			_lunge_next -= dt
			if _lunge > 0.0:
				_lunge -= dt
				want_speed = 3.4
				_neck_t = -10.0
				_head_t = -4.0
			elif _lunge_next <= 0.0:
				_lunge_next = _rng.randf_range(6.0, 15.0)
				if absf(rel) < 0.5 and Vector2(to_d.x, to_d.z).length() < 22.0:
					_lunge = _rng.randf_range(0.6, 1.1)
			if state_t > _bay_len:
				# walks off, away from the dog
				_dog_cool = _rng.randf_range(22.0, 45.0)
				var away := global_position - dog_pos
				away.y = 0.0
				away = (away.normalized() if away.length() > 0.5 else -forward()).rotated(Vector3.UP, _rng.randf_range(-0.6, 0.6))
				_target = global_position + away * 90.0
				_set_state(State.WANDER)
		State.FLEE:
			steer = true
			turn_rate = 2.4
			var run: float = float(info["speed"]) * (1.0 - limp * 0.45) * (0.72 if wounded else 1.0)
			if state_t < _flee_len:
				want_speed = run
			elif state_t < _flee_len + 5.0:
				want_speed = 4.2 * (1.0 - limp * 0.4)
			else:
				awareness = 0.7
				if wounded:
					_pick_target(true)
					_set_state(State.WANDER)
				else:
					_set_state(State.ALERT)
			_neck_t = -4.0
			_head_t = -2.0
			_look_t = 0.0
	if steer:
		_steer(dt, turn_rate, want_speed)
	speed = move_toward(speed, want_speed, (9.0 if want_speed > speed else 5.0) * dt)
	if speed > 0.01:
		var f := forward()
		var np := position + f * speed * dt
		var h: float = G.terrain.height(np.x, np.z)
		if h < -1.0 and h < G.terrain.height(position.x, position.z):
			speed *= 0.5
			_target = position - f * 60.0     # deep water ahead: turn round
			_stuck += dt
		else:
			position = Vector3(np.x, h, np.z)
			_stuck = maxf(_stuck - dt, 0.0)
		_leave_marks(speed * dt)
	else:
		position.y = G.terrain.height(position.x, position.z)

func _steer(dt: float, turn_rate: float, want_speed: float) -> void:
	var to := Vector2(_target.x - position.x, _target.z - position.z)
	var desired := to.normalized() if to.length() > 0.1 else Vector2(-sin(heading), -cos(heading))
	var f := forward()
	if G.flora:
		desired += G.flora.avoid_vector(position + f * (1.5 + speed * 0.25), 2.4) * 1.6
	var st: Structures = G.world.structures if G.world else null
	if st:
		desired += st.avoid_vector(position + f * (1.5 + speed * 0.25), 3.0) * 2.0
	# keep out of lakes and off cliffs
	var look := 5.0 + speed * 1.2
	var ahead := position + Vector3(desired.x, 0, desired.y).normalized() * look
	var ha: float = G.terrain.height(ahead.x, ahead.z)
	if ha < -0.6 or G.terrain.slope(ahead.x, ahead.z) > 0.42:
		var n: Vector3 = G.terrain.normal(ahead.x, ahead.z)
		var side := Vector2(-desired.y, desired.x)
		var uphill := -Vector2(n.x, n.z)
		var pushv := uphill if ha < -0.6 else -uphill
		desired = (desired * 0.3 + pushv * 1.5 + side * (0.8 * _side)).normalized()
		if state == State.FLEE:
			_target = position + Vector3(desired.x, 0, desired.y) * 140.0
	var r := Vector2(position.x, position.z).length()
	if r > 395.0:
		desired += -Vector2(position.x, position.z).normalized() * ((r - 395.0) / 12.0)
		if state == State.FLEE and r > 410.0:
			_target = Vector3.ZERO
	var want := atan2(-desired.x, -desired.y)
	var diff := wrapf(want - heading, -PI, PI)
	heading += clampf(diff, -turn_rate * dt, turn_rate * dt)
	if want_speed > 5.0 and absf(diff) > 1.6:
		speed = minf(speed, 4.0)

func _leave_marks(step: float) -> void:
	if G.tracks == null:
		return
	_track_acc += step
	if _track_acc > 2.3:
		_track_acc = 0.0
		_side = -_side
		var f := forward()
		var right := Vector3(f.z, 0, -f.x)
		G.tracks.add_print(position + right * (0.1 * _side), Vector2(f.x, f.z), id, label())
	if wounded:
		_blood_acc += step
		if _blood_acc > clampf(5.5 - bleed * 0.6, 1.2, 4.5):
			_blood_acc = 0.0
			var off := Vector3(_rng.randf_range(-0.4, 0.4), 0, _rng.randf_range(-0.4, 0.4))
			G.tracks.add_blood(position + off, _rng.randf_range(0.5, 1.2), id, label())
	if speed > 5.0:
		_hoof_acc += step
		if _hoof_acc > 1.9:
			_hoof_acc = 0.0
			if G.player and position.distance_to(G.player.global_position) < 110.0:
				Sfx.play_var_at("hoof", 3, position, -3.0, 9.0, 0.12)

# ---------------------------------------------------------------- animate
func _animate(dt: float) -> void:
	var t: TerrainData = G.terrain
	var f := forward()
	# follow the slope
	var reach := 0.85 * size
	var hf := t.height(position.x + f.x * reach, position.z + f.z * reach)
	var hr := t.height(position.x - f.x * reach, position.z - f.z * reach)
	_pitch = lerpf(_pitch, atan2(hf - hr, reach * 2.0), 1.0 - exp(-6.0 * dt))
	var sp := G.spring(_flinch.x, _flinch_v.x, 0.0, 9.0, 0.45, dt)
	_flinch.x = sp[0]
	_flinch_v.x = sp[1]
	sp = G.spring(_flinch.y, _flinch_v.y, 0.0, 9.0, 0.45, dt)
	_flinch.y = sp[0]
	_flinch_v.y = sp[1]
	rotation = Vector3(_pitch + deg_to_rad(_flinch.x), heading, deg_to_rad(_flinch.y))

	var run := smoothstep(2.6, 7.0, speed)
	var amp := clampf(speed / 1.1, 0.0, 1.0)
	var stride := lerpf(1.9, 3.4, run) * size
	_phase = fposmod(_phase + speed * dt / stride, 1.0)
	var a_up := lerpf(19.0, 36.0, run) * amp
	var a_knee := lerpf(30.0, 62.0, run) * amp
	# walk: lateral sequence; run: diagonal pairs (a big ground-covering trot)
	var offs := [0.25, 0.75, 0.0, 0.5]                    # FL, FR, HL, HR
	var offs_run := [0.5, 0.0, 0.03, 0.53]
	var lame := limp * 0.6
	for leg in 4:
		var ph := fposmod(_phase + lerpf(offs[leg], offs_run[leg], run), 1.0)
		var sw := sin(ph * TAU)
		var lift := maxf(cos(ph * TAU), 0.0)
		var up_a := sw * a_up
		var fl := lift * a_knee
		# standing, the legs are not set side by side: one foreleg a little forward, the
		# other hind leg back, so all four read from the side
		up_a += [-8.0, 5.0, 1.5, -1.5][leg] * (1.0 - amp)
		if leg == 0:
			_rx(B.FL_U, up_a + fl * 0.25)
			_rx(B.FL_L, -fl * (1.0 + lame))
		elif leg == 1:
			_rx(B.FR_U, up_a + fl * 0.25)
			_rx(B.FR_L, -fl)
		elif leg == 2:
			_rx(B.HL_T, up_a * 0.85 + fl * 0.35)
			_rx(B.HL_S, -fl * 0.75)
			_rx(B.HL_C, fl * 0.95)
		else:
			_rx(B.HR_T, up_a * 0.85 + fl * 0.35)
			_rx(B.HR_S, -fl * 0.75)
			_rx(B.HR_C, fl * 0.95 * (1.0 - lame))
	# body bob + spine flex
	var bob := absf(sin(_phase * TAU * 2.0)) * (0.035 + 0.05 * run) * amp
	skel.set_bone_pose_position(B.HIPS, MooseModel.rest(B.HIPS) + Vector3(0, -bob, 0))
	var graze_k := clampf(-_neck / 46.0, 0.0, 1.0)
	_rx(B.HIPS, sin(_phase * TAU * 2.0 + 0.6) * 2.0 * run)
	_rx(B.CHEST, -sin(_phase * TAU * 2.0) * 3.0 * run - graze_k * 5.0)
	# grazing from the ground, a moose spreads its long forelegs to get its head down
	var splay := graze_k * (1.0 - amp)
	if splay > 0.01:
		for fb in [[B.FL_U, -1.0], [B.FR_U, 1.0]]:
			var q := skel.get_bone_pose_rotation(fb[0])
			skel.set_bone_pose_rotation(fb[0], Quaternion(Vector3.FORWARD, deg_to_rad(9.0 * float(fb[1]) * splay)) * Quaternion(Vector3.RIGHT, deg_to_rad(-7.0 * splay)) * q)
	# neck and head
	var k := 1.0 - exp(-(4.0 if state in [State.ALERT, State.FLEE, State.BAYED] else 2.2) * dt)
	_neck = lerpf(_neck, _neck_t, k)
	_head = lerpf(_head, _head_t, k)
	_look = lerpf(_look, _look_t, k)
	var nod := sin(_phase * TAU * 2.0 + 0.9) * 3.5 * amp
	skel.set_bone_pose_rotation(B.NECK, Quaternion.from_euler(Vector3(deg_to_rad(_neck + nod), deg_to_rad(_look * 0.55), 0)))
	skel.set_bone_pose_rotation(B.HEAD, Quaternion.from_euler(Vector3(deg_to_rad(_head - nod * 0.6), deg_to_rad(_look * 0.45), 0)))

func _rx(bone: int, degrees: float) -> void:
	skel.set_bone_pose_rotation(bone, Quaternion(Vector3.RIGHT, deg_to_rad(degrees)))

# ------------------------------------------------------------------- hits
## Segment vs this animal. Returns {t, zone, pos} or {}.
func ray_test(from: Vector3, to: Vector3) -> Dictionary:
	var xf := skel.global_transform
	var best_t := 2.0
	var zone := ""
	var seg := to - from
	var seg_len := seg.length()
	for s in MooseModel.SHAPES:
		var t := _capsule_t(xf, s, from, to, seg_len)
		if t >= 0.0 and t < best_t:
			best_t = t
			zone = s[0]
	if zone == "":
		return {}
	# which organ, if any, lies on the bullet's path through the body?
	var rank := 0
	for o in MooseModel.ORGANS:
		var r: int = MooseModel.ORGAN_RANK[o[0]]
		if r <= rank:
			continue
		var t := _capsule_t(xf, o, from, to, seg_len)
		if t >= 0.0 and t < best_t + 1.4 / maxf(seg_len, 0.01):
			rank = r
			zone = o[0]
	return {"t": best_t, "zone": zone, "pos": from + seg * best_t, "moose": self}

func _capsule_t(xf: Transform3D, s: Array, from: Vector3, to: Vector3, seg_len: float) -> float:
	var bone: int = s[1]
	var pose := xf * skel.get_bone_global_pose(bone)
	var ro := MooseModel.rest(bone)
	var a := pose * ((s[2] as Vector3) - ro)
	var b := pose * ((s[3] as Vector3) - ro)
	var rad: float = float(s[4]) * size
	var pts := Geometry3D.get_closest_points_between_segments(from, to, a, b)
	var d := pts[0].distance_to(pts[1])
	if d > rad:
		return -1.0
	var along := from.distance_to(pts[0]) - sqrt(maxf(rad * rad - d * d, 0.0))
	return clampf(along / maxf(seg_len, 0.0001), 0.0, 1.0)

func take_hit(zone: String, pos: Vector3, dir: Vector3, damage: float, dist: float, weapon: String, _part: int) -> void:
	if G.fx:
		G.fx.blood_hit(pos, dir, damage > 90.0 or zone in ["heart", "lungs", "brain"])
	if dead:
		if ragdoll:
			ragdoll.push(pos, dir * damage * 0.05)
		return
	var mult := 1.0
	var text := "Body shot"
	match zone:
		"brain":
			mult = 6.0
			text = "Brain shot"
		"spine":
			mult = 4.0
			text = "Spine shot"
		"heart":
			mult = 3.4
			text = "Heart shot"
		"lungs":
			mult = 2.0
			text = "Lung shot"
		"neck":
			mult = 1.5
			text = "Neck shot"
		"head":
			mult = 1.0
			text = "Jaw shot"
		"chest":
			mult = 1.05
			text = "Shoulder shot"
		"rear":
			mult = 0.7
			text = "Gut shot"
		"leg":
			mult = 0.42
			text = "Leg shot"
	hits += 1
	winded = false
	var undisturbed := state in [State.GRAZE, State.WANDER, State.LURED] and awareness < 0.5
	last_hit = {
		"zone": zone, "text": text, "dist": dist, "weapon": weapon, "moving": speed > 3.0,
		"undisturbed": undisturbed, "hits": hits,
	}
	health -= damage * mult
	_flinch_v += Vector2(-28.0, 40.0 * signf(dir.dot(Vector3(forward().z, 0, -forward().x)))) * clampf(damage * mult / 120.0, 0.3, 1.6)
	if G.tracks:
		G.tracks.add_blood(global_position, 1.3, id, label())
	if G.herd:
		G.herd.alarm(global_position, 140.0, pos - dir * dist, self)
	if health <= 0.0:
		if zone in ["heart", "lungs"] and _rng.randf() < 0.62:
			# classic death run: bolts a short way and piles up
			_dying_in = _rng.randf_range(0.5, 2.3) if zone == "heart" else _rng.randf_range(1.2, 3.4)
			wounded = true
			bleed = 0.0
			_start_flee(pos - dir * dist)
			_flee_len = 20.0
		else:
			_die(dir * clampf(damage * 0.035, 1.5, 6.0), pos, "")
		return
	wounded = true
	bleed = maxf(bleed, clampf(damage * mult * 0.05, 1.3, 7.0))
	if zone == "leg":
		limp = 1.0
	_start_flee(pos - dir * dist)

func _die(impulse: Vector3, at: Vector3, cause: String) -> void:
	if dead:
		return
	dead = true
	state = State.DEAD
	var vel := forward() * speed
	speed = 0.0
	var spread: float = [0.16, 0.3, 0.55, 0.74][int(info["antlers"])]
	ragdoll = MooseRagdoll.new()
	ragdoll.setup(skel, size, vel, at, impulse, spread)
	kill = last_hit.duplicate()
	if cause != "":
		kill["cause"] = cause
	kill["kind"] = kind
	kill["weight"] = weight
	if G.main and G.main.has_method("on_kill"):
		G.main.on_kill(self)

## Give the carcass a compact body that stays visible from far away.
func distance_to_player() -> float:
	if G.player == null:
		return 0.0
	return centre().distance_to(G.player.global_position)
