class_name Ambience
extends Node
## The sound of the place: wind, lapping water, birds by time of day, and the
## menu drone. Birds fall silent for a while after a shot.

const DAY_BIRDS := ["bird_1", "bird_2", "bird_3", "bird_4", "bird_5"]

var hush := 0.0
var music_on := true
var in_hunt := false
var _wind: AudioStreamPlayer
var _water: AudioStreamPlayer
var _music: AudioStreamPlayer
var _wind_v := 0.0
var _water_v := 0.0
var _music_v := 0.0
var _lake := 0.0
var _lake_t := 0.0
var _bird_t := 2.0
var _rng := RandomNumberGenerator.new()

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_rng.randomize()
	_wind = Sfx.loop("wind_loop", "Ambience")
	_water = Sfx.loop("water_loop", "Ambience")
	_music = Sfx.loop("menu_pad", "Music")

static func _db(v: float) -> float:
	return linear_to_db(maxf(v, 0.0001))

func _process(dt: float) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null or G.terrain == null or not G.terrain.ready:
		return
	var p := cam.global_position
	var paused := get_tree().paused
	# wind: stronger on high, open ground
	var open: float = 1.0 - G.terrain.forest_at(p.x, p.z) * 0.5
	var wind_target := (0.16 + clampf((p.y - 5.0) / 90.0, 0.0, 1.0) * 0.3) * open
	if G.wind:
		wind_target *= 0.5 + 0.5 * G.wind.strength()
	if not in_hunt:
		wind_target *= 0.7
	_wind_v = lerpf(_wind_v, wind_target * (0.5 if paused else 1.0), 1.0 - exp(-1.5 * dt))
	if _wind:
		_wind.volume_db = _db(_wind_v)
	# water near the shore
	_lake_t -= dt
	if _lake_t <= 0.0:
		_lake_t = 0.4
		var nearest := 60.0
		for ring in [6.0, 16.0, 30.0, 48.0]:
			for i in 8:
				var a := TAU * i / 8.0
				if G.terrain.height(p.x + cos(a) * ring, p.z + sin(a) * ring) < 0.0:
					nearest = minf(nearest, ring)
		if G.terrain.height(p.x, p.z) < 0.0:
			nearest = 0.0
		_lake = clampf(1.0 - nearest / 50.0, 0.0, 1.0) * clampf(1.0 - (p.y - 6.0) / 30.0, 0.0, 1.0)
	_water_v = lerpf(_water_v, _lake * _lake * 0.5 * (0.5 if paused else 1.0), 1.0 - exp(-2.0 * dt))
	if _water:
		_water.volume_db = _db(_water_v)
	_music_v = lerpf(_music_v, 0.55 if music_on else 0.0, 1.0 - exp(-(0.8 if music_on else 1.6) * dt))
	if _music:
		_music.volume_db = _db(_music_v)
	if paused:
		return
	hush = maxf(hush - dt, 0.0)
	_bird_t -= dt
	if _bird_t <= 0.0:
		var tod: float = G.sky.time if G.sky else 0.3
		var lively := 1.0 - absf(tod - 0.3) * 0.9      # the dawn chorus fades through the day
		_bird_t = _rng.randf_range(2.5, 7.0) / clampf(lively, 0.35, 1.0)
		if hush <= 0.0:
			_sing(p, tod)

func _sing(p: Vector3, tod: float) -> void:
	var ang := _rng.randf() * TAU
	var dist := _rng.randf_range(14.0, 60.0)
	var pos := p + Vector3(cos(ang) * dist, 0, sin(ang) * dist)
	var ground: float = G.terrain.height(pos.x, pos.z)
	var forest: float = G.terrain.forest_at(pos.x, pos.z)
	pos.y = maxf(ground, 0.0) + _rng.randf_range(4.0, 12.0)
	var sound := ""
	var vol := -9.0
	var roll := _rng.randf()
	var twilight := tod < 0.1 or tod > 0.88
	if twilight and roll < 0.2:
		sound = "owl"
		vol = -6.0
	elif (twilight or tod < 0.22) and _lake > 0.1 and roll < 0.42:
		sound = "loon"
		vol = -4.0
		pos = p + Vector3(cos(ang), 0, sin(ang)) * 90.0
	elif roll < 0.1:
		sound = "raven" if _rng.randf() < 0.5 else "crow"
		vol = -7.0
		pos.y += 25.0
	elif roll < 0.2 and forest > 0.35:
		sound = "woodpecker"
		vol = -7.0
	elif forest > 0.12 or roll < 0.6:
		sound = DAY_BIRDS[_rng.randi() % DAY_BIRDS.size()]
		if tod > 0.9:
			return
	if sound != "":
		Sfx.play_at(sound, pos, vol, _rng.randf_range(0.94, 1.07), 16.0, 0.0, "Ambience")
