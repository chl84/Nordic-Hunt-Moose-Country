class_name Menus
extends Control
## All menu screens: loading, main, gear, records, settings, pause, summary.

const TIPS := [
	"Crouch (Ctrl) to move quietly. A walking hunter is heard from 30 metres, a sprinting one from 60.",
	"Aim just behind the shoulder, a third of the way up the chest. Heart and lungs sit there.",
	"Hold Shift while aiming to steady your breath - for a few seconds.",
	"Scroll the mouse wheel in the scope to change magnification.",
	"The marks under the crosshair are hold-overs: each is labelled with its distance in metres.",
	"Moose drink and graze on the bogs around the lakes at dawn and dusk.",
	"Press E on hoof prints to read their age and direction. Q lights up tracks around you.",
	"A hit moose leaves blood. Follow the trail - it rarely goes far.",
	"Walk up to a fallen moose and press E to tag it for a bonus.",
	"Climb a hunting tower for a clear view over the bog and a steadier aim.",
	"Sound travels slower than your bullet: far-off moose are hit before they hear the shot.",
]

var main: Node
var _screen := ""
var _screens := {}
var _progress: ColorRect
var _progress_label: Label
var _wallet_labels: Array = []
var _gear_list: VBoxContainer
var _gear_detail: VBoxContainer
var _gear_sel := "varg308"
var _gear_is_weapon := true
var _settings_back := "main"
var _records_box: VBoxContainer
var _summary_box: VBoxContainer
var _keys_grid: GridContainer
var _settings_box: VBoxContainer
var _dim: ColorRect
var _best_label: Label
var _tip: Label

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = UiKit.theme()
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	process_mode = Node.PROCESS_MODE_ALWAYS
	_dim = ColorRect.new()
	_dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_dim.color = Color(0.02, 0.03, 0.035, 0.6)
	_dim.visible = false
	add_child(_dim)
	_build_loading()
	_build_main()
	_build_pause()
	_build_gear()
	_build_records()
	_build_settings()
	_build_summary()
	SaveGame.changed.connect(_refresh_wallet)
	show_screen("loading")

func current() -> String:
	return _screen

func show_screen(screen: String) -> void:
	_screen = screen
	for key in _screens:
		(_screens[key] as Control).visible = key == screen
	_dim.visible = screen in ["pause", "gear", "records", "settings", "summary"]
	mouse_filter = Control.MOUSE_FILTER_IGNORE if screen == "" else Control.MOUSE_FILTER_STOP
	match screen:
		"pause":
			_refresh_keys()
		"gear":
			_refresh_gear()
		"records":
			_refresh_records()
		"settings":
			_refresh_settings()
		"main":
			_refresh_wallet()
			_tip.text = TIPS[randi() % TIPS.size()]

func _full(screen: String) -> Control:
	var c := Control.new()
	c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	c.visible = false
	add_child(c)
	_screens[screen] = c
	return c

func _centered(screen: String, min_size: Vector2) -> VBoxContainer:
	var root := _full(screen)
	var cc := CenterContainer.new()
	cc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(cc)
	var p := UiKit.panel(UiKit.PANEL, 12, 30)
	p.custom_minimum_size = min_size
	cc.add_child(p)
	var v := UiKit.vbox(10)
	p.add_child(v)
	return v

func _title(text: String, sub := "") -> Control:
	var v := UiKit.vbox(0)
	v.add_child(UiKit.label(text, 34, UiKit.TEXT, true))
	if sub != "":
		v.add_child(UiKit.label(sub, 17, UiKit.DIM))
	v.add_child(UiKit.spacer(8))
	v.add_child(UiKit.rule())
	v.add_child(UiKit.spacer(6))
	return v

# ---------------------------------------------------------------- loading
func _build_loading() -> void:
	var root := _full("loading")
	var bg := ColorRect.new()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0.043, 0.055, 0.063)
	root.add_child(bg)
	var cc := CenterContainer.new()
	cc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(cc)
	var v := UiKit.vbox(6)
	v.custom_minimum_size = Vector2(520, 0)
	cc.add_child(v)
	var t := UiKit.label("NORDIC HUNT", 64, UiKit.TEXT, true)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(t)
	var s := UiKit.label("M O O S E   C O U N T R Y", 22, UiKit.ACCENT, true)
	s.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(s)
	v.add_child(UiKit.spacer(40))
	var track := ColorRect.new()
	track.color = Color(1, 1, 1, 0.12)
	track.custom_minimum_size = Vector2(520, 4)
	v.add_child(track)
	_progress = ColorRect.new()
	_progress.color = UiKit.ACCENT
	_progress.size = Vector2(0, 4)
	track.add_child(_progress)
	v.add_child(UiKit.spacer(6))
	_progress_label = UiKit.label("Waking up", 17, UiKit.DIM)
	_progress_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(_progress_label)

func set_progress(f: float, text: String) -> void:
	_progress.size = Vector2(520.0 * clampf(f, 0.0, 1.0), 4)
	_progress_label.text = text

# ------------------------------------------------------------------- main
func _build_main() -> void:
	var root := _full("main")
	var grad := Gradient.new()
	grad.set_color(0, Color(0.02, 0.03, 0.035, 0.9))
	grad.set_color(1, Color(0.02, 0.03, 0.035, 0.0))
	var gt := GradientTexture2D.new()
	gt.gradient = grad
	gt.fill_from = Vector2(0, 0)
	gt.fill_to = Vector2(1, 0)
	var shade := TextureRect.new()
	shade.texture = gt
	shade.anchor_right = 0.62
	shade.anchor_bottom = 1.0
	shade.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	shade.stretch_mode = TextureRect.STRETCH_SCALE
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(shade)
	var v := UiKit.vbox(4)
	v.anchor_bottom = 1.0
	v.offset_left = 90
	v.offset_top = 110
	v.offset_right = 620
	v.offset_bottom = -70
	root.add_child(v)
	v.add_child(UiKit.shadowed(UiKit.label("NORDIC HUNT", 76, UiKit.TEXT, true), 0.5))
	v.add_child(UiKit.shadowed(UiKit.label("M O O S E   C O U N T R Y", 25, UiKit.ACCENT, true), 0.5))
	v.add_child(UiKit.spacer(54))
	var start := UiKit.button("Start the hunt", func(): main.start_hunt(), 32)
	start.add_theme_font_override("font", UiKit.bold())
	v.add_child(start)
	v.add_child(UiKit.spacer(6))
	v.add_child(UiKit.button("Gear", func(): show_screen("gear"), 26))
	v.add_child(UiKit.button("Records", func(): show_screen("records"), 26))
	v.add_child(UiKit.button("Settings", func():
		_settings_back = "main"
		show_screen("settings"), 26))
	v.add_child(UiKit.button("Quit", func(): main.quit_game(), 26))
	v.add_child(UiKit.expander())
	var wl := UiKit.shadowed(UiKit.label("", 22, UiKit.TEXT, true))
	_wallet_labels.append(wl)
	v.add_child(wl)
	_best_label = UiKit.shadowed(UiKit.label("", 17, UiKit.DIM))
	v.add_child(_best_label)
	_tip = UiKit.shadowed(UiKit.label("", 17, UiKit.DIM))
	_tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_tip.anchor_left = 1.0
	_tip.anchor_right = 1.0
	_tip.anchor_top = 1.0
	_tip.anchor_bottom = 1.0
	_tip.offset_left = -560
	_tip.offset_right = -70
	_tip.offset_top = -130
	_tip.offset_bottom = -60
	_tip.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_tip.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	root.add_child(_tip)

func _refresh_wallet() -> void:
	for l in _wallet_labels:
		(l as Label).text = "%s kr" % G.fmt_int(SaveGame.wallet)
	if _best_label:
		var best := SaveGame.best_score()
		_best_label.text = "Best hunt  %s" % G.fmt_int(best) if best > 0 else "No hunts logged yet - the season is open"
	if _screen == "gear":
		_refresh_gear()

# ------------------------------------------------------------------ pause
func _build_pause() -> void:
	var v := _centered("pause", Vector2(430, 0))
	v.add_child(_title("Paused"))
	v.add_child(UiKit.button("Resume", func(): main.resume()))
	v.add_child(UiKit.button("Settings", func():
		_settings_back = "pause"
		show_screen("settings")))
	v.add_child(UiKit.button("End the hunt", func(): main.end_hunt(true)))
	v.add_child(UiKit.button("Quit to desktop", func(): main.quit_game()))
	v.add_child(UiKit.spacer(10))
	v.add_child(UiKit.rule())
	v.add_child(UiKit.spacer(4))
	_keys_grid = GridContainer.new()
	_keys_grid.columns = 2
	_keys_grid.add_theme_constant_override("h_separation", 26)
	_keys_grid.add_theme_constant_override("v_separation", 3)
	v.add_child(_keys_grid)

## The key list on the pause screen. Keys that need a rifle or a piece of
## equipment you have not bought yet are greyed out and say so.
func _refresh_keys() -> void:
	for c in _keys_grid.get_children():
		c.queue_free()
	var rifles := 0
	for w in WeaponDB.ORDER:
		if SaveGame.owns_weapon(w):
			rifles += 1
	var more := rifles > 1
	var keys := [
		["WASD", "Move", true], ["Shift", "Sprint / steady aim", true], ["Ctrl", "Crouch", true], ["Space", "Jump", true],
		["Mouse L / R", "Fire / aim", true],
		["Wheel", "Scope zoom / next rifle" if more else "Scope zoom while aiming", true],
		["R", "Reload", true],
		["1-%d" % WeaponDB.ORDER.size(), "Rifles you own (%d of %d)" % [rifles, WeaponDB.ORDER.size()] if more else "Rifles - buy a second one in Gear", more],
		["E", "Interact", true], ["Q", "Reveal tracks", true],
		["B", "Binoculars (hold)" if SaveGame.owns_gear("binoculars") else "Binoculars - buy in Gear", SaveGame.owns_gear("binoculars")],
		["V", "Moose call" if SaveGame.owns_gear("call") else "Moose call - buy in Gear", SaveGame.owns_gear("call")],
		["M / Tab", "Map", true],
	]
	for k in keys:
		var on: bool = k[2]
		var key_label := UiKit.label(k[0], 16, UiKit.ACCENT if on else UiKit.DIM, true)
		var what := UiKit.label(k[1], 16, UiKit.DIM)
		if not on:
			key_label.modulate.a = 0.55
			what.modulate.a = 0.7
		_keys_grid.add_child(key_label)
		_keys_grid.add_child(what)

# ------------------------------------------------------------------- gear
func _build_gear() -> void:
	var v := _centered("gear", Vector2(1180, 830))
	var head := UiKit.hbox()
	head.add_child(_title("Gear", "Spend what the hunt earns. Rifles and equipment stay yours."))
	head.add_child(UiKit.expander())
	var wl := UiKit.label("", 28, UiKit.ACCENT, true)
	_wallet_labels.append(wl)
	head.add_child(wl)
	v.add_child(head)
	var body := UiKit.hbox(26)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(body)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(430, 630)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body.add_child(scroll)
	_gear_list = UiKit.vbox(4)
	_gear_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_gear_list)
	var right := UiKit.panel(UiKit.PANEL_LIGHT, 10, 26)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(right)
	_gear_detail = UiKit.vbox(10)
	right.add_child(_gear_detail)
	v.add_child(UiKit.button("Back", func(): show_screen("main")))

func _refresh_gear() -> void:
	for c in _gear_list.get_children():
		c.queue_free()
	_gear_list.add_child(UiKit.label("RIFLES", 15, UiKit.DIM, true))
	for id in WeaponDB.ORDER:
		_gear_list.add_child(_gear_row(id, true))
	_gear_list.add_child(UiKit.spacer(10))
	_gear_list.add_child(UiKit.label("EQUIPMENT", 15, UiKit.DIM, true))
	for id in WeaponDB.GEAR_ORDER:
		_gear_list.add_child(_gear_row(id, false))
	_refresh_gear_detail()

func _gear_row(id: String, is_weapon: bool) -> Button:
	var d: Dictionary = WeaponDB.get_weapon(id) if is_weapon else WeaponDB.GEAR[id]
	var owned := SaveGame.owns_weapon(id) if is_weapon else SaveGame.owns_gear(id)
	var status := ""
	if is_weapon and SaveGame.equipped == id:
		status = "EQUIPPED"
	elif owned:
		status = "OWNED"
	else:
		status = "%s kr" % G.fmt_int(int(d["cost"]))
	var b := UiKit.button("", func():
		_gear_sel = id
		_gear_is_weapon = is_weapon
		_refresh_gear(), 21)
	b.custom_minimum_size = Vector2(0, 54)
	var h := UiKit.hbox()
	h.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	h.offset_left = 18
	h.offset_right = -14
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var selected := _gear_sel == id and _gear_is_weapon == is_weapon
	var name_l := UiKit.label(d["name"], 21, UiKit.ACCENT if selected else UiKit.TEXT, selected)
	name_l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(name_l)
	h.add_child(UiKit.expander())
	var st := UiKit.label(status, 15, UiKit.GOOD if status == "EQUIPPED" else (UiKit.DIM if owned else (UiKit.TEXT if SaveGame.wallet >= int(d["cost"]) else UiKit.FAINT)), true)
	st.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(st)
	b.add_child(h)
	return b

func _refresh_gear_detail() -> void:
	for c in _gear_detail.get_children():
		c.queue_free()
	var id := _gear_sel
	if _gear_is_weapon:
		var w: Dictionary = WeaponDB.get_weapon(id)
		_gear_detail.add_child(UiKit.label(w["name"], 34, UiKit.TEXT, true))
		_gear_detail.add_child(UiKit.label(str(w["kind"]).to_upper(), 15, UiKit.ACCENT, true))
		var desc := UiKit.label(w["desc"], 18, UiKit.DIM)
		desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		desc.custom_minimum_size = Vector2(560, 0)
		_gear_detail.add_child(desc)
		_gear_detail.add_child(UiKit.spacer(8))
		var bars: Dictionary = WeaponDB.bars(id)
		for key in bars:
			var row := UiKit.hbox(14)
			var kl := UiKit.label(key, 17, UiKit.DIM)
			kl.custom_minimum_size = Vector2(110, 0)
			row.add_child(kl)
			row.add_child(UiKit.bar(bars[key], UiKit.ACCENT, 320.0))
			_gear_detail.add_child(row)
		_gear_detail.add_child(UiKit.spacer(8))
		var zs: Array = w["zooms"]
		var sight := "Open sights"
		if w["sight"] == "scope":
			sight = "%s-%sx scope" % [str(zs[0]).trim_suffix(".0"), str(zs[-1]).trim_suffix(".0")]
		elif w["sight"] == "reddot":
			sight = "Red dot sight"
		var facts := "%d rounds   ·   %d m/s   ·   zeroed at %d m   ·   %s" % [int(w["mag"]), int(w["velocity"]), int(w["zero"]), sight]
		_gear_detail.add_child(UiKit.label(facts, 16, UiKit.DIM))
		_gear_detail.add_child(UiKit.expander())
		var row2 := UiKit.hbox(14)
		if SaveGame.owns_weapon(id):
			if SaveGame.equipped == id:
				row2.add_child(UiKit.label("This is the rifle you carry first.", 18, UiKit.GOOD))
			else:
				row2.add_child(UiKit.cta("Equip", func():
					SaveGame.equip(id)
					_refresh_gear()))
			row2.add_child(UiKit.label("All rifles you own come along - switch with 1-5.", 15, UiKit.FAINT))
		else:
			_buy_row(row2, int(w["cost"]), func(): return SaveGame.buy_weapon(id, int(w["cost"])))
		_gear_detail.add_child(row2)
	else:
		var g: Dictionary = WeaponDB.GEAR[id]
		_gear_detail.add_child(UiKit.label(g["name"], 34, UiKit.TEXT, true))
		_gear_detail.add_child(UiKit.label("EQUIPMENT", 15, UiKit.ACCENT, true))
		var desc := UiKit.label(g["desc"], 19, UiKit.DIM)
		desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		desc.custom_minimum_size = Vector2(560, 0)
		_gear_detail.add_child(desc)
		_gear_detail.add_child(UiKit.expander())
		var row2 := UiKit.hbox(14)
		if SaveGame.owns_gear(id):
			row2.add_child(UiKit.label("In your pack.", 18, UiKit.GOOD))
		else:
			_buy_row(row2, int(g["cost"]), func(): return SaveGame.buy_gear(id, int(g["cost"])))
		_gear_detail.add_child(row2)

func _buy_row(row: HBoxContainer, cost: int, buy: Callable) -> void:
	var can := SaveGame.wallet >= cost
	var b := UiKit.cta("Buy for %s kr" % G.fmt_int(cost), func():
		if buy.call():
			Sfx.ui("ui_buy")
		else:
			Sfx.ui("ui_error")
		_refresh_gear())
	b.disabled = not can
	row.add_child(b)
	if not can:
		row.add_child(UiKit.label("%s kr short" % G.fmt_int(cost - SaveGame.wallet), 17, UiKit.BAD))

# ---------------------------------------------------------------- records
func _build_records() -> void:
	var v := _centered("records", Vector2(860, 700))
	v.add_child(_title("Records", "Your ten best hunts in Moose Country"))
	_records_box = UiKit.vbox(4)
	_records_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(_records_box)
	v.add_child(UiKit.button("Back", func(): show_screen("main")))

func _refresh_records() -> void:
	for c in _records_box.get_children():
		c.queue_free()
	if SaveGame.highscores.is_empty():
		_records_box.add_child(UiKit.spacer(30))
		_records_box.add_child(UiKit.label("Nothing here yet. Bring home a moose.", 20, UiKit.DIM))
	var cols := [60, 170, 130, 190, 150]
	_records_box.add_child(_record_row(["#", "SCORE", "MOOSE", "LONGEST SHOT", "DATE"], cols, UiKit.FAINT, 14, true))
	var i := 1
	for e in SaveGame.highscores:
		var col := UiKit.ACCENT if i == 1 else UiKit.TEXT
		_records_box.add_child(_record_row([str(i), G.fmt_int(int(e["score"])), str(int(e["moose"])), "%d m" % int(e["longest"]), str(e["date"])], cols, col, 20, i == 1))
		i += 1
	_records_box.add_child(UiKit.expander())
	_records_box.add_child(UiKit.rule())
	var st: Dictionary = SaveGame.stats
	var acc := 0
	if int(st["shots"]) > 0:
		acc = int(round(100.0 * float(st["hits"]) / float(st["shots"])))
	var line := "Hunts %d   ·   Moose %d   ·   Accuracy %d%%   ·   Longest shot %d m   ·   Best single kill %s   ·   Earned %s kr" % [
		int(st["hunts"]), int(st["moose"]), acc, int(st["longest_shot"]), G.fmt_int(int(st["best_kill"])), G.fmt_int(int(st["total_earned"]))]
	var l := UiKit.label(line, 16, UiKit.DIM)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_records_box.add_child(l)

func _record_row(cells: Array, widths: Array, color: Color, size: int, is_bold: bool) -> HBoxContainer:
	var h := UiKit.hbox(0)
	for i in cells.size():
		var l := UiKit.label(cells[i], size, color, is_bold)
		l.custom_minimum_size = Vector2(widths[i], 30)
		h.add_child(l)
	return h

# --------------------------------------------------------------- settings
func _build_settings() -> void:
	var v := _centered("settings", Vector2(900, 800))
	v.add_child(_title("Settings"))
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(840, 590)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(scroll)
	_settings_box = UiKit.vbox(6)
	_settings_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_settings_box)
	var row := UiKit.hbox(10)
	row.add_child(UiKit.button("Back", func(): show_screen(_settings_back)))
	row.add_child(UiKit.expander())
	row.add_child(UiKit.button("Restore defaults", func():
		Settings.reset_defaults()
		_refresh_settings(), 19))
	v.add_child(row)

func _refresh_settings() -> void:
	for c in _settings_box.get_children():
		c.queue_free()
	var b := _settings_box
	_section(b, "GRAPHICS")
	_option(b, "Quality preset", Settings.PRESET_NAMES, int(Settings.get_v("preset")), func(i):
		if i < 4:
			Settings.apply_preset(i)
		else:
			Settings.set_v("preset", 4)
		_refresh_settings.call_deferred())
	_slider(b, "Render scale", "render_scale", 0.5, 1.0, 0.05, func(x): return "%d%%" % int(round(x * 100.0)), true)
	_toggle(b, "Dynamic resolution (hold 60 fps)", "dynamic_res")
	_option(b, "Anti-aliasing", ["Off", "MSAA 2x", "MSAA 4x"], int(Settings.get_v("msaa")), func(i): _custom("msaa", i))
	_option(b, "Shadows", ["Off", "Low", "Medium", "High"], int(Settings.get_v("shadows")), func(i): _custom("shadows", i))
	_option(b, "View distance", ["Near", "Medium", "Far"], int(Settings.get_v("view_distance")), func(i): _custom("view_distance", i))
	_option(b, "Tree detail", ["Low", "Medium", "High"], int(Settings.get_v("tree_detail")), func(i): _custom("tree_detail", i))
	_option(b, "Ground cover", ["Off", "Sparse", "Normal", "Dense"], int(Settings.get_v("grass")), func(i): _custom("grass", i))
	_option(b, "Water", ["Simple", "Full"], int(Settings.get_v("water_quality")), func(i): _custom("water_quality", i))
	_section(b, "DISPLAY")
	_toggle(b, "Fullscreen", "fullscreen")
	_toggle(b, "V-Sync", "vsync")
	_option(b, "Frame rate limit", ["Unlimited", "30", "60", "90", "120"], [0, 30, 60, 90, 120].find(int(Settings.get_v("fps_limit"))), func(i): Settings.set_v("fps_limit", [0, 30, 60, 90, 120][i]))
	_slider(b, "Field of view", "fov", 60.0, 100.0, 1.0, func(x): return "%d°" % int(x), false)
	_toggle(b, "Show frame rate", "show_fps")
	_section(b, "GAMEPLAY")
	_option(b, "Length of a hunting day", ["8 minutes", "12 minutes", "20 minutes", "30 minutes"], [8, 12, 20, 30].find(int(Settings.get_v("hunt_minutes"))), func(i): Settings.set_v("hunt_minutes", [8, 12, 20, 30][i]))
	_toggle(b, "Slow motion on long kills", "slowmo")
	_toggle(b, "Blood", "blood")
	_toggle(b, "Weapon sway", "sway")
	_section(b, "CONTROLS")
	_slider(b, "Mouse sensitivity", "sensitivity", 0.2, 3.0, 0.05, func(x): return "%.2f" % x, false)
	_slider(b, "Scope sensitivity", "scope_sensitivity", 0.2, 2.0, 0.05, func(x): return "%.2f" % x, false)
	_toggle(b, "Invert vertical look", "invert_y")
	_toggle(b, "Toggle aim (instead of hold)", "aim_toggle")
	_toggle(b, "Toggle crouch", "crouch_toggle")
	_section(b, "AUDIO")
	_slider(b, "Master volume", "vol_master", 0.0, 1.0, 0.05, func(x): return "%d%%" % int(round(x * 100.0)), false)
	_slider(b, "Effects", "vol_sfx", 0.0, 1.0, 0.05, func(x): return "%d%%" % int(round(x * 100.0)), false)
	_slider(b, "Nature", "vol_ambience", 0.0, 1.0, 0.05, func(x): return "%d%%" % int(round(x * 100.0)), false)
	_slider(b, "Music", "vol_music", 0.0, 1.0, 0.05, func(x): return "%d%%" % int(round(x * 100.0)), false)

func _custom(key: String, value) -> void:
	Settings.data["preset"] = 4
	Settings.set_v(key, value)
	_refresh_settings.call_deferred()

func _section(box: VBoxContainer, text: String) -> void:
	box.add_child(UiKit.spacer(10))
	box.add_child(UiKit.label(text, 15, UiKit.ACCENT, true))
	box.add_child(UiKit.rule())

func _row(box: VBoxContainer, text: String) -> HBoxContainer:
	var h := UiKit.hbox(12)
	h.custom_minimum_size = Vector2(0, 40)
	var l := UiKit.label(text, 19, UiKit.TEXT)
	l.custom_minimum_size = Vector2(360, 0)
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(l)
	box.add_child(h)
	return h

func _option(box: VBoxContainer, text: String, options: Array, selected: int, fn: Callable) -> void:
	var h := _row(box, text)
	var ob := OptionButton.new()
	ob.custom_minimum_size = Vector2(300, 36)
	ob.focus_mode = Control.FOCUS_NONE
	for o in options:
		ob.add_item(o)
	ob.select(clampi(selected, 0, options.size() - 1))
	ob.item_selected.connect(func(i):
		Sfx.ui("ui_click")
		fn.call(i))
	h.add_child(ob)

func _slider(box: VBoxContainer, text: String, key: String, lo: float, hi: float, step: float, fmt: Callable, custom: bool) -> void:
	var h := _row(box, text)
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.value = float(Settings.get_v(key))
	s.custom_minimum_size = Vector2(300, 28)
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	s.focus_mode = Control.FOCUS_NONE
	var val := UiKit.label(fmt.call(s.value), 18, UiKit.DIM)
	val.custom_minimum_size = Vector2(70, 0)
	val.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	s.value_changed.connect(func(x):
		val.text = fmt.call(x)
		if custom:
			Settings.data["preset"] = 4
		Settings.set_v(key, x))
	h.add_child(s)
	h.add_child(val)

func _toggle(box: VBoxContainer, text: String, key: String) -> void:
	var h := _row(box, text)
	var cb := CheckButton.new()
	cb.button_pressed = bool(Settings.get_v(key))
	cb.focus_mode = Control.FOCUS_NONE
	cb.toggled.connect(func(on):
		Sfx.ui("ui_click")
		Settings.set_v(key, on))
	h.add_child(cb)

# ---------------------------------------------------------------- summary
## What the wallet can buy right now, as one line for the summary screen.
func _shopping_hint() -> String:
	var names := []
	for w in WeaponDB.ORDER:
		if not SaveGame.owns_weapon(w) and SaveGame.wallet >= int(WeaponDB.DATA[w]["cost"]):
			names.append("the %s" % WeaponDB.DATA[w]["name"])
	for g in WeaponDB.GEAR_ORDER:
		if not SaveGame.owns_gear(g) and SaveGame.wallet >= int(WeaponDB.GEAR[g]["cost"]):
			names.append("the %s" % WeaponDB.GEAR[g]["name"])
	if names.is_empty():
		return ""
	var shown: Array = names.slice(0, 3)
	var text: String = str(shown[0])
	if shown.size() > 1:
		text = ", ".join(PackedStringArray(shown.slice(0, shown.size() - 1))) + " or " + str(shown[shown.size() - 1])
	return "You have %s kr - enough for %s. Rifles and equipment are bought under Gear in the main menu." % [G.fmt_int(SaveGame.wallet), text]

func _build_summary() -> void:
	var v := _centered("summary", Vector2(900, 0))
	_summary_box = v

func show_summary(hunt: Dictionary, rank: int, early: bool) -> void:
	for c in _summary_box.get_children():
		c.queue_free()
	var v := _summary_box
	var kills: Array = hunt.get("kills", [])
	var head := "The day is done" if not early else "Hunt called off"
	v.add_child(_title(head, "The sun sets over Moose Country" if not early else "You head back to the cabin"))
	var top := UiKit.hbox(40)
	var sc := UiKit.vbox(0)
	sc.add_child(UiKit.label("SCORE", 15, UiKit.DIM, true))
	sc.add_child(UiKit.label(G.fmt_int(int(hunt.get("score", 0))), 64, UiKit.ACCENT, true))
	top.add_child(sc)
	var facts := GridContainer.new()
	facts.columns = 2
	facts.add_theme_constant_override("h_separation", 24)
	facts.add_theme_constant_override("v_separation", 4)
	facts.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var shots := int(hunt.get("shots", 0))
	var hits := int(hunt.get("hits", 0))
	var rows := [
		["Moose taken", str(kills.size())],
		["Longest shot", "%d m" % int(hunt.get("longest", 0.0))],
		["Shots fired", "%d  (%d%% on target)" % [shots, int(round(100.0 * hits / maxf(shots, 1.0)))]],
		["Earned", "%s kr" % G.fmt_int(int(hunt.get("score", 0)))],
	]
	for r in rows:
		facts.add_child(UiKit.label(r[0], 18, UiKit.DIM))
		facts.add_child(UiKit.label(r[1], 18, UiKit.TEXT, true))
	top.add_child(facts)
	v.add_child(top)
	if rank == 1 and int(hunt.get("score", 0)) > 0:
		v.add_child(UiKit.label("New record - your best hunt yet!", 22, UiKit.GOOD, true))
	elif rank > 1:
		v.add_child(UiKit.label("That is number %d on your record board." % rank, 19, UiKit.GOOD))
	v.add_child(UiKit.spacer(6))
	v.add_child(UiKit.rule())
	if kills.is_empty():
		v.add_child(UiKit.label("No moose today. They heard you coming - try moving low and slow, and glass the bogs.", 18, UiKit.DIM))
	else:
		var scroll := ScrollContainer.new()
		scroll.custom_minimum_size = Vector2(820, minf(kills.size() * 36.0 + 8.0, 300.0))
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		var list := UiKit.vbox(2)
		list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		scroll.add_child(list)
		for k in kills:
			var h := UiKit.hbox(0)
			var cells := [[k["title"], 230, UiKit.TEXT, true], [k["text"], 190, UiKit.DIM, false], ["%d m" % int(k["dist"]), 100, UiKit.DIM, false],
				["tagged" if k.get("tagged", false) else "", 110, UiKit.GOOD, false], ["+" + G.fmt_int(int(k["points"])), 150, UiKit.ACCENT, true]]
			for cdef in cells:
				var l := UiKit.label(cdef[0], 19, cdef[2], cdef[3])
				l.custom_minimum_size = Vector2(cdef[1], 32)
				h.add_child(l)
			list.add_child(h)
		v.add_child(scroll)
	var shop := _shopping_hint()
	if shop != "":
		v.add_child(UiKit.spacer(4))
		var sl := UiKit.label(shop, 18, UiKit.GOOD)
		sl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		sl.custom_minimum_size = Vector2(820, 0)
		v.add_child(sl)
	v.add_child(UiKit.spacer(12))
	var row := UiKit.hbox(14)
	row.add_child(UiKit.cta("Back to the cabin", func(): main.to_menu()))
	row.add_child(UiKit.button("Hunt again", func(): main.start_hunt(), 22))
	if shop != "":
		row.add_child(UiKit.button("Gear", func():
			main.to_menu()
			show_screen("gear"), 22))
	v.add_child(row)
	show_screen("summary")
