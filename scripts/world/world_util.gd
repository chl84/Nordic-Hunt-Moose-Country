class_name WorldUtil
extends RefCounted
## Shared procedural texture helpers.

static var _cache := {}

## Seamless RGB noise texture: three independent fBm channels.
static func noise_texture(size: int, seed_v: int, freqs: Array = [0.012, 0.02, 0.016]) -> ImageTexture:
	var key := "%d_%d_%s" % [size, seed_v, str(freqs)]
	if _cache.has(key):
		return _cache[key]
	var chans: Array[PackedByteArray] = []
	for k in 3:
		var nz := FastNoiseLite.new()
		nz.seed = seed_v + k * 101
		nz.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		nz.frequency = freqs[k]
		nz.fractal_type = FastNoiseLite.FRACTAL_FBM
		nz.fractal_octaves = 4
		var img := nz.get_seamless_image(size, size, false, false, 0.25, true)
		img.convert(Image.FORMAT_L8)
		chans.append(img.get_data())
	var out := PackedByteArray()
	out.resize(size * size * 4)
	var c0 := chans[0]
	var c1 := chans[1]
	var c2 := chans[2]
	for i in size * size:
		var o := i * 4
		out[o] = c0[i]
		out[o + 1] = c1[i]
		out[o + 2] = c2[i]
		out[o + 3] = 255
	var rgba := Image.create_from_data(size, size, false, Image.FORMAT_RGBA8, out)
	rgba.generate_mipmaps()
	var tex := ImageTexture.create_from_image(rgba)
	_cache[key] = tex
	return tex

## Soft round blob (white centre -> transparent edge) for particles and flashes.
static func blob_texture(size := 64, power := 2.0) -> ImageTexture:
	var key := "blob_%d_%f" % [size, power]
	if _cache.has(key):
		return _cache[key]
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var c := Vector2(size, size) * 0.5
	for y in size:
		for x in size:
			var d := (Vector2(x + 0.5, y + 0.5) - c).length() / (size * 0.5)
			var a := pow(clampf(1.0 - d, 0.0, 1.0), power)
			img.set_pixel(x, y, Color(1, 1, 1, a))
	var tex := ImageTexture.create_from_image(img)
	_cache[key] = tex
	return tex

## Star-burst texture for muzzle flashes.
static func flash_texture(size := 128, spikes := 5, seed_v := 1) -> ImageTexture:
	var key := "flash_%d_%d_%d" % [size, spikes, seed_v]
	if _cache.has(key):
		return _cache[key]
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var c := Vector2(size, size) * 0.5
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	var ph := rng.randf() * TAU
	for y in size:
		for x in size:
			var p := (Vector2(x + 0.5, y + 0.5) - c) / (size * 0.5)
			var d := p.length()
			var ang := atan2(p.y, p.x)
			var ray := pow(absf(cos(ang * spikes * 0.5 + ph)), 6.0)
			var ray2 := pow(absf(cos(ang * (spikes + 2) * 0.5 + ph * 2.3)), 10.0) * 0.6
			var reach := 0.32 + 0.68 * maxf(ray, ray2)
			var a := clampf(1.0 - d / reach, 0.0, 1.0)
			a = pow(a, 1.4)
			var core := clampf(1.0 - d / 0.3, 0.0, 1.0)
			img.set_pixel(x, y, Color(1.0, 0.75 + 0.25 * core, 0.35 + 0.65 * core, a))
	var tex := ImageTexture.create_from_image(img)
	_cache[key] = tex
	return tex
