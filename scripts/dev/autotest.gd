extends Node
## Dev harness: scripted shots + perf numbers. Run with `-- --test=<name> --out=<dir>`.

var cam: Camera3D
var main: Node

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	main = G.main
	cam = Camera3D.new()
	cam.fov = 75.0
	cam.near = 0.1
	cam.far = 4000.0
	add_child(cam)
	await call("_test_" + G.test_mode)
	get_tree().quit()

func _shot(shot_name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	if G.out_dir != "":
		img.save_png("%s/%s.png" % [G.out_dir, shot_name])

func _wait(frames: int) -> void:
	for i in frames:
		await get_tree().process_frame

func _secs(t: float) -> void:
	while t > 0.0:
		await get_tree().process_frame
		t -= get_process_delta_time() / maxf(Engine.time_scale, 0.05)

func _perf(label: String, frames := 90) -> void:
	var vp := get_viewport().get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(vp, true)
	await _wait(20)
	var t0 := Time.get_ticks_usec()
	var gpu := 0.0
	var cpu := 0.0
	for i in frames:
		await get_tree().process_frame
		gpu += RenderingServer.viewport_get_measured_render_time_gpu(vp)
		cpu += RenderingServer.viewport_get_measured_render_time_cpu(vp)
	var dt := float(Time.get_ticks_usec() - t0) / frames / 1000.0
	print("[perf] %-18s %6.2f ms  %5.1f fps | gpu %5.2f ms  render cpu %5.2f ms | draws %d  prims %dk" % [label, dt, 1000.0 / dt, gpu / frames, cpu / frames,
		Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
		int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME) / 1000.0)])

func _look(pos: Vector3, target: Vector3) -> void:
	cam.make_current()
	cam.global_position = pos
	cam.look_at(target, Vector3.UP)
	if G.flora:
		G.flora.focus = pos

func _ground(x: float, z: float, up := 1.7) -> Vector3:
	return Vector3(x, G.terrain.height(x, z) + up, z)

## Nearest spot to (x, z) that is clear of trunks; `in_forest` picks dense woods.
func _open_spot(x: float, z: float, in_forest: bool) -> Vector3:
	var best := Vector3(x, 0, z)
	var best_s := -INF
	for i in 400:
		var p := Vector3(x + (G.hash2(i, 1, 77) - 0.5) * 120.0, 0, z + (G.hash2(i, 2, 77) - 0.5) * 120.0)
		var f: float = G.terrain.forest_at(p.x, p.z)
		var h: float = G.terrain.height(p.x, p.z)
		if h < 1.0:
			continue
		var clear: float = 1.0 - minf(G.flora.avoid_vector(p, 3.5).length(), 1.0)
		var score := clear * 2.0 + (f if in_forest else 1.0 - f)
		if score > best_s:
			best_s = score
			best = p
	return _ground(best.x, best.z)

func _aim_player_at(target: Vector3) -> void:
	var pl: Player = G.player
	var d := target - pl.cam.global_position
	pl.yaw = atan2(-d.x, -d.z)
	pl.pitch = atan2(d.y, Vector2(d.x, d.z).length())

## Feed a real input event for `action` through the engine's input pipeline.
func _send(action: String, pressed: bool) -> void:
	var evs := InputMap.action_get_events(action)
	if evs.is_empty():
		return
	var ev: InputEvent = evs[0].duplicate()
	if ev is InputEventKey:
		(ev as InputEventKey).pressed = pressed
	elif ev is InputEventMouseButton:
		(ev as InputEventMouseButton).pressed = pressed
	Input.parse_input_event(ev)

func _hold(action: String) -> void:
	_send(action, true)

func _release(action: String) -> void:
	_send(action, false)

func _tap(action: String) -> void:
	_send(action, true)
	await _wait(3)
	_send(action, false)
	await _wait(1)

# ------------------------------------------------------------------ world
func _test_world() -> void:
	var d: TerrainData = G.terrain
	main.menus.show_screen("")
	var sp := d.spawn_pos
	var fwd := Vector3(sin(d.cabin_yaw), 0, cos(d.cabin_yaw))
	var views := [
		["spawn", 0.12, sp + Vector3(0, 1.7, 0) + fwd * 4.0, d.cabin_pos + Vector3(0, 1.5, 0)],
		["lake", 0.06, sp + Vector3(0, 1.7, 0), sp + fwd * 60.0],
		["forest", 0.3, _open_spot(-90, -120, true), _open_spot(-90, -120, true) + Vector3(20, -1.0, 14)],
		["hill", 0.5, _ground(150, -80, 14.0), Vector3(0, 10, 60)],
		["dusk", 0.95, _open_spot(-60, 150, false), Vector3(40, 6, 30)],
		["tower", 0.6, d.tower_sites[0][0] + Vector3(9, 4, 7), d.tower_sites[0][0] + Vector3(0, 3, 0)],
	]
	for v in views:
		G.sky.set_time(v[1], true)
		_look(v[2], v[3])
		await _wait(50)
		await _shot("w_" + v[0])
		await _perf(v[0], 60)
	# a boulder in full sun
	var rock := Vector3.ZERO
	var best := INF
	for key in G.flora.obstacles:
		var arr: PackedFloat32Array = G.flora.obstacles[key]
		for i in range(0, arr.size(), 5):
			if arr[i + 4] > 0.5 and arr[i + 2] > 1.0:
				var p := Vector3(arr[i], 0, arr[i + 1])
				var score: float = p.distance_to(Vector3(150, 0, -80)) + G.terrain.forest_at(p.x, p.z) * 400.0
				if score < best:
					best = score
					rock = Vector3(arr[i], arr[i + 3], arr[i + 1])
	G.sky.set_time(0.5, true)
	_look(rock + Vector3(-3.5, 1.2, 4.5), rock + Vector3(0, -0.4, 0))
	await _wait(40)
	await _shot("w_rock")

## Dev: hide parts of the scene to see what they cost on the GPU (`--xhide=near,far,...`;
## also spruce_near, single, shadow, cover, terrain, sunshadow, glow, water, and meshinfo
## to print the trees' vertex and triangle counts).
func _apply_xhide() -> void:
	var hide: PackedStringArray = String(G.args.get("xhide", "")).split(",", false)
	if hide.is_empty():
		return
	var fl: Vegetation = G.flora
	var groups := {
		"near": fl._near, "far": fl._far, "single": fl._single.map(func(e): return e[0]), "shadow": fl._shadow,
	}
	for key in groups:
		if hide.has(key):
			for n in groups[key]:
				(n as Node3D).visible = false
	if hide.has("spruce_near"):
		for n in fl._near:
			if (n as MultiMeshInstance3D).multimesh.mesh in [fl.kinds["spruce"][0], fl.kinds["spruce_b"][0], fl.kinds["spruce_c"][0]]:
				(n as Node3D).visible = false
	if hide.has("cover"):
		fl.grass_mat.set_shader_parameter("fade_end", 0.001)
		fl.grass_mat.set_shader_parameter("fade_start", 0.0)
	if hide.has("terrain"):
		for n in G.world._chunks_hi + G.world._chunks_lo:
			(n as Node3D).visible = false
	if hide.has("sunshadow"):
		G.sky.sun.shadow_enabled = false
	if hide.has("glow"):
		G.sky.env.glow_enabled = false
	if hide.has("water"):
		G.world.get_node("Water").visible = false
	print("[xhide] ", hide)
	if hide.has("meshinfo"):
		for kind in Vegetation.BIG + ["sapling"]:
			var m: ArrayMesh = fl.kinds[kind][0]
			var line := "[mesh] %-9s" % kind
			for si in m.get_surface_count():
				var arr := m.surface_get_arrays(si)
				line += "  surface %d: %d verts %d tris" % [si, (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size(), (arr[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3]
			print(line)

## Quick visual check: a handful of fixed views. `--views=a,b` limits the set.
func _test_gfx() -> void:
	var d: TerrainData = G.terrain
	main.menus.show_screen("")
	_apply_xhide()
	var sp := d.spawn_pos
	var fwd := Vector3(sin(d.cabin_yaw), 0, cos(d.cabin_yaw))
	var forest := _open_spot(-90, -120, true)
	var only: PackedStringArray = String(G.args.get("views", "")).split(",", false)
	var views := [
		["dawn", 0.0, sp + Vector3(0, 1.7, 0), sp + fwd * 60.0 + Vector3(0, 6.0, 0)],
		["cabin", 0.12, sp + Vector3(0, 1.7, 0) + fwd * 4.0, d.cabin_pos + Vector3(0, 1.5, 0)],
		["forest", 0.3, forest, forest + Vector3(20, -1.0, 14)],
		["noon", 0.5, _ground(150, -80, 14.0), Vector3(0, 10, 60)],
		["ground", 0.5, _ground(150, -80, 1.7), _ground(150, -80, 1.7) + Vector3(-9, -2.2, 12)],
		["dusk", 0.95, _open_spot(-60, 150, false), Vector3(40, 6, 30)],
		["shore", 0.75, sp + Vector3(0, 1.7, 0) - fwd * 3.0, sp + fwd * 80.0 + Vector3(30, 2.0, 0)],
		# the mountainsides through a long lens (only when asked for)
		["peaks", 0.45, _ground(150, -80, 14.0), Vector3(0, 10, 60) + (Vector3(0, 10, 60) - _ground(150, -80, 14.0)).normalized() * 1400.0 + Vector3(0, 160, 0)],
		["peaks2", 0.62, sp + Vector3(0, 1.7, 0), sp + fwd * 1500.0 + Vector3(0, 230, 0)],
		["top", 0.5, Vector3(0, 900, 0.01), Vector3(0, 0, 0)],
		# across the smaller lakes, near and far shores mirrored at different sizes
		["pond", 0.4, _ground(-255.0, -175.0 + 74.0, 1.7), Vector3(-255.0, 4.0, -175.0 - 70.0)],
		["pond_dusk", 0.93, _ground(-255.0 + 86.0, -175.0, 1.7), Vector3(-255.0 - 88.0, 4.0, -175.0)],
	]
	if only.has("litter"):
		# the ground round the birch and the spruce nearest the spawn point, looked down on from 7 m
		for kind in ["birch", "spruce"]:
			var best := Vector3.ZERO
			var best_d := INF
			for n in G.flora._near:
				var mmi := n as MultiMeshInstance3D
				if mmi.multimesh.mesh != G.flora.kinds[kind][0]:
					continue
				for k in mmi.multimesh.instance_count:
					var p: Vector3 = mmi.position + mmi.multimesh.get_instance_transform(k).origin
					var dd := p.distance_to(sp + fwd * 40.0)
					if dd < best_d:
						best_d = dd
						best = p
			views.append(["litter_" + kind, 0.45, best + Vector3(5.5, 4.5, 4.0), best + Vector3(0, 0.3, 0)])
		# the steepest bank within reach, looked at from 35 m off across its face
		var best := Vector3.ZERO
		var best_s := -1.0
		var x := -480.0
		while x < 480.0:
			var z := -480.0
			while z < 480.0:
				var sl: float = absf(d.height(x + 2.0, z) - d.height(x, z)) + absf(d.height(x, z + 2.0) - d.height(x, z))
				if d.height(x, z) > 3.0 and sl > best_s:
					best_s = sl
					best = Vector3(x, d.height(x, z), z)
				z += 2.0
			x += 2.0
		var e := 0.6
		var nrm := Vector3(d.height(best.x - e, best.z) - d.height(best.x + e, best.z), 2.0 * e, d.height(best.x, best.z - e) - d.height(best.x, best.z + e)).normalized()
		var out := Vector3(nrm.x, 0, nrm.z).normalized()
		var eye := best + out * 35.0
		eye.y = maxf(d.height(eye.x, eye.z), 0.5) + 1.7
		print("[cliff] at ", best, " slope ", best_s)
		views.append(["cliff", 0.45, eye, best + Vector3(0, 2.0, 0)])
		views.append(["cliff_near", 0.45, best + out * 12.0 + Vector3(0, 3.0, 0), best + Vector3(0, 1.0, 0)])
	for v in views:
		if (not only.is_empty() and not only.has(v[0])) or (only.is_empty() and String(v[0]).begins_with("peaks")) or (only.is_empty() and (String(v[0]).begins_with("cliff") or String(v[0]).begins_with("litter") or String(v[0]).begins_with("pond") or v[0] == "top")):
			continue
		G.sky.set_time(v[1], true)
		_look(v[2], v[3])
		cam.fov = 28.0 if String(v[0]).begins_with("peaks") else (40.0 if v[0] == "cliff" else (58.0 if v[0] == "top" else 75.0))
		await _wait(45)
		await _shot("x_" + v[0])
		await _perf(v[0], 40)
	cam.fov = 75.0
	if only.is_empty() or only.has("fp"):
		main.start_hunt()
		var pl: Player = G.player
		await _secs(2.5)
		for fp in [["fp_dawn", 0.0, sp, sp + fwd * 60.0 + Vector3(0, 2.0, 0)], ["fp_noon", 0.5, forest - Vector3(0, 1.7, 0), forest + Vector3(20, 0.0, 14)]]:
			main.hunt["time_left"] = main.hunt["duration"] * (1.0 - float(fp[1]))
			pl.global_position = fp[2]
			pl.vel = Vector3.ZERO
			await _wait(4)
			_aim_player_at(fp[3])
			await _wait(70)
			await _shot("x_" + fp[0])
			await _perf(fp[0], 40)

## What each part of the scene costs on the GPU, measured in one run: for each view,
## each part is hidden and shown again with a plain measurement either side, so the
## laptop warming up over the run does not skew the comparison. `--views=` limits views,
## `--parts=` the parts, `--rounds=` repeats each pair.
func _test_price() -> void:
	var d: TerrainData = G.terrain
	main.menus.show_screen("")
	var fl: Vegetation = G.flora
	var sp := d.spawn_pos
	var fwd := Vector3(sin(d.cabin_yaw), 0, cos(d.cabin_yaw))
	var forest := _open_spot(-90, -120, true)
	var views := [
		["forest", 0.3, forest, forest + Vector3(20, -1.0, 14)],
		["noon", 0.5, _ground(150, -80, 14.0), Vector3(0, 10, 60)],
		["shore", 0.75, sp + Vector3(0, 1.7, 0) - fwd * 3.0, sp + fwd * 80.0 + Vector3(30, 2.0, 0)],
		["dawn", 0.02, sp + Vector3(0, 1.7, 0) - fwd * 3.0, sp + fwd * 80.0 + Vector3(25, 1.0, 0)],
	]
	var spruce_meshes := [fl.kinds["spruce"][0], fl.kinds["spruce_b"][0], fl.kinds["spruce_c"][0]]
	var nodes := {
		"near": fl._near.filter(func(n): return not ((n as MultiMeshInstance3D).multimesh.mesh in spruce_meshes)),
		"spruce_near": fl._near.filter(func(n): return (n as MultiMeshInstance3D).multimesh.mesh in spruce_meshes),
		"far": fl._far, "single": fl._single.map(func(e): return e[0]), "shadow": fl._shadow,
		"terrain": G.world._chunks_hi + G.world._chunks_lo, "water": [G.world.get_node("Water")],
	}
	var fade_s: float = fl.grass_mat.get_shader_parameter("fade_start")
	var fade_e: float = fl.grass_mat.get_shader_parameter("fade_end")
	var set_part := func(part: String, on: bool) -> void:
		if nodes.has(part):
			for n in nodes[part]:
				(n as Node3D).visible = on
		elif part == "cover":
			fl.grass_mat.set_shader_parameter("fade_start", fade_s if on else 0.0)
			fl.grass_mat.set_shader_parameter("fade_end", fade_e if on else 0.001)
		elif part == "sunshadow":
			G.sky.sun.shadow_enabled = on
		elif part == "glow":
			G.sky.env.glow_enabled = on
		elif part == "msaa":
			get_viewport().msaa_3d = Viewport.MSAA_2X if on else Viewport.MSAA_DISABLED
		elif part == "res85":
			get_viewport().scaling_3d_scale = 1.0 if on else 0.85
		elif part == "sky":
			G.sky.env.background_mode = Environment.BG_SKY if on else Environment.BG_COLOR
		elif part == "shoremirror":     # dev A/B: the far shore's trees in the lakes (on) or not
			G.world.water_mat.set_shader_parameter("shore_trees", on)
		elif part == "mist":
			(main.get_node("NatureFx") as NatureFx).mist_scale = 1.0 if on else 0.0
		elif part == "clouds":
			G.sky.cloud_scale = 1.0 if on else 0.0
		elif part == "adjust":
			G.sky.env.adjustment_enabled = on
		elif part == "tonemap":
			G.sky.env.tonemap_mode = Environment.TONE_MAPPER_FILMIC if on else Environment.TONE_MAPPER_LINEAR
		elif part == "post":
			G.sky.env.adjustment_enabled = on
			G.sky.env.tonemap_mode = Environment.TONE_MAPPER_FILMIC if on else Environment.TONE_MAPPER_LINEAR
		elif part == "build":
			(G.world.get_node("Structures") as Node3D).visible = on
		elif part == "mountains":
			(G.world.get_node("FarMountains") as Node3D).visible = on
		elif part == "moose":
			if G.herd:
				(G.herd as Node3D).visible = on
		elif part == "all":
			for key in nodes:
				for n in nodes[key]:
					(n as Node3D).visible = on
			fl.grass_mat.set_shader_parameter("fade_start", fade_s if on else 0.0)
			fl.grass_mat.set_shader_parameter("fade_end", fade_e if on else 0.001)
			G.sky.sun.shadow_enabled = on
			G.sky.env.glow_enabled = on
	var parts: PackedStringArray = String(G.args.get("parts", "spruce_near,near,far,single,shadow,sunshadow,cover,terrain,water,glow")).split(",", false)
	var rounds := int(G.args.get("rounds", "2"))
	var only: PackedStringArray = String(G.args.get("views", "")).split(",", false)
	var vp := get_viewport().get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(vp, true)
	if G.args.has("floor"):       # price what is left with the trees, ground, water, grass, shadows and glow gone
		set_part.call("all", false)
	var measure := func(frames: int) -> float:
		await _wait(12)
		var g := 0.0
		for i in frames:
			await get_tree().process_frame
			g += RenderingServer.viewport_get_measured_render_time_gpu(vp)
		return g / frames
	for v in views:
		if not only.is_empty() and not only.has(v[0]):
			continue
		G.sky.set_time(v[1], true)
		_look(v[2], v[3])
		await _wait(60)
		var base_all := 0.0
		var line := "[price] %-7s" % v[0]
		for part in parts:
			var saved := 0.0
			var b_sum := 0.0
			for r in rounds:
				var b0: float = await measure.call(30)
				set_part.call(part, false)
				var h: float = await measure.call(30)
				set_part.call(part, true)
				var b1: float = await measure.call(30)
				saved += (b0 + b1) * 0.5 - h
				b_sum += (b0 + b1) * 0.5
			base_all += b_sum / rounds
			line += "  %s %.2f" % [part, saved / rounds]
		print(line, "   | base %.2f ms" % (base_all / parts.size()))

## Moose seen from afar through a long lens, at dawn, noon and dusk: stood in
## the open meadow by the cabin, watched from the spawn point.
func _test_far() -> void:
	main.start_hunt()
	var pl: Player = G.player
	await _wait(30)
	var d: TerrainData = G.terrain
	var dist := float(G.args.get("dist", "90"))
	var eye: Vector3 = d.spawn_pos + Vector3(0, 1.7, 0)
	var spot := Vector3.ZERO
	var found := false
	for i in 72:
		var az := TAU * i / 72.0
		var p: Vector3 = d.spawn_pos + Vector3(sin(az), 0, cos(az)) * dist
		p.y = d.height(p.x, p.z)
		if p.y < 0.8 or p.y > 14.0 or d.forest_at(p.x, p.z) > 0.12 or d.slope(p.x, p.z) > 0.2:
			continue
		if not d.line_clear(eye, p + Vector3(0, 1.3, 0)) or not G.flora.ray(eye, p + Vector3(0, 1.3, 0)).is_empty():
			continue
		spot = p
		found = true
		break
	print("[far] spot ", spot, " found=", found)
	pl.visible = false
	pl.active = false
	var across := (spot - d.spawn_pos).cross(Vector3.UP).normalized()
	var kinds := ["trophy", "bull", "young", "cow"]
	var placed: Array = []
	for i in 4:
		for cand in G.herd.moose:
			if cand.kind == kinds[i] and not placed.has(cand):
				var p := spot + across * (-6.0 + i * 4.0)
				cand.position = Vector3(p.x, d.height(p.x, p.z), p.z)
				cand.heading = atan2(across.x, across.z) + (0.25 if i % 2 == 0 else -0.2)
				cand.awareness = 0.0
				cand._set_state(Moose.State.GRAZE)
				cand._graze_len = 999.0
				cand._peek_next = 999.0
				placed.append(cand)
				break
	for m in G.herd.moose:
		if not placed.has(m):
			m.position = Vector3(300, d.height(300, 300), 300)
	main.hud.visible = false
	if G.args.has("nofog"):
		G.sky.env.fog_enabled = false
	if G.args.has("noglow"):
		G.sky.env.glow_enabled = false
	for t in [0.0, 0.12, 0.5, 0.95]:
		main.hunt["time_left"] = main.hunt["duration"] * (1.0 - t)
		_look(eye, spot + Vector3(0, 1.2, 0))
		cam.fov = 12.0
		await _secs(1.2)
		await _shot("f_%d" % int(t * 100.0))
		var e: Environment = G.sky.env
		print("[far] t=%.2f fog dens=%.5f mode=%d height=%.2f hdens=%.5f energy=%.2f scatter=%.2f aerial=%.2f depth=%.1f..%.1f cam=%s dist=%.1f" % [t, e.fog_density, e.fog_mode,
			e.fog_height, e.fog_height_density, e.fog_light_energy, e.fog_sun_scatter, e.fog_aerial_perspective, e.fog_depth_begin, e.fog_depth_end,
			cam.global_position, cam.global_position.distance_to(spot)])
	cam.fov = 75.0

## Calibration: how do known colour values from different material types end up on screen?
func _test_calib() -> void:
	main.menus.show_screen("")
	var d: TerrainData = G.terrain
	var eye: Vector3 = d.spawn_pos + Vector3(0, 30.0, 0)
	G.sky.set_time(0.5, true)
	G.sky.env.fog_enabled = not G.args.has("nofog")
	G.sky.env.glow_enabled = not G.args.has("noglow")
	var codes := [
		"shader_type spatial;\nvoid fragment(){ ALBEDO=vec3(0.0); SPECULAR=0.0; EMISSION=vec3(0.19); }",
		"shader_type spatial;\nrender_mode fog_disabled;\nvoid fragment(){ ALBEDO=vec3(0.0); SPECULAR=0.0; EMISSION=vec3(0.19); }",
		"shader_type spatial;\nrender_mode unshaded;\nvoid fragment(){ ALBEDO=vec3(0.19); }",
		"shader_type spatial;\nrender_mode fog_disabled;\nvoid fragment(){ ALBEDO=vec3(0.0); SPECULAR=0.0; EMISSION=vec3(0.5); }",
		"shader_type spatial;\nrender_mode fog_disabled, ambient_light_disabled;\nvoid fragment(){ ALBEDO=vec3(0.19); SPECULAR=0.0; ROUGHNESS=1.0; }",
	]
	var fwd := Vector3(0, 0, -1)
	for i in codes.size() + 2:
		var mi := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.5
		sm.height = 1.0
		mi.mesh = sm
		if i < codes.size():
			var sh := Shader.new()
			sh.code = codes[i]
			var m := ShaderMaterial.new()
			m.shader = sh
			mi.material_override = m
		else:
			var m := StandardMaterial3D.new()
			m.albedo_color = Color.BLACK
			m.metallic_specular = 0.0
			if i == codes.size():
				m.emission_enabled = true
				m.emission = Color.WHITE
				m.emission_energy_multiplier = 0.19
			else:
				m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
				m.albedo_color = Color(0.19, 0.19, 0.19)
			mi.material_override = m
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
		mi.global_position = eye + fwd * 12.0 + Vector3(-4.5 + i * 1.5, 0, 0)
	# black balls 90 m out, with the engine's fog left on: how much fog do they pick up?
	var far_mats: Array = []
	var std := StandardMaterial3D.new()
	std.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	std.albedo_color = Color.BLACK
	far_mats.append(std)
	var lit := StandardMaterial3D.new()
	lit.albedo_color = Color.BLACK
	lit.metallic_specular = 0.0
	far_mats.append(lit)
	var csh := Shader.new()
	csh.code = "shader_type spatial;\nrender_mode unshaded;\nvoid fragment(){ ALBEDO=vec3(0.0); }"
	var cm := ShaderMaterial.new()
	cm.shader = csh
	far_mats.append(cm)
	var far_pos: Array = []
	for i in far_mats.size():
		var mi := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 3.0
		sm.height = 6.0
		mi.mesh = sm
		mi.material_override = far_mats[i]
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
		mi.global_position = eye + fwd * 90.0 + Vector3(-9.0 + i * 9.0, 6.0, 0)
		far_pos.append(mi.global_position)
	G.sky.env.fog_enabled = true
	G.sky.env.fog_sun_scatter = 0.0
	for f in [60.0, 12.0]:
		_look(eye, eye + fwd * 90.0 + Vector3(0, 6.0, 0))
		cam.fov = f
		await _wait(30)
		var im := get_viewport().get_texture().get_image()
		for i in far_pos.size():
			var sp2 := cam.unproject_position(far_pos[i]) * (Vector2(im.get_size()) / get_viewport().get_visible_rect().size)
			var c2 := im.get_pixelv(Vector2i(sp2))
			print("[fogball] fov=%d mat=%d -> %d %d %d   (density %.5f, colour %s)" % [int(f), i, int(c2.r * 255.0), int(c2.g * 255.0), int(c2.b * 255.0), G.sky.env.fog_density, G.sky.env.fog_light_color])
	G.sky.env.fog_enabled = not G.args.has("nofog")
	_look(eye, eye + fwd * 12.0)
	cam.fov = 60.0
	await _wait(40)
	await _shot("calib")
	var img := get_viewport().get_texture().get_image()
	for i in codes.size() + 2:
		var sp := cam.unproject_position(eye + fwd * 12.0 + Vector3(-4.5 + i * 1.5, 0, 0)) * (Vector2(img.get_size()) / get_viewport().get_visible_rect().size)
		var c := img.get_pixelv(Vector2i(sp))
		print("[calib] %d -> %d %d %d" % [i, int(c.r * 255.0), int(c.g * 255.0), int(c.b * 255.0)])

## Open ground `dist` metres from the spawn point with nothing in the way: [eye, spot, across].
func _clear_stage(dist: float, half_width: float) -> Array:
	var d: TerrainData = G.terrain
	var eye: Vector3 = d.spawn_pos + Vector3(0, 1.7, 0)
	for i in 96:
		var az := TAU * i / 96.0
		var dirv := Vector3(sin(az), 0, cos(az))
		var p: Vector3 = d.spawn_pos + dirv * dist
		p.y = d.height(p.x, p.z)
		var across := dirv.cross(Vector3.UP).normalized()
		if p.y < 0.8 or p.y > 14.0 or d.forest_at(p.x, p.z) > 0.12 or d.slope(p.x, p.z) > 0.2:
			continue
		var ok := true
		for off in [-half_width, 0.0, half_width]:
			var q: Vector3 = p + across * off
			q.y = d.height(q.x, q.z)
			if q.y < 0.6 or q.distance_to(d.cabin_pos) < 30.0 or not G.world.structures.ray(eye, q + Vector3(0, 3.0, 0)).is_empty() \
					or not d.line_clear(eye, q + Vector3(0, 1.3, 0)) or not G.flora.ray(eye, q + Vector3(0, 6.0, 0)).is_empty() \
					or not G.flora.ray(eye, q + Vector3(0, 1.0, 0)).is_empty() or G.flora.avoid_vector(q, 3.5).length() > 0.05:
				ok = false
				break
		if ok:
			return [eye, p, across, true]
	return [eye, d.spawn_pos + Vector3(0, 0, dist), Vector3(1, 0, 0), false]

## Moose portraits for judging the model: a trophy bull, a bull and a cow on open
## ground at noon - the group, each in profile, the trophy's head close up, the group
## backlit at dawn and from 70 m through a long lens - with the HUD hidden.
func _test_mooseshow() -> void:
	main.start_hunt()
	var pl: Player = G.player
	await _wait(20)
	main.hud.visible = false
	var d: TerrainData = G.terrain
	var spot := _flat_spot(float(G.args.get("x", "-60")), float(G.args.get("z", "200")))
	pl.global_position = spot + Vector3(0, -30, 60)
	pl.visible = false
	pl.active = false
	pl.noise = 0.0
	var kinds := ["trophy", "bull", "cow"]
	var placed: Array = []
	for i in kinds.size():
		for cand in G.herd.moose:
			if cand.kind == kinds[i] and not placed.has(cand):
				var p := spot + Vector3(-8.0 + i * 8.0, 0, -(i % 2) * 1.5)
				cand.position = Vector3(p.x, d.height(p.x, p.z), p.z)
				cand.heading = PI * 0.5 + (0.12 if i == 1 else -0.08)
				cand.awareness = 0.0
				cand._set_state(Moose.State.GRAZE)
				cand._graze_len = 999.0
				cand._peek_next = 999.0
				placed.append(cand)
				break
	for m in G.herd.moose:
		if not placed.has(m):
			m.position = Vector3(300, d.height(300, 300), 300)
	# heads up: grazing, but "peeking" - standing still with the head raised
	var heads_up := func(look: float) -> void:
		for m in placed:
			m._peek = 999.0
			m._peek_next = 9999.0
			m._look_t = look
	var cow: Moose = placed[2]
	var centre := spot + Vector3(0, 1.3, 0)
	# a camera position `dist` from `target` towards `angle` (radians round Y, 0 = +Z) with
	# no tree or hill in the way, trying angles either side until one is clear
	var clear_cam := func(target: Vector3, dist: float, angle: float, height: float) -> Vector3:
		for k in 96:
			var a := angle + (0.13 * ceilf((k % 48) / 2.0)) * (1.0 if k % 2 == 0 else -1.0)
			var p := target + Vector3(sin(a), 0, cos(a)) * dist * (1.0 if k < 48 else 0.75)
			p.y = d.height(p.x, p.z) + height
			var ok: bool = G.flora.ray(p, target).is_empty() and d.line_clear(p, target)
			for t in [0.15, 0.3, 0.45, 0.6, 0.75, 0.88]:
				if ok and G.flora.avoid_vector(p.lerp(target, t), 3.5).length() > 0.01:
					ok = false              # a crown could hang into the view
			if ok:
				return p
		var p0 := target + Vector3(sin(angle), 0, cos(angle)) * dist
		p0.y = d.height(p0.x, p0.z) + height
		return p0
	var only: PackedStringArray = String(G.args.get("views", "")).split(",", false)
	var tp: Vector3 = placed[0].position
	var shots := [
		["group", 0.42, clear_cam.call(centre, 21.0, 0.0, 1.7), centre, 48.0, 0.0],
		["bull_side", 0.42, clear_cam.call(placed[1].position + Vector3(0, 1.35, 0), 8.5, 0.0, 1.5), placed[1].position + Vector3(0, 1.35, 0), 42.0, 0.0],
		["trophy_head", 0.42, tp + Vector3(-5.0, 2.0, 3.2), tp + Vector3(-1.9, 2.15, 0), 42.0, -25.0],
		["head_side", 0.42, tp + Vector3(-1.95, 1.9, 3.6), tp + Vector3(-1.95, 1.85, 0), 36.0, 0.0],
		["head_front", 0.42, tp + Vector3(-5.5, 2.2, 0.0), tp + Vector3(-1.9, 2.2, 0), 36.0, 0.0],
		["head_top", 0.42, tp + Vector3(-1.6, 6.0, 0.4), tp + Vector3(-1.7, 2.2, 0), 40.0, 0.0],
		["cow_side", 0.42, clear_cam.call(cow.position + Vector3(0, 1.25, 0), 7.5, 0.0, 1.4), cow.position + Vector3(0, 1.25, 0), 42.0, 999.0],
		["backlit", 0.06, clear_cam.call(centre, 19.0, PI, 1.7), centre, 50.0, 0.0],
		["far", 0.42, clear_cam.call(centre, 68.0, 0.35, 1.7), centre, 17.0, 0.0],
	]
	for sh in shots:
		if (not only.is_empty() and not only.has(sh[0])) or (only.is_empty() and (sh[0] == "head_front" or sh[0] == "head_top")):
			continue
		main.hunt["time_left"] = main.hunt["duration"] * (1.0 - float(sh[1]))
		G.sky.set_time(sh[1], true)
		if sh[0] == "backlit":
			# into the low sun, a little off its line, so the animals are lit from behind
			var sd: Vector3 = G.sky.sun_dir
			sh[2] = clear_cam.call(centre, 19.0, atan2(-sd.x, -sd.z) + 0.35, 1.7)
			print("[mooseshow] backlit: sun_dir %s, camera->herd . sun %.2f" % [sd, ((centre - (sh[2] as Vector3)).normalized()).dot(sd)])
		for m in placed:
			m._set_state(Moose.State.GRAZE)
			m._graze_len = 999.0
			m._peek = 0.0
			m._peek_next = 9999.0
		if float(sh[5]) < 900.0:           # 999 = leave them grazing
			heads_up.call(float(sh[5]))
		_look(sh[2], sh[3])
		cam.fov = sh[4]
		await _secs(2.2)
		await _shot("ms_" + sh[0])
	cam.fov = 75.0

## Mist over the lake at dawn, thinning, and at dusk; the hunter's and a moose's breath on
## a cold morning; birch leaves coming down. `--views=mist,breath,leaves` limits the set.
func _test_nature() -> void:
	var d: TerrainData = G.terrain
	var only: PackedStringArray = String(G.args.get("views", "")).split(",", false)
	var nat: NatureFx = main.get_node("NatureFx")
	var sp := d.spawn_pos
	var fwd := Vector3(sin(d.cabin_yaw), 0, cos(d.cabin_yaw))
	if only.is_empty() or only.has("mist"):
		main.menus.show_screen("")
		for t in [0.02, 0.12, 0.96]:
			G.sky.set_time(t, true)
			_look(sp + Vector3(0, 1.7, 0) - fwd * 3.0, sp + fwd * 80.0 + Vector3(25, 1.0, 0))
			await _wait(40)
			print("[nature] t=%.2f mist %.2f cold %.2f" % [t, NatureFx.mist_amount(t), NatureFx.cold_at(t)])
			await _shot("n_mist_%02d" % int(t * 100))
			if t < 0.05:
				nat.mist_scale = 0.0
				await _wait(3)
				await _shot("n_mist_%02d_off" % int(t * 100))
				nat.mist_scale = 1.0
		G.sky.set_time(0.02, true)
		await _perf("mist_dawn", 40)
	if only.is_empty() or only.has("leaves"):
		main.menus.show_screen("")
		G.sky.set_time(0.45, true)
		var best := Vector3.ZERO
		var best_d := INF
		for n in G.flora._near:
			var mmi := n as MultiMeshInstance3D
			if mmi.multimesh.mesh != G.flora.kinds["birch"][0]:
				continue
			for k in mmi.multimesh.instance_count:
				var p: Vector3 = mmi.position + mmi.multimesh.get_instance_transform(k).origin
				if p.distance_to(sp + fwd * 40.0) < best_d:
					best_d = p.distance_to(sp + fwd * 40.0)
					best = p
		_look(best + Vector3(4.0, 2.2, 3.0), best + Vector3(0, 2.0, 0))
		await _secs(10.0)
		print("[nature] leaves falling/lying ", nat.leaf_count(), " birches near ", G.flora.birches_near(best, 28.0).size() / 4)
		var shown := 0
		for lf in nat._leaves:
			if lf["on"] and shown < 4:
				shown += 1
				print("[nature] leaf at ", lf["pos"], " cam ", cam.global_position, " birch ", best)
		await _shot("n_leaves")
		_look(best + Vector3(2.5, 1.4, 1.8), best + Vector3(0, 0.0, 0))
		await _wait(10)
		await _shot("n_leaves_ground")
	if only.is_empty() or only.has("breath"):
		G.sky.set_time(0.05, true)
		main.start_hunt()
		var pl: Player = G.player
		await _secs(1.5)
		main.hunt["time_left"] = main.hunt["duration"] * 0.95
		G.sky.set_time(0.05, true)
		var spot := _open_spot(sp.x + 40.0, sp.z - 30.0, false) - Vector3(0, 1.7, 0)
		pl.global_position = spot
		pl.vel = Vector3.ZERO
		var mp := spot + Vector3(0, 0, -13.0)
		mp.y = d.height(mp.x, mp.z)
		var m: Moose = G.herd.spawn("bull", mp, false)
		m.heading = PI          # nose towards the hunter
		await _wait(4)
		_aim_player_at(m.head_pos())
		await _wait(30)
		for k in 3:
			nat._breath_t = 0.0
			nat._moose_t[m.get_instance_id()] = 0.0
			await _secs(0.45 + k * 0.25)
			await _shot("n_breath_%d" % k)

## Bushes and other small props, three sizes of each kind in rows on open ground,
## close up and from 12 m. `--kinds=bush,bush_b` picks the kinds.
func _test_props() -> void:
	main.menus.show_screen("")
	var d: TerrainData = G.terrain
	var ground := _open_spot(d.spawn_pos.x + 30.0, d.spawn_pos.z + 20.0, false)
	var across := Vector3(1, 0, 0)
	var back := Vector3(0, 0, 1)
	var kinds: PackedStringArray = String(G.args.get("kinds", "bush,bush_b")).split(",", false)
	var at := ground - back * 6.0
	at.y = d.height(at.x, at.z)
	for ki in kinds.size():
		if not G.flora.kinds.has(kinds[ki]):
			print("[props] no kind ", kinds[ki])
			continue
		var mesh: Mesh = G.flora.kinds[kinds[ki]][0]
		for si in 3:
			var s: float = [0.7, 1.1, 1.5][si]
			var mi := MeshInstance3D.new()
			mi.mesh = mesh
			if mesh.surface_get_material(0) == null:
				mi.material_override = G.flora.mat
			add_child(mi)
			var p: Vector3 = at + across * ((si - 1) * 2.6) - back * (ki * 3.2)
			p.y = d.height(p.x, p.z) - 0.05
			mi.global_position = p
			mi.rotation.y = 0.9 + si * 2.2 + ki
			mi.scale = Vector3.ONE * s
	for t in [0.5, 0.15]:
		G.sky.set_time(t, true)
		var tag := "noon" if t > 0.3 else "morning"
		_look(at + back * 5.0 + Vector3(0, 1.5, 0), at - back * 1.6 + Vector3(0, 0.5, 0))
		cam.fov = 60.0
		await _wait(30)
		await _shot("p_close_" + tag)
		if t > 0.3:
			_look(at + back * 12.0 + Vector3(0, 1.7, 0), at - back * 1.6 + Vector3(0, 0.4, 0))
			cam.fov = 45.0
			await _wait(30)
			await _shot("p_mid_" + tag)
	cam.fov = 75.0

## Boulders: three sizes side by side on open ground (close and from 15 m), then real ones
## out in the valley as the scatter placed them. `--views=row,mid,wild` limits the set.
func _test_rocks() -> void:
	main.menus.show_screen("")
	var d: TerrainData = G.terrain
	var ground := _open_spot(d.spawn_pos.x + 30.0, d.spawn_pos.z + 20.0, false)
	var across := Vector3(1, 0, 0)
	var back := Vector3(0, 0, 1)
	var spot := ground - back * 4.0
	var only: PackedStringArray = String(G.args.get("views", "")).split(",", false)
	var mesh: Mesh = G.flora.kinds["rock"][0]
	var i := 0
	for s in [0.6, 1.2, 2.2]:
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		if mesh.surface_get_material(0) == null:
			mi.material_override = G.flora.mat
		add_child(mi)
		var p: Vector3 = spot + across * ((i - 1) * 3.6) + back * 4.0
		p.y = d.height(p.x, p.z) - 0.25 * s
		mi.global_position = p
		mi.rotation.y = 0.7 + i * 2.1
		mi.scale = Vector3(s, s * 0.85, s * 0.95)
		i += 1
	var at := spot + back * 4.0
	at.y = d.height(at.x, at.z)
	# the nearest real boulders to the stage
	var wild: Array = []
	for key in G.flora.obstacles:
		var arr: PackedFloat32Array = G.flora.obstacles[key]
		for j in range(0, arr.size(), 5):
			if arr[j + 4] > 0.5 and arr[j + 2] > 1.1:
				wild.append(Vector3(arr[j], arr[j + 3], arr[j + 1]))
	wild.sort_custom(func(a: Vector3, b: Vector3) -> bool: return a.distance_squared_to(at) < b.distance_squared_to(at))
	for t in [0.5, 0.15]:
		G.sky.set_time(t, true)
		var tag := "noon" if t > 0.3 else "morning"
		if only.is_empty() or only.has("row"):
			_look(at + back * 7.0 + Vector3(0, 1.6, 0), at + Vector3(0, 0.4, 0))
			cam.fov = 60.0
			await _wait(30)
			await _shot("r_row_" + tag)
		if t > 0.3 and (only.is_empty() or only.has("close")):
			var p: Vector3 = at + across * 3.6
			_look(p + back * 2.6 + across * 0.8 + Vector3(0, 1.4, 0), p + Vector3(0, 0.5, 0))
			cam.fov = 60.0
			await _wait(25)
			await _shot("r_close_" + tag)
		if t > 0.3 and (only.is_empty() or only.has("mid")):
			_look(at + back * 16.0 + Vector3(0, 1.7, 0), at + Vector3(0, 0.5, 0))
			cam.fov = 40.0
			await _wait(25)
			await _shot("r_mid_" + tag)
		if t > 0.3 and (only.is_empty() or only.has("wild")):
			for n in mini(2, wild.size()):
				var w: Vector3 = wild[n]
				var dirv := Vector3(sin(n * 2.3 + 0.4), 0, cos(n * 2.3 + 0.4))
				var e := w + dirv * 7.0
				e.y = d.height(e.x, e.z) + 1.7
				_look(e, Vector3(w.x, d.height(w.x, w.z) + 0.5, w.z))
				cam.fov = 60.0
				await _wait(30)
				await _shot("r_wild%d_%s" % [n, tag])
	cam.fov = 75.0
	G.sky.set_time(0.5, true)
	_look(at + back * 7.0 + Vector3(0, 1.6, 0), at + Vector3(0, 0.4, 0))
	await _perf("rocks", 60)

## The three big trees up close, each on its own on open ground, plus a look up into a crown.
func _test_trees() -> void:
	main.menus.show_screen("")
	var d: TerrainData = G.terrain
	var stage: Array = []
	for dist in [24.0, 28.0, 20.0, 33.0, 38.0, 16.0]:
		stage = _clear_stage(dist, 7.5)
		if stage[3]:
			break
	print("[trees] stage found=", stage[3], " at ", stage[1])
	var eye: Vector3 = stage[0]
	var spot: Vector3 = stage[1]
	var across: Vector3 = stage[2]
	var back := (eye - spot)
	back.y = 0.0
	back = back.normalized()
	var kinds: PackedStringArray = String(G.args.get("kinds", "spruce,pine,birch")).split(",", false)
	var only: PackedStringArray = String(G.args.get("views", "")).split(",", false)
	var at: Array = []
	for i in kinds.size():
		var mi := MeshInstance3D.new()
		mi.mesh = G.flora.kinds[kinds[i]][0]
		add_child(mi)
		var p := spot + across * ((i - 1) * 8.0)
		p.y = d.height(p.x, p.z) - 0.05
		mi.global_position = p
		mi.rotation.y = 0.8 + i
		at.append(p)
	for t in [0.5, 0.08]:
		G.sky.set_time(t, true)
		var tag := "noon" if t > 0.3 else "dawn"
		if only.is_empty() or only.has("row"):
			_look(eye + Vector3(0, 1.0, 0), spot + Vector3(0, 6.0, 0))
			cam.fov = 62.0
			await _wait(40)
			await _shot("t_row_" + tag)
			await _perf("row_" + tag, 40)
		if t > 0.3 and only.has("far"):
			# as seen beyond the foliage shader's fine_range (shrunk to 4 m here): limbs and
			# dead twigs drop out, but whole trunks must stay
			var mats: Array = []
			for k in kinds:
				var m: ShaderMaterial = G.flora.kinds[k][0].surface_get_material(0)
				if m and not mats.has(m):
					mats.append(m)
			for m: ShaderMaterial in mats:
				m.set_shader_parameter("fine_range", 4.0)
			_look(eye + Vector3(0, 1.0, 0), spot + Vector3(0, 6.0, 0))
			cam.fov = 62.0
			await _wait(40)
			await _shot("t_far_" + tag)
			for m: ShaderMaterial in mats:
				m.set_shader_parameter("fine_range", 32.0)
		cam.fov = 75.0
		for i in kinds.size():
			if not (only.is_empty() or only.has(kinds[i])):
				continue
			var p: Vector3 = at[i]
			_look(p + back * 11.5 + across * 2.0 + Vector3(0, 2.0, 0), p + Vector3(0, 6.5, 0))
			await _wait(25)
			await _shot("t_%s_%s" % [kinds[i], tag])
		if t > 0.3 and (only.is_empty() or only.has("bark")):
			# each trunk up close at chest height, and the pine's upper trunk where the bark turns thin and orange
			for bi in kinds.size():
				var bp: Vector3 = at[bi]
				_look(bp + back * 2.4 + across * 0.5 + Vector3(0, 1.5, 0), bp + Vector3(0, 1.9, 0))
				await _wait(25)
				await _shot("t_bark" if kinds[bi] == "birch" else "t_bark_" + kinds[bi])
				if kinds[bi] == "pine":
					_look(bp + back * 3.2 + across * 0.8 + Vector3(0, 5.0, 0), bp + Vector3(0, 6.2, 0))
					await _wait(25)
					await _shot("t_bark_pine_high")
			_look(at[0] + back * 9.0 + Vector3(0, 9.0, 0), at[0] + Vector3(0, 10.6, 0))
			cam.fov = 30.0
			await _wait(25)
			await _shot("t_spruce_top")
			cam.fov = 75.0
		if t > 0.3 and (only.is_empty() or only.has("up")):
			var p: Vector3 = at[0]
			_look(p + back * 2.6 + across * 1.4 + Vector3(0, 1.7, 0), p + Vector3(0, 7.0, 0))
			await _wait(25)
			await _shot("t_up_spruce")

## The cabin from all sides, close up and at dusk. `--views=` limits the set.
func _test_cabin() -> void:
	main.menus.show_screen("")
	var st: Structures = G.world.structures
	var xf: Transform3D = st.cabin.global_transform
	var only: PackedStringArray = String(G.args.get("views", "")).split(",", false)
	# [name, time, eye (cabin space), target (cabin space), fov]
	var views := [
		["front3q", 0.42, Vector3(7.5, 2.0, 10.5), Vector3(0, 2.2, 0), 62.0],
		["front", 0.42, Vector3(0.4, 1.7, 12.0), Vector3(0, 2.4, 0), 60.0],
		["left", 0.42, Vector3(-12.0, 2.0, 1.5), Vector3(0, 2.2, 0), 60.0],
		["back3q", 0.42, Vector3(-8.0, 2.4, -9.5), Vector3(0, 2.2, 0), 62.0],
		["right", 0.42, Vector3(11.5, 1.9, -2.0), Vector3(0, 2.0, 0), 60.0],
		["roof", 0.42, Vector3(8.0, 8.5, 9.0), Vector3(0, 2.8, 0), 60.0],
		["porch", 0.42, Vector3(2.6, 1.7, 6.2), Vector3(-1.0, 1.6, 2.3), 70.0],
		["window", 0.42, Vector3(2.4, 1.75, 4.6), Vector3(1.5, 1.8, 2.3), 60.0],
		["dusk", 0.97, Vector3(6.5, 1.8, 10.0), Vector3(0, 2.0, 0), 62.0],
		["trophy", 0.42, Vector3(-6.2, 2.9, 0.6), Vector3(-3.6, 2.85, 0.0), 50.0],
		["door", 0.42, Vector3(-0.2, 2.05, 4.9), Vector3(-0.9, 1.75, 2.5), 70.0],
		["outhouse", 0.42, Vector3(-4.6, 1.6, -0.6), Vector3(-6.3, 1.1, -4.4), 60.0],
		["shed", 0.42, Vector3(8.6, 1.7, 2.2), Vector3(4.6, 0.9, 0.0), 62.0],
		["menu", 0.085, Vector3.INF, Vector3.ZERO, 55.0],
	]
	for v in views:
		if not only.is_empty() and not only.has(v[0]):
			continue
		G.sky.set_time(v[1], true)
		st.update_lights(main.twilight_at(float(v[1])))
		if v[2] == Vector3.INF:
			main._place_menu_cam(0.0)
			_look(main.menu_cam.global_position, main.menu_cam.global_position - main.menu_cam.global_basis.z)
		else:
			_look(xf * (v[2] as Vector3), xf * (v[3] as Vector3))
		cam.fov = v[4]
		await _wait(30)
		await _shot("c_" + v[0])
	cam.fov = 75.0

## Walk the hunter at the cabin: up the steps onto the deck, into the railing, the
## walls, the woodshed and the outhouse; and fire a few rays at it.
func _test_cabinwalk() -> void:
	main.start_hunt()
	var pl: Player = G.player
	var st: Structures = G.world.structures
	var xf: Transform3D = st.cabin.global_transform
	await _wait(20)
	# [name, start (cabin space), heading (cabin space), seconds]
	var walks := [
		["steps", Vector3(-0.9, 0, 7.5), Vector3(0, 0, -1), 4.0],
		["railing", Vector3(2.2, 0, 7.5), Vector3(0, 0, -1), 3.0],
		["west wall", Vector3(-7.0, 0, 0.5), Vector3(1, 0, 0), 3.0],
		["back wall", Vector3(0.5, 0, -7.0), Vector3(0, 0, 1), 3.0],
		["woodshed", Vector3(9.0, 0, 0.0), Vector3(-1, 0, 0), 3.0],
		["outhouse", Vector3(-6.3, 0, -0.5), Vector3(0, 0, -1), 3.0],
		["under eave", Vector3(1.5, 0, -5.5), Vector3(0, 0, 1), 1.2],
	]
	for w in walks:
		var start: Vector3 = xf * (w[1] as Vector3)
		start.y = G.terrain.height(start.x, start.z)
		pl.global_position = start
		pl.vel = Vector3.ZERO
		var hd: Vector3 = xf.basis * (w[2] as Vector3)
		pl.yaw = atan2(-hd.x, -hd.z)
		pl.pitch = 0.0
		await _wait(3)
		_hold("move_forward")
		await _secs(float(w[3]))
		_release("move_forward")
		await _wait(5)
		var l: Vector3 = st.cabin_inv * pl.global_position
		print("[walk] %-10s ended at x=%.2f z=%.2f, %.2f m above the cabin floor line" % [w[0], l.x, l.z, l.y])
	# rays: [name, from, to] in cabin space
	var rays := [
		["railing", Vector3(0.0, 1.0, 20.0), Vector3(0.0, 1.0, -20.0)],
		["door", Vector3(-0.9, 1.4, 20.0), Vector3(-0.9, 1.4, -20.0)],
		["plinth", Vector3(-20.0, 0.2, 0.0), Vector3(20.0, 0.2, 0.0)],
		["roof", Vector3(0.0, 3.7, 20.0), Vector3(0.0, 3.7, -20.0)],
		["over", Vector3(0.0, 7.0, 20.0), Vector3(0.0, 7.0, -20.0)],
	]
	for r in rays:
		var hit: Dictionary = st.ray(xf * (r[1] as Vector3), xf * (r[2] as Vector3))
		if hit.is_empty():
			print("[ray] %-8s no hit" % r[0])
		else:
			var lp: Vector3 = st.cabin_inv * (hit["pos"] as Vector3)
			print("[ray] %-8s %s at x=%.2f y=%.2f z=%.2f" % [r[0], hit["kind"], lp.x, lp.y, lp.z])

## Facts about the cabin's surroundings, in cabin space, for framing shots.
func _test_site() -> void:
	var st: Structures = G.world.structures
	var inv: Transform3D = st.cabin_inv
	G.sky.set_time(0.085, true)
	var sd: Vector3 = inv.basis * G.sky.sun_dir
	print("[site] sun at dawn (cabin space) ", sd)
	G.sky.set_time(0.97, true)
	print("[site] sun at dusk (cabin space) ", inv.basis * G.sky.sun_dir)
	print("[site] pier start ", inv * (st.pier_xf * Vector3(0, 0, 0)), " end ", inv * (st.pier_xf * Vector3(0, 0, st.pier_len)))
	print("[site] old menu camera ", inv * G.terrain.menu_cam_pos)
	for ang in [-60, -30, 0, 30, 60]:
		var line := ""
		for dd in [6, 9, 12, 15, 18, 22, 26, 30]:
			var a := deg_to_rad(float(ang))
			var p: Vector3 = st.cabin.global_transform * Vector3(sin(a) * dd, 0, cos(a) * dd)
			line += " %d:%.1f" % [dd, G.terrain.height(p.x, p.z)]
		print("[site] heights towards %+d deg:%s" % [ang, line])

## Paint the foliage textures afresh and save them for a look.
func _test_cards() -> void:
	var t0 := Time.get_ticks_msec()
	var cover := PackedFloat32Array()
	var img := FloraTextures.build_image(cover)
	print("[cards] painted in %d ms, cover per tile %s" % [Time.get_ticks_msec() - t0, cover])
	img.save_png(G.out_dir + "/cards.png")
	print("[cards] spray trapezoid A %s  B %s" % [FloraTextures.spray_trap(FloraTextures.SPRUCE), FloraTextures.spray_trap(FloraTextures.SPRUCE_B)])
	print("[cards] curtain bottom %s" % [FloraTextures.curtain_bottom(FloraTextures.SPRUCE_HANG, 2)])

# ------------------------------------------------------------------ menus
func _test_menu() -> void:
	await _wait(40)
	await _shot("m_main")
	main.menus.show_screen("gear")
	await _wait(8)
	await _shot("m_gear")
	main.menus._gear_sel = "nordlys300"
	main.menus.show_screen("gear")
	await _wait(8)
	await _shot("m_gear2")
	main.menus._gear_sel = "dog"
	main.menus._gear_is_weapon = false
	main.menus.show_screen("gear")
	await _wait(8)
	await _shot("m_gear3")
	main.menus._gear_is_weapon = true
	main.menus.show_screen("settings")
	await _wait(8)
	await _shot("m_settings")
	main.menus.show_screen("records")
	await _wait(8)
	await _shot("m_records")
	main.start_hunt()
	await _wait(30)
	main.pause()
	await _wait(6)
	await _shot("m_pause")
	main.resume()
	main.hunt["score"] = 2340
	main.hunt["kills"] = [
		{"title": "Bull Moose", "text": "Heart shot", "dist": 187.0, "points": 1480, "moose": 1, "tagged": true},
		{"title": "Moose Cow", "text": "Lung shot", "dist": 96.0, "points": 860, "moose": 2, "tagged": false},
	]
	main.hunt["shots"] = 5
	main.hunt["hits"] = 3
	main.hunt["longest"] = 187.0
	main.end_hunt(false)
	await _wait(10)
	await _shot("m_summary")

# ----------------------------------------------------------------- weapon
func _test_weapon() -> void:
	main.start_hunt()
	var pl: Player = G.player
	main.hunt["time_left"] = main.hunt["duration"] * 0.7
	await _wait(60)
	var d: TerrainData = G.terrain
	_aim_player_at(pl.cam.global_position + Vector3(sin(d.cabin_yaw), -0.02, cos(d.cabin_yaw)) * 50.0)
	await _wait(40)
	var id: String = pl.weapon.id
	await _shot("g_%s_hip" % id)
	_hold("aim")
	await _wait(8)
	await _shot("g_%s_ads_mid" % id)
	await _wait(40)
	await _shot("g_%s_ads" % id)
	await _tap("fire")
	await _wait(2)
	await _shot("g_%s_fire" % id)
	await _wait(22)
	await _shot("g_%s_cycle" % id)
	_release("aim")
	await _secs(1.4)
	await _tap("fire")
	await _wait(1)
	await _shot("g_%s_hipfire" % id)
	await _secs(0.35)
	await _shot("g_%s_hipcycle" % id)
	await _secs(1.3)
	await _tap("reload")
	await _secs(float(pl.weapon.stats["reload"]) * 0.35)
	await _shot("g_%s_reload" % id)
	await _secs(float(pl.weapon.stats["reload"]) * 0.3)
	await _shot("g_%s_reload2" % id)
	await _secs(3.0)
	print("[weapon] %s rounds=%d state=%s" % [id, pl.weapon.rounds(), pl.weapon.state])

# ------------------------------------------------------------------ moose
## Flattest open ground near (x, z).
func _flat_spot(x: float, z: float) -> Vector3:
	var best := Vector3(x, 0, z)
	var best_s := -INF
	for i in 600:
		var p := Vector3(x + (G.hash2(i, 1, 99) - 0.5) * 300.0, 0, z + (G.hash2(i, 2, 99) - 0.5) * 300.0)
		var h: float = G.terrain.height(p.x, p.z)
		if h < 1.2 or p.distance_to(G.terrain.cabin_pos) < 60.0:
			continue
		var worst := 0.0
		for q in [Vector3(12, 0, 0), Vector3(-12, 0, 0), Vector3(0, 0, 12), Vector3(0, 0, -12), Vector3(0, 0, -24)]:
			worst = maxf(worst, absf(G.terrain.height(p.x + q.x, p.z + q.z) - h))
		var score: float = -worst * 2.0 - G.terrain.forest_at(p.x, p.z) * 3.0 - G.flora.avoid_vector(p, 6.0).length()
		if score > best_s:
			best_s = score
			best = p
	best.y = G.terrain.height(best.x, best.z)
	return best

func _test_moose() -> void:
	main.start_hunt()
	var pl: Player = G.player
	main.hunt["time_left"] = main.hunt["duration"] * 0.62
	await _wait(30)
	var d: TerrainData = G.terrain
	var spot := _flat_spot(float(G.args.get("x", "-60")), float(G.args.get("z", "200")))
	pl.global_position = spot + Vector3(0, 0, 30)
	pl.crouching = true
	pl.visible = false
	var kinds := ["trophy", "bull", "young", "cow"]
	var placed: Array = []
	for i in 4:
		for cand in G.herd.moose:
			if cand.kind == kinds[i] and not placed.has(cand):
				var p := spot + Vector3(-7.5 + i * 5.0, 0, -(i % 2) * 2.5)
				cand.position = Vector3(p.x, d.height(p.x, p.z), p.z)
				cand.heading = PI * 0.5 + (0.25 if i % 2 == 0 else -0.2)
				cand.awareness = 0.0
				cand._set_state(Moose.State.GRAZE)
				cand._graze_len = 999.0
				cand._peek_next = 999.0
				placed.append(cand)
				break
	for m in G.herd.moose:
		if not placed.has(m):
			m.position = Vector3(300, d.height(300, 300), 300)
	pl.noise = 0.0
	pl.active = false
	_look(spot + Vector3(0, 1.8, 13.0), spot + Vector3(0, 1.2, 0))
	await _secs(2.5)
	await _shot("a_graze")
	for m in placed:
		m.threat = spot + Vector3(0, 0, 30)
		m.awareness = 0.8
		m._set_state(Moose.State.ALERT)
	await _secs(2.0)
	await _shot("a_alert")
	_look(placed[0].position + Vector3(-1.0, 1.7, 5.5), placed[0].position + Vector3(-0.6, 1.45, 0))
	await _wait(5)
	await _shot("a_trophy_close")
	_look(placed[0].position + Vector3(-5.0, 1.9, -3.0), placed[0].position + Vector3(-0.5, 1.5, 0))
	await _wait(5)
	await _shot("a_trophy_front")
	_look(placed[3].position + Vector3(0.5, 1.6, 5.0), placed[3].position + Vector3(0.2, 1.3, 0))
	await _wait(5)
	await _shot("a_cow_close")
	# walk / run profile
	var runner: Moose = placed[1]
	runner._target = runner.position + Vector3(-60, 0, 0)
	runner._set_state(Moose.State.WANDER)
	await _secs(2.2)
	_look(runner.position + Vector3(0, 1.5, 7.0), runner.position + Vector3(0, 1.3, 0))
	await _wait(3)
	await _shot("a_walk")
	runner._start_flee(runner.position + Vector3(30, 0, 0))
	runner._target = runner.position + Vector3(-160, 0, 0)
	await _secs(1.7)
	_look(runner.position + Vector3(-3, 1.5, 8.0), runner.position + Vector3(-3, 1.3, 0))
	await _wait(2)
	await _shot("a_run")
	await _secs(0.12)
	_look(runner.position + Vector3(-3, 1.5, 8.0), runner.position + Vector3(-3, 1.3, 0))
	await _wait(2)
	await _shot("a_run2")
	# shoot the trophy bull and watch it fall
	var target: Moose = placed[0]
	var from := target.position + Vector3(0, 1.4, 14.0)
	var aim := target.centre() + Vector3(0, -0.05, 0) + target.forward() * 0.45
	_look(target.position + Vector3(1.0, 1.7, 8.5), target.position + Vector3(0, 1.0, 0))
	G.ballistics.fire(from, (aim - from).normalized(), WeaponDB.get_weapon("nordlys300"), "nordlys300")
	for f in 7:
		await _secs(0.28)
		await _shot("a_death_%d" % f)
	await _secs(3.5)
	await _shot("a_death_rest")
	_look(target.centre() + Vector3(2.5, 1.6, 3.5), target.centre())
	await _wait(4)
	await _shot("a_death_rest2")
	print("[moose] target dead=%s kill=%s score=%d asleep=%s" % [target.dead, target.kill, main.hunt["score"], target.ragdoll.asleep if target.ragdoll else false])
	# a running kill
	var r2: Moose = placed[2]
	r2._start_flee(r2.position + Vector3(40, 0, 0))
	r2._target = r2.position + Vector3(-160, 0, 0)
	await _secs(1.9)
	var a2 := r2.centre() + r2.forward() * 0.75
	var f2 := a2 + Vector3(0, 0.2, 14)
	_look(r2.position + Vector3(-7, 1.8, 9.0), r2.position + Vector3(-7, 1.0, 0))
	G.ballistics.fire(f2, (a2 - f2).normalized(), WeaponDB.get_weapon("tordenskjold"), "tordenskjold")
	for f in 6:
		await _secs(0.3)
		await _shot("a_tumble_%d" % f)
	print("[moose] runner dead=%s kill=%s" % [r2.dead, r2.kill])

# ------------------------------------------------------------------- play
## Smoke test: a short scripted hunt exercising movement, weapons and UI.
func _test_play() -> void:
	main.start_hunt()
	var pl: Player = G.player
	await _wait(30)
	await _perf("hunt_start", 120)
	await _shot("p_start")
	_hold("move_forward")
	await _secs(2.0)
	_hold("sprint")
	await _secs(2.0)
	_release("sprint")
	await _tap("jump")
	await _secs(1.0)
	_release("move_forward")
	await _tap("crouch")
	_hold("aim")
	await _secs(0.8)
	await _tap("fire")
	await _secs(1.6)
	_release("aim")
	await _tap("reload")
	await _secs(3.2)
	for w in ["finnskog4570", "storm93", "tordenskjold", "nordlys300"]:
		if SaveGame.owns_weapon(w):
			pl.weapon.equip(w)
			await _secs(1.0)
			await _tap("fire")
			await _secs(1.2)
			await _tap("fire")
			await _secs(1.2)
			await _tap("reload")
			await _secs(3.6)
	main.hud.toggle_map()
	await _wait(10)
	await _shot("p_map")
	main.hud.toggle_map()
	# find a moose, stalk and shoot it for real through the player's rifle
	# (from a spot with a clear line to a calm animal, so a miss means something is broken)
	var m: Moose = null
	var stand := Vector3.ZERO
	# the hunter is crouched by now: check the line from where the eye really is
	var eye_h: float = pl.cam.global_position.y - pl.global_position.y
	for cand in G.herd.moose:
		if cand.dead or m != null:
			continue
		for i in 24:
			var az := TAU * i / 24.0
			var p: Vector3 = cand.position + Vector3(sin(az), 0, cos(az)) * 70.0
			p.y = G.terrain.height(p.x, p.z)
			if p.y < 0.5 or Vector2(p.x, p.z).length() > 400.0:
				continue
			var eye_at := p + Vector3(0, eye_h, 0)
			var aim_at: Vector3 = cand.centre() + Vector3(0, 0.15, 0)
			if G.terrain.line_clear(eye_at, aim_at) and G.flora.ray(eye_at, aim_at).is_empty() and G.flora.avoid_vector(p, 2.0).length() < 0.05:
				m = cand
				stand = p
				break
	if m == null:
		m = G.herd.nearest_alive(pl.global_position)
		print("[play] no clear shot found: falling back to the nearest moose")
		if m:
			var off := (pl.global_position - m.position)
			off.y = 0
			stand = m.position + off.normalized() * 70.0
	if m:
		# the opening shots of this test have the whole valley on its toes: settle this one
		m.awareness = 0.0
		m._set_state(Moose.State.GRAZE)
		m._graze_len = 999.0
		m._peek_next = 999.0
		pl.noise = 0.0
		pl.global_position = Vector3(stand.x, G.terrain.height(stand.x, stand.z), stand.z)
		await _wait(5)
		pl.weapon.equip("varg308")
		await _secs(1.2)
		_hold("aim")
		# behind the shoulder, on the lungs, as a hunter aims
		var vitals := func() -> Vector3:
			return m.global_position + Vector3(0, 1.42 * m.size, 0) + m.forward() * 0.47 * m.size
		for k in 40:
			_aim_player_at(vitals.call())
			await _wait(1)
		await _shot("p_scope_moose")
		var eye_p: Vector3 = pl.cam.global_position
		var tgt: Vector3 = vitals.call()
		print("[play] before shot: dist=%.1f tree_in_way=%s ground_in_way=%s ads=%.2f state=%s rounds=%d shots=%d moose_state=%d" % [eye_p.distance_to(tgt),
			not G.flora.ray(eye_p, tgt).is_empty(), not G.terrain.line_clear(eye_p, tgt), pl.weapon.ads, pl.weapon.state, pl.weapon.rounds(), main.hunt["shots"], m.state])
		await _tap("fire")
		await _secs(0.5)
		await _shot("p_after_shot")
		_release("aim")
		await _secs(3.0)
		print("[play] moose dead=%s wounded=%s score=%d hits=%d shots=%d zone=%s kind=%s heading=%.2f" % [m.dead, m.wounded, main.hunt["score"], main.hunt["hits"], main.hunt["shots"], m.last_hit.get("zone", "-"), m.kind, m.heading])
		if m.dead:
			var c := m.centre()
			pl.global_position = Vector3(c.x + 2.0, G.terrain.height(c.x + 2.0, c.z), c.z)
			await _secs(0.5)
			_aim_player_at(c)
			await _wait(10)
			await _shot("p_carcass")
			await _tap("interact")
			await _wait(10)
			await _shot("p_tagged")
	await _perf("hunt_mid", 120)
	main.end_hunt(false)
	await _wait(20)
	await _shot("p_summary")
	print("[play] done score=%d" % main.hunt["score"])

# ------------------------------------------------------------------- gear
## Every rifle from the hip, aimed, firing and reloading; plus binoculars,
## a tower view and highlighted tracks.
func _test_gear() -> void:
	main.start_hunt()
	var pl: Player = G.player
	main.hunt["time_left"] = main.hunt["duration"] * 0.6
	await _wait(40)
	var d: TerrainData = G.terrain
	var fwd := Vector3(sin(d.cabin_yaw), 0, cos(d.cabin_yaw))
	_aim_player_at(pl.cam.global_position + (fwd + Vector3(0.5, -0.03, 0.2)).normalized() * 50.0)
	var only: String = G.args.get("only", "")
	for id in WeaponDB.ORDER:
		if only != "" and id != only:
			continue
		pl.weapon.equip(id, true)
		await _secs(0.8)
		await _shot("w_%s_1hip" % id)
		_hold("aim")
		await _secs(0.7)
		await _shot("w_%s_2ads" % id)
		print("[gear] %s ads=%.3f root=%s rot=%s lower=%.2f state=%s" % [id, pl.weapon.ads, pl.weapon.root.position, pl.weapon.root.rotation_degrees, pl.weapon._lower, pl.weapon.state])
		await _tap("fire")
		await _wait(1)
		await _shot("w_%s_3fire" % id)
		_release("aim")
		await _secs(float(pl.weapon.stats["cycle"]) + 0.5)
		await _tap("fire")
		await _wait(1)
		await _shot("w_%s_4hipfire" % id)
		await _secs(float(pl.weapon.stats["cycle"]) * 0.42)
		await _shot("w_%s_5cycle" % id)
		await _secs(float(pl.weapon.stats["cycle"]) + 0.4)
		await _tap("reload")
		var rl: float = float(pl.weapon.stats["reload"]) if pl.weapon.stats["type"] != "lever" else 1.6
		await _secs(rl * 0.33)
		await _shot("w_%s_6reload" % id)
		await _secs(rl * 0.25)
		await _shot("w_%s_7reload" % id)
		await _secs(rl * 0.6 + 2.0)
		print("[gear] %s rounds=%d/%d state=%s" % [id, pl.weapon.rounds(), pl.weapon.mag_size(), pl.weapon.state])
	if only != "":
		return
	# binoculars
	_hold("binoculars")
	await _secs(0.8)
	await _shot("x_binoculars")
	_release("binoculars")
	await _secs(0.5)
	# tracks: light up whatever is around the nearest moose
	var m: Moose = G.herd.nearest_alive(pl.global_position)
	if m:
		m._target = m.position + m.forward() * 40.0
		m._set_state(Moose.State.WANDER)
		m.wounded = true
		m.bleed = 4.0
		m.health = 9999.0
		await _secs(6.0)
		var back := m.position - m.forward() * 9.0
		pl.global_position = Vector3(back.x, d.height(back.x, back.z), back.z)
		pl.noise = 0.0
		_aim_player_at(m.position + Vector3(0, 0.3, 0))
		pl.pitch -= 0.25
		await _secs(0.4)
		await _shot("x_tracks")
		await _tap("track_sense")
		await _secs(1.2)
		await _shot("x_tracks_lit")
		print("[gear] prompt='%s'" % pl.prompt)
	# hunting tower
	var top: Vector3 = d.tower_sites[0][0]
	pl.global_position = top + Vector3(0, 0, 0.5)
	await _secs(0.4)
	print("[gear] tower prompt='%s'" % pl.prompt)
	await _tap("interact")
	await _secs(1.2)
	pl.pitch = -0.12
	await _wait(10)
	await _shot("x_tower_view")
	_look(top + Vector3(7, 3, 9), top + Vector3(0, 3.5, 0))
	await _wait(5)
	await _shot("x_tower")

# ------------------------------------------------------------------- perf
## Frame times for every quality preset at a few representative spots.
func _test_perf() -> void:
	main.start_hunt()
	var pl: Player = G.player
	main.hunt["time_left"] = main.hunt["duration"] * 0.6
	var d: TerrainData = G.terrain
	var fwd := Vector3(sin(d.cabin_yaw), 0, cos(d.cabin_yaw))
	var forest := _open_spot(-90, -120, true)
	var spots := [
		["lake", d.spawn_pos, d.spawn_pos + fwd * 50.0 + Vector3(0, 1.5, 0)],
		["forest", forest - Vector3(0, 1.7, 0), forest + Vector3(20, -1.0, 14)],
		["hill", _ground(150, -80, 0.0), Vector3(0, 10, 60)],
	]
	for preset in 4:
		Settings.apply_preset(preset)
		await _wait(30)
		var worst := 0.0
		for s in spots:
			pl.global_position = s[1]
			pl.vel = Vector3.ZERO
			await _wait(4)
			_aim_player_at(s[2])
			await _wait(90)     # let ground cover stream in
			var t0 := Time.get_ticks_usec()
			await _wait(120)
			var ms := float(Time.get_ticks_usec() - t0) / 120.0 / 1000.0
			worst = maxf(worst, ms)
			print("[perf] %-7s %-7s %6.2f ms  %5.1f fps | draws %d  prims %dk" % [Settings.PRESET_NAMES[preset], s[0], ms, 1000.0 / ms,
				Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
				int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME) / 1000.0)])
			if preset == 2:
				await _shot("perf_high_%s" % s[0])
		print("[perf] %-7s worst %.2f ms (%.0f fps)" % [Settings.PRESET_NAMES[preset], worst, 1000.0 / worst])

# -------------------------------------------------------------------- dog
## Portraits of the elkhound, posed by hand: standing, sitting, barking, trotting,
## galloping, and from hunting distance (no HUD).
func _test_dogshow() -> void:
	main.start_hunt()
	var pl: Player = G.player
	main.hunt["time_left"] = main.hunt["duration"] * 0.55
	await _wait(20)
	main.hud.visible = false
	var d: TerrainData = G.terrain
	var spot := _flat_spot(float(G.args.get("x", "-60")), float(G.args.get("z", "200")))
	pl.global_position = spot + Vector3(0, -30, 60)
	pl.visible = false
	pl.active = false
	for m in G.herd.moose:
		m.position = Vector3(300, d.height(300, 300), 300)
	var dog: Dog = G.dog
	dog.active = false        # posed by hand: nothing moves it
	dog.visible = true
	dog.position = spot
	dog.heading = PI * 0.5    # nose towards -X
	var c := spot + Vector3(0, 0.38, 0)
	# name, speed, sit, jaw, neck, head, camera offset
	var shots := [
		["side", 0.0, 0.0, 0.0, 4.0, -6.0, Vector3(0, 0.25, 2.3)],
		["front34", 0.0, 0.0, 0.0, 4.0, -6.0, Vector3(-1.6, 0.45, 1.4)],
		["rear34", 0.0, 0.0, 0.0, 4.0, -6.0, Vector3(1.5, 0.6, 1.3)],
		["head", 0.0, 0.0, 0.0, 10.0, -8.0, Vector3(-0.85, 0.32, 0.55)],
		["sit", 0.0, 1.0, 0.0, 4.0, -6.0, Vector3(-0.7, 0.3, 2.1)],
		["bark", 0.0, 0.0, 1.0, 14.0, -12.0, Vector3(-1.2, 0.35, 1.7)],
		["trot", 3.6, 0.0, 0.0, -2.0, -10.0, Vector3(0, 0.3, 2.6)],
		["gallop", 7.6, 0.0, 0.0, -6.0, -12.0, Vector3(0, 0.3, 2.8)],
		["far", 0.0, 0.0, 0.0, 4.0, -6.0, Vector3(-5.0, 1.2, 13.0)],
	]
	for s in shots:
		dog.speed = s[1]
		dog._sit = s[2]
		dog._neck_t = s[4]
		dog._head_t = s[5]
		dog._look_t = 0.0
		for i in 90:
			dog._jaw = s[3]
			dog._animate(1.0 / 60.0)
		var cp: Vector3 = c + (s[6] as Vector3)
		cp.y = maxf(cp.y, d.height(cp.x, cp.z) + 0.25)
		_look(cp, c + Vector3(-0.05, -0.02 if s[0] != "head" else 0.25, 0))
		cam.fov = 50.0 if s[0] != "far" else 40.0
		await _wait(3)
		await _shot("dog_" + s[0])
	# a bull at bay: the dog loose and circling it, barking
	var bull: Moose = null
	for m in G.herd.moose:
		if m.kind == "bull":
			bull = m
			break
	var bpos := spot + Vector3(-14.0, 0, 0)
	bull.position = Vector3(bpos.x, d.height(bpos.x, bpos.z), bpos.z)
	bull.heading = -PI * 0.5
	bull.awareness = 0.0
	dog.position = spot
	dog.active = true
	dog.target = bull
	bull.meet_dog(dog.global_position)
	bull._set_state(Moose.State.BAYED)
	bull._bay_len = 999.0
	dog._enter(Dog.S.BAY)
	dog._bay_ang = dog._angle_from(bull.global_position)
	for k in 3:
		await _secs(1.6)
		# from behind the dog, low, the bull beyond it
		var back := (dog.global_position - bull.global_position)
		back.y = 0.0
		back = back.normalized()
		var cp2 := dog.global_position + back * 3.6 + back.cross(Vector3.UP) * 1.4
		cp2.y = d.height(cp2.x, cp2.z) + 0.95
		_look(cp2, bull.global_position + Vector3(0, 1.1, 0))
		cam.fov = 40.0
		await _wait(2)
		await _shot("dog_bayshow_%d" % k)
	cam.fov = 75.0

## The dog in a real hunt (needs --allgear; the wind is fixed with --wind=<from>,<m/s>):
## let loose it should find the moose upwind, bay or follow it, show on the compass and
## the map, guard the kill, come back when whistled in, and a shot past it is a fault.
func _test_dog() -> void:
	main.start_hunt()
	var pl: Player = G.player
	var dog: Dog = G.dog
	main.hunt["time_left"] = main.hunt["duration"] * 0.6
	await _wait(30)
	var d: TerrainData = G.terrain
	var spot := _flat_spot(float(G.args.get("x", "-60")), float(G.args.get("z", "200")))
	# a wind that puts land 170 m upwind of the hunter
	var bull: Moose = null
	for cand in G.herd.moose:
		if cand.kind == "bull":
			bull = cand
			break
	var up := Vector2.ZERO
	var target_p := Vector3.ZERO
	for i in 16:
		var from_b := fposmod(float(G.args.get("windfrom", "250")) + i * 22.5, 360.0)
		G.wind._set_from(from_b, 4.0)
		G.wind._apply()
		up = -G.wind.dir
		target_p = spot + Vector3(up.x, 0, up.y) * 170.0
		if d.height(target_p.x, target_p.z) > 1.0 and d.slope(target_p.x, target_p.z) < 0.25 and Vector2(target_p.x, target_p.z).length() < 360.0:
			break
	print("[dog] wind from %s (%.0f deg) %.1f m/s - %s; hunter at (%.0f, %.0f), bull at (%.0f, %.0f)" % [G.wind.from_name(), G.wind.from_bearing(), G.wind.speed, G.wind.describe(), spot.x, spot.z, target_p.x, target_p.z])
	for m in G.herd.moose:
		if m != bull:
			m.position = Vector3(-spot.x, d.height(-spot.x, -spot.z), -spot.z)
			m._set_state(Moose.State.GRAZE)
			m._graze_len = 9999.0
	bull.position = Vector3(target_p.x, d.height(target_p.x, target_p.z), target_p.z)
	bull.awareness = 0.0
	bull._set_state(Moose.State.GRAZE)
	bull._graze_len = 9999.0
	pl.global_position = Vector3(spot.x, d.height(spot.x, spot.z), spot.z)
	pl.yaw = atan2(-up.x, -up.y)
	dog.position = pl.global_position + Vector3(-1, 0, 1)
	await _secs(2.0)
	print("[dog] at start: %s, %.0f m from the bull" % [dog.status(), dog.global_position.distance_to(bull.global_position)])
	await _tap("dog")
	print("[dog] released: %s" % dog.status())
	Engine.time_scale = 3.0
	var last := ""
	var t := 0.0
	while t < 150.0:
		await _secs(0.5 / 3.0)
		t += 0.5
		var line := "%s / bull %s" % [dog.status(), Moose.State.keys()[bull.state]]
		if line != last or fmod(t, 10.0) < 0.01:
			last = line
			var dp := dog.global_position
			print("[dog] t=%5.1f  %s  dog-bull %.0f m  dog-hunter %.0f m  at (%.0f, %.0f) h %.1f speed %.1f" % [t, line, dp.distance_to(bull.global_position), dp.distance_to(pl.global_position), dp.x, dp.z, d.height(dp.x, dp.z), dog.speed])
		if dog.state == Dog.S.BAY and dog.state_t > 3.0:
			break
	Engine.time_scale = 1.0
	if dog.state != Dog.S.BAY:
		print("[dog] FAIL: no bay after %.0f s (%s)" % [t, dog.status()])
	var bp := bull.global_position
	var mid := (bp + dog.global_position) * 0.5
	# a camera 22 m off to the side with nothing in the way
	var base_a := atan2((dog.global_position - bp).x, (dog.global_position - bp).z) + PI * 0.5
	var cp := mid
	for k in 48:
		var a := base_a + 0.13 * ceilf(k / 2.0) * (1.0 if k % 2 == 0 else -1.0)
		cp = mid + Vector3(sin(a), 0, cos(a)) * 22.0
		cp.y = d.height(cp.x, cp.z) + 1.6
		var tgt := mid + Vector3(0, 0.9, 0)
		if d.height(cp.x, cp.z) > 0.0 and d.line_clear(cp, tgt) and G.flora.ray(cp, tgt).is_empty() and G.flora.ray(cp, bp + Vector3(0, 1.4, 0)).is_empty():
			break
	main.hud.visible = false
	_look(cp, mid + Vector3(0, 0.9, 0))
	cam.fov = 32.0
	await _wait(10)
	await _shot("dog_bay")
	await _secs(0.4)
	await _shot("dog_bay2")
	cam.fov = 75.0
	main.hud.visible = true
	# the hunter sneaks up downwind to 75 m: the bark covers him, the wind is right
	var dn: Vector2 = G.wind.dir
	# a stand downwind, 65-85 m off, with a clear line to the bull's chest
	var hp := bp + Vector3(dn.x, 0, dn.y) * 75.0
	var vit := bp + Vector3(0, 1.42 * bull.size, 0)
	for k in 60:
		var a := atan2(dn.y, dn.x) + 0.1 * ceilf(k / 2.0) * (1.0 if k % 2 == 0 else -1.0)
		var r := 75.0 + (k % 3 - 1) * 10.0
		var q := bp + Vector3(cos(a), 0, sin(a)) * r
		q.y = d.height(q.x, q.z)
		var eye := q + Vector3(0, 1.1, 0)
		if q.y > 0.3 and d.line_clear(eye, vit) and G.flora.ray(eye, vit).is_empty() and G.flora.avoid_vector(q, 2.0).length() < 0.1:
			hp = q
			break
	pl.global_position = Vector3(hp.x, d.height(hp.x, hp.z), hp.z)
	_hold("crouch")
	await _secs(6.0)
	print("[dog] hunter 75 m downwind for 6 s: bull %s awareness %.2f" % [Moose.State.keys()[bull.state], bull.awareness])
	pl.cam.make_current()
	_aim_player_at(bull.centre())
	main.hud.visible = true
	await _wait(10)
	await _shot("dog_hud")
	main.hud.toggle_map()
	await _wait(4)
	await _shot("dog_map")
	main.hud.toggle_map()
	# the shot, when the dog is well clear of the line
	for i in 40:
		var to_b := bull.centre() - pl.cam.global_position
		if not dog.near_segment(pl.cam.global_position, bull.centre() + to_b.normalized() * 3.0, 4.0):
			break
		await _secs(0.25)
	var aim := bull.global_position + Vector3(0, 1.42 * bull.size, 0) + bull.forward() * 0.47 * bull.size
	var from := pl.cam.global_position
	G.ballistics.fire(from, (aim - from).normalized(), WeaponDB.get_weapon("varg308"), "varg308")
	await _secs(5.0)
	print("[dog] after the shot: bull dead=%s hits=%d last=%s | dog %s | score %d" % [bull.dead, bull.hits, bull.last_hit.get("zone", "-"), dog.status(), main.hunt["score"]])
	if bull.dead:
		var gp := dog.global_position + Vector3(4.0, 0, 5.0)
		gp.y = d.height(gp.x, gp.z) + 1.6
		_look(gp, dog.global_position + Vector3(0, 0.5, 0))
		await _wait(6)
		await _shot("dog_guard")
		var np := bull.global_position + Vector3(dn.x, 0, dn.y) * 6.0
		pl.global_position = Vector3(np.x, d.height(np.x, np.z), np.z)
		await _secs(2.0)
		print("[dog] hunter at the kill: %s" % dog.status())
	_release("crouch")
	# whistle in from a search
	await _secs(2.0)
	await _tap("dog")
	await _secs(4.0)
	print("[dog] loose again: %s" % dog.status())
	await _tap("dog")
	Engine.time_scale = 3.0
	await _secs(12.0 / 3.0)
	Engine.time_scale = 1.0
	print("[dog] whistled in: %s, %.0f m from the hunter" % [dog.status(), dog.global_position.distance_to(pl.global_position)])
	# a shot past the dog
	main.hunt["score"] = int(main.hunt["score"]) + 1000
	var score0: int = main.hunt["score"]
	var dc := dog.centre()
	var muzzle := pl.cam.global_position
	G.ballistics.fire(muzzle, (dc + Vector3(0, 0.25, 0) - muzzle).normalized(), WeaponDB.get_weapon("varg308"), "varg308")
	await _secs(0.5)
	print("[dog] shot past the dog: score %d -> %d, dog %s, message '%s'" % [score0, main.hunt["score"], dog.status(), main.hud._msg.text])

## Scent: with a fixed wind a still, unseen hunter upwind of a grazing moose is smelled
## and it leaves; downwind, across the wind or far beyond reach it grazes on.
func _test_scent() -> void:
	main.start_hunt()
	var pl: Player = G.player
	main.hunt["time_left"] = main.hunt["duration"] * 0.6
	await _wait(30)
	var d: TerrainData = G.terrain
	var spot := _flat_spot(float(G.args.get("x", "-60")), float(G.args.get("z", "200")))
	var cow: Moose = null
	for m in G.herd.moose:
		if m.kind == "cow" and cow == null:
			cow = m
		else:
			m.position = Vector3(-spot.x, d.height(-spot.x, -spot.z), -spot.z)
	var mps := float(G.args.get("mps", "4.0"))
	var cases := []
	for i in 16:
		G.wind._set_from(fposmod(250.0 + i * 22.5, 360.0), mps)
		G.wind._apply()
		var w := Vector3(G.wind.dir.x, 0, G.wind.dir.y)
		var across := w.cross(Vector3.UP)
		cases = [["upwind", -w * 110.0], ["upwind_near", -w * 45.0], ["downwind", w * 110.0], ["across", across * 110.0], ["upwind_far", -w * 250.0]]
		var ok := true
		for cs in cases:
			var p: Vector3 = spot + (cs[1] as Vector3)
			if d.height(p.x, p.z) < 0.8:
				ok = false
		if ok:
			break
	print("[scent] wind from %s %.1f m/s (%s)" % [G.wind.from_name(), G.wind.speed, G.wind.describe()])
	Engine.time_scale = 2.0
	for cs in cases:
		cow.position = Vector3(spot.x, d.height(spot.x, spot.z), spot.z)
		cow.awareness = 0.0
		cow.speed = 0.0
		cow._set_state(Moose.State.GRAZE)
		cow._graze_len = 9999.0
		cow._peek_next = 9999.0
		var p: Vector3 = spot + (cs[1] as Vector3)
		pl.global_position = Vector3(p.x, d.height(p.x, p.z), p.z)
		pl.vel = Vector3.ZERO
		var away := p - spot
		pl.yaw = atan2(away.x, away.z)     # looking away from the moose
		var peak := 0.0
		var t := 0.0
		var fled_at := -1.0
		while t < 20.0:
			await _secs(0.25 / 2.0)
			t += 0.25
			peak = maxf(peak, cow.awareness)
			if cow.state == Moose.State.FLEE and fled_at < 0.0:
				fled_at = t
		var smell: float = G.wind.scent(pl.global_position + Vector3(0, 1.2, 0), cow.head_pos())
		print("[scent] %-12s %4.0f m  smell %.2f  peak awareness %.2f  %s" % [cs[0], (cs[1] as Vector3).length(), smell, peak, ("FLED after %.1f s" % fled_at) if fled_at >= 0.0 else "grazed on"])
	Engine.time_scale = 1.0
