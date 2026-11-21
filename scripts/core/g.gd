extends Node
## Global registry: the handful of long-lived systems that everything talks to.

var main: Node = null
var terrain = null      # TerrainData
var world = null        # World (terrain meshes, water, sky, vegetation)
var flora = null        # Vegetation (obstacle queries)
var sky = null          # SkySystem
var player = null       # Player
var herd = null         # Herd
var fx = null           # Effects
var hud = null          # Hud
var tracks = null       # Tracks
var ballistics = null   # Ballistics

## Dev/test switches set from the command line (after `--`).
var test_mode := ""
var out_dir := ""
var args := {}
var no_save := false    ## dev runs never touch the player's settings or save

func _enter_tree() -> void:
	for a in OS.get_cmdline_user_args():
		var s: String = a.trim_prefix("--")
		var kv := s.split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	test_mode = args.get("test", "")
	out_dir = args.get("out", "")
	no_save = test_mode != "" or args.has("inputlog") or args.has("nosave") or args.has("check")

## Deterministic 2D hash -> [0, 1).
static func hash2(x: int, y: int, salt: int = 0) -> float:
	var h: int = (x * 374761393 + y * 668265263 + salt * 2147483647) & 0x7fffffff
	h = ((h ^ (h >> 13)) * 1274126177) & 0x7fffffff
	h = h ^ (h >> 16)
	return float(h & 0xffffff) / 16777216.0

static func fmt_int(v: int) -> String:
	var s := str(absi(v))
	var out := ""
	while s.length() > 3:
		out = " " + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return ("-" if v < 0 else "") + s + out

static func fmt_time(seconds: float) -> String:
	var t := int(maxf(seconds, 0.0))
	return "%d:%02d" % [t / 60, t % 60]

## Critically damped spring step. Returns [value, velocity].
static func spring(value: float, vel: float, target: float, freq: float, damp: float, dt: float) -> Array:
	var k := freq * freq
	var c := 2.0 * damp * freq
	var acc := (target - value) * k - vel * c
	vel += acc * dt
	value += vel * dt
	return [value, vel]

static func spring_v3(value: Vector3, vel: Vector3, target: Vector3, freq: float, damp: float, dt: float) -> Array:
	var k := freq * freq
	var c := 2.0 * damp * freq
	var acc := (target - value) * k - vel * c
	vel += acc * dt
	value += vel * dt
	return [value, vel]
