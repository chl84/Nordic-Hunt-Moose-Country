class_name WeaponRig
extends Node3D
## First-person rifle: aiming, firing, recoil, cycling and reload animation.
## Lives under the player's camera.

signal weapon_changed(id: String)

const V0 := Vector3.ZERO

var player: Player
var id := ""
var stats := {}
var model := {}
var root: Node3D
var parts := {}
var rest := {}
var loaded := {}            ## weapon id -> rounds in the gun
var state := "idle"         ## idle | cycle | reload | reload_in | reload_loop | reload_out | lower | raise
var ads := 0.0
var zoom_index := 0
var zero_angle := 0.0
var holdovers: Array = []   ## [[distance, angle_rad], ...] below the crosshair
var scope_shift := Vector2.ZERO   ## read by the scope overlay while cycling/recoiling
var scope_roll := 0.0
var flash_amount := 0.0
var enabled := true
var lowered_by_player := false

var _anim := {}
var _anim_t := 0.0
var _anim_len := 1.0
var _anim_ev := 0
var _pending_id := ""
var _lower := 0.0
var _reload_pose := 0.0
var _kick_pos := V0
var _kick_pos_v := V0
var _kick_rot := V0
var _kick_rot_v := V0
var _lag := Vector2.ZERO
var _lag_v := Vector2.ZERO
var _bob := 0.0
var _grab_r := 0.0
var _grab_r_t := 0.0
var _grab_l := 0.0
var _grab_l_t := 0.0
var _flash: MeshInstance3D
var _flash_light: OmniLight3D
var _flash_t := 0.0
var _fire_cool := 0.0
var _idle_t := 0.0
var _queued_reload := false
var _models := {}           ## id -> built model (kept, so switching never hitches)

func setup(p_player: Player) -> void:
	player = p_player
	_flash = MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(0.34, 0.34)
	_flash.mesh = qm
	var fm := StandardMaterial3D.new()
	fm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	fm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	fm.albedo_texture = WorldUtil.flash_texture(128, 5, 3)
	fm.albedo_color = Color(1.0, 0.85, 0.6, 1.0)
	fm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	fm.billboard_keep_scale = true
	fm.use_fov_override = true
	fm.fov_override = WeaponModels.VIEW_FOV
	fm.no_depth_test = true
	fm.cull_mode = BaseMaterial3D.CULL_DISABLED
	_flash.material_override = fm
	_flash.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_flash.visible = false
	add_child(_flash)
	_flash_light = OmniLight3D.new()
	_flash_light.light_color = Color(1.0, 0.72, 0.4)
	_flash_light.omni_range = 11.0
	_flash_light.light_energy = 0.0
	_flash_light.shadow_enabled = false
	add_child(_flash_light)

func rounds() -> int:
	return int(loaded.get(id, 0))

func mag_size() -> int:
	return int(stats.get("mag", 0))

func is_scope() -> bool:
	return stats.get("sight", "") == "scope"

func scoped() -> bool:
	return is_scope() and ads > 0.93

func zoom() -> float:
	var zs: Array = stats.get("zooms", [1.0])
	return float(zs[clampi(zoom_index, 0, zs.size() - 1)])

func busy() -> bool:
	return state != "idle"

# ------------------------------------------------------------------ equip
func equip(new_id: String, instant := false) -> void:
	if new_id == id and root != null:
		return
	if instant or root == null:
		_swap(new_id)
		_lower = 1.0
		state = "raise"
	elif state == "idle" or state == "reload_loop":
		_pending_id = new_id
		_stop_anim()
		state = "lower"

## Build (once) the models of these rifles so the first switch is instant.
func preload_models(ids: Array) -> void:
	for wid in ids:
		_model_for(wid)

func _model_for(wid: String) -> Dictionary:
	if not _models.has(wid):
		var m: Dictionary = WeaponModels.build(wid)
		var r: Node3D = m["root"]
		r.visible = false
		add_child(r)
		var rests := {}
		var nodes := {}
		for part_name in ["bolt", "mag", "lever", "barrels", "round", "hand_l", "hand_r", "muzzle", "eject", "knob"]:
			var n := r.find_child(part_name, true, false)
			if n:
				nodes[part_name] = n
				rests[part_name] = (n as Node3D).transform
		m["parts"] = nodes
		m["rest"] = rests
		_models[wid] = m
	return _models[wid]

func _swap(new_id: String) -> void:
	if root:
		root.visible = false
		for part_name in parts:
			(parts[part_name] as Node3D).transform = rest[part_name]
		if parts.has("round"):
			parts["round"].visible = false
	id = new_id
	stats = WeaponDB.get_weapon(id)
	model = _model_for(id)
	root = model["root"]
	parts = model["parts"]
	rest = model["rest"]
	if not loaded.has(id):
		loaded[id] = int(stats["mag"])
	zoom_index = 0
	zero_angle = Ballistics.zero_angle(stats["velocity"], stats["drag"], stats["zero"])
	holdovers.clear()
	var zero: float = stats["zero"]
	for d in [100.0, 200.0, 300.0, 400.0, 500.0]:
		if d > zero + 1.0:
			var drop := Ballistics.drop_at(stats["velocity"], stats["drag"], zero_angle, d)
			holdovers.append([d, atan2(-drop, d)])
	_grab_r = 0.0
	_grab_l = 0.0
	_grab_r_t = 0.0
	_grab_l_t = 0.0
	_reload_pose = 0.0
	weapon_changed.emit(id)

# -------------------------------------------------------------- animation
func _play(anim: Dictionary, length: float) -> void:
	_anim = anim
	_anim_t = 0.0
	_anim_len = maxf(length, 0.05)
	_anim_ev = 0

func _stop_anim() -> void:
	_anim = {}
	_grab_r_t = 0.0
	_grab_l_t = 0.0
	if parts.has("round"):
		parts["round"].visible = false

static func _sample(keys: Array, t: float) -> Array:
	if t <= keys[0][0]:
		return [keys[0][1], keys[0][2]]
	for i in keys.size() - 1:
		var a: Array = keys[i]
		var b: Array = keys[i + 1]
		if t <= b[0]:
			var k := smoothstep(0.0, 1.0, (t - a[0]) / maxf(b[0] - a[0], 0.0001))
			return [(a[1] as Vector3).lerp(b[1], k), (a[2] as Vector3).lerp(b[2], k)]
	return [keys[-1][1], keys[-1][2]]

func _anim_cycle() -> Dictionary:
	match stats["type"]:
		"bolt":
			return {
				"bolt": [[0.10, V0, V0], [0.24, V0, Vector3(0, 0, 62)], [0.43, Vector3(0, 0, 0.088), Vector3(0, 0, 62)],
						[0.52, Vector3(0, 0, 0.088), Vector3(0, 0, 62)], [0.70, V0, Vector3(0, 0, 62)], [0.84, V0, V0]],
				"rig": [[0.0, V0, V0], [0.18, Vector3(0.004, -0.01, 0.012), Vector3(2.5, -2, -8)],
						[0.45, Vector3(0.008, -0.016, 0.03), Vector3(4, -3.5, -13)],
						[0.72, Vector3(0.004, -0.008, 0.006), Vector3(1.5, -2, -7)], [1.0, V0, V0]],
				"events": [[0.05, "grab_r:1"], [0.11, "s:bolt_up"], [0.27, "s:bolt_back"], [0.36, "eject"],
						[0.54, "s:bolt_fwd"], [0.73, "s:bolt_down"], [0.86, "grab_r:0"]],
			}
		"lever":
			return {
				"lever": [[0.06, V0, V0], [0.40, V0, Vector3(52, 0, 0)], [0.50, V0, Vector3(52, 0, 0)], [0.88, V0, V0]],
				"rig": [[0.0, V0, V0], [0.3, Vector3(0, -0.012, 0.01), Vector3(3, 0, -5)],
						[0.6, Vector3(0, -0.008, 0.012), Vector3(-2, 0, -3)], [1.0, V0, V0]],
				"events": [[0.08, "s:lever_open"], [0.34, "eject"], [0.55, "s:lever_close"]],
			}
		"semi":
			return {
				"bolt": [[0.0, V0, V0], [0.35, Vector3(0, 0, 0.06), V0], [1.0, V0, V0]],
				"events": [[0.25, "eject"]],
			}
	return {}

func _anim_reload() -> Dictionary:
	match stats["type"]:
		"double":
			return {
				"rig": [[0.0, V0, V0], [0.14, Vector3(-0.02, -0.03, 0.05), Vector3(10, 8, -16)],
						[0.82, Vector3(-0.02, -0.03, 0.05), Vector3(10, 8, -16)], [1.0, V0, V0]],
				"barrels": [[0.08, V0, V0], [0.2, V0, Vector3(-30, 0, 0)], [0.78, V0, Vector3(-30, 0, 0)], [0.9, V0, V0]],
				"round": [[0.3, Vector3(0.05, -0.2, 0.22), V0], [0.5, Vector3(0, 0.03, 0.1), Vector3(-24, 0, 0)],
						[0.62, Vector3(0, 0.012, 0.03), Vector3(-28, 0, 0)], [1.0, Vector3(0, 0.012, 0.03), Vector3(-28, 0, 0)]],
				"events": [[0.05, "s:rustle_1"], [0.09, "s:break_open"], [0.2, "eject2"], [0.3, "show:1"], [0.3, "grab_l:1"],
						[0.56, "s:shell_insert"], [0.61, "s:shell_insert"], [0.63, "refill"], [0.66, "show:0"],
						[0.68, "grab_l:0"], [0.84, "s:break_close"]],
			}
	var a := {
		"rig": [[0.0, V0, V0], [0.16, Vector3(-0.03, -0.035, 0.04), Vector3(16, 10, -24)],
				[0.80, Vector3(-0.03, -0.03, 0.04), Vector3(15, 9, -23)], [1.0, V0, V0]],
		"mag": [[0.20, V0, V0], [0.30, Vector3(0, -0.14, 0.01), V0], [0.36, Vector3(0.02, -0.45, 0.1), Vector3(20, 0, 0)],
				[0.54, Vector3(0.02, -0.45, 0.1), Vector3(20, 0, 0)], [0.63, Vector3(0, -0.14, 0.01), V0], [0.72, V0, V0]],
		"events": [[0.06, "s:rustle_1"], [0.14, "grab_l:1"], [0.21, "s:mag_out"], [0.70, "s:mag_in"], [0.72, "refill"],
				[0.78, "grab_l:0"], [0.9, "s:rustle_2"]],
	}
	if stats["type"] == "semi":
		a["bolt"] = [[0.82, V0, V0], [0.88, Vector3(0, 0, 0.06), V0], [0.93, V0, V0]]
		a["events"].append([0.86, "s:bolt_back"])
		a["events"].append([0.92, "s:bolt_fwd"])
		a["events"].sort_custom(func(x, y): return x[0] < y[0])
	return a

func _anim_insert() -> Dictionary:
	return {
		"round": [[0.0, Vector3(0.08, -0.22, 0.14), V0], [0.5, Vector3(0.014, 0.0, 0.0), V0],
				[0.74, Vector3(0.0, 0.0, -0.048), V0], [1.0, Vector3(0.0, 0.0, -0.05), V0]],
		"events": [[0.02, "show:1"], [0.55, "s:shell_insert"], [0.72, "ammo+"], [0.8, "show:0"]],
	}

func _event(ev: String) -> void:
	if ev.begins_with("s:"):
		Sfx.play(ev.substr(2), -7.0, randf_range(0.96, 1.05))
	elif ev == "eject":
		_eject(1)
	elif ev == "eject2":
		_eject(2)
	elif ev == "refill":
		loaded[id] = mag_size()
	elif ev == "ammo+":
		loaded[id] = mini(rounds() + 1, mag_size())
	elif ev.begins_with("grab_r:"):
		_grab_r_t = float(ev.substr(7))
	elif ev.begins_with("grab_l:"):
		_grab_l_t = float(ev.substr(7))
	elif ev.begins_with("show:"):
		if parts.has("round"):
			parts["round"].visible = ev.ends_with("1")

func _eject(count: int) -> void:
	if G.fx == null or not parts.has("eject"):
		return
	var cam := player.cam.global_transform
	for i in count:
		var pos: Vector3 = parts["eject"].global_position if not scoped() else cam.origin + cam.basis * Vector3(0.12, -0.08, -0.35)
		var vel := cam.basis.x * randf_range(1.8, 2.8) + cam.basis.y * randf_range(1.4, 2.4) + cam.basis.z * randf_range(0.2, 0.9)
		if stats["type"] == "double":
			vel = cam.basis.z * randf_range(1.2, 2.0) + cam.basis.y * randf_range(0.6, 1.4) + cam.basis.x * (float(i) - 0.5) * 0.8
		G.fx.eject_casing(pos, vel + player.vel)

# ------------------------------------------------------------------ firing
func _try_fire() -> void:
	if _fire_cool > 0.0:
		return
	if state == "reload_loop" or state == "reload_in":
		if rounds() > 0:
			_stop_anim()
			state = "reload_out"
		return
	if state != "idle":
		return
	if rounds() <= 0:
		Sfx.play("dry_fire", -4.0)
		_fire_cool = 0.3
		_queued_reload = true
		return
	loaded[id] = rounds() - 1
	var cam := player.cam.global_transform
	var spread := lerpf(1.9 + player.speed_ratio() * 2.2, 0.0, smoothstep(0.5, 1.0, ads))
	var dir := -cam.basis.z
	dir = dir.rotated(cam.basis.x, zero_angle + deg_to_rad(randf_range(-spread, spread)))
	dir = dir.rotated(cam.basis.y, deg_to_rad(randf_range(-spread, spread)))
	G.ballistics.fire(cam.origin, dir.normalized(), stats, id)
	var rec: float = stats["recoil"]
	player.add_recoil(rec * randf_range(0.9, 1.15), rec * randf_range(-0.28, 0.28))
	_kick_pos_v += Vector3(randf_range(-0.2, 0.2), randf_range(0.1, 0.4), 1.9 + rec * 0.42)
	_kick_rot_v += Vector3(rec * 34.0, randf_range(-1, 1) * rec * 7.0, randf_range(-1, 1) * rec * 12.0)
	Sfx.play(stats["sound"], -1.5, randf_range(0.97, 1.03))
	_flash_t = 0.055
	flash_amount = 1.0
	if G.fx:
		var m := muzzle_position()
		G.fx.muzzle_smoke(m, -cam.basis.z, player.vel)
	if G.herd:
		G.herd.gunshot(cam.origin)
	if G.main and G.main.has_method("on_shot"):
		G.main.on_shot()
	match stats["type"]:
		"bolt", "lever":
			state = "cycle"
			_play(_anim_cycle(), stats["cycle"])
		"semi":
			state = "cycle"
			_play(_anim_cycle(), 0.13)
			_fire_cool = stats["cycle"]
		"double":
			_fire_cool = stats["cycle"]

func muzzle_position() -> Vector3:
	if scoped() or not parts.has("muzzle"):
		var cam := player.cam.global_transform
		return cam.origin + cam.basis * Vector3(0.0, -0.06, -0.9)
	# the viewmodel is drawn with its own FOV: convert to where it appears in the world view
	var local: Vector3 = player.cam.global_transform.affine_inverse() * (parts["muzzle"] as Node3D).global_position
	var k := tan(deg_to_rad(WeaponModels.VIEW_FOV) * 0.5) / tan(deg_to_rad(player.cam.fov) * 0.5)
	local.x /= k
	local.y /= k
	return player.cam.global_transform * local

func _start_reload() -> void:
	if state != "idle" or rounds() >= mag_size():
		return
	_queued_reload = false
	if stats["type"] == "lever":
		state = "reload_in"
		_anim_t = 0.0
		Sfx.play("rustle_1", -9.0)
	else:
		state = "reload"
		_play(_anim_reload(), stats["reload"])

# ----------------------------------------------------------------- update
func _process(dt: float) -> void:
	if root == null or player == null:
		return
	var active: bool = enabled and player.controls_enabled() and not lowered_by_player
	_fire_cool = maxf(_fire_cool - dt, 0.0)
	var want_aim := false
	if active:
		if Settings.get_v("aim_toggle"):
			if Input.is_action_just_pressed("aim"):
				player.aim_latch = not player.aim_latch
			want_aim = player.aim_latch
		else:
			want_aim = Input.is_action_pressed("aim")
		if Input.is_action_just_pressed("fire"):
			_try_fire()
		elif stats["type"] == "semi" and Input.is_action_pressed("fire") and false:
			_try_fire()
		if Input.is_action_just_pressed("reload"):
			if state == "idle" and rounds() >= mag_size():
				player.message.emit("Magazine is full", 1.6)
			_start_reload()
		if _queued_reload and state == "idle" and _fire_cool <= 0.0:
			_start_reload()
	var can_aim := state in ["idle", "cycle"] and not player.sprinting and not lowered_by_player
	var target := 1.0 if (want_aim and can_aim and active) else 0.0
	ads = move_toward(ads, target, dt / float(stats["ads_time"]))

	_update_state(dt)
	_update_pose(dt)
	_update_flash(dt)

func _update_state(dt: float) -> void:
	match state:
		"cycle", "reload":
			_advance_anim(dt)
			if _anim_t >= 1.0:
				_stop_anim()
				state = "idle"
		"reload_in":
			_reload_pose = move_toward(_reload_pose, 1.0, dt / 0.28)
			if _reload_pose >= 1.0:
				state = "reload_loop"
				_grab_l_t = 1.0
				_play(_anim_insert(), stats["reload"])
		"reload_loop":
			_advance_anim(dt)
			if _anim_t >= 1.0:
				if rounds() >= mag_size():
					_stop_anim()
					state = "reload_out"
				else:
					_play(_anim_insert(), stats["reload"])
		"reload_out":
			_reload_pose = move_toward(_reload_pose, 0.0, dt / 0.26)
			if _reload_pose <= 0.0:
				state = "idle"
		"lower":
			_lower = move_toward(_lower, 1.0, dt / 0.22)
			if _lower >= 1.0:
				_swap(_pending_id)
				state = "raise"
				Sfx.play("rustle_2", -8.0)
		"raise":
			_lower = move_toward(_lower, 0.0, dt / 0.3)
			if _lower <= 0.0:
				state = "idle"

func _advance_anim(dt: float) -> void:
	if _anim.is_empty():
		_anim_t = 1.0
		return
	_anim_t += dt / _anim_len
	var evs: Array = _anim.get("events", [])
	while _anim_ev < evs.size() and evs[_anim_ev][0] <= _anim_t:
		_event(evs[_anim_ev][1])
		_anim_ev += 1

func _update_pose(dt: float) -> void:
	# animated parts
	var rig_pos := V0
	var rig_rot := V0
	for part_name in ["bolt", "mag", "lever", "barrels", "round"]:
		if not parts.has(part_name):
			continue
		var node: Node3D = parts[part_name]
		var base: Transform3D = rest[part_name]
		if _anim.has(part_name):
			var s := _sample(_anim[part_name], _anim_t)
			var r: Vector3 = s[1]
			node.transform = base * Transform3D(Basis.from_euler(Vector3(deg_to_rad(r.x), deg_to_rad(r.y), deg_to_rad(r.z))), s[0])
		else:
			node.transform = base
	if _anim.has("rig"):
		var s := _sample(_anim["rig"], _anim_t)
		rig_pos = s[0]
		rig_rot = s[1]
	# lever-action loading tilt
	if _reload_pose > 0.0:
		var k := smoothstep(0.0, 1.0, _reload_pose)
		rig_pos += Vector3(-0.045, -0.02, 0.05) * k
		rig_rot += Vector3(13, 14, 40) * k

	# recoil springs
	var sp := G.spring_v3(_kick_pos, _kick_pos_v, V0, 13.0, 0.62, dt)
	_kick_pos = sp[0]
	_kick_pos_v = sp[1]
	sp = G.spring_v3(_kick_rot, _kick_rot_v, V0, 12.0, 0.55, dt)
	_kick_rot = sp[0]
	_kick_rot_v = sp[1]
	# look lag
	var look := player.look_delta
	var lag_target := Vector2(clampf(-look.x * 0.9, -3.5, 3.5), clampf(-look.y * 0.9, -3.0, 3.0))
	var sl := G.spring(_lag.x, _lag_v.x, lag_target.x, 11.0, 0.75, dt)
	_lag.x = sl[0]
	_lag_v.x = sl[1]
	sl = G.spring(_lag.y, _lag_v.y, lag_target.y, 11.0, 0.75, dt)
	_lag.y = sl[0]
	_lag_v.y = sl[1]
	# walk bob + breathing
	_idle_t += dt
	var move := player.speed_ratio()
	_bob += dt * (5.2 + 7.5 * move) * (1.0 if player.on_ground else 0.3)
	var bob_amt := move * (1.0 - ads * 0.85)
	var bob := Vector3(sin(_bob) * 0.011, -absf(cos(_bob)) * 0.012, 0.0) * bob_amt
	bob += Vector3(sin(_idle_t * 0.9) * 0.0016, sin(_idle_t * 1.5) * 0.0022, 0.0) * (1.0 - ads * 0.7)
	bob.y += clampf(-player.vel.y * 0.006, -0.03, 0.03)

	var want_lower := 1.0 if (lowered_by_player or (player.sprinting and state == "idle")) else 0.0
	if state != "lower" and state != "raise":
		_lower = move_toward(_lower, want_lower, dt / 0.2)
	var low := smoothstep(0.0, 1.0, _lower)
	var sprint_pose := player.sprinting and not lowered_by_player and state == "idle"
	var low_pos := Vector3(-0.04, -0.06, 0.03) if sprint_pose else Vector3(0.03, -0.3, 0.12)
	var low_rot := Vector3(-8, 34, 14) if sprint_pose else Vector3(-42, 16, 6)

	var e := smoothstep(0.0, 1.0, ads)
	var hip: Vector3 = model["hip_pos"]
	var hip_r: Vector3 = model["hip_rot"]
	var ads_pos := Vector3(0.0, -float(model["sight_y"]), float(model["eye_f"]))
	var pos := hip.lerp(ads_pos, e)
	var rot := hip_r.lerp(V0, e)
	var anim_w := lerpf(1.0, 0.75, e)
	pos += rig_pos * anim_w + bob + _kick_pos * Vector3(0.01, 0.012, 0.022) * lerpf(1.0, 0.55, e) + low_pos * low
	rot += rig_rot * anim_w + Vector3(_lag.y, _lag.x, _lag.x * 0.6) * (1.0 - e * 0.6) + low_rot * low
	rot += Vector3(_kick_rot.x * 0.11, _kick_rot.y * 0.12, _kick_rot.z * 0.12) * lerpf(1.0, 0.4, e)
	root.position = pos
	root.rotation = Vector3(deg_to_rad(rot.x), deg_to_rad(rot.y), deg_to_rad(rot.z))
	root.visible = not scoped() and _lower < 0.98

	# what the scope picture does while the action is worked
	scope_shift = Vector2(rig_rot.y * 0.006 + _kick_rot.y * 0.0012, rig_rot.x * 0.007 + rig_pos.y * 0.8 + _kick_rot.x * 0.0011)
	scope_roll = deg_to_rad(rig_rot.z * 0.45 + _kick_rot.z * 0.06)

	# hands follow the parts they are working
	_grab_r = move_toward(_grab_r, _grab_r_t, dt * 9.0)
	_grab_l = move_toward(_grab_l, _grab_l_t, dt * 7.0)
	_place_hand("hand_r", "knob", _grab_r, Vector3(0.016, 0.006, 0.03))
	var l_target: String = model.get("grab_l", "")
	_place_hand("hand_l", l_target, _grab_l, Vector3(0.0, -0.045, 0.012) if l_target == "mag" else Vector3(0.012, -0.03, 0.05))

func _place_hand(hand: String, target: String, w: float, offset: Vector3) -> void:
	if not parts.has(hand):
		return
	var h: Node3D = parts[hand]
	h.transform = rest[hand]
	if w <= 0.001 or target == "" or not parts.has(target):
		return
	var parent := h.get_parent() as Node3D
	var goal: Vector3 = (parts[target] as Node3D).global_transform * offset
	var goal_local := parent.global_transform.affine_inverse() * goal
	var k := smoothstep(0.0, 1.0, w)
	h.position = (rest[hand] as Transform3D).origin.lerp(goal_local, k)

func _update_flash(dt: float) -> void:
	flash_amount = maxf(flash_amount - dt * 9.0, 0.0)
	if _flash_t > 0.0:
		_flash_t -= dt
		var m := muzzle_position()
		_flash_light.global_position = m
		_flash_light.light_energy = 5.0 * (_flash_t / 0.055)
		_flash.visible = not scoped() and parts.has("muzzle")
		if _flash.visible:
			_flash.global_position = (parts["muzzle"] as Node3D).global_position - player.cam.global_transform.basis.z * 0.06
			var s := randf_range(0.8, 1.25) * (1.0 + float(stats["recoil"]) * 0.08)
			_flash.scale = Vector3(s, s, s)
			_flash.rotation.z = randf() * TAU
	else:
		_flash.visible = false
		_flash_light.light_energy = 0.0

func cycle_zoom(step: int) -> void:
	var zs: Array = stats.get("zooms", [1.0])
	var before := zoom_index
	zoom_index = clampi(zoom_index + step, 0, zs.size() - 1)
	if zoom_index != before:
		Sfx.play("zoom_tick", -6.0)

func reset_for_hunt() -> void:
	loaded.clear()
	if id != "":
		loaded[id] = mag_size()
	state = "idle"
	_stop_anim()
	ads = 0.0
	_lower = 1.0
	state = "raise"
