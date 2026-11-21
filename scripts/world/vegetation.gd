class_name Vegetation
extends Node3D
## Scatters trees, rocks and undergrowth as MultiMeshes on a chunk grid with
## two detail levels, streams ground cover around the camera, and answers
## "what solid thing is near here?" for collision and bullets.

const CHUNK := 64.0
const GRID := 16
const SPACING := 4.0
const OBST_CELL := 8.0
const COVER_CELL := 20.0
## The trees built from a solid part and foliage cards, each pictured for the distance.
const BIG := ["spruce", "spruce_b", "spruce_c", "pine", "birch"]

## name -> [lod0 mesh, lod1 mesh or null, far range scale, trunk radius, height]
var kinds := {}
var mat: ShaderMaterial
var grass_mat: ShaderMaterial
var card_mat: ShaderMaterial   ## boughs, needle clusters and leaf sprays (second surface of the big trees)

var cover_meshes := {}
var obstacles := {}            ## Vector2i -> PackedFloat32Array [x, z, radius, top_y, kind] * n
var tree_count := 0
var _near: Array = []          ## [MultiMeshInstance3D]
var _far: Array = []
var _shadow: Array = []        ## plain stand-ins that only cast the big trees' shadows
var _shadow_meshes := {}
var _single: Array = []        ## [mmi, range scale]
var _cover := {}               ## Vector2i -> Array[MultiMeshInstance3D]
var _cover_timer := 0.0
var _cover_queue: Array = []
var _cover_radius := -1.0
var _cover_density := -1.0
var focus := Vector3.ZERO      ## camera position driving ground-cover streaming
var data: TerrainData
var _world: World
## Crown radius (m, at scale 1) of the kinds that shade the ground and drop litter, and
## whether that litter is leaves (birch) or needles.
const CROWN := {"spruce": [2.0, false], "spruce_b": [1.5, false], "spruce_c": [1.8, false],
	"pine": [2.4, false], "birch": [1.9, true], "sapling": [0.7, false]}
var _litter := PackedFloat32Array()  ## TerrainData grid x 3: under a crown, leaves, needles
## Birch crowns for the falling leaves: Vector2i(32 m cell) -> [x, crown centre y, z, radius] * n
var birch_crowns := {}

func build(world: World) -> void:
	data = world.data
	_world = world
	_litter.resize(TerrainData.N * TerrainData.N * 3)
	_litter.fill(0.0)
	mat = ShaderMaterial.new()
	mat.shader = load("res://shaders/foliage.gdshader")
	mat.set_shader_parameter("noise_tex", world.noise_tex)
	grass_mat = ShaderMaterial.new()
	grass_mat.shader = load("res://shaders/grass.gdshader")
	grass_mat.set_shader_parameter("gust_tex", world.noise_tex)
	card_mat = ShaderMaterial.new()
	card_mat.shader = load("res://shaders/foliage_card.gdshader")
	card_mat.set_shader_parameter("card_tex", FloraTextures.atlas())
	kinds = {
		"spruce": [FloraMeshes.spruce(0, 11, 0), FloraMeshes.spruce(1, 11, 0), 1.0, 0.25, 12.0],
		"spruce_b": [FloraMeshes.spruce(0, 17, 1), FloraMeshes.spruce(1, 17, 1), 1.0, 0.25, 12.0],
		"spruce_c": [FloraMeshes.spruce(0, 23, 2), FloraMeshes.spruce(1, 23, 2), 1.0, 0.25, 13.0],
		"pine": [FloraMeshes.pine(0), FloraMeshes.pine(1), 1.0, 0.27, 12.5],
		"birch": [FloraMeshes.birch(0), FloraMeshes.birch(1), 1.0, 0.17, 9.0],
		"snag": [FloraMeshes.snag(0), FloraMeshes.snag(1), 0.7, 0.24, 7.0],
		"sapling": [FloraMeshes.sapling(), null, 0.34, 0.0, 0.0],
		"bush": [FloraMeshes.juniper(), null, 0.3, 0.0, 0.0],
		"bush_b": [FloraMeshes.dwarf_birch(), null, 0.3, 0.0, 0.0],
		"rock": [FloraMeshes.rock(71, 2), FloraMeshes.rock(71, 1), 0.6, 0.95, 0.9],
		"log": [FloraMeshes.log_mesh(), null, 0.28, 0.0, 0.0],
	}
	# the big trees carry their own materials: solid wood first, then the foliage cards
	if G.args.has("plainnear"):      # dev: the old all-solid models up close, for timing comparisons
		for sk in ["spruce", "spruce_b", "spruce_c"]:
			kinds[sk][0] = FloraMeshes._plain_spruce(0)
		kinds["pine"][0] = FloraMeshes._plain_pine(0)
		kinds["birch"][0] = FloraMeshes._plain_birch(0)
	# boulders: their own surface shader; a smooth model up close, a coarser one further out
	var rock_mat := ShaderMaterial.new()
	rock_mat.shader = load("res://shaders/rock.gdshader")
	rock_mat.set_shader_parameter("noise_tex", WorldUtil.noise_texture(256, 4713, [0.045, 0.09, 0.07]))
	for m: ArrayMesh in [kinds["rock"][0], kinds["rock"][1]]:
		m.surface_set_material(0, rock_mat)
	var birch_mat: ShaderMaterial = mat.duplicate()
	birch_mat.set_shader_parameter("birch_bark", 1.0)
	var spruce_mat: ShaderMaterial = mat.duplicate()
	spruce_mat.set_shader_parameter("bark_kind", 2.0)
	var pine_mat: ShaderMaterial = mat.duplicate()
	pine_mat.set_shader_parameter("bark_kind", 3.0)
	var wood_mats := {"birch": birch_mat, "pine": pine_mat, "spruce": spruce_mat, "spruce_b": spruce_mat, "spruce_c": spruce_mat}
	# the young spruces are built the same way, without a far model of their own
	var young: ArrayMesh = kinds["sapling"][0]
	young.surface_set_material(0, mat)
	young.surface_set_material(1, card_mat)
	# so are the bushes: juniper and dwarf birch, twigs and leaf cards
	for bk in ["bush", "bush_b"]:
		var bm: ArrayMesh = kinds[bk][0]
		bm.surface_set_material(0, mat)
		bm.surface_set_material(1, card_mat)
	for kind in BIG:
		var near: ArrayMesh = kinds[kind][0]
		near.surface_set_material(0, wood_mats.get(kind, mat))
		if near.get_surface_count() > 1:
			near.surface_set_material(1, card_mat)
		# shadows are cast by the plain model: solid, a tenth of the triangles, nothing to cut out
		_shadow_meshes[kind] = kinds[kind][1]
	# distant trees: one card each, showing a picture of the full model
	var big: Array = BIG
	var near_meshes := {}
	for kind in big:
		near_meshes[kind] = kinds[kind][0]
	var pics: Dictionary = {} if G.args.has("noimpostors") else await Impostors.bake(self, big, near_meshes, FloraTextures.atlas())
	if not pics.is_empty():
		for kind in big:
			var info: Dictionary = pics["kinds"][kind]
			var im := ShaderMaterial.new()
			im.shader = load("res://shaders/impostor.gdshader")
			im.set_shader_parameter("atlas", pics["texture"])
			im.set_shader_parameter("tile_u", info["tile_u"])
			im.set_shader_parameter("tile_w", pics["tile_w"])
			im.set_shader_parameter("lod_cut", info["cuts"])
			var card := Impostors.card_mesh(info["y0"], info["height"], info["outline"])
			card.surface_set_material(0, im)
			kinds[kind][1] = card
	elif G.test_mode != "":
		print("[flora] no pictures of distant trees: using the plain models")
	cover_meshes = {
		"grass": FloraMeshes.grass_tuft(),
		"fern": FloraMeshes.fern(),
		"shrub": FloraMeshes.shrub(),
		"reed": FloraMeshes.reed(),
	}
	for cz in GRID:
		for cx in GRID:
			_build_chunk(cx, cz)
		world.progress.emit(0.62 + 0.33 * (cz + 1) / GRID, "Planting spruce and birch")
		await get_tree().process_frame
	_bake_litter()
	Settings.changed.connect(_apply_settings)
	_apply_settings()
	if G.test_mode != "":
		print("[flora] trees=%d near_mmi=%d far_mmi=%d single=%d" % [tree_count, _near.size(), _far.size(), _single.size()])

func _apply_settings() -> void:
	var lod := Settings.tree_lod_distance()
	var view := Settings.view_range()
	for m in _near:
		m.visibility_range_end = lod
	for m in _far:
		m.visibility_range_begin = lod
		m.visibility_range_end = maxf(view * float(m.get_meta("range", 1.0)), lod + 20.0)
	for e in _single:
		e[0].visibility_range_end = maxf(view * e[1], 70.0)
	var sh: int = clampi(int(Settings.get_v("shadows")), 0, 3)
	if _world and _world.terrain_mat:
		# beyond the sun's shadow map the ground stands in for the trees' shadows itself
		_world.terrain_mat.set_shader_parameter("shadow_reach", [1.0, 55.0, 95.0, 160.0][sh])
	var shadows: bool = sh > 0 and not G.args.has("noshadowtrees")
	var on := GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	var off := GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for m in _far:
		m.cast_shadow = on if (shadows and sh >= 2 and not m.has_meta("stand_in")) else off
	for m in _near:
		m.cast_shadow = on if (shadows and not m.has_meta("stand_in")) else off
	for m in _shadow:
		m.visible = shadows
		m.visibility_range_end = [0.0, 55.0, 95.0, 160.0][sh] + 55.0
	var changed := not is_equal_approx(_cover_radius, Settings.grass_radius()) or not is_equal_approx(_cover_density, Settings.grass_density())
	_cover_radius = Settings.grass_radius()
	_cover_density = Settings.grass_density()
	grass_mat.set_shader_parameter("fade_start", _cover_radius * 0.62)
	grass_mat.set_shader_parameter("fade_end", _cover_radius * 0.98)
	if changed:
		for key in _cover.keys():
			_free_cover(key)

# ------------------------------------------------------------------ trees
func _build_chunk(cx: int, cz: int) -> void:
	var x0 := cx * CHUNK - TerrainData.HALF
	var z0 := cz * CHUNK - TerrainData.HALF
	var center := Vector3(x0 + CHUNK * 0.5, 0.0, z0 + CHUNK * 0.5)
	var lists := {}
	var per := int(CHUNK / SPACING)
	for j in per:
		for i in per:
			var gx := cx * per + i
			var gz := cz * per + j
			var x := x0 + (i + G.hash2(gx, gz, 1)) * SPACING
			var z := z0 + (j + G.hash2(gx, gz, 2)) * SPACING
			if x * x + z * z > 505.0 * 505.0 or absf(x) > 508.0 or absf(z) > 508.0:
				continue
			var h := data.height(x, z)
			if h < 0.45 or data.in_clear_zone(x, z):
				continue
			var f := data.forest_at(x, z)
			var roll := G.hash2(gx, gz, 3)
			var r2 := G.hash2(gx, gz, 4)
			var r3 := G.hash2(gx, gz, 5)
			var kind := ""
			var scale := 1.0
			if roll < f * 0.78:
				var sp := data.species_at(x, z)
				var p_birch := 0.10 + 0.45 * (1.0 - smoothstep(1.5, 7.0, h)) + 0.30 * (1.0 - smoothstep(0.25, 0.7, f)) + 0.25 * smoothstep(0.55, 0.8, sp)
				var p_pine := 0.08 + 0.55 * smoothstep(22.0, 60.0, h) + 0.35 * smoothstep(0.5, 0.2, sp)
				if r2 < 0.025:
					kind = "snag"
				elif r2 < 0.025 + p_birch * 0.5:
					kind = "birch"
				elif r2 < 0.025 + p_birch * 0.5 + p_pine * 0.5:
					kind = "pine"
				else:
					# spruces in the light keep their boughs to the ground, the forest's edge
					# included; deep in dense forest most have lost the lower ones; narrow comb
					# spruces stand among them all
					kind = "spruce"
					var fr := G.hash2(gx, gz, 13)
					var deep := minf(minf(data.forest_at(x + 9.0, z), data.forest_at(x - 9.0, z)), minf(data.forest_at(x, z + 9.0), data.forest_at(x, z - 9.0)))
					if f > 0.55 and deep > 0.5 and fr < 0.65:
						kind = "spruce_c"
					elif fr < (0.55 if f > 0.3 else 0.25):
						kind = "spruce_b"
				scale = 0.72 + r3 * 0.62
				if h > 85.0:
					scale *= lerpf(1.0, 0.5, smoothstep(85.0, 150.0, h))
			elif roll < f * 0.78 + 0.05 * f + 0.012:
				kind = "sapling"
				scale = 0.7 + r3 * 1.3
			elif roll < f * 0.83 + 0.012 + 0.03:
				if h > 1.2 and data.slope(x, z) < 0.35:
					# juniper in the woods and on dry ground, dwarf birch out in the open and on wet ground
					var juniper := G.hash2(gx, gz, 12) < lerpf(0.2, 0.75, f) - (0.25 if h < 2.5 else 0.0)
					kind = ("bush" if juniper else "bush_b") if r2 < 0.6 else ("log" if f > 0.3 else ("bush" if juniper else "bush_b"))
					scale = 0.7 + r3 * 0.8
			elif roll > 0.985 - 0.02 * smoothstep(0.15, 0.4, data.slope(x, z)):
				kind = "rock"
				scale = 0.45 + r3 * r3 * 1.9
			elif roll > 0.972 and h > 1.0 and h < 3.2 and f < 0.2:
				kind = "pine"          # stunted bog pines
				scale = 0.3 + r3 * 0.28
			elif roll > 0.962 and f < 0.25 and h > 2.5 and h < 100.0 and data.slope(x, z) < 0.3:
				kind = "birch" if r2 < 0.55 else "pine"   # lone trees in the open
				scale = 0.75 + r3 * 0.5
			if kind == "":
				continue
			var yaw := G.hash2(gx, gz, 6) * TAU
			var tilt := Vector3((G.hash2(gx, gz, 7) - 0.5) * 0.09, yaw, (G.hash2(gx, gz, 8) - 0.5) * 0.09)
			if kind == "rock" or kind == "log":
				tilt = Vector3((G.hash2(gx, gz, 7) - 0.5) * 0.5, yaw, (G.hash2(gx, gz, 8) - 0.5) * 0.3)
			var sy := scale * (0.9 + G.hash2(gx, gz, 9) * 0.25)
			var basis := Basis.from_euler(tilt).scaled(Vector3(scale, sy, scale))
			if kind == "rock":
				basis = Basis.from_euler(tilt).scaled(Vector3(scale, scale * (0.7 + r2 * 0.5), scale * (0.8 + r3 * 0.4)))
			var sink := 0.25 * scale if kind == "rock" else 0.05
			var t := Transform3D(basis, Vector3(x, h - sink, z) - center)
			var b := 0.84 + G.hash2(gx, gz, 10) * 0.30
			var tint := Color(b, b * (0.95 + G.hash2(gx, gz, 11) * 0.1), b * 0.96)
			if kind == "birch":
				var w := G.hash2(gx, gz, 12)
				tint = Color(b, b * lerpf(0.86, 1.06, w), b * lerpf(0.8, 1.0, w))
			if not lists.has(kind):
				lists[kind] = []
			lists[kind].append([t, tint])
			if CROWN.has(kind):
				_splat_litter(x, z, CROWN[kind][0] * scale, CROWN[kind][1])
			if kind == "birch":
				var cell := Vector2i(floori(x / 32.0), floori(z / 32.0))
				if not birch_crowns.has(cell):
					birch_crowns[cell] = PackedFloat32Array()
				var arr: PackedFloat32Array = birch_crowns[cell]
				arr.append_array(PackedFloat32Array([x, h + 6.0 * sy, z, 1.7 * scale]))
				birch_crowns[cell] = arr
			var info: Array = kinds[kind]
			if info[3] > 0.0:
				_add_obstacle(x, z, info[3] * scale, h + info[4] * sy, 1.0 if kind == "rock" else 0.0)
				if kind != "rock":
					tree_count += 1
	for kind in lists:
		_spawn_multimesh(kind, lists[kind], center)

## Birch crowns within `radius` of `p`: [x, y, z, crown radius] * n.
func birches_near(p: Vector3, radius: float) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	var c0 := Vector2i(floori((p.x - radius) / 32.0), floori((p.z - radius) / 32.0))
	var c1 := Vector2i(floori((p.x + radius) / 32.0), floori((p.z + radius) / 32.0))
	for cz in range(c0.y, c1.y + 1):
		for cx in range(c0.x, c1.x + 1):
			var arr: PackedFloat32Array = birch_crowns.get(Vector2i(cx, cz), PackedFloat32Array())
			for i in range(0, arr.size(), 4):
				var dx := arr[i] - p.x
				var dz := arr[i + 2] - p.z
				if dx * dx + dz * dz < radius * radius:
					out.append_array(arr.slice(i, i + 4))
	return out

## Mark the ground under a tree's crown (radius `r`) and the litter it drops round it,
## on the terrain map's grid: soft discs, merged as "either" so overlapping crowns saturate.
func _splat_litter(x: float, z: float, r: float, leaves: bool) -> void:
	var n := TerrainData.N
	var cell := TerrainData.CELL
	var cx := (x + TerrainData.HALF) / cell
	var cz := (z + TerrainData.HALF) / cell
	var rl := r * (1.6 if leaves else 1.15)          # leaves blow further than needles fall
	var rp := rl / cell
	for j in range(maxi(int(cz - rp), 0), mini(int(cz + rp) + 2, n)):
		for i in range(maxi(int(cx - rp), 0), mini(int(cx + rp) + 2, n)):
			var dx := (i - cx) * cell
			var dz := (j - cz) * cell
			var d := sqrt(dx * dx + dz * dz)
			if d >= rl:
				continue
			var o := (j * n + i) * 3
			var kl := 1.0 - d / rl
			kl = kl * kl * (3.0 - 2.0 * kl)
			var kc := clampf(1.0 - d / r, 0.0, 1.0)
			kc = kc * kc * (3.0 - 2.0 * kc)
			_litter[o] = 1.0 - (1.0 - _litter[o]) * (1.0 - kc * 0.85)
			var ch := o + (1 if leaves else 2)
			_litter[ch] = 1.0 - (1.0 - _litter[ch]) * (1.0 - kl * 0.8)

## Hand the ground its map of crowns and litter (see terrain.gdshaderinc).
func _bake_litter() -> void:
	var n := TerrainData.N
	var bytes := PackedByteArray()
	bytes.resize(n * n * 4)
	for k in n * n:
		bytes[k * 4] = int(_litter[k * 3] * 255.0)
		bytes[k * 4 + 1] = int(_litter[k * 3 + 1] * 255.0)
		bytes[k * 4 + 2] = int(_litter[k * 3 + 2] * 255.0)
		bytes[k * 4 + 3] = 255
	var img := Image.create_from_data(n, n, false, Image.FORMAT_RGBA8, bytes)
	img.generate_mipmaps()
	var tex := ImageTexture.create_from_image(img)
	_world.terrain_mat.set_shader_parameter("litter_tex", tex)
	if _world.water_mat:
		_world.water_mat.set_shader_parameter("litter_tex", tex)      # the lakes mirror the shores' trees
	_litter = PackedFloat32Array()

func _spawn_multimesh(kind: String, items: Array, center: Vector3) -> void:
	var info: Array = kinds[kind]
	var count := items.size()
	var buf := PackedFloat32Array()
	buf.resize(count * 16)
	var y_min := INF
	var y_max := -INF
	for i in count:
		var t: Transform3D = items[i][0]
		var col: Color = items[i][1]
		var o := i * 16
		buf[o] = t.basis.x.x
		buf[o + 1] = t.basis.y.x
		buf[o + 2] = t.basis.z.x
		buf[o + 3] = t.origin.x
		buf[o + 4] = t.basis.x.y
		buf[o + 5] = t.basis.y.y
		buf[o + 6] = t.basis.z.y
		buf[o + 7] = t.origin.y
		buf[o + 8] = t.basis.x.z
		buf[o + 9] = t.basis.y.z
		buf[o + 10] = t.basis.z.z
		buf[o + 11] = t.origin.z
		buf[o + 12] = col.r
		buf[o + 13] = col.g
		buf[o + 14] = col.b
		buf[o + 15] = 1.0
		y_min = minf(y_min, t.origin.y)
		y_max = maxf(y_max, t.origin.y)
	var aabb := AABB(Vector3(-CHUNK * 0.5 - 4.0, y_min - 2.0, -CHUNK * 0.5 - 4.0), Vector3(CHUNK + 8.0, y_max - y_min + 22.0, CHUNK + 8.0))
	for lod in 2:
		var mesh: Mesh = info[lod]
		if mesh == null:
			continue
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.mesh = mesh
		mm.instance_count = count
		mm.buffer = buf
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		if mesh.surface_get_material(0) == null:
			mmi.material_override = mat
		mmi.position = center
		mmi.custom_aabb = aabb
		mmi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
		add_child(mmi)
		if _shadow_meshes.has(kind):
			mmi.set_meta("stand_in", true)
		if info[1] == null:
			_single.append([mmi, info[2]])
			if kind in ["bush", "bush_b", "log", "sapling"]:
				mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		elif lod == 0:
			_near.append(mmi)
		else:
			_far.append(mmi)
			if kind == "rock":
				mmi.set_meta("range", info[2])     # boulders fade out sooner than trees
	if _shadow_meshes.has(kind):
		var smm := MultiMesh.new()
		smm.transform_format = MultiMesh.TRANSFORM_3D
		smm.use_colors = true
		smm.mesh = _shadow_meshes[kind]
		smm.instance_count = count
		smm.buffer = buf
		var caster := MultiMeshInstance3D.new()
		caster.multimesh = smm
		caster.material_override = mat
		caster.position = center
		caster.custom_aabb = aabb
		caster.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
		caster.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
		add_child(caster)
		_shadow.append(caster)

# -------------------------------------------------------------- obstacles
func _add_obstacle(x: float, z: float, radius: float, top_y: float, kind: float) -> void:
	var key := Vector2i(floori(x / OBST_CELL), floori(z / OBST_CELL))
	if not obstacles.has(key):
		obstacles[key] = PackedFloat32Array()
	var arr: PackedFloat32Array = obstacles[key]
	arr.append_array(PackedFloat32Array([x, z, radius, top_y, kind]))
	obstacles[key] = arr

## Pushes a circle (pos.xz, radius) out of trunks and boulders; returns the corrected position.
func push_out(pos: Vector3, radius: float) -> Vector3:
	var kx := floori(pos.x / OBST_CELL)
	var kz := floori(pos.z / OBST_CELL)
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			var key := Vector2i(kx + dx, kz + dz)
			if not obstacles.has(key):
				continue
			var arr: PackedFloat32Array = obstacles[key]
			for i in range(0, arr.size(), 5):
				if pos.y > arr[i + 3]:
					continue
				var ox := pos.x - arr[i]
				var oz := pos.z - arr[i + 1]
				var rr := arr[i + 2] + radius
				var d2 := ox * ox + oz * oz
				if d2 < rr * rr and d2 > 0.00001:
					var d := sqrt(d2)
					pos.x = arr[i] + ox / d * rr
					pos.z = arr[i + 1] + oz / d * rr
	return pos

## Sum of repulsion from nearby obstacles (for animal steering).
func avoid_vector(pos: Vector3, reach: float) -> Vector2:
	var out := Vector2.ZERO
	var kx := floori(pos.x / OBST_CELL)
	var kz := floori(pos.z / OBST_CELL)
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			var key := Vector2i(kx + dx, kz + dz)
			if not obstacles.has(key):
				continue
			var arr: PackedFloat32Array = obstacles[key]
			for i in range(0, arr.size(), 5):
				var ox := pos.x - arr[i]
				var oz := pos.z - arr[i + 1]
				var rr := arr[i + 2] + reach
				var d2 := ox * ox + oz * oz
				if d2 < rr * rr and d2 > 0.0001:
					var d := sqrt(d2)
					out += Vector2(ox, oz) / d * (1.0 - d / rr)
	return out

## Segment vs trunks/boulders. Returns {pos, normal, kind} for the first hit, or {}.
func ray(from: Vector3, to: Vector3) -> Dictionary:
	var best_t := 2.0
	var best := {}
	var d := to - from
	var x_min := floori(minf(from.x, to.x) / OBST_CELL - 0.2)
	var x_max := floori(maxf(from.x, to.x) / OBST_CELL + 0.2)
	var z_min := floori(minf(from.z, to.z) / OBST_CELL - 0.2)
	var z_max := floori(maxf(from.z, to.z) / OBST_CELL + 0.2)
	if (x_max - x_min + 1) * (z_max - z_min + 1) > 64:
		return best
	var a := d.x * d.x + d.z * d.z
	if a < 1e-9:
		return best
	for kz in range(z_min, z_max + 1):
		for kx in range(x_min, x_max + 1):
			var key := Vector2i(kx, kz)
			if not obstacles.has(key):
				continue
			var arr: PackedFloat32Array = obstacles[key]
			for i in range(0, arr.size(), 5):
				var fx := from.x - arr[i]
				var fz := from.z - arr[i + 1]
				var r := arr[i + 2]
				var b := 2.0 * (fx * d.x + fz * d.z)
				var c := fx * fx + fz * fz - r * r
				var disc := b * b - 4.0 * a * c
				if disc < 0.0:
					continue
				var t := (-b - sqrt(disc)) / (2.0 * a)
				if t < 0.0 or t > 1.0 or t >= best_t:
					continue
				var p := from + d * t
				if p.y > arr[i + 3]:
					continue
				best_t = t
				best = {"pos": p, "normal": Vector3(p.x - arr[i], 0.0, p.z - arr[i + 1]).normalized(), "kind": "rock" if arr[i + 4] > 0.5 else "wood"}
	return best

# ----------------------------------------------------------- ground cover
func _process(dt: float) -> void:
	if data == null or not data.ready:
		return
	_cover_timer -= dt
	if _cover_timer <= 0.0:
		_cover_timer = 0.2
		_update_cover_set()
	if not _cover_queue.is_empty():
		var key: Vector2i = _cover_queue.pop_front()
		if not _cover.has(key):
			_build_cover(key)

func _update_cover_set() -> void:
	var r := _cover_radius
	var pc := Vector2(focus.x, focus.z)
	for key in _cover.keys():
		var c := (Vector2(key) + Vector2(0.5, 0.5)) * COVER_CELL
		if r <= 0.0 or c.distance_to(pc) > r + COVER_CELL * 1.6:
			_free_cover(key)
	if r <= 0.0:
		_cover_queue.clear()
		return
	var kx := floori(focus.x / COVER_CELL)
	var kz := floori(focus.z / COVER_CELL)
	var span := int(ceil(r / COVER_CELL)) + 1
	var want: Array = []
	for dz in range(-span, span + 1):
		for dx in range(-span, span + 1):
			var key := Vector2i(kx + dx, kz + dz)
			if _cover.has(key):
				continue
			var c := (Vector2(key) + Vector2(0.5, 0.5)) * COVER_CELL
			var d := c.distance_to(pc)
			if d < r + COVER_CELL * 0.75:
				want.append([d, key])
	want.sort_custom(func(a, b): return a[0] < b[0])
	_cover_queue.clear()
	for w in want:
		_cover_queue.append(w[1])

## Drop the ground cover around `pos` so it grows again (e.g. round a new building).
func clear_cover_near(pos: Vector3, radius: float) -> void:
	for key in _cover.keys():
		var c := (Vector2(key) + Vector2(0.5, 0.5)) * COVER_CELL
		if c.distance_to(Vector2(pos.x, pos.z)) < radius + COVER_CELL:
			_free_cover(key)

func _free_cover(key: Vector2i) -> void:
	for n in _cover[key]:
		n.queue_free()
	_cover.erase(key)

func _build_cover(key: Vector2i) -> void:
	var x0 := key.x * COVER_CELL
	var z0 := key.y * COVER_CELL
	var center := Vector3(x0 + COVER_CELL * 0.5, 0.0, z0 + COVER_CELL * 0.5)
	var bufs := {"grass": PackedFloat32Array(), "fern": PackedFloat32Array(), "shrub": PackedFloat32Array(), "reed": PackedFloat32Array()}
	var step := 0.8
	var per := int(COVER_CELL / step)
	var y_min := INF
	var y_max := -INF
	var st: Structures = G.world.structures if G.world else null
	for j in per:
		for i in per:
			var gx := key.x * per + i
			var gz := key.y * per + j
			var x := x0 + (i + G.hash2(gx, gz, 21)) * step
			var z := z0 + (j + G.hash2(gx, gz, 22)) * step
			if absf(x) > 505.0 or absf(z) > 505.0:
				continue
			if st and st.covers(x, z):
				continue
			var h := data.height(x, z)
			if h < -0.45:
				continue
			var roll := G.hash2(gx, gz, 23)
			if roll > _cover_density:
				continue
			roll /= maxf(_cover_density, 0.01)
			var f := data.forest_at(x, z)
			var kind := ""
			var s := 0.8 + G.hash2(gx, gz, 24) * 0.7
			var col := Color.WHITE
			if h < 0.3:
				if roll < 0.5:
					kind = "reed"
					col = Color(0.42, 0.44, 0.17).lerp(Color(0.58, 0.47, 0.2), G.hash2(gx, gz, 25))
			else:
				var sl := data.slope(x, z)
				if sl > 0.3:
					continue
				var patch := data.patch_at(x, z)
				var wet := 1.0 - smoothstep(0.9, 2.6, h)
				var p_grass := lerpf(0.72, 0.16, f) + wet * 0.2
				var p_fern := 0.07 * smoothstep(0.3, 0.7, f)
				var p_shrub := 0.06 + 0.2 * f + 0.2 * smoothstep(0.6, 0.8, patch) * (1.0 - wet)
				if roll < p_grass:
					kind = "grass"
					var g := data.ground_color(x, z)
					var gv := 0.85 + G.hash2(gx, gz, 25) * 0.35
					col = Color((g.r * 1.5 + 0.05) * gv, (g.g * 1.5 + 0.05) * gv, (g.b * 1.3 + 0.02) * gv)
					s *= 1.0 + wet * 0.6
				elif roll < p_grass + p_fern:
					kind = "fern"
					col = Color(0.36, 0.27, 0.09).lerp(Color(0.17, 0.25, 0.07), G.hash2(gx, gz, 25))
					s *= 0.9
				elif roll < p_grass + p_fern + p_shrub:
					kind = "shrub"
					col = Color(0.40, 0.09, 0.07).lerp(Color(0.15, 0.24, 0.07), G.hash2(gx, gz, 25))
					if patch > 0.7:
						col = col.lerp(Color(0.30, 0.13, 0.22), 0.5)
					s *= 0.95
			if kind == "":
				continue
			var yaw := G.hash2(gx, gz, 26) * TAU
			var cs := cos(yaw) * s
			var sn := sin(yaw) * s
			var buf: PackedFloat32Array = bufs[kind]
			buf.append_array(PackedFloat32Array([
				cs, 0.0, sn, x - center.x,
				0.0, s * (0.85 + G.hash2(gx, gz, 27) * 0.4), 0.0, h,
				-sn, 0.0, cs, z - center.z,
				col.r, col.g, col.b, 1.0]))
			bufs[kind] = buf
			y_min = minf(y_min, h)
			y_max = maxf(y_max, h)
	var nodes: Array = []
	for kind in bufs:
		var buf: PackedFloat32Array = bufs[kind]
		if buf.is_empty():
			continue
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.mesh = cover_meshes[kind]
		mm.instance_count = buf.size() / 16
		mm.buffer = buf
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.material_override = grass_mat
		mmi.position = center
		mmi.custom_aabb = AABB(Vector3(-COVER_CELL * 0.5 - 1.0, y_min - 1.0, -COVER_CELL * 0.5 - 1.0), Vector3(COVER_CELL + 2.0, y_max - y_min + 4.0, COVER_CELL + 2.0))
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mmi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
		add_child(mmi)
		nodes.append(mmi)
	_cover[key] = nodes
