class_name Hud
extends Control
## In-hunt HUD: crosshair, compass, clock, score, ammo, prompts, scope mask,
## kill banners and the fold-out map. Deliberately sparse.

const COMPASS_W := 460.0
const POINTS := ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]

var scope: ColorRect
var scope_mat: ShaderMaterial
var _clock: Label
var _score: Label
var _score_sub: Label
var _weapon: Label
var _prompt: Label
var _msg: Label
var _banner: VBoxContainer
var _banner_title: Label
var _banner_sub: Label
var _banner_pts: Label
var _fps: Label
var _zoom: Label
var _map: Control
var _map_tex: TextureRect
var _map_markers: Control
var _msg_t := 0.0
var _banner_t := 0.0
var _hit_t := 0.0
var _hit_kill := false
var _range_t := 0.0
var _range := -1.0
var _shown_score := 0.0
var _holds_px: Array = []
var _fade := 0.0
var _canvas: Control

func _ready() -> void:
	G.hud = self
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	theme = UiKit.theme()
	# a soft darkening towards the corners draws the eye into the view
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.55, 1.0])
	grad.colors = PackedColorArray([Color(0, 0, 0, 0), Color(0, 0, 0, 0), Color(0.02, 0.015, 0.03, 0.34)])
	var vig_tex := GradientTexture2D.new()
	vig_tex.gradient = grad
	vig_tex.fill = GradientTexture2D.FILL_RADIAL
	vig_tex.fill_from = Vector2(0.5, 0.5)
	vig_tex.fill_to = Vector2(1.0, 1.0)
	vig_tex.width = 256
	vig_tex.height = 256
	var vignette := TextureRect.new()
	vignette.texture = vig_tex
	vignette.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	vignette.stretch_mode = TextureRect.STRETCH_SCALE
	vignette.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(vignette)
	scope = ColorRect.new()
	scope.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scope.mouse_filter = Control.MOUSE_FILTER_IGNORE
	scope_mat = ShaderMaterial.new()
	scope_mat.shader = load("res://shaders/scope.gdshader")
	scope.material = scope_mat
	scope.visible = false
	add_child(scope)
	_canvas = Control.new()
	_canvas.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.draw.connect(_draw_hud)
	add_child(_canvas)

	_clock = UiKit.shadowed(UiKit.label("06:30", 24, UiKit.TEXT, true))
	_clock.position = Vector2(40, 30)
	add_child(_clock)

	_score = UiKit.shadowed(UiKit.label("0", 34, UiKit.TEXT, true))
	_score.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_anchor(_score, 1, 0, -340, 24, 300, 44)
	_score_sub = UiKit.shadowed(UiKit.label("", 16, UiKit.DIM))
	_score_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_anchor(_score_sub, 1, 0, -340, 66, 300, 24)

	_weapon = UiKit.shadowed(UiKit.label("", 18, UiKit.DIM))
	_weapon.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_anchor(_weapon, 1, 1, -440, -62, 400, 26)

	_prompt = UiKit.shadowed(UiKit.label("", 21, UiKit.TEXT))
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_anchor(_prompt, 0.5, 1, -400, -190, 800, 30)

	_msg = UiKit.shadowed(UiKit.label("", 22, UiKit.TEXT))
	_msg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_anchor(_msg, 0.5, 1, -500, -250, 1000, 32)
	_msg.modulate.a = 0.0

	_banner = UiKit.vbox(2)
	_anchor(_banner, 0.5, 0, -400, 150, 800, 160)
	_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_banner_title = UiKit.shadowed(UiKit.label("", 40, UiKit.TEXT, true))
	_banner_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner_sub = UiKit.shadowed(UiKit.label("", 22, UiKit.TEXT))
	_banner_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner_pts = UiKit.shadowed(UiKit.label("", 32, UiKit.ACCENT, true))
	_banner_pts.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner.add_child(_banner_title)
	_banner.add_child(_banner_sub)
	_banner.add_child(_banner_pts)
	_banner.modulate.a = 0.0

	_zoom = UiKit.shadowed(UiKit.label("", 20, UiKit.TEXT))
	_zoom.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_anchor(_zoom, 0.5, 1, -200, -112, 400, 28)

	_fps = UiKit.shadowed(UiKit.label("", 16, UiKit.DIM))
	_fps.position = Vector2(40, 64)
	add_child(_fps)
	_build_map()

func _anchor(c: Control, ax: float, ay: float, x: float, y: float, w: float, h: float) -> void:
	c.anchor_left = ax
	c.anchor_right = ax
	c.anchor_top = ay
	c.anchor_bottom = ay
	c.offset_left = x
	c.offset_top = y
	c.offset_right = x + w
	c.offset_bottom = y + h
	add_child(c)

func _build_map() -> void:
	_map = UiKit.panel(Color(0.04, 0.05, 0.055, 0.93), 12, 18)
	_map.anchor_left = 0.5
	_map.anchor_right = 0.5
	_map.anchor_top = 0.5
	_map.anchor_bottom = 0.5
	_map.offset_left = -390
	_map.offset_right = 390
	_map.offset_top = -420
	_map.offset_bottom = 420
	_map.visible = false
	add_child(_map)
	var v := UiKit.vbox(10)
	_map.add_child(v)
	var head := UiKit.hbox()
	head.add_child(UiKit.label("MOOSE COUNTRY", 22, UiKit.TEXT, true))
	head.add_child(UiKit.expander())
	head.add_child(UiKit.label("N ↑", 18, UiKit.DIM))
	v.add_child(head)
	_map_tex = TextureRect.new()
	_map_tex.custom_minimum_size = Vector2(744, 744)
	_map_tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_map_tex.stretch_mode = TextureRect.STRETCH_SCALE
	_map_tex.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	v.add_child(_map_tex)
	_map_markers = Control.new()
	_map_markers.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_map_markers.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_map_markers.draw.connect(_draw_map_markers)
	_map_tex.add_child(_map_markers)

func set_map_image(img: Image) -> void:
	_map_tex.texture = ImageTexture.create_from_image(img)

func _map_pt(world: Vector3) -> Vector2:
	var s := _map_tex.size
	# the map shows the walkable valley (+-450 m)
	return Vector2((world.x / 900.0 + 0.5) * s.x, (world.z / 900.0 + 0.5) * s.y)

func _draw_map_markers() -> void:
	var c := _map_markers
	var t: TerrainData = G.terrain
	var f := UiKit.bold()
	# cabin
	var cp := _map_pt(t.cabin_pos)
	c.draw_rect(Rect2(cp - Vector2(7, 6), Vector2(14, 12)), Color(0.75, 0.16, 0.12))
	c.draw_colored_polygon(PackedVector2Array([cp + Vector2(-10, -6), cp + Vector2(0, -15), cp + Vector2(10, -6)]), Color(0.9, 0.9, 0.86))
	c.draw_string(f, cp + Vector2(14, 5), "Cabin", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, UiKit.TEXT)
	for site in t.tower_sites:
		var tp := _map_pt(site[0])
		c.draw_rect(Rect2(tp - Vector2(5, 5), Vector2(10, 10)), Color(0.9, 0.82, 0.6), false, 2.0)
		c.draw_line(tp + Vector2(-5, 5), tp + Vector2(-8, 11), Color(0.9, 0.82, 0.6), 2.0)
		c.draw_line(tp + Vector2(5, 5), tp + Vector2(8, 11), Color(0.9, 0.82, 0.6), 2.0)
	if G.herd:
		for m in G.herd.moose:
			if m.dead:
				var mp := _map_pt(m.centre())
				var col := UiKit.FAINT if m.tagged else UiKit.ACCENT
				c.draw_line(mp + Vector2(-6, -6), mp + Vector2(6, 6), col, 3.0)
				c.draw_line(mp + Vector2(-6, 6), mp + Vector2(6, -6), col, 3.0)
	if G.player:
		var pp := _map_pt(G.player.global_position)
		var ang: float = -G.player.yaw
		var fwd := Vector2(sin(ang), -cos(ang))
		var side := Vector2(-fwd.y, fwd.x)
		c.draw_colored_polygon(PackedVector2Array([pp + fwd * 14.0, pp - fwd * 8.0 + side * 8.0, pp - fwd * 3.0, pp - fwd * 8.0 - side * 8.0]), Color.WHITE)
		c.draw_polyline(PackedVector2Array([pp + fwd * 14.0, pp - fwd * 8.0 + side * 8.0, pp - fwd * 3.0, pp - fwd * 8.0 - side * 8.0, pp + fwd * 14.0]), Color(0, 0, 0, 0.7), 1.5)

# ----------------------------------------------------------------- events
func show_message(text: String, seconds := 3.0) -> void:
	_msg.text = text
	_msg_t = seconds

func show_kill(title: String, sub: String, points: int) -> void:
	_banner_title.text = title
	_banner_sub.text = sub
	_banner_pts.text = "+" + G.fmt_int(points)
	_banner_t = 5.0
	_hit_kill = true
	_hit_t = 0.5

func show_bonus(text: String, points: int) -> void:
	_banner_title.text = text
	_banner_sub.text = ""
	_banner_pts.text = "+" + G.fmt_int(points)
	_banner_t = 3.5

func hit_marker() -> void:
	if _hit_t <= 0.0:
		_hit_kill = false
	_hit_t = maxf(_hit_t, 0.28)

func reset() -> void:
	_banner_t = 0.0
	_msg_t = 0.0
	_shown_score = 0.0
	_map.visible = false
	_fade = 1.0

# ----------------------------------------------------------------- update
func _process(dt: float) -> void:
	if not visible:
		return
	var main = G.main
	var pl: Player = G.player
	if pl == null or main == null:
		return
	var w: WeaponRig = pl.weapon
	_fade = maxf(_fade - dt * 0.9, 0.0)
	# clock + score
	var hunt: Dictionary = main.hunt
	_clock.text = "%s   ·   %s left" % [G.sky.clock(), G.fmt_time(hunt.get("time_left", 0.0))]
	_shown_score = lerpf(_shown_score, float(hunt.get("score", 0)), 1.0 - exp(-6.0 * dt))
	_score.text = G.fmt_int(int(round(_shown_score)))
	var kills: Array = hunt.get("kills", [])
	_score_sub.text = "%d moose" % kills.size() if kills.size() != 1 else "1 moose"
	if SaveGame.best_score() > 0:
		_score_sub.text += "   ·   best %s" % G.fmt_int(SaveGame.best_score())
	# weapon
	if w.root:
		_weapon.text = w.stats.get("name", "")
	# prompt + messages
	_prompt.text = ("[ E ]   " + pl.prompt) if pl.prompt != "" and pl.controls_enabled() else ""
	_msg_t = maxf(_msg_t - dt, 0.0)
	_msg.modulate.a = clampf(_msg_t * 2.0, 0.0, 1.0)
	_banner_t = maxf(_banner_t - dt / maxf(Engine.time_scale, 0.1), 0.0)
	_banner.modulate.a = clampf(_banner_t * 1.5, 0.0, 1.0)
	_banner.offset_top = 150.0 - clampf((_banner_t - 4.6) * 60.0, 0.0, 30.0)
	_hit_t = maxf(_hit_t - dt / maxf(Engine.time_scale, 0.1), 0.0)
	_fps.visible = Settings.get_v("show_fps")
	if _fps.visible:
		_fps.text = "%d fps" % Engine.get_frames_per_second()

	# scope / binocular mask
	var aspect := size.x / maxf(size.y, 1.0)
	var scoped := w.root != null and w.is_scope() and w.ads > 0.6
	var binoc := pl.binoc_k > 0.3
	scope.visible = scoped or binoc
	_holds_px.clear()
	if scope.visible:
		scope_mat.set_shader_parameter("aspect", aspect)
		scope_mat.set_shader_parameter("px", 1.0 / maxf(size.y, 1.0))
		var holds := PackedFloat32Array([0, 0, 0, 0, 0])
		if binoc:
			scope_mat.set_shader_parameter("mode", 1)
			scope_mat.set_shader_parameter("alpha", smoothstep(0.3, 0.9, pl.binoc_k))
			scope_mat.set_shader_parameter("radius", 0.4)
			scope_mat.set_shader_parameter("shift", Vector2.ZERO)
		else:
			scope_mat.set_shader_parameter("mode", 0)
			scope_mat.set_shader_parameter("alpha", smoothstep(0.6, 0.95, w.ads))
			scope_mat.set_shader_parameter("radius", lerpf(0.3, 0.47, smoothstep(0.6, 1.0, w.ads)))
			scope_mat.set_shader_parameter("shift", w.scope_shift)
			scope_mat.set_shader_parameter("shadow", w.scope_shift * 2.2 + Vector2(pl.look_delta.x, pl.look_delta.y) * 0.004)
			scope_mat.set_shader_parameter("roll", w.scope_roll)
			scope_mat.set_shader_parameter("flash", w.flash_amount)
			var half := tan(deg_to_rad(pl.cam.fov) * 0.5)
			var i := 0
			for h in w.holdovers:
				if i >= 5:
					break
				var y: float = tan(h[1]) / half * 0.5
				var last: float = holds[i - 1] if i > 0 else 0.0
				if y > 0.011 and y < 0.4 and y - last > 0.011:
					holds[i] = y
					_holds_px.append([y, int(h[0])])
					i += 1
		scope_mat.set_shader_parameter("holds", holds)
	# zoom + rangefinder readout
	var txt := ""
	if scoped and w.ads > 0.9:
		txt = "%.0fx" % w.zoom() if is_equal_approx(w.zoom(), round(w.zoom())) else "%.1fx" % w.zoom()
		txt += "   ·   zero %d m" % int(w.stats["zero"])
	elif binoc:
		txt = "8x"
	if (scoped or binoc) and SaveGame.owns_gear("rangefinder"):
		_range_t -= dt
		if _range_t <= 0.0:
			_range_t = 0.2
			_range = main.range_probe()
		if _range > 0.0:
			txt += "   ·   %d m" % int(round(_range))
	_zoom.text = txt
	if _map.visible:
		_map_markers.queue_redraw()
	_canvas.queue_redraw()

func toggle_map() -> void:
	_map.visible = not _map.visible
	Sfx.ui("rustle_2", -8.0)

func map_open() -> bool:
	return _map.visible

func _draw_hud() -> void:
	var cv := _canvas
	var pl: Player = G.player
	if pl == null or G.main == null:
		return
	var c := size * 0.5
	var w: WeaponRig = pl.weapon
	var f := UiKit.font()
	var fb := UiKit.bold()
	var sh := Color(0, 0, 0, 0.55)
	# ---- compass
	var top := 34.0
	var heading := fposmod(rad_to_deg(-pl.yaw), 360.0)
	var px_per_deg := COMPASS_W / 120.0
	cv.draw_rect(Rect2(c.x - COMPASS_W * 0.5, top + 26, COMPASS_W, 1.5), Color(1, 1, 1, 0.3))
	for deg in range(0, 360, 15):
		var rel := wrapf(deg - heading, -180.0, 180.0)
		if absf(rel) > 60.0:
			continue
		var x := c.x + rel * px_per_deg
		var a := 1.0 - smoothstep(40.0, 60.0, absf(rel))
		var major := deg % 45 == 0
		cv.draw_line(Vector2(x, top + (14 if major else 20)), Vector2(x, top + 26), Color(1, 1, 1, 0.75 * a), 2.0 if major else 1.0)
		if major:
			var txt: String = POINTS[deg / 45]
			var fs := 19 if deg % 90 == 0 else 14
			var tw := fb.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			cv.draw_string(fb, Vector2(x - tw * 0.5 + 1, top + 9), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0, 0, 0, 0.5 * a))
			var col := UiKit.ACCENT if deg == 0 else UiKit.TEXT
			cv.draw_string(fb, Vector2(x - tw * 0.5, top + 8), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(col.r, col.g, col.b, a))
	cv.draw_colored_polygon(PackedVector2Array([Vector2(c.x - 6, top + 33), Vector2(c.x + 6, top + 33), Vector2(c.x, top + 27)]), UiKit.TEXT)
	# ---- crosshair
	var scoped := w.root != null and w.is_scope() and w.ads > 0.6
	if w.root and not scoped and pl.binoc_k < 0.2 and pl.controls_enabled():
		var a := 1.0 - smoothstep(0.15, 0.6, w.ads)
		if a > 0.01 and not pl.sprinting:
			var gap := 9.0 + pl.speed_ratio() * 16.0
			var col := Color(1, 1, 1, 0.85 * a)
			for d in [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]:
				cv.draw_line(c + d * gap + Vector2(1, 1), c + d * (gap + 8.0) + Vector2(1, 1), Color(0, 0, 0, 0.4 * a), 2.0)
				cv.draw_line(c + d * gap, c + d * (gap + 8.0), col, 2.0)
			cv.draw_circle(c, 1.6, col)
	# ---- hit marker
	if _hit_t > 0.0:
		var a := clampf(_hit_t * 5.0, 0.0, 1.0)
		var col := Color(0.95, 0.25, 0.2, a) if _hit_kill else Color(1, 1, 1, a)
		var r0 := 9.0
		var r1 := 20.0 if _hit_kill else 16.0
		for d in [Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1)]:
			var n: Vector2 = d.normalized()
			cv.draw_line(c + n * r0, c + n * r1, col, 3.0)
	# ---- hold-over labels in the scope
	if scoped and w.ads > 0.9:
		for h in _holds_px:
			var y: float = c.y + float(h[0]) * size.y + w.scope_shift.y * size.y
			cv.draw_string(f, Vector2(c.x + 0.03 * size.y, y + 5), str(h[1]), HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0, 0, 0, 0.8))
	# ---- breath meter
	if (w.ads > 0.8 or pl.binoc_k > 0.8) and (pl.breath < 0.995 or pl.holding_breath):
		var bw := 150.0
		var y := size.y - 70.0
		cv.draw_rect(Rect2(c.x - bw * 0.5, y, bw, 4), Color(0, 0, 0, 0.45))
		cv.draw_rect(Rect2(c.x - bw * 0.5, y, bw * pl.breath, 4), UiKit.ACCENT if pl.breath > 0.25 else UiKit.BAD)
		var hint := "holding breath" if pl.holding_breath else "breath"
		var tw := f.get_string_size(hint, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
		cv.draw_string(f, Vector2(c.x - tw * 0.5, y - 6), hint, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(1, 1, 1, 0.7))
	elif w.ads > 0.9 and scoped and pl.breath >= 0.995:
		var hint := "Shift  steady aim"
		var tw := f.get_string_size(hint, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
		cv.draw_string(f, Vector2(c.x - tw * 0.5, size.y - 66.0), hint, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(1, 1, 1, 0.45))
	# ---- ammo pips
	if w.root:
		var n := w.mag_size()
		var have := w.rounds()
		var x0 := size.x - 42.0
		var y0 := size.y - 76.0
		for i in n:
			var r := Rect2(x0 - (i + 1) * 13.0, y0 - 26.0, 8.0, 26.0)
			cv.draw_rect(Rect2(r.position + Vector2(1, 1), r.size), sh)
			if i < have:
				cv.draw_rect(r, UiKit.ACCENT)
				cv.draw_rect(Rect2(r.position, Vector2(8, 7)), Color(0.75, 0.48, 0.3))
			else:
				cv.draw_rect(r, Color(1, 1, 1, 0.22), false, 1.5)
		if have == 0 and not w.busy():
			var hint := "R  reload"
			var tw := fb.get_string_size(hint, HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x
			cv.draw_string(fb, Vector2(x0 - tw, y0 - 40.0), hint, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, UiKit.BAD)
	# ---- fade from black at the start of a hunt
	if _fade > 0.0:
		cv.draw_rect(Rect2(Vector2.ZERO, size), Color(0.02, 0.03, 0.03, smoothstep(0.0, 0.8, _fade)))
