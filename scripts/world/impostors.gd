class_name Impostors
extends RefCounted
## Distant trees are drawn as one upright card each, carrying a picture of the
## full model. The pictures are taken here, once, when the world is built: every
## kind is photographed from two sides into a strip of tiles.

const TILE_W := 512
const TILE_H := 1024
const BANDS := 8      ## the card is cut to the tree's outline in this many steps
const LEVELS := 12    ## mip levels of the atlas that get their own alpha cut-off

const SOLID_CODE := """shader_type spatial;
render_mode unshaded, cull_back;
varying float shade;
void vertex() {
	shade = 0.72 + 0.28 * clamp(NORMAL.y * 0.5 + 0.5, 0.0, 1.0);
}
void fragment() {
	vec3 alb = pow(COLOR.rgb, vec3(1.3)) * 0.62;
	alb = mix(vec3(dot(alb, vec3(0.3, 0.59, 0.11))), alb, 0.88);
	ALBEDO = alb * shade;
}
"""

const CARD_CODE := """shader_type spatial;
render_mode unshaded, cull_disabled;
uniform sampler2D card_tex : filter_linear_mipmap, repeat_disable;
varying float shade;
void vertex() {
	shade = 0.72 + 0.28 * clamp(NORMAL.y * 0.5 + 0.5, 0.0, 1.0);
}
void fragment() {
	vec4 t = texture(card_tex, UV);
	ALPHA = t.a;
	ALPHA_SCISSOR_THRESHOLD = 0.5;
	vec3 alb = pow(COLOR.rgb, vec3(1.3)) * 0.62 * (0.28 + t.r * 0.86) * (vec3(1.0) + vec3(0.22, -0.03, -0.3) * (t.b * 2.0 - 1.0));
	alb = mix(vec3(dot(alb, vec3(0.3, 0.59, 0.11))), alb, 0.88);
	ALBEDO = alb * shade;
}
"""

## Photographs `meshes[kind]` (two surfaces: solid, cards) for every kind.
## Returns {} if the pictures could not be taken, otherwise
## { "texture": ImageTexture, "tile_w": float, "kinds": { kind: { "tile_u", "y0", "height", "outline", "cuts" } } }.
static func bake(host: Node, kinds: Array, meshes: Dictionary, card_tex: Texture2D) -> Dictionary:
	var slots := kinds.size() * 2
	var vp := SubViewport.new()
	vp.size = Vector2i(TILE_W * slots, TILE_H)
	vp.own_world_3d = true
	vp.transparent_bg = true
	vp.msaa_3d = Viewport.MSAA_DISABLED
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	host.add_child(vp)
	var view_h := 10.0
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = view_h
	cam.near = 0.1
	cam.far = 200.0
	vp.add_child(cam)
	cam.position = Vector3(0, view_h * 0.5, 80.0)
	cam.current = true
	var solid_sh := Shader.new()
	solid_sh.code = SOLID_CODE
	var solid_mat := ShaderMaterial.new()
	solid_mat.shader = solid_sh
	var card_sh := Shader.new()
	card_sh.code = CARD_CODE
	var card_mat := ShaderMaterial.new()
	card_mat.shader = card_sh
	card_mat.set_shader_parameter("card_tex", card_tex)
	var out := {"tile_w": 1.0 / slots, "kinds": {}}
	for i in kinds.size():
		var mesh: ArrayMesh = meshes[kinds[i]]
		var bb := mesh.get_aabb()
		var radius := 0.0
		for surf in mesh.get_surface_count():
			var verts: PackedVector3Array = mesh.surface_get_arrays(surf)[Mesh.ARRAY_VERTEX]
			for p in verts:
				radius = maxf(radius, Vector2(p.x, p.z).length())
		var y0 := bb.position.y
		var height := maxf(bb.size.y, radius * 4.0) * 1.03
		var s := view_h / height
		for variant in 2:
			var slot := i * 2 + variant
			var mi := MeshInstance3D.new()
			mi.mesh = mesh
			mi.set_surface_override_material(0, solid_mat)
			if mesh.get_surface_count() > 1:
				mi.set_surface_override_material(1, card_mat)
			mi.transform = Transform3D(Basis(Vector3.UP, 0.7 + variant * 2.3).scaled(Vector3(s, s, s)),
				Vector3((slot + 0.5 - slots * 0.5) * view_h * 0.5, -y0 * s, 0.0))
			vp.add_child(mi)
		out["kinds"][kinds[i]] = {"tile_u": float(i * 2) / slots, "y0": y0, "height": height}
	var img: Image = null
	for attempt in 45:
		await host.get_tree().process_frame
		# draw now rather than wait for the window's next frame: a window that is not
		# on screen (another workspace, minimised) is never asked to draw
		RenderingServer.force_draw(false)
		var got := vp.get_texture().get_image()
		if got and not got.is_empty() and _has_trees(got, slots):
			img = got
			break
	vp.queue_free()
	if img == null:
		return {}
	if img.get_format() != Image.FORMAT_RGBA8:
		img.convert(Image.FORMAT_RGBA8)
	if G.out_dir != "" and G.args.has("dumpimpostors"):
		img.save_png(G.out_dir + "/impostors.png")
	# how far the tree reaches to either side, top to bottom: the cards are cut to that
	var small: Image = img.duplicate()
	small.resize(img.get_width() / 8, img.get_height() / 8, Image.INTERPOLATE_BILINEAR)
	for i in kinds.size():
		out["kinds"][kinds[i]]["outline"] = _outline(small, slots, i)
	img.generate_mipmaps()
	for i in kinds.size():
		out["kinds"][kinds[i]]["cuts"] = _level_cuts(img, slots, i)
	out["texture"] = ImageTexture.create_from_image(img)
	return out

## The alpha cut-off for each mip level of a kind's pictures that keeps as much
## of the tree solid as in the full-size picture. Thin needles and twigs average
## out to faint alpha in the smaller copies; a fixed cut-off would let a distant
## crown thin out to bare branches.
static func _level_cuts(img: Image, slots: int, kind_index: int) -> PackedFloat32Array:
	var data := img.get_data()
	var cuts := PackedFloat32Array()
	var cover := -1.0
	for level in LEVELS:
		var w := maxi(img.get_width() >> level, 1)
		var h := maxi(img.get_height() >> level, 1)
		var slot_w := maxi(w / slots, 1)
		var x0 := kind_index * 2 * slot_w
		var x1 := mini(x0 + slot_w * 2, w)
		var off := img.get_mipmap_offset(level)
		# a few thousand samples are plenty to find the quantile
		var stride := maxi(1, int(sqrt(float((x1 - x0) * h) / 4096.0)))
		var hist := PackedInt32Array()
		hist.resize(256)
		var n := 0
		for y in range(0, h, stride):
			var row := off + (y * w) * 4 + 3
			for x in range(x0, x1, stride):
				hist[data[row + x * 4]] += 1
				n += 1
		if n == 0:
			cuts.append(cuts[-1] if not cuts.is_empty() else 0.5)
			continue
		if cover < 0.0:
			# the full-size picture: alpha is all or nothing
			var solid := 0
			for a in range(128, 256):
				solid += hist[a]
			cover = float(solid) / n
			cuts.append(0.5)
			continue
		var need := int(cover * n)
		var acc := 0
		var a := 255
		while a > 1:
			acc += hist[a]
			if acc >= need:
				break
			a -= 1
		cuts.append(clampf(a / 255.0, 0.06, 0.5))
	return cuts

## Half-width of a kind's two pictures at BANDS + 1 heights from the top down,
## as a fraction (0..1) of half a tile.
static func _outline(small: Image, slots: int, kind_index: int) -> PackedFloat32Array:
	var w := small.get_width() / slots
	var h := small.get_height()
	var half := w / 2
	var band_max := PackedFloat32Array()
	band_max.resize(BANDS)
	for y in h:
		var band := mini(y * BANDS / h, BANDS - 1)
		for variant in 2:
			var x0 := (kind_index * 2 + variant) * w
			var reach := 0
			for dx in range(half - 1, -1, -1):
				if small.get_pixel(x0 + half + dx, y).a > 0.03 or small.get_pixel(x0 + half - 1 - dx, y).a > 0.03:
					reach = dx + 1
					break
			band_max[band] = maxf(band_max[band], float(reach))
	var out := PackedFloat32Array()
	for k in BANDS + 1:
		var reach := maxf(band_max[maxi(k - 1, 0)], band_max[mini(k, BANDS - 1)])
		out.append(clampf((reach + 2.0) / half, 0.06, 1.0))
	return out

## Every tile should show a trunk low down in its middle.
static func _has_trees(img: Image, slots: int) -> bool:
	var w := img.get_width() / slots
	for slot in slots:
		var hit := false
		for row in [0.9, 0.93, 0.96]:
			for dx in range(-12, 13, 3):
				if img.get_pixel(slot * w + w / 2 + dx, int(img.get_height() * row)).a > 0.5:
					hit = true
		if not hit:
			return false
	return true

## The card a distant tree is drawn on: upright, `height` tall with its foot at `y0`,
## at most half as wide as it is tall and cut in to follow `outline` (see _outline).
static func card_mesh(y0: float, height: float, outline: PackedFloat32Array) -> ArrayMesh:
	var k := MeshKit.new()
	var half := height * 0.25
	var rows := outline.size()
	for r in rows:
		var v := float(r) / (rows - 1)
		var f := outline[r]
		k.vert(Vector3(-half * f, y0 + height * (1.0 - v), 0), Vector3(0, 0, 1), Color.WHITE, Vector2(0.5 - 0.5 * f, v))
		k.vert(Vector3(half * f, y0 + height * (1.0 - v), 0), Vector3(0, 0, 1), Color.WHITE, Vector2(0.5 + 0.5 * f, v))
	for r in rows - 1:
		var a := r * 2
		k.quad(a + 2, a + 3, a + 1, a)
	return k.commit()
