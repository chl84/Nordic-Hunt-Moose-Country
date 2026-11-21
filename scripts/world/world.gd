class_name World
extends Node3D
## Builds and owns the landscape: terrain chunks, distant mountains, lakes,
## sky, vegetation and structures.

signal progress(fraction: float, label: String)

const CHUNK_Q := 32          ## quads per chunk side at full resolution
const CHUNKS := 16
const CHUNK_SIZE := 64.0

var data: TerrainData
var sky: SkySystem
var flora: Vegetation
var structures: Structures
var noise_tex: ImageTexture
var map_tex: ImageTexture
var depth_tex: ImageTexture
var terrain_mat: ShaderMaterial
var far_mat: ShaderMaterial
var water_mat: ShaderMaterial
var _chunks_hi: Array[MeshInstance3D] = []
var _chunks_lo: Array[MeshInstance3D] = []
var _t0 := 0

func _tick(f: float, label: String) -> void:
	progress.emit(f, label)
	await get_tree().process_frame

func build(seed_v := 1905) -> void:
	_t0 = Time.get_ticks_msec()
	G.world = self
	data = TerrainData.new(seed_v)
	G.terrain = data
	await _tick(0.02, "Raising the mountains")
	if not data.load_cache():
		data.alloc()
		var rows := 0
		while rows < TerrainData.N:
			data.generate_rows(rows, rows + 24)
			rows += 24
			await _tick(0.02 + 0.28 * rows / TerrainData.N, "Raising the mountains")
		data.save_cache()
	_log("heights")
	data.place_sites()
	var map_bytes := PackedByteArray()
	map_bytes.resize(TerrainData.N * TerrainData.N * 4)
	var depth_bytes := PackedByteArray()
	depth_bytes.resize(TerrainData.N * TerrainData.N)
	var r := 0
	while r < TerrainData.N:
		data.build_field_rows(r, r + 48, map_bytes, depth_bytes)
		r += 48
		await _tick(0.30 + 0.12 * r / TerrainData.N, "Growing the forest")
	var map_img := Image.create_from_data(TerrainData.N, TerrainData.N, false, Image.FORMAT_RGBA8, map_bytes)
	map_img.generate_mipmaps()
	map_tex = ImageTexture.create_from_image(map_img)
	depth_tex = ImageTexture.create_from_image(Image.create_from_data(TerrainData.N, TerrainData.N, false, Image.FORMAT_L8, depth_bytes))
	data.ready = true
	_log("fields")

	noise_tex = WorldUtil.noise_texture(512, seed_v)
	terrain_mat = ShaderMaterial.new()
	terrain_mat.shader = load("res://shaders/terrain.gdshader")
	terrain_mat.set_shader_parameter("map_tex", map_tex)
	terrain_mat.set_shader_parameter("noise_tex", noise_tex)
	terrain_mat.set_shader_parameter("detail_tex", WorldUtil.noise_texture(256, seed_v + 900, [0.055, 0.1, 0.075]))
	terrain_mat.set_shader_parameter("use_map", true)
	far_mat = terrain_mat.duplicate()
	far_mat.shader = load("res://shaders/terrain_far.gdshader")
	far_mat.set_shader_parameter("use_map", false)
	await _tick(0.44, "Laying the ground")

	for cz in CHUNKS:
		for cx in CHUNKS:
			_add_chunk(cx, cz)
		await _tick(0.44 + 0.16 * (cz + 1) / CHUNKS, "Laying the ground")
	_build_far_ring()
	_build_water()
	_log("terrain meshes")

	sky = SkySystem.new()
	sky.name = "Sky"
	add_child(sky)
	G.sky = sky
	await _tick(0.62, "Planting spruce and birch")

	flora = Vegetation.new()
	flora.name = "Vegetation"
	add_child(flora)
	G.flora = flora
	await flora.build(self)
	_log("vegetation")

	structures = Structures.new()
	structures.name = "Structures"
	add_child(structures)
	structures.build(data)
	await _tick(0.97, "Brewing coffee")
	Settings.changed.connect(_apply_settings)
	_apply_settings()
	_log("world ready")

func _log(what: String) -> void:
	if G.test_mode != "":
		print("[world] %s @ %d ms" % [what, Time.get_ticks_msec() - _t0])

func _apply_settings() -> void:
	var lod := 230.0 + 60.0 * int(Settings.get_v("view_distance"))
	for m in _chunks_hi:
		m.visibility_range_end = lod
	for m in _chunks_lo:
		m.visibility_range_begin = lod
	if water_mat:
		water_mat.set_shader_parameter("ripple", 1.0 if int(Settings.get_v("water_quality")) > 0 else 0.6)

# ----------------------------------------------------------------- terrain
func _add_chunk(cx: int, cz: int) -> void:
	var center := Vector3((cx + 0.5) * CHUNK_SIZE - TerrainData.HALF, 0.0, (cz + 0.5) * CHUNK_SIZE - TerrainData.HALF)
	for step in [1, 4]:
		var mi := MeshInstance3D.new()
		mi.mesh = _chunk_mesh(cx, cz, step)
		mi.material_override = terrain_mat
		mi.position = center
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
		add_child(mi)
		if step == 1:
			_chunks_hi.append(mi)
		else:
			_chunks_lo.append(mi)

func _chunk_mesh(cx: int, cz: int, step: int) -> ArrayMesh:
	var q := CHUNK_Q / step
	var vn := q + 1
	var gx0 := cx * CHUNK_Q
	var gz0 := cz * CHUNK_Q
	var cell := TerrainData.CELL
	var half := CHUNK_Q * cell * 0.5
	var n := TerrainData.N
	var hts := data.heights
	var verts := PackedVector3Array()
	verts.resize(vn * vn)
	for j in vn:
		var row := (gz0 + j * step) * n + gx0
		var lz := j * step * cell - half
		for i in vn:
			verts[j * vn + i] = Vector3(i * step * cell - half, hts[row + i * step], lz)
	var indices := PackedInt32Array()
	indices.resize(q * q * 6)
	var k := 0
	for j in q:
		for i in q:
			var a := j * vn + i
			indices[k] = a
			indices[k + 1] = a + 1
			indices[k + 2] = a + vn + 1
			indices[k + 3] = a
			indices[k + 4] = a + vn + 1
			indices[k + 5] = a + vn
			k += 6
	# skirts hide the cracks between detail levels (deep ones seal the world edge)
	for side in 4:
		var deep := (side == 0 and cz == 0) or (side == 1 and cz == CHUNKS - 1) or (side == 2 and cx == 0) or (side == 3 and cx == CHUNKS - 1)
		var drop := 40.0 if deep else 1.2 + 1.6 * step
		var border := PackedInt32Array()
		for i in vn:
			match side:
				0: border.append(i)
				1: border.append(q * vn + i)
				2: border.append(i * vn)
				3: border.append(i * vn + q)
		var base := verts.size()
		for b in border:
			verts.append(verts[b] - Vector3(0, drop, 0))
		for i in q:
			var b0 := border[i]
			var b1 := border[i + 1]
			var l0 := base + i
			var l1 := base + i + 1
			indices.append_array(PackedInt32Array([b0, b1, l1, b0, l1, l0, b0, l1, b1, b0, l0, l1]))
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return mesh

func _build_far_ring() -> void:
	var step := 40.0
	var half_n := 52
	var vn := half_n * 2 + 1
	var inner := 480.0
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var cols := PackedColorArray()
	var hs := PackedFloat32Array()
	verts.resize(vn * vn)
	norms.resize(vn * vn)
	cols.resize(vn * vn)
	hs.resize(vn * vn)
	for j in vn:
		for i in vn:
			hs[j * vn + i] = data.height_fn((i - half_n) * step, (j - half_n) * step)
	for j in vn:
		for i in vn:
			var x := (i - half_n) * step
			var z := (j - half_n) * step
			var h := hs[j * vn + i]
			var hl := hs[j * vn + maxi(i - 1, 0)]
			var hr := hs[j * vn + mini(i + 1, vn - 1)]
			var hu := hs[maxi(j - 1, 0) * vn + i]
			var hd := hs[mini(j + 1, vn - 1) * vn + i]
			var nrm := Vector3(hl - hr, 2.0 * step, hu - hd).normalized()
			var f := (1.0 - smoothstep(100.0, 175.0, h)) * (1.0 - smoothstep(0.22, 0.42, 1.0 - nrm.y))
			f *= smoothstep(0.3, 0.55, data.n_forest.get_noise_2d(x, z) * 0.5 + 0.62)
			var sink := 9.0 if (absf(x) <= inner and absf(z) <= inner) else 0.0
			verts[j * vn + i] = Vector3(x, h - sink, z)
			norms[j * vn + i] = nrm
			cols[j * vn + i] = Color(0, 0, f, 0)
	var indices := PackedInt32Array()
	for j in vn - 1:
		for i in vn - 1:
			var x0 := (i - half_n) * step
			var z0 := (j - half_n) * step
			if maxf(absf(x0), absf(x0 + step)) <= inner and maxf(absf(z0), absf(z0 + step)) <= inner:
				continue   # hidden under the detailed terrain
			var a := j * vn + i
			indices.append_array(PackedInt32Array([a, a + 1, a + vn + 1, a, a + vn + 1, a + vn]))
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = norms
	arr[Mesh.ARRAY_COLOR] = cols
	arr[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	var mi := MeshInstance3D.new()
	mi.name = "FarMountains"
	mi.mesh = mesh
	mi.material_override = far_mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)

func _build_water() -> void:
	var pm := PlaneMesh.new()
	pm.size = Vector2(1020.0, 1020.0)
	pm.subdivide_width = 8
	pm.subdivide_depth = 8
	water_mat = ShaderMaterial.new()
	water_mat.shader = load("res://shaders/water.gdshader")
	water_mat.set_shader_parameter("depth_tex", depth_tex)
	water_mat.set_shader_parameter("noise_tex", noise_tex)
	water_mat.set_shader_parameter("skyline_tex", _skyline_texture())
	water_mat.set_shader_parameter("map_tex", map_tex)
	var mi := MeshInstance3D.new()
	mi.name = "Water"
	mi.mesh = pm
	mi.material_override = water_mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)

## How high the land stands above the horizon in every compass direction, seen
## from the big lake. The water shader mirrors the mountains from this instead
## of rendering the scene a second time.
func _skyline_texture() -> ImageTexture:
	var n := 256
	var bytes := PackedByteArray()
	bytes.resize(n)
	var c := Vector2(40.0, 30.0)
	for i in n:
		var az := TAU * (float(i) + 0.5) / n - PI     # the shader looks this up with atan(x, z)
		var dirv := Vector2(sin(az), cos(az))
		var best := 0.0
		var d := 150.0
		while d < 2100.0:
			var h: float = data.height_fn(c.x + dirv.x * d, c.y + dirv.y * d)
			if h > 0.0:
				best = maxf(best, h / sqrt(d * d + h * h))
			d *= 1.1
		bytes[i] = int(clampf(best / 0.6, 0.0, 1.0) * 255.0)
	return ImageTexture.create_from_image(Image.create_from_data(n, 1, false, Image.FORMAT_L8, bytes))

## Top-down map of the walkable valley (+-450 m), north (-Z) up.
func make_map_image(size := 300) -> Image:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var n := TerrainData.N
	var hts := data.heights
	var frs := data.forest
	for y in size:
		var wz := ((float(y) + 0.5) / size - 0.5) * 900.0
		var gj := clampi(int((wz + TerrainData.HALF) / TerrainData.CELL), 1, n - 2)
		for x in size:
			var wx := ((float(x) + 0.5) / size - 0.5) * 900.0
			var gi := clampi(int((wx + TerrainData.HALF) / TerrainData.CELL), 1, n - 2)
			var k := gj * n + gi
			var h := hts[k]
			var col: Color
			if h < 0.0:
				col = Color(0.30, 0.47, 0.56).lerp(Color(0.17, 0.30, 0.42), clampf(-h / 5.0, 0.0, 1.0))
			else:
				var f := frs[k]
				var wet := 1.0 - smoothstep(0.9, 2.8, h)
				col = Color(0.62, 0.60, 0.36).lerp(Color(0.66, 0.52, 0.28), wet)
				col = col.lerp(Color(0.20, 0.34, 0.18), f * 0.9)
				col = col.lerp(Color(0.62, 0.60, 0.56), smoothstep(100.0, 170.0, h))
				var shade := clampf(1.0 + ((hts[k - 1] - hts[k + 1]) + (hts[k - n] - hts[k + n])) * 0.09, 0.62, 1.35)
				col = Color(col.r * shade, col.g * shade, col.b * shade)
				# contour lines every 10 m
				if absf(fposmod(h, 10.0) - 5.0) > 4.72:
					col = col.darkened(0.14)
			img.set_pixel(x, y, col)
	return img
