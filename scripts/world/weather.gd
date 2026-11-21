class_name Weather
extends Node3D
## The day's weather: clear, overcast, rain, fog or the first snow of the autumn.
## It greys the sky and dims the sun (SkySystem reads it), wets or whitens the ground,
## rocks, trees and roofs (the `atmo_weather` shader global), draws the rain or snow
## falling round the camera, and changes the hunt: rain hides the hunter's footsteps
## but washes scent and blood away, fog hides him from the moose, snow crunches
## underfoot but shows every track. Rain and snow come in showers through the day; the
## fog lifts by mid-morning.

const KINDS := ["clear", "overcast", "rain", "fog", "snow"]
const ODDS := [0.32, 0.24, 0.18, 0.14, 0.12]
const DROPS := 4200             ## raindrops / flakes in the box round the camera at full strength

var kind := "clear"
var cloud := 0.08               ## overcast 0..1: grey sky, dim sun, soft shadows
var rain := 0.0                 ## rain falling now 0..1
var snowfall := 0.0             ## snow falling now 0..1
var snow := 0.0                 ## snow lying on the ground 0..1
var wet := 0.0                  ## wet ground 0..1
var fog := 0.0                  ## fog in the valley 0..1

var _strength := 1.0            ## how hard it rains or snows today
var _phase := 0.0
var _t := 0.0
var _push_t := 0.0
var _precip: MeshInstance3D
var _precip_mat: ShaderMaterial
var _rain_snd: AudioStreamPlayer
var _rain_v := 0.0

func _ready() -> void:
	G.weather = self
	_build_precip()
	_rain_snd = Sfx.loop("rain_loop", "Ambience")
	set_kind("clear")

## The weather for a new hunting day: the player's choice in Settings, or the luck of
## the day. (--weather=<kind> forces one; test runs stay clear unless told otherwise.)
func new_day(seed_v := 0) -> void:
	var rng := RandomNumberGenerator.new()
	if seed_v != 0:
		rng.seed = seed_v
	else:
		rng.randomize()
	var pick := "clear"
	if G.args.has("weather"):
		pick = String(G.args["weather"])
	elif G.test_mode != "":
		pick = "clear"
	elif int(Settings.get_v("weather")) > 0:
		pick = KINDS[clampi(int(Settings.get_v("weather")) - 1, 0, KINDS.size() - 1)]
	else:
		var r := rng.randf()
		for i in KINDS.size():
			r -= ODDS[i]
			if r <= 0.0:
				pick = KINDS[i]
				break
	_strength = rng.randf_range(0.55, 1.0) if G.test_mode == "" else 1.0
	_phase = rng.randf() * TAU
	set_kind(pick)

func set_kind(k: String) -> void:
	kind = k if KINDS.has(k) else "clear"
	_t = 0.0
	_update(true)

func _process(dt: float) -> void:
	if get_tree().paused:
		return
	_t += dt
	_push_t -= dt
	if _push_t <= 0.0:
		_push_t = 0.25
		_update(false)
	# the rain on the leaves, louder in the open than under the trees
	var target := rain * 0.75
	_rain_v = lerpf(_rain_v, target, 1.0 - exp(-1.5 * dt))
	if _rain_snd:
		_rain_snd.volume_db = linear_to_db(maxf(_rain_v, 0.0001)) if _rain_v > 0.003 else -80.0

## Showers: a slow swell and ebb through the day (0..1).
func _shower() -> float:
	var t := _t + _phase * 40.0
	return clampf(0.5 + 0.5 * sin(t * 0.021 + _phase) * cos(t * 0.0083 + _phase * 1.7), 0.0, 1.0)

func _update(_force: bool) -> void:
	var k: float = G.sky.time if G.sky else 0.3
	cloud = 0.08
	rain = 0.0
	snowfall = 0.0
	snow = 0.0
	wet = 0.0
	fog = 0.0
	match kind:
		"overcast":
			cloud = 0.85
			wet = 0.12
			fog = 0.12
		"rain":
			cloud = 1.0
			rain = clampf((0.3 + 0.7 * _shower()) * _strength, 0.18, 1.0)
			wet = 0.9
			fog = 0.22 + 0.2 * rain
		"fog":
			# thick at dawn, lifting through the morning; a haze stays
			var lift := smoothstep(0.2, 0.46, k)
			fog = 1.0 - 0.75 * lift
			cloud = 0.62 - 0.3 * lift
			wet = 0.35
		"snow":
			cloud = 0.92
			snowfall = clampf((0.35 + 0.65 * _shower()) * _strength, 0.12, 1.0) * (1.0 - 0.65 * smoothstep(0.55, 0.85, k))
			snow = 0.6 + 0.35 * _strength
			fog = 0.18 + 0.25 * snowfall
	RenderingServer.global_shader_parameter_set(&"atmo_weather", Vector4(wet, snow, rain, snowfall))
	var falling := maxf(rain, snowfall)
	_precip.visible = falling > 0.01
	if _precip.visible:
		_precip_mat.set_shader_parameter("amount", falling)
		_precip_mat.set_shader_parameter("snow", 1.0 if snowfall > rain else 0.0)

# ------------------------------------------------------------- the hunt
## How well a moose hears the hunter: rain on the leaves hides his footsteps.
func hear_mul() -> float:
	return 1.0 - 0.45 * rain

## How far a moose sees him: fog and falling rain or snow hide him; on fresh snow a
## dark figure stands out.
func see_mul() -> float:
	return (1.0 - 0.55 * fog) * (1.0 - 0.18 * rain - 0.22 * snowfall) * (1.0 + 0.15 * snow)

## How far scent carries: rain and snow wash it out of the air.
func scent_mul() -> float:
	return (1.0 - 0.35 * rain) * (1.0 - 0.2 * snowfall)

## How loud each footstep is: snow crunches, soaked ground is soft.
func step_mul() -> float:
	return 1.0 + 0.32 * snow - 0.12 * wet

func describe() -> String:
	match kind:
		"overcast":
			return "overcast"
		"rain":
			return "heavy rain" if rain > 0.7 else ("rain" if rain > 0.35 else "drizzle")
		"fog":
			return "fog" if fog > 0.55 else "mist"
		"snow":
			return "snowing" if snowfall > 0.4 else ("light snow" if snowfall > 0.12 else "snow on the ground")
	return "clear"

## A line for the start of the hunt: what today's weather means.
func intro() -> String:
	match kind:
		"overcast":
			return "Grey and still today."
		"rain":
			return "Rain today: it hides your footsteps, but washes out scent and blood trails."
		"fog":
			return "Fog in the valley: you can get close unseen. It lifts by mid-morning."
		"snow":
			return "First snow: every track shows, but it crunches underfoot."
	return "A clear day."

# --------------------------------------------------------------- the drops
## One mesh of small quads; the shader scatters them through a box round the camera,
## lets them fall and wraps them round (see precip.gdshader). Each quad's colour is its
## seed: rgb its place in the box, a which share of the strength it belongs to.
func _build_precip() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 4711
	var v := PackedVector3Array()
	var c := PackedColorArray()
	var uv := PackedVector2Array()
	var idx := PackedInt32Array()
	v.resize(DROPS * 4)
	c.resize(DROPS * 4)
	uv.resize(DROPS * 4)
	idx.resize(DROPS * 6)
	for i in DROPS:
		var seed := Color(rng.randf(), rng.randf(), rng.randf(), rng.randf())
		for j in 4:
			v[i * 4 + j] = Vector3.ZERO
			c[i * 4 + j] = seed
		uv[i * 4] = Vector2(0, 0)
		uv[i * 4 + 1] = Vector2(1, 0)
		uv[i * 4 + 2] = Vector2(1, 1)
		uv[i * 4 + 3] = Vector2(0, 1)
		var b := i * 4
		idx[i * 6] = b
		idx[i * 6 + 1] = b + 1
		idx[i * 6 + 2] = b + 2
		idx[i * 6 + 3] = b
		idx[i * 6 + 4] = b + 2
		idx[i * 6 + 5] = b + 3
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = v
	arrays[Mesh.ARRAY_COLOR] = c
	arrays[Mesh.ARRAY_TEX_UV] = uv
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.custom_aabb = AABB(Vector3(-5000, -500, -5000), Vector3(10000, 3000, 10000))
	_precip_mat = ShaderMaterial.new()
	_precip_mat.shader = load("res://shaders/precip.gdshader")
	mesh.surface_set_material(0, _precip_mat)
	_precip = MeshInstance3D.new()
	_precip.name = "Precipitation"
	_precip.mesh = mesh
	_precip.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_precip.visible = false
	add_child(_precip)

func precip_node() -> MeshInstance3D:
	return _precip
