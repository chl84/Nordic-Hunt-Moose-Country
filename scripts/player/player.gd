class_name Player
extends Node3D
## First-person hunter. Movement is kinematic on the terrain height field
## (no physics engine): walk, sprint, crouch, jump, wade, climb towers.

signal message(text: String, seconds: float)

const EYE_STAND := 1.72
const EYE_CROUCH := 1.08
const WALK := 3.7
const SPRINT := 6.4
const CROUCH := 1.8
const AIM := 1.9
const RADIUS := 0.38
const MAX_WADE := 1.25

var cam: Camera3D
var weapon: WeaponRig
var yaw := 0.0
var pitch := 0.0
var vel := Vector3.ZERO
var on_ground := true
var crouching := false
var sprinting := false
var aim_latch := false
var active := false
var look_delta := Vector2.ZERO
var eye := EYE_STAND
var noise := 5.0            ## metres at which a calm moose hears us
var visibility := 1.0       ## multiplier on how far a moose can spot us
var scent := 1.0            ## how much of our scent the wind carries to the animals
var binoc := false
var binoc_k := 0.0
var breath := 1.0
var holding_breath := false
var on_tower := -1
var prompt := ""
var wading := 0.0
var fatigue := 0.0

var _recoil := Vector2.ZERO
var _recoil_v := Vector2.ZERO
var _sway := Vector2.ZERO
var _sway_t := 0.0
var _shake := 0.0
var _fov_punch := 0.0
var _step := 0.0
var _bob_t := 0.0
var _exhausted := 0.0
var _tower_local := Vector2.ZERO
var _prompt_timer := 0.0
var _target := {}
var _call_cool := 0.0
var _look_accum := Vector2.ZERO
var _edge_warned := 0.0
var _climb_t := 0.0
var _climb_from := Vector3.ZERO
var _climb_to := Vector3.ZERO
var _noise_spike := 0.0

func _ready() -> void:
	cam = Camera3D.new()
	cam.near = 0.05
	cam.far = 3600.0
	cam.fov = 75.0
	add_child(cam)
	weapon = WeaponRig.new()
	weapon.name = "Weapon"
	cam.add_child(weapon)
	weapon.setup(self)

func controls_enabled() -> bool:
	return active and not get_tree().paused and _climb_t <= 0.0

func speed_ratio() -> float:
	return clampf(Vector2(vel.x, vel.z).length() / SPRINT, 0.0, 1.0)

func spawn_at(pos: Vector3, facing: float) -> void:
	global_position = pos
	yaw = facing + PI     # local -Z should look along `facing` (+Z convention of the sites)
	pitch = 0.0
	vel = Vector3.ZERO
	on_tower = -1
	crouching = false
	binoc = false
	aim_latch = false
	breath = 1.0
	fatigue = 0.0
	_recoil = Vector2.ZERO
	_recoil_v = Vector2.ZERO
	_update_camera(0.0)

func add_recoil(pitch_deg: float, yaw_deg: float) -> void:
	_recoil_v += Vector2(pitch_deg, yaw_deg) * 19.0
	pitch += deg_to_rad(pitch_deg * 0.16)
	_shake = minf(_shake + pitch_deg * 0.2, 1.6)
	_fov_punch = minf(_fov_punch + pitch_deg * 0.5, 4.0)
	_noise_spike = 2.0

func shake(amount: float) -> void:
	_shake = minf(_shake + amount, 2.0)

func _unhandled_input(event: InputEvent) -> void:
	if not controls_enabled():
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var base_fov: float = Settings.get_v("fov")
		var sens: float = float(Settings.get_v("sensitivity")) * 0.0022 * (cam.fov / base_fov)
		if weapon.scoped() or binoc:
			sens *= float(Settings.get_v("scope_sensitivity"))
		var rel: Vector2 = event.relative
		yaw -= rel.x * sens
		pitch += rel.y * sens * (1.0 if Settings.get_v("invert_y") else -1.0)
		pitch = clampf(pitch, deg_to_rad(-86.0), deg_to_rad(86.0))
		_look_accum += rel * sens * 57.3
	elif event.is_action_pressed("zoom_in"):
		if weapon.scoped():
			weapon.cycle_zoom(1)
		elif weapon.ads < 0.2:
			_cycle_weapon(-1)
	elif event.is_action_pressed("zoom_out"):
		if weapon.scoped():
			weapon.cycle_zoom(-1)
		elif weapon.ads < 0.2:
			_cycle_weapon(1)
	elif event.is_action_pressed("interact"):
		_interact()
	elif event.is_action_pressed("moose_call"):
		_use_call()
	elif event.is_action_pressed("dog"):
		if not SaveGame.owns_gear("dog"):
			_need_gear("dog")
		elif G.dog:
			G.dog.toggle()
	elif event.is_action_pressed("track_sense"):
		if G.tracks:
			# (in fresh snow every track shows from far off)
			var snowy: float = G.weather.snow if G.weather else 0.0
			var n: int = G.tracks.highlight(global_position, 60.0 * (1.0 + 0.9 * snowy), 10.0)
			message.emit("No tracks nearby" if n == 0 else "Tracks nearby", 2.0)
	else:
		for i in 5:
			if event.is_action_pressed("weapon_%d" % (i + 1)):
				_select_rifle(i)

func _owned() -> Array:
	var out := []
	for w in WeaponDB.ORDER:
		if SaveGame.owns_weapon(w):
			out.append(w)
	return out

## Number keys pick among the rifles you own, in shop order. A key with no
## rifle behind it says so instead of doing nothing.
func _select_rifle(slot: int) -> void:
	var owned := _owned()
	if slot < owned.size():
		if owned[slot] == weapon.id:
			message.emit("%s is already in your hands" % WeaponDB.DATA[owned[slot]]["name"], 2.0)
		else:
			weapon.equip(owned[slot])
			SaveGame.equip(owned[slot])
		return
	var text := "No rifle on %d - you own %d of %d." % [slot + 1, owned.size(), WeaponDB.ORDER.size()]
	for w in WeaponDB.ORDER:
		if not SaveGame.owns_weapon(w):
			text += "  The %s costs %s kr under Gear in the main menu." % [WeaponDB.DATA[w]["name"], G.fmt_int(int(WeaponDB.DATA[w]["cost"]))]
			break
	_denied(text)

func _need_gear(id: String) -> void:
	var g: Dictionary = WeaponDB.GEAR[id]
	_denied("You don't own the %s yet - %s kr under Gear in the main menu." % [g["name"], G.fmt_int(int(g["cost"]))])

func _denied(text: String) -> void:
	message.emit(text, 4.5)
	Sfx.ui("ui_back", -8.0)

func _cycle_weapon(step: int) -> void:
	var owned := _owned()
	if owned.size() < 2 or weapon.busy():
		return
	var i := owned.find(weapon.id)
	var next: String = owned[posmod(i + step, owned.size())]
	weapon.equip(next)
	SaveGame.equip(next)

# ----------------------------------------------------------------- update
func _process(dt: float) -> void:
	look_delta = _look_accum
	_look_accum = Vector2.ZERO
	if G.terrain == null or not G.terrain.ready:
		return
	if _climb_t > 0.0:
		_climb_t -= dt
		var k := 1.0 - clampf(_climb_t / 0.7, 0.0, 1.0)
		global_position = _climb_from.lerp(_climb_to, smoothstep(0.0, 1.0, k))
		_update_camera(dt)
		return
	if active and not get_tree().paused:
		_move(dt)
		_update_abilities(dt)
		_prompt_timer -= dt
		if _prompt_timer <= 0.0:
			_prompt_timer = 0.15
			_update_prompt()
	_update_camera(dt)
	if G.flora:
		G.flora.focus = cam.global_position

func _move(dt: float) -> void:
	var t: TerrainData = G.terrain
	var pos := global_position
	var inp := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	if Settings.get_v("crouch_toggle"):
		if Input.is_action_just_pressed("crouch"):
			crouching = not crouching
	else:
		crouching = Input.is_action_pressed("crouch")

	if on_tower >= 0:
		sprinting = false
		var yb := Basis(Vector3.UP, yaw - G.world.structures.tower_yaw(on_tower))
		var mv := yb * Vector3(inp.x, 0, inp.y) * 1.4 * dt
		_tower_local = Vector2(clampf(_tower_local.x + mv.x, -0.62, 0.62), clampf(_tower_local.y + mv.z, -0.62, 0.62))
		var top: Vector3 = G.world.structures.tower_top(on_tower)
		var rot := Basis(Vector3.UP, G.world.structures.tower_yaw(on_tower))
		global_position = top + rot * Vector3(_tower_local.x, 0, _tower_local.y)
		vel = Vector3.ZERO
		on_ground = true
		noise = 4.0
		visibility = 0.55
		scent = 0.3             # up in the tower the scent mostly carries over them
		eye = lerpf(eye, EYE_CROUCH + 0.25 if crouching else EYE_STAND, 1.0 - exp(-10.0 * dt))
		return

	var wish := Basis(Vector3.UP, yaw) * Vector3(inp.x, 0, inp.y)
	if wish.length() > 1.0:
		wish = wish.normalized()
	wading = clampf(-t.height(pos.x, pos.z), 0.0, 2.0) if pos.y < 0.3 else 0.0
	sprinting = Input.is_action_pressed("sprint") and inp.y < -0.5 and on_ground and weapon.ads < 0.3 and not binoc and wading < 0.5 and not weapon.busy()
	if sprinting:
		crouching = false
	var max_speed := SPRINT if sprinting else (CROUCH if crouching else WALK)
	if weapon.ads > 0.5 or binoc:
		max_speed = minf(max_speed, AIM)
	max_speed *= lerpf(1.0, 0.45, clampf(wading / 1.1, 0.0, 1.0))
	var nrm := t.normal(pos.x, pos.z)
	if wish.length_squared() > 0.001:
		var uphill := -wish.normalized().dot(Vector3(nrm.x, 0, nrm.z))
		max_speed *= 1.0 - clampf(uphill * 0.9, -0.2, 0.55)
	var hv := Vector3(vel.x, 0, vel.z)
	var accel := 11.0 if on_ground else 2.2
	hv = hv.lerp(wish * max_speed, 1.0 - exp(-accel * dt))
	vel.x = hv.x
	vel.z = hv.z
	if on_ground:
		vel.y = 0.0
		if Input.is_action_just_pressed("jump") and wading < 0.6:
			vel.y = 5.3
			on_ground = false
			crouching = false
	else:
		vel.y -= 17.0 * dt
	var next := pos + vel * dt

	# too steep to climb: slide back
	var n2 := t.normal(next.x, next.z)
	if n2.y < 0.7 and t.height(next.x, next.z) > pos.y + 0.01 and on_ground:
		next.x = pos.x + n2.x * 2.0 * dt
		next.z = pos.z + n2.z * 2.0 * dt
		vel.x *= 0.5
		vel.z *= 0.5
	# solid things
	if G.flora:
		next = G.flora.push_out(next, RADIUS)
	var st: Structures = G.world.structures if G.world else null
	if st:
		next = st.push_out(next, RADIUS)
	var ground := t.height(next.x, next.z)
	var surface := st.surface_height(next.x, next.z, ground, pos.y) if st else ground
	# deep water: turn back unless standing on the pier
	if surface <= ground and ground < -MAX_WADE and ground < t.height(pos.x, pos.z):
		next.x = pos.x
		next.z = pos.z
		ground = t.height(next.x, next.z)
		surface = ground
		vel.x = 0.0
		vel.z = 0.0
	# the valley rim
	var r := Vector2(next.x, next.z).length()
	if r > TerrainData.PLAY_RADIUS:
		var inward := -Vector2(next.x, next.z) / r
		var over := r - TerrainData.PLAY_RADIUS
		next.x += inward.x * over
		next.z += inward.y * over
		_edge_warned -= dt
		if _edge_warned <= 0.0:
			_edge_warned = 6.0
			message.emit("The mountains are too steep to cross. Turn back.", 3.0)
	if next.y <= surface or (on_ground and vel.y <= 0.0 and next.y - surface < 0.5):
		if not on_ground and vel.y < -4.5:
			Sfx.play("land", -6.0)
			_shake = minf(_shake + 0.5, 1.5)
			_noise_spike = 1.0
		next.y = surface
		vel.y = 0.0
		on_ground = true
	else:
		on_ground = false
	global_position = next
	eye = lerpf(eye, EYE_CROUCH if crouching else EYE_STAND, 1.0 - exp(-10.0 * dt))

	# footsteps
	var sp := Vector2(vel.x, vel.z).length()
	if on_ground and sp > 0.4:
		_bob_t += dt * (4.0 + sp * 1.5)
		_step += sp * dt
		var stride := 1.9 if sprinting else (0.85 if crouching else 1.05)
		if _step >= stride:
			_step = 0.0
			_footstep()
	# how loud / visible we are
	var quiet := 0.62 if SaveGame.owns_gear("boots") else 1.0
	if G.weather:
		quiet *= G.weather.step_mul()
	var target_noise := 5.0
	if sp > 0.4:
		target_noise = 60.0 if sprinting else (13.0 if crouching else 32.0)
		target_noise *= quiet
		if wading > 0.15:
			target_noise *= 1.3
	_noise_spike = maxf(_noise_spike - dt, 0.0)
	if _noise_spike > 0.0:
		target_noise = maxf(target_noise, 28.0)
	noise = lerpf(noise, target_noise, 1.0 - exp(-(6.0 if target_noise > noise else 1.5) * dt))
	visibility = (0.58 if crouching else 1.0) * (0.8 if sp < 0.3 else (1.25 if sprinting else 1.0))
	scent = 1.0 + fatigue * 0.3
	fatigue = clampf(fatigue + (dt / 9.0 if sprinting else -dt / 6.0), 0.0, 1.0)

func _footstep() -> void:
	var t: TerrainData = G.terrain
	var p := global_position
	var vol := -4.0 if sprinting else (-17.0 if crouching else -10.0)
	if SaveGame.owns_gear("boots"):
		vol -= 4.0
	if wading > 0.08:
		Sfx.play_var("step_water", 3, vol + 4.0)
	elif on_tower >= 0 or (G.world.structures.surface_height(p.x, p.z, -99.0, p.y) > -90.0):
		Sfx.play_var("step_rock", 3, vol - 2.0, 0.05)
	elif t.slope(p.x, p.z) > 0.26 or p.y > 120.0:
		Sfx.play_var("step_rock", 3, vol)
	elif G.weather and G.weather.snow > 0.3:
		Sfx.play_var("step_snow", 4, vol + 1.0)
	elif t.forest_at(p.x, p.z) > 0.4:
		Sfx.play_var("step_forest", 4, vol)
	else:
		Sfx.play_var("step_grass", 4, vol)

func _update_abilities(dt: float) -> void:
	# binoculars
	if Input.is_action_just_pressed("binoculars") and not SaveGame.owns_gear("binoculars"):
		_need_gear("binoculars")
	var want_binoc := SaveGame.owns_gear("binoculars") and Input.is_action_pressed("binoculars") and weapon.ads < 0.1 and not weapon.busy() and not sprinting
	if want_binoc != binoc:
		binoc = want_binoc
		Sfx.play("rustle_2", -10.0)
	weapon.lowered_by_player = binoc
	binoc_k = move_toward(binoc_k, 1.0 if binoc else 0.0, dt / 0.22)
	# steady breath
	var aiming := weapon.ads > 0.8 or binoc_k > 0.8
	_exhausted = maxf(_exhausted - dt, 0.0)
	var want_hold := aiming and Input.is_action_pressed("sprint") and _exhausted <= 0.0 and breath > 0.0
	if want_hold and not holding_breath:
		Sfx.play("breath_in", -8.0)
	elif holding_breath and not want_hold:
		Sfx.play("breath_out", -8.0)
	holding_breath = want_hold
	if holding_breath:
		breath -= dt / 6.0
		if breath <= 0.0:
			breath = 0.0
			_exhausted = 2.8
	else:
		breath = minf(breath + dt / 4.5, 1.0)
	_call_cool = maxf(_call_cool - dt, 0.0)
	# aim wander
	_sway_t += dt
	var amp := 0.0
	if aiming:
		amp = 0.34 * float(weapon.stats.get("sway", 1.0)) if not binoc else 0.22
		amp *= (0.6 if crouching else 1.0) * (1.0 + speed_ratio() * 3.0) * (1.0 + fatigue * 1.3)
		if on_tower >= 0:
			amp *= 0.6
		if holding_breath:
			amp *= 0.12
		elif _exhausted > 0.0:
			amp *= 2.1
		if not Settings.get_v("sway"):
			amp *= 0.3
	var st := _sway_t
	var target := Vector2(sin(st * 0.83) + 0.5 * sin(st * 2.17 + 1.3), sin(st * 1.21 + 2.0) + 0.5 * sin(st * 2.71 + 0.4)) * (amp / 1.5)
	_sway = _sway.lerp(target, 1.0 - exp(-5.0 * dt))

func _update_camera(dt: float) -> void:
	if dt > 0.0:
		var s := G.spring(_recoil.x, _recoil_v.x, 0.0, 8.5, 0.82, dt)
		_recoil.x = s[0]
		_recoil_v.x = s[1]
		s = G.spring(_recoil.y, _recoil_v.y, 0.0, 8.5, 0.82, dt)
		_recoil.y = s[0]
		_recoil_v.y = s[1]
		_shake = maxf(_shake - dt * 5.0, 0.0)
		_fov_punch = maxf(_fov_punch - dt * 22.0, 0.0)
	var bob := Vector3.ZERO
	var sp := Vector2(vel.x, vel.z).length()
	if on_ground and sp > 0.3 and weapon and weapon.ads < 0.5:
		bob = Vector3(sin(_bob_t * 0.5) * 0.018, -absf(sin(_bob_t * 0.5 + 0.4)) * 0.032, 0) * clampf(sp / WALK, 0.0, 1.4)
	cam.position = Vector3(0, eye, 0) + Basis(Vector3.UP, yaw) * bob
	var shake_r := Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * _shake * 0.006
	cam.rotation = Vector3(pitch + deg_to_rad(_recoil.x + _sway.y) + shake_r.x, yaw + deg_to_rad(_recoil.y + _sway.x) + shake_r.y, shake_r.z)
	# field of view: scope / sights / binoculars
	var base_fov: float = Settings.get_v("fov")
	var z := 1.0
	if weapon and weapon.root:
		if weapon.is_scope():
			z = lerpf(1.0, weapon.zoom(), smoothstep(0.55, 1.0, weapon.ads))
		else:
			z = lerpf(1.0, weapon.zoom(), smoothstep(0.0, 1.0, weapon.ads))
	z = lerpf(z, 8.0, smoothstep(0.3, 1.0, binoc_k))
	var fov := rad_to_deg(2.0 * atan(tan(deg_to_rad(base_fov) * 0.5) / z))
	fov += (3.0 if sprinting else 0.0) + _fov_punch * (1.0 / z)
	cam.fov = lerpf(cam.fov, fov, 1.0 - exp(-22.0 * dt)) if dt > 0.0 else fov

# ------------------------------------------------------------ interaction
func _update_prompt() -> void:
	prompt = ""
	_target = {}
	var p := global_position
	if on_tower >= 0:
		prompt = "Climb down"
		_target = {"kind": "tower_down"}
		return
	if G.herd:
		var c = G.herd.nearest_carcass(p, 3.6)
		if c != null:
			prompt = "Tag the moose"
			_target = {"kind": "tag", "moose": c}
			return
	var st: Structures = G.world.structures
	var ti := st.tower_near(p)
	if ti >= 0:
		prompt = "Climb the hunting tower"
		_target = {"kind": "tower_up", "index": ti}
		return
	if G.tracks:
		var tr: Dictionary = G.tracks.nearest(p, 2.4)
		if not tr.is_empty():
			prompt = "Examine blood trail" if tr["blood"] else "Examine tracks"
			_target = {"kind": "tracks", "info": tr}

func _interact() -> void:
	_update_prompt()
	if _target.is_empty():
		return
	match _target["kind"]:
		"tag":
			if G.main and G.main.has_method("tag_moose"):
				G.main.tag_moose(_target["moose"])
		"tower_up":
			var st: Structures = G.world.structures
			on_tower = _target["index"]
			_tower_local = Vector2(0, -0.3)
			_climb_from = global_position
			_climb_to = st.tower_top(on_tower) + Basis(Vector3.UP, st.tower_yaw(on_tower)) * Vector3(0, 0, -0.3)
			_climb_t = 0.7
			crouching = false
			vel = Vector3.ZERO
			Sfx.play("rustle_1", -6.0)
			Sfx.play_var("step_rock", 3, -8.0)
		"tower_down":
			var st: Structures = G.world.structures
			var base: Vector3 = st.towers[on_tower][0]
			var back := Basis(Vector3.UP, st.tower_yaw(on_tower)) * Vector3(0, 0, -2.6)
			var dest := base + back
			dest.y = G.terrain.height(dest.x, dest.z)
			_climb_from = global_position
			_climb_to = dest
			_climb_t = 0.7
			on_tower = -1
			vel = Vector3.ZERO
			Sfx.play("rustle_2", -6.0)
		"tracks":
			var info: Dictionary = _target["info"]
			message.emit(G.tracks.describe(info), 5.0)
			G.tracks.highlight_trail(info, 14.0)
			Sfx.ui("ui_click", -6.0)
	_prompt_timer = 0.0

func _use_call() -> void:
	if not SaveGame.owns_gear("call"):
		_need_gear("call")
		return
	if _call_cool > 0.0:
		message.emit("Let the forest settle before calling again", 2.0)
		return
	if weapon.busy() or weapon.ads > 0.2:
		return
	_call_cool = 22.0
	Sfx.play("call_blow", -2.0, randf_range(0.96, 1.04))
	var n := 0
	if G.herd:
		n = G.herd.call_from(global_position)
	message.emit("You call into the forest..." if n == 0 else "A bull answers your call", 3.5)
	if n > 0:
		Sfx.call_later(2.6, func(): Sfx.play("moose_bull", -14.0, 0.95))
