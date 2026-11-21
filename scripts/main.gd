extends Node
## Game flow: load the world, run the menu, a hunting day, and the summary.

enum Mode { LOADING, MENU, HUNT, SUMMARY }

var mode := Mode.LOADING
var world: World
var player: Player
var herd: Herd
var fx: Effects
var tracks: Tracks
var ballistics: Ballistics
var ambience: Ambience
var wind: Wind
var dog: Dog
var hud: Hud
var menus: Menus
var menu_cam: Camera3D
var hunt := {}
var _slow_until := 0
var _menu_t := 0.0
var _ui: CanvasLayer
var _dyn_t := 0.0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	G.main = self
	get_tree().auto_accept_quit = true
	if G.args.has("check"):
		_check_scripts()
		return
	_ui = CanvasLayer.new()
	_ui.layer = 10
	add_child(_ui)
	menus = Menus.new()
	menus.main = self
	_ui.add_child(menus)
	await get_tree().process_frame

	world = World.new()
	world.name = "World"
	world.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(world)
	world.progress.connect(menus.set_progress)
	await world.build(int(G.args.get("seed", "1905")))

	wind = _add(Wind.new(), "Wind")
	fx = _add(Effects.new(), "Effects")
	G.fx = fx
	tracks = _add(Tracks.new(), "Tracks")
	ballistics = _add(Ballistics.new(), "Ballistics")
	G.ballistics = ballistics
	herd = _add(Herd.new(), "Herd")
	player = _add(Player.new(), "Player")
	G.player = player
	player.message.connect(func(text, seconds): hud.show_message(text, seconds))
	dog = _add(Dog.new(), "Dog")
	_add(NatureFx.new(), "NatureFx")
	ambience = Ambience.new()
	ambience.name = "Ambience"
	add_child(ambience)
	menu_cam = Camera3D.new()
	menu_cam.fov = 55.0
	menu_cam.near = 0.2
	menu_cam.far = 3600.0
	add_child(menu_cam)
	hud = Hud.new()
	hud.visible = false
	hud.process_mode = Node.PROCESS_MODE_PAUSABLE
	_ui.add_child(hud)
	_ui.move_child(hud, 0)
	menus.set_progress(0.99, "Sharpening the knife")
	await get_tree().process_frame
	hud.set_map_image(world.make_map_image())
	player.weapon.preload_models(WeaponDB.ORDER)
	player.weapon.equip(SaveGame.equipped, true)
	fx.prewarm(world.data.cabin_pos + Vector3(0, -30, 0))
	herd.populate()
	to_menu()
	if G.test_mode != "":
		var t: Node = load("res://scripts/dev/autotest.gd").new()
		t.name = "AutoTest"
		add_child(t)
	elif G.args.has("hunt"):
		start_hunt()
		if G.args.has("rounds"):
			player.weapon.loaded[player.weapon.id] = int(G.args["rounds"])
	if G.args.has("quitafter"):
		await get_tree().create_timer(float(G.args["quitafter"]), true, false, true).timeout
		print("[run] fps=%d mode=%d display=%s scale=%.2f" % [Engine.get_frames_per_second(), mode, DisplayServer.get_name(), get_viewport().scaling_3d_scale])
		get_tree().quit()

func _add(node: Node, node_name: String) -> Node:
	node.name = node_name
	node.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(node)
	return node

# ------------------------------------------------------------------- flow
func to_menu() -> void:
	mode = Mode.MENU
	get_tree().paused = false
	Engine.time_scale = 1.0
	AudioServer.playback_speed_scale = 1.0
	player.active = false
	player.visible = false
	herd.active = false
	dog.end_hunt()
	hud.visible = false
	ambience.music_on = true
	ambience.in_hunt = false
	world.sky.set_time(0.085, true)
	world.structures.update_lights(twilight_at(0.085))
	menu_cam.make_current()
	_place_menu_cam(0.0)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	menus.show_screen("main")

func start_hunt() -> void:
	get_tree().paused = false
	Engine.time_scale = 1.0
	AudioServer.playback_speed_scale = 1.0
	tracks.clear()
	herd.populate(int(G.args.get("herdseed", "0")))
	herd.active = true
	wind.new_day(int(G.args.get("windseed", "0")))
	var minutes: int = int(G.args.get("minutes", str(Settings.get_v("hunt_minutes"))))
	hunt = {
		"score": 0, "kills": [], "shots": 0, "hits": 0, "longest": 0.0, "best": 0,
		"duration": minutes * 60.0, "time_left": minutes * 60.0,
	}
	world.sky.set_time(0.0, true)
	player.visible = true
	player.spawn_at(world.data.spawn_pos, world.data.spawn_yaw)
	player.active = true
	if SaveGame.owns_gear("dog"):
		dog.begin_hunt(world.data.spawn_pos + Basis(Vector3.UP, player.yaw) * Vector3(-0.9, 0, 1.3), player.yaw)
	else:
		dog.end_hunt()
	player.cam.make_current()
	player.weapon.loaded.clear()
	if player.weapon.id != SaveGame.equipped:
		player.weapon.equip(SaveGame.equipped, true)
	player.weapon.reset_for_hunt()
	hud.visible = true
	hud.reset()
	ambience.music_on = false
	ambience.in_hunt = true
	menus.show_screen("")
	mode = Mode.HUNT
	if G.test_mode == "":
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if int(SaveGame.stats["hunts"]) == 0:
		hud.show_message("Right mouse to aim, left to fire.  Ctrl crouches.  M opens the map, Esc lists all keys.", 9.0)
	elif SaveGame.weapons.size() < 2 and SaveGame.gear.is_empty() and SaveGame.wallet >= 800:
		hud.show_message("You have %s kr unspent - rifles, binoculars and the moose call are bought under Gear in the main menu." % G.fmt_int(SaveGame.wallet), 8.0)
	else:
		hud.show_message("Dawn over Moose Country. Good hunting.", 5.0)

func pause() -> void:
	if mode != Mode.HUNT or get_tree().paused:
		return
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	hud.show_message("", 0.0)     # the frozen HUD would leave it showing through the menu
	menus.show_screen("pause")

func resume() -> void:
	if mode != Mode.HUNT:
		return
	get_tree().paused = false
	menus.show_screen("")
	if G.test_mode == "":
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func end_hunt(early := false) -> void:
	if mode != Mode.HUNT:
		return
	mode = Mode.SUMMARY
	get_tree().paused = false
	Engine.time_scale = 1.0
	AudioServer.playback_speed_scale = 1.0
	player.active = false
	player.visible = false
	herd.active = false
	dog.end_hunt()
	hud.visible = false
	ambience.music_on = true
	ambience.in_hunt = false
	var kills: Array = hunt["kills"]
	var rank := SaveGame.submit_hunt(int(hunt["score"]), kills.size(), float(hunt["longest"]), int(hunt["best"]), int(hunt["shots"]), int(hunt["hits"]))
	menu_cam.make_current()
	_place_menu_cam(0.0)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	menus.show_summary(hunt, rank, early)

func quit_game() -> void:
	get_tree().quit()

## How dark it is at time of day `k` (0 dawn .. 1 dusk): 1 in deep twilight, 0 by day.
static func twilight_at(k: float) -> float:
	return clampf(1.0 - sin(PI * clampf(k, 0.0, 1.0)) * 2.2, 0.0, 1.0)

## The menu looks back at the cabin from the end of the pier, the cabin in the
## right half of the picture (the menu itself sits on the left), drifting slowly.
func _place_menu_cam(t: float) -> void:
	var view: Array = world.structures.menu_view(t)
	menu_cam.global_position = view[0]
	menu_cam.look_at(view[1], Vector3.UP)
	if world.flora:
		world.flora.focus = view[0]

# ----------------------------------------------------------------- update
func _process(dt: float) -> void:
	if G.args.has("inputlog"):
		_ilog_state()
	if _slow_until > 0 and Time.get_ticks_msec() > _slow_until:
		_slow_until = 0
		Engine.time_scale = 1.0
		AudioServer.playback_speed_scale = 1.0
	if mode == Mode.MENU or mode == Mode.SUMMARY:
		_menu_t += dt
		_place_menu_cam(_menu_t)
		if mode == Mode.SUMMARY:
			world.sky.set_time(0.97)
			world.structures.update_lights(twilight_at(0.97))
	elif mode == Mode.HUNT and not get_tree().paused:
		_dyn_t += dt / maxf(Engine.time_scale, 0.05)
		if _dyn_t > 1.0:
			_dyn_t = 0.0
			var goal := 60.0
			if int(Settings.get_v("fps_limit")) > 0:
				goal = minf(goal, float(Settings.get_v("fps_limit")))
			if G.test_mode == "":
				Settings.tune_dynamic_resolution(Engine.get_frames_per_second(), goal)
		hunt["time_left"] = float(hunt["time_left"]) - dt
		var k: float = 1.0 - float(hunt["time_left"]) / float(hunt["duration"])
		world.sky.set_time(float(G.args.get("time", str(k))))
		world.structures.update_lights(twilight_at(k))
		if float(hunt["time_left"]) <= 0.0:
			end_hunt(false)
		elif float(hunt["time_left"]) < 60.0 and float(hunt["time_left"]) + dt >= 60.0:
			hud.show_message("The light is going. One minute left.", 4.0)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		match mode:
			Mode.HUNT:
				if hud.map_open():
					hud.toggle_map()
				elif get_tree().paused:
					if menus.current() == "settings":
						menus.show_screen("pause")
					else:
						resume()
				else:
					pause()
			Mode.MENU:
				if menus.current() != "main":
					Sfx.ui("ui_back")
					menus.show_screen("main")
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("map") and mode == Mode.HUNT and not get_tree().paused:
		hud.toggle_map()

func _notification(what: int) -> void:
	if G.args.has("inputlog"):
		if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_APPLICATION_FOCUS_IN:
			print("[focus] ", "in" if what == NOTIFICATION_APPLICATION_FOCUS_IN else "out")
		return
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and mode == Mode.HUNT and G.test_mode == "":
		pause()

## Dev aid (`-- --inputlog`): print every key event, the actions it maps to and
## what the game did with it.
var _ilog_last := ""

func _input(event: InputEvent) -> void:
	if not G.args.has("inputlog") or not (event is InputEventKey):
		return
	var k: InputEventKey = event
	if k.pressed and not k.echo and k.physical_keycode == KEY_F12:
		var shot := "%s/ilog_%d.png" % [G.out_dir if G.out_dir != "" else "user://", Time.get_ticks_msec()]
		get_viewport().get_texture().get_image().save_png(shot)
		print("[shot] ", shot)
		return
	if k.pressed and not k.echo and k.physical_keycode >= KEY_F1 and k.physical_keycode <= KEY_F9:
		# click the n-th visible menu button with a synthetic (but GUI-routed) mouse click
		var btns := menus.find_children("*", "Button", true, false).filter(func(b): return b.is_visible_in_tree())
		var i: int = k.physical_keycode - KEY_F1
		print("[buttons] ", btns.map(func(b): return b.text))
		if i < btns.size():
			var at: Vector2 = get_viewport().get_final_transform() * (btns[i].get_global_transform_with_canvas() * (btns[i].size * 0.5))
			var mm := InputEventMouseMotion.new()
			mm.position = at
			mm.global_position = at
			Input.parse_input_event(mm)
			for down in [true, false]:
				var mb := InputEventMouseButton.new()
				mb.button_index = MOUSE_BUTTON_LEFT
				mb.pressed = down
				mb.position = at
				mb.global_position = at
				Input.parse_input_event(mb)
			print("[click] ", btns[i].text, " at ", at)
		return
	var acts := []
	for a in InputMap.get_actions():
		if not String(a).begins_with("ui_") and k.is_action(a):
			acts.append(String(a))
	print("[key] %s%s phys=%s key=%s label=%s uni=%d mods=%d -> %s" % [
		"down" if k.pressed else "up", " echo" if k.echo else "",
		OS.get_keycode_string(k.physical_keycode), OS.get_keycode_string(k.keycode),
		OS.get_keycode_string(k.key_label), k.unicode, k.get_modifiers_mask(), acts])

func _ilog_state() -> void:
	if player == null or hud == null or menus == null:
		return
	var w := player.weapon
	var fo := get_viewport().gui_get_focus_owner()
	var line := "mode=%d paused=%s screen='%s' map=%s crouch=%s sprint=%s binoc=%s weapon=%s/%s rounds=%d focus=%s msg='%s'" % [
		mode, get_tree().paused, menus.current(), hud.map_open(), player.crouching, player.sprinting,
		player.binoc, w.id, w.state, w.rounds(), (fo.get_class() + ":" + (fo.text if fo is Button else String(fo.name))) if fo else "-",
		hud._msg.text if hud._msg_t > 0.0 else ""]
	if line != _ilog_last:
		_ilog_last = line
		print("[state] ", line)

# ------------------------------------------------------------ hunt events
func on_shot() -> void:
	if mode != Mode.HUNT:
		return
	hunt["shots"] = int(hunt["shots"]) + 1
	ambience.hush = 10.0

func on_hit() -> void:
	if mode != Mode.HUNT:
		return
	hunt["hits"] = int(hunt["hits"]) + 1
	hud.hit_marker()

func on_kill(m: Moose) -> void:
	if mode != Mode.HUNT:
		return
	var k: Dictionary = m.kill
	if k.is_empty() or not k.has("zone"):
		return
	var dist: float = k["dist"]
	var base: int = int(m.info["points"])
	var mult := 1.0
	match k["zone"]:
		"heart":
			mult = 1.6
		"brain":
			mult = 1.5
		"spine":
			mult = 1.35
		"lungs":
			mult = 1.3
		"neck":
			mult = 1.15
	var text: String = k["text"]
	if k.get("cause", "") == "bled out":
		mult = minf(mult, 0.8)
		text = "Tracked down"
	var points := int((base + dist * 1.6) * mult)
	var extras: Array = []
	if int(k.get("hits", 1)) == 1 and k.get("cause", "") == "":
		points += 100
		extras.append("one shot")
	if k.get("undisturbed", false):
		points += 80
		extras.append("unaware")
	if k.get("moving", false) and dist > 40.0:
		points += 120
		extras.append("on the run")
	points = int(round(points / 10.0)) * 10
	hunt["score"] = int(hunt["score"]) + points
	hunt["longest"] = maxf(float(hunt["longest"]), dist)
	hunt["best"] = maxi(int(hunt["best"]), points)
	var entry := {"title": m.info["title"], "text": text, "dist": dist, "points": points, "moose": m.id, "tagged": false}
	(hunt["kills"] as Array).append(entry)
	var sub := "%s   ·   %d m" % [text, int(round(dist))]
	if not extras.is_empty():
		sub += "   ·   " + ", ".join(extras)
	hud.show_kill(str(m.info["title"]).to_upper() + " DOWN", sub, points)
	Sfx.ui("kill", -3.0)
	if m.kind == "trophy":
		SaveGame.stats["trophies"] = int(SaveGame.stats["trophies"]) + 1
	if Settings.get_v("slowmo") and dist > 80.0 and k.get("cause", "") == "":
		Engine.time_scale = 0.3
		AudioServer.playback_speed_scale = 0.8
		_slow_until = Time.get_ticks_msec() + 1700

## A shot went close past the dog: points off, and the dog comes back to the hunter.
func dog_endangered() -> void:
	if mode != Mode.HUNT:
		return
	var cost := mini(250, int(hunt["score"]))
	hunt["score"] = int(hunt["score"]) - cost
	hud.show_message("That shot went close to %s%s. Never fire with the dog near the line of fire." % [Dog.NAME, (" (-%d)" % cost) if cost > 0 else ""], 6.0)
	Sfx.ui("ui_error", -4.0)

func tag_moose(m: Moose) -> void:
	if m.tagged or mode != Mode.HUNT:
		return
	m.tagged = true
	var bonus := 0
	for e in hunt["kills"]:
		if int(e["moose"]) == m.id:
			bonus = int(round(int(e["points"]) * 0.2 / 10.0)) * 10
			e["points"] = int(e["points"]) + bonus
			e["tagged"] = true
	if bonus <= 0:
		bonus = 50
	hunt["score"] = int(hunt["score"]) + bonus
	hud.show_bonus("Tagged   ·   %s, %d kg" % [m.info["title"], int(m.weight)], bonus)
	Sfx.ui("tag", -2.0)

## Distance to whatever is under the crosshair (rangefinder).
func range_probe() -> float:
	var cam := player.cam.global_transform
	var from := cam.origin
	var to := from - cam.basis.z * 900.0
	var best := -1.0
	var gh = world.data.ray(from, to)
	if gh != null:
		best = from.distance_to(gh)
	var md := herd.probe(from, to)
	if md > 0.0 and (best < 0.0 or md < best):
		best = md
	return best

# -------------------------------------------------------------------- dev
## `-- --check`: compile every script and shader, report, quit.
func _check_scripts() -> void:
	var bad := 0
	var files := _scan("res://scripts") + _scan("res://shaders")
	for path in files:
		var res = ResourceLoader.load(path)
		if res == null or (res is GDScript and not (res as GDScript).can_instantiate()):
			print("FAILED: ", path)
			bad += 1
	print("checked %d files, %d failed" % [files.size(), bad])
	get_tree().quit(1 if bad > 0 else 0)

func _scan(dir: String) -> Array:
	var out := []
	var d := DirAccess.open(dir)
	if d == null:
		return out
	for f in d.get_files():
		if f.ends_with(".gd") or f.ends_with(".gdshader"):
			out.append(dir + "/" + f)
	for sub in d.get_directories():
		out.append_array(_scan(dir + "/" + sub))
	return out
