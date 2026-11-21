class_name Wind
extends Node
## The day's wind: which way it blows and how hard. A new wind comes with every hunt
## and veers slowly through the day, lighter at dawn and dusk. The grass, the trees,
## falling leaves, breath and the clouds all go with it (the `atmo_wind` global), and
## it carries scent: a moose smells the hunter downwind of him, the dog smells moose.

const CALM := 1.2               ## m/s below which the air just drifts

var dir := Vector2(0.8, 0.6)    ## unit (x, z): the way the wind blows TO
var speed := 3.3                ## m/s at ground level right now

var _base_ang := 0.0
var _base_speed := 3.3
var _veer := Vector3.ZERO       ## amplitudes / phase of the slow swing
var _t := 0.0
var _frozen := false
var _push_t := 0.0

func _ready() -> void:
	G.wind = self
	# test pictures stay comparable: the old fixed wind unless asked for another
	_frozen = G.test_mode != "" and not G.args.has("wind")
	_base_ang = atan2(0.6, 0.8)
	_apply()

## A fresh wind for a new hunting day. `seed_v` 0 picks one at random.
## (--wind=<from bearing>,<m/s> sets it, e.g. --wind=225,4 for a south-westerly)
func new_day(seed_v := 0) -> void:
	var rng := RandomNumberGenerator.new()
	if seed_v != 0:
		rng.seed = seed_v
	else:
		rng.randomize()
	_t = 0.0
	if G.args.has("wind"):
		var parts := String(G.args["wind"]).split(",")
		_set_from(float(parts[0]), float(parts[1]) if parts.size() > 1 else 3.3)
		_veer = Vector3.ZERO if G.test_mode != "" else Vector3(0.3, 0.12, rng.randf() * TAU)
	elif _frozen:
		return
	else:
		_set_from(rng.randf() * 360.0, rng.randf_range(1.6, 6.2))
		_veer = Vector3(rng.randf_range(0.25, 0.55), rng.randf_range(0.08, 0.2), rng.randf() * TAU)
	_apply()

func _set_from(bearing_deg: float, mps: float) -> void:
	# a wind *from* a bearing blows the opposite way; bearings: N = -Z, E = +X
	var to := deg_to_rad(bearing_deg + 180.0)
	var v := Vector2(sin(to), -cos(to))
	_base_ang = atan2(v.y, v.x)
	_base_speed = mps

func _process(dt: float) -> void:
	if _frozen or get_tree().paused:
		return
	_t += dt
	# it turns slowly: a few updates a second are plenty
	_push_t -= dt
	if _push_t <= 0.0:
		_push_t = 0.2
		_apply()

func _apply() -> void:
	var ang := _base_ang
	var day := 0.5
	if not _frozen:
		ang += _veer.x * sin(_t * 0.0095 + _veer.z) + _veer.y * sin(_t * 0.041 + _veer.z * 2.3)
		if G.sky:
			day = clampf(G.sky.time, 0.0, 1.0)
	dir = Vector2(cos(ang), sin(ang))
	# the air is stillest round sunrise and sunset
	speed = _base_speed if _frozen else _base_speed * (0.62 + 0.38 * sin(PI * day))
	RenderingServer.global_shader_parameter_set(&"atmo_wind", Vector4(dir.x, dir.y, strength(), speed))

## How hard the trees and grass move: 1 is a moderate breeze (the old fixed wind).
func strength() -> float:
	return clampf(speed / 3.3, 0.5, 1.7)

## Compass bearing (degrees, 0 = N) the wind comes FROM.
func from_bearing() -> float:
	return fposmod(rad_to_deg(atan2(-dir.x, dir.y)), 360.0)

func from_name() -> String:
	return Hud.POINTS[int(round(from_bearing() / 45.0)) % 8]

func describe() -> String:
	if speed < CALM:
		return "almost still"
	if speed < 2.6:
		return "light air"
	if speed < 4.4:
		return "light breeze"
	return "fresh breeze"

## How strongly scent from `src` reaches `rcv` (0..1). Downwind it carries far in a
## cone that is narrow in a steady wind and wide when the air only drifts; close by,
## eddies carry a little every way. `reach` scales the distances (a dog's nose: ~2).
func scent(src: Vector3, rcv: Vector3, reach := 1.0) -> float:
	var d := Vector2(rcv.x - src.x, rcv.z - src.z)
	var dist := d.length()
	if dist < 0.5:
		return 1.0
	var near := (1.0 - smoothstep(9.0 * reach, 24.0 * reach, dist)) * 0.7
	var steady := clampf((speed - CALM) / 4.0, 0.0, 1.0)
	var range_m := (70.0 + 140.0 * steady) * reach
	if dist > range_m:
		return near
	var c := d.dot(dir) / dist                     # 1 = straight downwind of the source
	var half := lerpf(0.7, 0.34, steady)           # half-width of the cone (radians)
	var cone := smoothstep(cos(half * 1.45), cos(half * 0.65), c)
	var fall := 1.0 - smoothstep(range_m * 0.45, range_m, dist)
	return maxf(cone * fall, near)
