class_name UiKit
extends RefCounted
## Shared look for menus and HUD: colours, fonts and small widget builders.

const ACCENT := Color(0.94, 0.63, 0.22)
const TEXT := Color(0.94, 0.93, 0.89)
const DIM := Color(0.94, 0.93, 0.89, 0.62)
const FAINT := Color(0.94, 0.93, 0.89, 0.32)
const PANEL := Color(0.035, 0.05, 0.055, 0.86)
const PANEL_LIGHT := Color(0.12, 0.15, 0.16, 0.7)
const GOOD := Color(0.55, 0.82, 0.45)
const BAD := Color(0.88, 0.36, 0.3)

static var _font: Font
static var _bold: Font
static var _theme: Theme

static func font() -> Font:
	if _font == null:
		var f := SystemFont.new()
		f.font_names = PackedStringArray(["Inter", "Noto Sans", "Cantarell", "DejaVu Sans", "Liberation Sans", "sans-serif"])
		f.font_weight = 450
		f.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_AUTO
		_font = f
	return _font

static func bold() -> Font:
	if _bold == null:
		var f := SystemFont.new()
		f.font_names = PackedStringArray(["Inter", "Noto Sans", "Cantarell", "DejaVu Sans", "Liberation Sans", "sans-serif"])
		f.font_weight = 750
		_bold = f
	return _bold

static func flat(color: Color, radius := 6, border := 0, border_color := Color.TRANSPARENT) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = color
	s.set_corner_radius_all(radius)
	s.set_border_width_all(border)
	s.border_color = border_color
	s.set_content_margin_all(10)
	return s

static func theme() -> Theme:
	if _theme != null:
		return _theme
	var t := Theme.new()
	t.default_font = font()
	t.default_font_size = 20
	t.set_color("font_color", "Label", TEXT)
	# buttons
	var normal := flat(Color(1, 1, 1, 0.0), 4)
	normal.content_margin_left = 18
	normal.content_margin_right = 18
	var hover := flat(Color(1, 1, 1, 0.09), 4)
	hover.content_margin_left = 18
	hover.content_margin_right = 18
	hover.border_width_left = 3
	hover.border_color = ACCENT
	var pressed := flat(Color(ACCENT.r, ACCENT.g, ACCENT.b, 0.25), 4)
	pressed.content_margin_left = 18
	pressed.content_margin_right = 18
	pressed.border_width_left = 3
	pressed.border_color = ACCENT
	var disabled := flat(Color(1, 1, 1, 0.0), 4)
	disabled.content_margin_left = 18
	disabled.content_margin_right = 18
	t.set_stylebox("normal", "Button", normal)
	t.set_stylebox("hover", "Button", hover)
	t.set_stylebox("pressed", "Button", pressed)
	t.set_stylebox("focus", "Button", hover)
	t.set_stylebox("disabled", "Button", disabled)
	t.set_color("font_color", "Button", TEXT)
	t.set_color("font_hover_color", "Button", Color.WHITE)
	t.set_color("font_pressed_color", "Button", ACCENT)
	t.set_color("font_focus_color", "Button", Color.WHITE)
	t.set_color("font_disabled_color", "Button", FAINT)
	t.set_font_size("font_size", "Button", 24)
	# option buttons / popups
	var box := flat(PANEL_LIGHT, 4)
	for st in ["normal", "hover", "pressed", "focus"]:
		t.set_stylebox(st, "OptionButton", box if st != "hover" else flat(Color(0.2, 0.24, 0.25, 0.9), 4))
	t.set_font_size("font_size", "OptionButton", 19)
	t.set_stylebox("panel", "PopupMenu", flat(Color(0.07, 0.09, 0.1, 0.98), 4, 1, Color(1, 1, 1, 0.12)))
	t.set_stylebox("hover", "PopupMenu", flat(Color(ACCENT.r, ACCENT.g, ACCENT.b, 0.3), 3))
	t.set_font_size("font_size", "PopupMenu", 19)
	# sliders
	var track := flat(Color(1, 1, 1, 0.16), 3)
	track.set_content_margin_all(3)
	var fill := flat(ACCENT, 3)
	fill.set_content_margin_all(3)
	t.set_stylebox("slider", "HSlider", track)
	t.set_stylebox("grabber_area", "HSlider", fill)
	t.set_stylebox("grabber_area_highlight", "HSlider", fill)
	var knob := _disc(16, TEXT)
	t.set_icon("grabber", "HSlider", knob)
	t.set_icon("grabber_highlight", "HSlider", _disc(16, Color.WHITE))
	t.set_icon("grabber_disabled", "HSlider", knob)
	# check buttons
	t.set_font_size("font_size", "CheckButton", 19)
	for st in ["normal", "hover", "pressed", "focus", "hover_pressed"]:
		t.set_stylebox(st, "CheckButton", flat(Color(1, 1, 1, 0.0), 4))
	t.set_stylebox("panel", "PanelContainer", flat(PANEL, 10))
	t.set_stylebox("panel", "ScrollContainer", StyleBoxEmpty.new())
	var sb := flat(Color(1, 1, 1, 0.18), 3)
	sb.set_content_margin_all(3)
	t.set_stylebox("grabber", "VScrollBar", sb)
	t.set_stylebox("grabber_highlight", "VScrollBar", flat(Color(1, 1, 1, 0.3), 3))
	t.set_stylebox("grabber_pressed", "VScrollBar", flat(ACCENT, 3))
	t.set_stylebox("scroll", "VScrollBar", flat(Color(1, 1, 1, 0.04), 3))
	_theme = t
	return t

static func _disc(size: int, color: Color) -> ImageTexture:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var c := Vector2(size, size) * 0.5
	for y in size:
		for x in size:
			var d := (Vector2(x + 0.5, y + 0.5) - c).length()
			img.set_pixel(x, y, Color(color.r, color.g, color.b, clampf(size * 0.5 - d, 0.0, 1.0)))
	return ImageTexture.create_from_image(img)

static func label(text: String, size := 20, color := TEXT, is_bold := false) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	if is_bold:
		l.add_theme_font_override("font", bold())
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

static func shadowed(l: Label, strength := 0.7) -> Label:
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, strength))
	l.add_theme_constant_override("shadow_offset_x", 0)
	l.add_theme_constant_override("shadow_offset_y", 2)
	l.add_theme_constant_override("shadow_outline_size", 6)
	return l

static func button(text: String, fn: Callable, size := 24) -> Button:
	var b := Button.new()
	b.text = text
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.add_theme_font_size_override("font_size", size)
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(func():
		Sfx.ui("ui_click")
		fn.call())
	b.mouse_entered.connect(func():
		if not b.disabled:
			Sfx.ui("ui_hover"))
	return b

## Solid accent button (calls to action).
static func cta(text: String, fn: Callable, size := 22) -> Button:
	var b := button(text, fn, size)
	b.alignment = HORIZONTAL_ALIGNMENT_CENTER
	var n := flat(ACCENT, 5)
	n.content_margin_left = 22
	n.content_margin_right = 22
	var h := flat(ACCENT.lightened(0.15), 5)
	h.content_margin_left = 22
	h.content_margin_right = 22
	var d := flat(Color(1, 1, 1, 0.1), 5)
	d.content_margin_left = 22
	d.content_margin_right = 22
	b.add_theme_stylebox_override("normal", n)
	b.add_theme_stylebox_override("hover", h)
	b.add_theme_stylebox_override("pressed", h)
	b.add_theme_stylebox_override("focus", n)
	b.add_theme_stylebox_override("disabled", d)
	b.add_theme_color_override("font_color", Color(0.08, 0.06, 0.03))
	b.add_theme_color_override("font_hover_color", Color(0.08, 0.06, 0.03))
	b.add_theme_color_override("font_pressed_color", Color(0.08, 0.06, 0.03))
	b.add_theme_color_override("font_focus_color", Color(0.08, 0.06, 0.03))
	b.add_theme_font_override("font", bold())
	return b

static func panel(color := PANEL, radius := 10, margin := 24) -> PanelContainer:
	var p := PanelContainer.new()
	var s := flat(color, radius)
	s.set_content_margin_all(margin)
	p.add_theme_stylebox_override("panel", s)
	return p

static func vbox(sep := 8) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", sep)
	return v

static func hbox(sep := 8) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", sep)
	return h

static func spacer(h := 12.0, w := 0.0) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(w, h)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c

static func expander() -> Control:
	var c := Control.new()
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	c.size_flags_vertical = Control.SIZE_EXPAND_FILL
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c

static func rule(color := Color(1, 1, 1, 0.12)) -> ColorRect:
	var r := ColorRect.new()
	r.color = color
	r.custom_minimum_size = Vector2(0, 1)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r

## Horizontal stat bar 0..1.
static func bar(value: float, color := ACCENT, width := 160.0) -> Control:
	var bg := ColorRect.new()
	bg.color = Color(1, 1, 1, 0.12)
	bg.custom_minimum_size = Vector2(width, 6)
	bg.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var fg := ColorRect.new()
	fg.color = color
	fg.size = Vector2(width * clampf(value, 0.0, 1.0), 6)
	bg.add_child(fg)
	return bg
