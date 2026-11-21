class_name SkySystem
extends Node3D
## Sun, sky, fog and ambient light, driven by a 0..1 "time of day"
## (0 = dawn, 0.5 = noon, 1 = dusk).

## time, sun colour, sun energy, sky top, horizon, fog colour, fog density, ambient colour, ambient energy, cloud lit, cloud dark
const KEYS := [
	[0.00, Color(1.00, 0.60, 0.34), 0.90, Color(0.24, 0.33, 0.56), Color(0.99, 0.68, 0.47), Color(0.86, 0.68, 0.60), 0.0024, Color(0.64, 0.58, 0.66), 1.2, Color(1.00, 0.74, 0.58), Color(0.46, 0.42, 0.54)],
	[0.10, Color(1.00, 0.76, 0.50), 1.08, Color(0.22, 0.37, 0.63), Color(0.96, 0.79, 0.63), Color(0.86, 0.78, 0.72), 0.0015, Color(0.66, 0.65, 0.72), 1.18, Color(1.00, 0.88, 0.76), Color(0.52, 0.52, 0.62)],
	[0.25, Color(1.00, 0.91, 0.76), 1.28, Color(0.20, 0.42, 0.74), Color(0.72, 0.83, 0.93), Color(0.76, 0.83, 0.90), 0.00062, Color(0.66, 0.72, 0.82), 1.10, Color(1.00, 0.98, 0.95), Color(0.60, 0.66, 0.76)],
	[0.50, Color(1.00, 0.95, 0.85), 1.38, Color(0.17, 0.41, 0.78), Color(0.66, 0.81, 0.95), Color(0.72, 0.82, 0.92), 0.00040, Color(0.66, 0.74, 0.86), 1.15, Color(1.00, 1.00, 1.00), Color(0.62, 0.69, 0.80)],
	[0.75, Color(1.00, 0.89, 0.70), 1.28, Color(0.19, 0.40, 0.74), Color(0.76, 0.82, 0.90), Color(0.78, 0.82, 0.87), 0.00055, Color(0.66, 0.71, 0.82), 1.10, Color(1.00, 0.96, 0.90), Color(0.60, 0.64, 0.74)],
	[0.90, Color(1.00, 0.70, 0.40), 1.08, Color(0.22, 0.33, 0.60), Color(0.99, 0.72, 0.46), Color(0.88, 0.71, 0.58), 0.0012, Color(0.66, 0.61, 0.68), 1.15, Color(1.00, 0.80, 0.58), Color(0.48, 0.44, 0.56)],
	[1.00, Color(1.00, 0.48, 0.27), 0.78, Color(0.17, 0.22, 0.44), Color(0.97, 0.52, 0.33), Color(0.74, 0.54, 0.52), 0.0021, Color(0.58, 0.53, 0.66), 1.15, Color(0.98, 0.58, 0.44), Color(0.36, 0.32, 0.46)],
]

var time := 0.25
var env: Environment
var sun: DirectionalLight3D
var sky_mat: ShaderMaterial
var world_env: WorldEnvironment
var sun_dir := Vector3.UP
var fog_scale := 1.0
var _cloud_offset := Vector2.ZERO
## Cloud shadows: the sky's cloud texture laid on the land along the sun's rays.
var cloud_scale := 1.0              ## 0 turns the cloud shadows off (dev A/B)
var _shadow_off := Vector2(0.37, 0.61)
var _cloud_img: Image
var _sun_energy := 1.0
var cam_sun := 1.0                  ## share of the sun reaching the camera through the clouds
var _applied_time := -1.0

var haze_height := 150.0       ## metres over which the haze thins by 1/e: low mist at dawn, deep haze at noon
var _step_timer := 0.0

func _ready() -> void:
	sky_mat = ShaderMaterial.new()
	sky_mat.shader = load("res://shaders/sky.gdshader")
	var cloud_tex := WorldUtil.noise_texture(256, 4242, [0.018, 0.04, 0.01])
	sky_mat.set_shader_parameter("cloud_tex", cloud_tex)
	_cloud_img = cloud_tex.get_image()
	if _cloud_img.is_compressed():
		_cloud_img.decompress()
	RenderingServer.global_shader_parameter_set(&"atmo_cloud_tex", cloud_tex)
	var sky := Sky.new()
	sky.sky_material = sky_mat
	sky.radiance_size = Sky.RADIANCE_SIZE_64
	sky.process_mode = Sky.PROCESS_MODE_INCREMENTAL
	env = Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_sky_contribution = 0.5
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_white = 5.0
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_EXPONENTIAL
	env.fog_sun_scatter = 0.25
	env.fog_aerial_perspective = 0.0
	env.fog_sky_affect = 0.0
	env.fog_height_density = 0.0
	env.glow_enabled = true
	env.glow_intensity = 0.55
	env.glow_bloom = 0.04
	env.glow_hdr_threshold = 1.05
	env.adjustment_enabled = true
	env.adjustment_contrast = 1.06
	env.adjustment_saturation = 1.12
	world_env = WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)
	sun = DirectionalLight3D.new()
	sun.light_angular_distance = 0.6
	sun.shadow_enabled = true
	sun.shadow_bias = 0.06
	sun.shadow_normal_bias = 1.6
	sun.shadow_opacity = 0.86
	sun.directional_shadow_blend_splits = false
	sun.directional_shadow_fade_start = 0.82
	add_child(sun)
	Settings.changed.connect(_apply_settings)
	_apply_settings()
	set_time(time, true)

func _apply_settings() -> void:
	var sh: int = int(Settings.get_v("shadows"))
	sun.shadow_enabled = sh > 0
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS if sh >= 3 else DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.directional_shadow_max_distance = [50.0, 55.0, 95.0, 160.0][clampi(sh, 0, 3)]
	sun.directional_shadow_split_1 = 0.28 if sh < 3 else 0.1
	env.glow_enabled = int(Settings.get_v("preset")) != 0
	_applied_time = -1.0

func set_time(t: float, force := false) -> void:
	time = clampf(t, 0.0, 1.0)
	if force:
		_applied_time = -1.0
		_apply()

func _process(dt: float) -> void:
	_cloud_offset -= _wind_dir() * 0.00115 * dt
	_update_cloud_shadows(dt)
	_step_timer -= dt
	# Sky uniforms re-bake the radiance map, so only touch them a few times a second.
	if _step_timer <= 0.0:
		_step_timer = 0.3
		_apply()

## The way the clouds go: with the day's wind (Wind), a little faster when it blows hard.
func _wind_dir() -> Vector2:
	if G.wind == null:
		return Vector2(0.8, 0.6)
	return G.wind.dir * lerpf(0.8, 1.25, clampf((float(G.wind.speed) - 1.5) / 4.5, 0.0, 1.0))

## The clouds' shadows drift downwind at about 8 m/s (frozen in test runs, so pictures
## compare, unless --clouddrift). They fade out with a low sun, when there is little direct
## light to take away. The sun itself is dimmed by the clouds over the camera, which keeps
## plain materials (moose, rifle) right; the landscape shaders correct for it elsewhere.
func _update_cloud_shadows(dt: float) -> void:
	if G.test_mode == "" or G.args.has("clouddrift"):
		_shadow_off -= _wind_dir() * 0.0072 * dt
	elif G.args.has("cloudoff"):          # dev: park the clouds elsewhere (--cloudoff=x,y)
		var parts := String(G.args["cloudoff"]).split(",")
		_shadow_off = Vector2(float(parts[0]), float(parts[1]))
	var strength := 0.78 * smoothstep(0.11, 0.3, sun_dir.y) * cloud_scale
	# under a grey sky there are no single clouds to cast shadows
	if G.weather:
		strength *= 1.0 - clampf((float(G.weather.cloud) - 0.08) / 0.6, 0.0, 1.0)
	if G.args.has("cloudshadow"):
		strength *= float(G.args["cloudshadow"])
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	cam_sun = cloud_sun_at(cam.global_position, strength) if cam else 1.0
	RenderingServer.global_shader_parameter_set(&"atmo_cloud", Vector4(_shadow_off.x, _shadow_off.y, strength, cam_sun))
	sun.light_energy = _sun_energy * cam_sun
	if G.args.has("clouddebug") and Engine.get_process_frames() % 120 == 0:
		var shaded := 0
		var lo := 1.0
		for i in 400:
			var v := cloud_sun_at(Vector3((i % 20) * 50.0 - 500.0, 10.0, (i / 20) * 50.0 - 500.0), strength)
			lo = minf(lo, v)
			if v < 0.8:
				shaded += 1
		print("[clouds] strength %.2f cam %.2f shaded %d/400 min %.2f sun_dir %s off %s" % [strength, cam_sun, shaded, lo, sun_dir, _shadow_off])

## Share of the sun that gets through the clouds at `p`: atmo_cloud_sun() in atmo.gdshaderinc,
## without the division by the camera's share.
func cloud_sun_at(p: Vector3, strength: float) -> float:
	if _cloud_img == null or strength <= 0.0:
		return 1.0
	var sy := maxf(sun_dir.y, 0.2)
	var q := Vector2(p.x, p.z) + Vector2(sun_dir.x, sun_dir.z) / sy * (400.0 - p.y)
	var c := _cloud_texel(q * 0.0009 + _shadow_off, 0) * 0.65 + _cloud_texel(q * 0.0026 + _shadow_off * 1.7 + Vector2(0.31, 0.31), 1) * 0.35
	return 1.0 - smoothstep(0.54, 0.6, c) * strength

## Bilinear, repeating lookup of one channel of the cloud texture, as the GPU filters it.
func _cloud_texel(uv: Vector2, ch: int) -> float:
	var w := _cloud_img.get_width()
	var h := _cloud_img.get_height()
	var x := uv.x * w - 0.5
	var y := uv.y * h - 0.5
	var x0 := floori(x)
	var y0 := floori(y)
	var fx := x - x0
	var fy := y - y0
	var a := lerpf(_cloud_img.get_pixel(posmod(x0, w), posmod(y0, h))[ch], _cloud_img.get_pixel(posmod(x0 + 1, w), posmod(y0, h))[ch], fx)
	var b := lerpf(_cloud_img.get_pixel(posmod(x0, w), posmod(y0 + 1, h))[ch], _cloud_img.get_pixel(posmod(x0 + 1, w), posmod(y0 + 1, h))[ch], fx)
	return lerpf(a, b, fy)

static func _lerp_key(a: Array, b: Array, k: float, i: int):
	if typeof(a[i]) == TYPE_COLOR:
		return (a[i] as Color).lerp(b[i], k)
	return lerpf(a[i], b[i], k)

func sample(t: float) -> Array:
	var a: Array = KEYS[0]
	var b: Array = KEYS[KEYS.size() - 1]
	for i in KEYS.size() - 1:
		if t >= KEYS[i][0] and t <= KEYS[i + 1][0]:
			a = KEYS[i]
			b = KEYS[i + 1]
			break
	var k := 0.0 if is_equal_approx(a[0], b[0]) else clampf((t - a[0]) / (b[0] - a[0]), 0.0, 1.0)
	var out := [t]
	for i in range(1, a.size()):
		out.append(_lerp_key(a, b, k, i))
	return out

func _apply() -> void:
	var s := sample(time)
	# the day's weather (Weather): grey cloud dims the sun and greys the sky, fog and
	# falling rain or snow thicken the haze. A clear day leaves the palette as it is.
	var w = G.weather
	var oc := 0.0
	var fogw := 0.0
	var precip := 0.0
	var snowy := 0.0
	if w:
		oc = clampf((float(w.cloud) - 0.08) / 0.92, 0.0, 1.0)
		fogw = w.fog
		precip = maxf(w.rain, w.snowfall)
		snowy = w.snow
	if oc > 0.0 or fogw > 0.0:
		var day := clampf(float(s[2]) / 1.38, 0.5, 1.0)
		s[1] = (s[1] as Color).lerp(Color(0.84, 0.86, 0.9), oc * 0.65)
		s[2] = float(s[2]) * (1.0 - 0.68 * oc)
		s[3] = (s[3] as Color).lerp(Color(0.5, 0.53, 0.57) * day, maxf(oc * 0.85, fogw * 0.55))
		s[4] = (s[4] as Color).lerp(Color(0.7, 0.72, 0.74) * day, maxf(oc * 0.8, fogw * 0.88))
		s[5] = (s[5] as Color).lerp(Color(0.76, 0.78, 0.8) * day, maxf(oc * 0.7, fogw * 0.92))
		s[6] = float(s[6]) * (1.0 + 16.0 * fogw + 2.5 * precip)
		s[8] = float(s[8]) * (1.0 + 0.35 * oc)
		s[9] = (s[9] as Color).lerp(Color(0.72, 0.74, 0.78) * day, oc)
		s[10] = (s[10] as Color).lerp(Color(0.44, 0.46, 0.5) * day, oc)
	sky_mat.set_shader_parameter("cloud_cover", 0.45 + 0.53 * oc)
	sky_mat.set_shader_parameter("veil", clampf(maxf(oc, fogw) * 1.3 - 0.2, 0.0, 1.0))
	sun.shadow_opacity = 0.86 * (1.0 - 0.75 * oc)
	env.adjustment_saturation = 1.12 - 0.12 * oc
	# low Nordic sun: east at dawn, south at noon, west at dusk
	var elev := deg_to_rad(6.5 + 25.0 * pow(sin(PI * time), 0.85))
	var azim := lerpf(deg_to_rad(-78.0), deg_to_rad(78.0), time)
	sun_dir = Vector3(-sin(azim) * cos(elev), sin(elev), cos(azim) * cos(elev)).normalized()
	sun.basis = Basis.looking_at(-sun_dir, Vector3.UP)
	sun.light_color = s[1]
	_sun_energy = s[2]
	sun.light_energy = _sun_energy * cam_sun
	# shared atmosphere: the sky shader and every landscape shader read these
	var density: float = float(s[6]) * fog_scale
	haze_height = 105.0 + 235.0 * pow(sin(PI * time), 1.5)
	# fog lies low in the valley: the peaks stand clear above it
	haze_height = lerpf(haze_height, 38.0, fogw * 0.85)
	var haze := _lin(s[5])
	var rs := RenderingServer
	rs.global_shader_parameter_set(&"atmo_sun_dir", sun_dir)
	rs.global_shader_parameter_set(&"atmo_sun_col", _lin(s[1]) * float(s[2]))
	rs.global_shader_parameter_set(&"atmo_top", _lin(s[3]))
	rs.global_shader_parameter_set(&"atmo_horizon", _lin(s[4]))
	var haze_band := clampf(0.3 + density * 210.0, 0.0, 0.9)
	rs.global_shader_parameter_set(&"atmo_haze", Vector4(haze.x, haze.y, haze.z, haze_band))
	rs.global_shader_parameter_set(&"atmo_fog", Vector4(density, haze_height, 0.26, 0.0))
	# (setting a material parameter is also what makes the sky re-bake its radiance map)
	sky_mat.set_shader_parameter("ground_color", (s[5] as Color).lerp(Color(0.42, 0.40, 0.32), 0.45))
	sky_mat.set_shader_parameter("cloud_lit", s[9])
	sky_mat.set_shader_parameter("cloud_dark", s[10])
	sky_mat.set_shader_parameter("cloud_offset", _cloud_offset)
	# built-in fog still serves the plain materials (cabin, moose, particles)
	var eye_y := 0.0
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	if cam:
		eye_y = maxf(cam.global_position.y, 0.0)
	env.fog_light_color = (s[4] as Color).lerp(s[5], haze_band)     # the sky at the horizon, as the shaders fade to
	env.fog_density = density * exp(-eye_y / haze_height)
	env.ambient_light_color = s[7]
	env.ambient_light_energy = s[8]
	_applied_time = time

## The palette is written as the colours meant to be seen. The renderer reads what shaders
## output as sRGB-encoded, so these go to the shaders untouched (see atmo.gdshaderinc).
static func _lin(c: Color) -> Vector3:
	return Vector3(c.r, c.g, c.b)

## Clock string for the HUD: the hunt runs 06:30 -> 18:30.
func clock() -> String:
	var minutes := int(390.0 + time * 720.0)
	return "%02d:%02d" % [minutes / 60, minutes % 60]

func is_twilight() -> bool:
	return time < 0.12 or time > 0.88
