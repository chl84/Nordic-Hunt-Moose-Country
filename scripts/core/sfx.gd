extends Node
## Sound bank + pooled players. All sounds are WAVs synthesised by tools/gen_audio.py.

const DIR := "res://audio/"
const SPEED_OF_SOUND := 343.0

var bank := {}
var _pool2d: Array[AudioStreamPlayer] = []
var _pool3d: Array[AudioStreamPlayer3D] = []
var _i2 := 0
var _i3 := 0
var _loops := {}
var _delayed: Array = []   # [time_left, callable]

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_load_bank()
	for i in 14:
		var p := AudioStreamPlayer.new()
		p.bus = "SFX"
		add_child(p)
		_pool2d.append(p)
	for i in 24:
		var p3 := AudioStreamPlayer3D.new()
		p3.bus = "SFX"
		p3.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		p3.attenuation_filter_cutoff_hz = 12000.0
		p3.attenuation_filter_db = -18.0
		add_child(p3)
		_pool3d.append(p3)

func _load_bank() -> void:
	var d := DirAccess.open(DIR)
	if d == null:
		push_warning("Audio folder missing - run tools/gen_audio.py")
		return
	for f in d.get_files():
		if not f.ends_with(".wav"):
			continue
		var s := AudioStreamWAV.load_from_file(DIR + f)
		if s == null:
			continue
		var key := f.get_basename()
		if key.ends_with("_loop") or key == "menu_pad":
			s.loop_mode = AudioStreamWAV.LOOP_FORWARD
			s.loop_begin = 0
			s.loop_end = int(s.get_length() * s.mix_rate)
		bank[key] = s

func has(sound: String) -> bool:
	return bank.has(sound)

## Non-positional one-shot.
func play(sound: String, vol_db := 0.0, pitch := 1.0, bus := "SFX") -> AudioStreamPlayer:
	if not bank.has(sound):
		return null
	var p := _pool2d[_i2]
	_i2 = (_i2 + 1) % _pool2d.size()
	p.stream = bank[sound]
	p.volume_db = vol_db
	p.pitch_scale = pitch
	p.bus = bus
	p.play()
	return p

func ui(sound: String, vol_db := 0.0) -> void:
	play(sound, vol_db, 1.0, "UI")

## Random variant: play_var("step_grass", 4) -> step_grass_1..4
func play_var(base: String, count: int, vol_db := 0.0, pitch_jitter := 0.08, bus := "SFX") -> void:
	play("%s_%d" % [base, randi_range(1, count)], vol_db, randf_range(1.0 - pitch_jitter, 1.0 + pitch_jitter), bus)

## Positional one-shot. `size` is the distance (m) at which the sound starts to fall off.
func play_at(sound: String, pos: Vector3, vol_db := 0.0, pitch := 1.0, size := 10.0, max_dist := 0.0, bus := "SFX") -> AudioStreamPlayer3D:
	if not bank.has(sound):
		return null
	var p := _pool3d[_i3]
	_i3 = (_i3 + 1) % _pool3d.size()
	p.stream = bank[sound]
	p.global_position = pos
	p.volume_db = vol_db
	p.pitch_scale = pitch
	p.unit_size = size
	p.max_distance = max_dist
	p.bus = bus
	p.play()
	return p

func play_var_at(base: String, count: int, pos: Vector3, vol_db := 0.0, size := 10.0, pitch_jitter := 0.08) -> void:
	play_at("%s_%d" % [base, randi_range(1, count)], pos, vol_db, randf_range(1.0 - pitch_jitter, 1.0 + pitch_jitter), size)

## Positional sound that arrives after the speed-of-sound delay from `listener`.
func play_at_delayed(sound: String, pos: Vector3, listener: Vector3, vol_db := 0.0, pitch := 1.0, size := 10.0) -> void:
	var delay := pos.distance_to(listener) / SPEED_OF_SOUND
	if delay < 0.03:
		play_at(sound, pos, vol_db, pitch, size)
	else:
		_delayed.append([delay, func(): play_at(sound, pos, vol_db, pitch, size)])

func call_later(delay: float, fn: Callable) -> void:
	_delayed.append([delay, fn])

## Looping bed; returns the player so callers can drive its volume.
func loop(sound: String, bus := "Ambience", vol_db := -60.0) -> AudioStreamPlayer:
	if _loops.has(sound):
		return _loops[sound]
	if not bank.has(sound):
		return null
	var p := AudioStreamPlayer.new()
	p.stream = bank[sound]
	p.bus = bus
	p.volume_db = vol_db
	add_child(p)
	p.play()
	_loops[sound] = p
	return p

func _process(dt: float) -> void:
	if _delayed.is_empty() or get_tree().paused:
		return
	var i := 0
	while i < _delayed.size():
		_delayed[i][0] -= dt
		if _delayed[i][0] <= 0.0:
			var fn: Callable = _delayed[i][1]
			_delayed.remove_at(i)
			fn.call()
		else:
			i += 1
