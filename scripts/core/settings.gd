extends Node
## User settings: graphics, audio, controls. Persisted to user://settings.cfg.

signal changed

const PATH := "user://settings.cfg"

const DEFAULTS := {
	# display
	"fullscreen": true,
	"vsync": true,
	"fps_limit": 0,
	"show_fps": false,
	# graphics
	"preset": 1,            # 0 low, 1 medium, 2 high, 3 ultra, 4 custom
	"render_scale": 0.85,
	"dynamic_res": true,
	"msaa": 0,              # 0 off, 1 = 2x, 2 = 4x
	"shadows": 2,           # 0 off .. 3 high
	"view_distance": 1,     # 0 near .. 2 far
	"tree_detail": 1,       # 0 .. 2
	"grass": 2,             # 0 off .. 3 dense
	"water_quality": 1,     # 0 simple, 1 full
	"fov": 75.0,
	# gameplay
	"hunt_minutes": 12,
	"weather": 0,           # 0 a new weather every day, 1.. one kind (Weather.KINDS)
	"slowmo": true,
	"blood": true,
	"sway": true,
	# controls
	"sensitivity": 1.0,
	"scope_sensitivity": 1.0,
	"invert_y": false,
	"aim_toggle": false,
	"crouch_toggle": true,
	# audio
	"vol_master": 0.9,
	"vol_sfx": 1.0,
	"vol_ambience": 0.8,
	"vol_music": 0.6,
}

const PRESETS := [
	{"render_scale": 0.7, "msaa": 0, "shadows": 0, "view_distance": 0, "tree_detail": 0, "grass": 1, "water_quality": 0},
	{"render_scale": 0.85, "msaa": 0, "shadows": 2, "view_distance": 1, "tree_detail": 1, "grass": 2, "water_quality": 1},
	{"render_scale": 1.0, "msaa": 1, "shadows": 2, "view_distance": 2, "tree_detail": 2, "grass": 3, "water_quality": 1},
	{"render_scale": 1.0, "msaa": 2, "shadows": 3, "view_distance": 2, "tree_detail": 2, "grass": 3, "water_quality": 1},
]
const PRESET_NAMES := ["Low", "Medium", "High", "Ultra", "Custom"]

var data := {}
var dynamic_factor := 1.0     ## lowered at runtime when the frame rate sags

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	data = DEFAULTS.duplicate(true)
	_load()
	_setup_buses()
	_setup_input()
	apply.call_deferred()

func get_v(key: String):
	return data.get(key, DEFAULTS.get(key))

func set_v(key: String, value, emit := true) -> void:
	data[key] = value
	if emit:
		apply()

func apply_preset(index: int) -> void:
	data["preset"] = index
	if index >= 0 and index < PRESETS.size():
		for k in PRESETS[index]:
			data[k] = PRESETS[index][k]
	apply()

func reset_defaults() -> void:
	data = DEFAULTS.duplicate(true)
	apply()

## Called about once a second during play with the measured frame rate.
## Trades a little sharpness for a steady frame rate on a warm laptop.
func tune_dynamic_resolution(fps: float, goal: float) -> void:
	var before := dynamic_factor
	if not data["dynamic_res"]:
		dynamic_factor = 1.0
	elif fps < goal * 0.92:
		dynamic_factor = maxf(dynamic_factor - 0.06, 0.62)
		_dyn_hold = 14
	elif _dyn_hold > 0:
		_dyn_hold -= 1
	elif dynamic_factor < 1.0:
		dynamic_factor = minf(dynamic_factor + 0.03, 1.0)
		_dyn_hold = 6
	if not is_equal_approx(before, dynamic_factor):
		var vp := get_viewport()
		if vp:
			vp.scaling_3d_scale = clampf(float(data["render_scale"]) * dynamic_factor, 0.5, 1.0)

var _dyn_hold := 0

# ------------------------------------------------------------------ derived
func view_range() -> float:
	return [380.0, 560.0, 800.0][clampi(int(data["view_distance"]), 0, 2)]

func tree_lod_distance() -> float:
	return [50.0, 72.0, 90.0][clampi(int(data["tree_detail"]), 0, 2)]

func grass_radius() -> float:
	return [0.0, 34.0, 50.0, 68.0][clampi(int(data["grass"]), 0, 3)]

func grass_density() -> float:
	return [0.0, 0.55, 0.8, 1.0][clampi(int(data["grass"]), 0, 3)]

# ------------------------------------------------------------------- apply
func apply() -> void:
	var windowed_test: bool = G.test_mode != "" or G.args.has("windowed")
	if not windowed_test:
		var want := DisplayServer.WINDOW_MODE_FULLSCREEN if data["fullscreen"] else DisplayServer.WINDOW_MODE_WINDOWED
		if DisplayServer.window_get_mode() != want:
			DisplayServer.window_set_mode(want)
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if data["vsync"] else DisplayServer.VSYNC_DISABLED)
		Engine.max_fps = int(data["fps_limit"])
	var vp := get_viewport()
	if vp:
		vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
		vp.scaling_3d_scale = clampf(float(data["render_scale"]) * dynamic_factor, 0.5, 1.0)
		vp.msaa_3d = [Viewport.MSAA_DISABLED, Viewport.MSAA_2X, Viewport.MSAA_4X][clampi(int(data["msaa"]), 0, 2)]
	var sh: int = clampi(int(data["shadows"]), 0, 3)
	RenderingServer.directional_shadow_atlas_set_size([1024, 1024, 2048, 4096][sh], true)
	_set_bus("Master", data["vol_master"])
	_set_bus("SFX", data["vol_sfx"])
	_set_bus("Ambience", data["vol_ambience"])
	_set_bus("Music", data["vol_music"])
	_save()
	changed.emit()

func _set_bus(bus_name: String, linear: float) -> void:
	var i := AudioServer.get_bus_index(bus_name)
	if i < 0:
		return
	AudioServer.set_bus_mute(i, linear <= 0.001)
	AudioServer.set_bus_volume_db(i, linear_to_db(maxf(linear, 0.001)))

func _setup_buses() -> void:
	for bus_name in ["SFX", "Ambience", "Music", "UI"]:
		if AudioServer.get_bus_index(bus_name) < 0:
			AudioServer.add_bus()
			var i := AudioServer.bus_count - 1
			AudioServer.set_bus_name(i, bus_name)
			AudioServer.set_bus_send(i, "Master")
	var lim := AudioEffectHardLimiter.new()
	lim.ceiling_db = -0.5
	AudioServer.add_bus_effect(0, lim)

# ------------------------------------------------------------------- input
func _setup_input() -> void:
	_bind("move_forward", [KEY_W, KEY_UP])
	_bind("move_back", [KEY_S, KEY_DOWN])
	_bind("move_left", [KEY_A, KEY_LEFT])
	_bind("move_right", [KEY_D, KEY_RIGHT])
	_bind("sprint", [KEY_SHIFT])
	_bind("crouch", [KEY_CTRL, KEY_C])
	_bind("jump", [KEY_SPACE])
	_bind("reload", [KEY_R])
	_bind("interact", [KEY_E])
	_bind("binoculars", [KEY_B])
	_bind("moose_call", [KEY_V])
	_bind("map", [KEY_M, KEY_TAB])
	_bind("track_sense", [KEY_Q])
	_bind("dog", [KEY_G])
	_bind("weapon_1", [KEY_1])
	_bind("weapon_2", [KEY_2])
	_bind("weapon_3", [KEY_3])
	_bind("weapon_4", [KEY_4])
	_bind("weapon_5", [KEY_5])
	_bind("pause", [KEY_ESCAPE, KEY_P])
	_bind_mouse("fire", MOUSE_BUTTON_LEFT)
	_bind_mouse("aim", MOUSE_BUTTON_RIGHT)
	_bind_mouse("zoom_in", MOUSE_BUTTON_WHEEL_UP)
	_bind_mouse("zoom_out", MOUSE_BUTTON_WHEEL_DOWN)

func _bind(action: String, keys: Array) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action, 0.2)
	for k in keys:
		var ev := InputEventKey.new()
		ev.physical_keycode = k
		InputMap.action_add_event(action, ev)

func _bind_mouse(action: String, button: int) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action, 0.2)
	var ev := InputEventMouseButton.new()
	ev.button_index = button
	InputMap.action_add_event(action, ev)

# ---------------------------------------------------------------- file i/o
func _load() -> void:
	var cf := ConfigFile.new()
	if cf.load(PATH) != OK:
		return
	for k in DEFAULTS:
		if cf.has_section_key("settings", k):
			var v = cf.get_value("settings", k)
			if typeof(v) == typeof(DEFAULTS[k]) or (typeof(v) in [TYPE_INT, TYPE_FLOAT] and typeof(DEFAULTS[k]) in [TYPE_INT, TYPE_FLOAT]):
				data[k] = v

func _save() -> void:
	if G.no_save:
		return
	var cf := ConfigFile.new()
	for k in data:
		cf.set_value("settings", k, data[k])
	cf.save(PATH)
