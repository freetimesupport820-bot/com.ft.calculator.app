class_name UI
extends RefCounted
## UI toolkit: palette (light/dark glass theme from the HTML), fonts, styled controls.

static var dark: bool = false
static var P: Dictionary = {}
static var _fonts: Dictionary = {}
static var _circle: ImageTexture = null
const GRAD_SHADER := "res://shaders/rgrad.gdshader"

const WEIGHTS: Dictionary = {400: "Regular", 500: "Medium", 600: "SemiBold", 700: "Bold", 800: "ExtraBold"}


static func set_dark(d: bool) -> void:
	dark = d
	if d:
		P = {
			"bg1": Color("#030615"), "bg2": Color("#12062c"), "bg3": Color("#021a22"),
			"tx": Color("#f1f6ff"), "mut": Color("#a5b4d6"),
			"ac": Color("#22d3ee"), "ac2": Color("#8b5cf6"), "ac3": Color("#f472b6"),
			"card": Color(1, 1, 1, 0.11), "line": Color(1, 1, 1, 0.2), "glass2": Color(1, 1, 1, 0.12),
			"input": Color(1, 1, 1, 0.07), "navbg": Color("#181d40"), "shadow": Color(0, 0, 0, 0.55),
			"o1": Color("#06b6d4"), "o2": Color("#7c3aed"), "o3": Color("#db2777"), "oa": 0.5,
			"bad": Color("#f87171"), "res": Color(1, 1, 1, 0.09),
		}
	else:
		P = {
			"bg1": Color("#dff4ff"), "bg2": Color("#ece4ff"), "bg3": Color("#ffe6f3"),
			"tx": Color("#12203f"), "mut": Color("#4d5f86"),
			"ac": Color("#06b6d4"), "ac2": Color("#7c3aed"), "ac3": Color("#ec4899"),
			"card": Color(1, 1, 1, 0.45), "line": Color(1, 1, 1, 0.85), "glass2": Color(1, 1, 1, 0.38),
			"input": Color(1, 1, 1, 0.3), "navbg": Color("#ffffff"), "shadow": Color(0.298, 0.235, 0.667, 0.22),
			"o1": Color("#22d3ee"), "o2": Color("#a78bfa"), "o3": Color("#f472b6"), "oa": 0.55,
			"bad": Color("#dc2626"), "res": Color(1, 1, 1, 0.3),
		}


static func col(k: Variant) -> Color:
	if k is Color:
		return k
	return P[k]


static func font(w: int = 500) -> FontFile:
	if not _fonts.has(w):
		_fonts[w] = load("res://assets/fonts/BalooDa2-%s.ttf" % WEIGHTS.get(w, "Medium"))
	return _fonts[w]


static func lbl(text: String, size: int = 17, weight: int = 500, color: Variant = "tx", wrap: bool = false, align: int = HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", font(weight))
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col(color))
	l.horizontal_alignment = align
	if wrap:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return l


static func flat(fill: Color, radius: float, border: Color = Color(0, 0, 0, 0), bw: int = 0, shadow: int = 0, shadow_col: Color = Color(0, 0, 0, 0.2), pad: Vector4 = Vector4(0, 0, 0, 0)) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = fill
	s.set_corner_radius_all(int(radius))
	s.anti_aliasing = true
	if bw > 0:
		s.border_color = border
		s.set_border_width_all(bw)
	if shadow > 0:
		s.shadow_size = shadow
		s.shadow_color = shadow_col
		s.shadow_offset = Vector2(0, shadow * 0.7)
	s.content_margin_left = pad.x
	s.content_margin_top = pad.y
	s.content_margin_right = pad.z
	s.content_margin_bottom = pad.w
	return s


static func empty() -> StyleBoxEmpty:
	return StyleBoxEmpty.new()


## Adds a rounded gradient background (shader) behind `host`.
static func grad_bg(host: Control, radius: float, c0: Color, c1: Color, c2: Color, mid: float = 0.55, gloss: float = 1.0, angle: float = 135.0) -> ColorRect:
	var r := ColorRect.new()
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.show_behind_parent = true
	r.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var m := ShaderMaterial.new()
	m.shader = load(GRAD_SHADER)
	m.set_shader_parameter("radius", radius)
	m.set_shader_parameter("c0", c0)
	m.set_shader_parameter("c1", c1)
	m.set_shader_parameter("c2", c2)
	m.set_shader_parameter("mid", mid)
	m.set_shader_parameter("gloss", gloss)
	m.set_shader_parameter("angle_deg", angle)
	r.material = m
	host.add_child(r)
	r.resized.connect(func() -> void: m.set_shader_parameter("rect_size", r.size))
	return r


static func brand_grad(host: Control, radius: float, mid: float = 0.55, gloss: float = 1.0) -> ColorRect:
	return grad_bg(host, radius, P["ac"], P["ac2"], P["ac3"], mid, gloss)


class Card extends PanelContainer:
	var box: VBoxContainer


static func card() -> Card:
	var c := Card.new()
	c.add_theme_stylebox_override("panel", flat(P["card"], 26, P["line"], 1, 18, P["shadow"], Vector4(16, 16, 16, 16)))
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	c.box = VBoxContainer.new()
	c.box.add_theme_constant_override("separation", 0)
	c.add_child(c.box)
	return c


static func btn(text: String, kind: String = "pri") -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(0, 54)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.add_theme_font_override("font", font(700))
	b.add_theme_font_size_override("font_size", 19)
	b.clip_text = true
	b.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	var empty_sb := empty()
	for st in ["normal", "hover", "pressed", "focus", "disabled"]:
		b.add_theme_stylebox_override(st, empty_sb)
	if kind == "sec":
		var sb := flat(P["glass2"], 16, P["line"], 1)
		for st in ["normal", "hover", "pressed"]:
			b.add_theme_stylebox_override(st, sb)
		for k in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
			b.add_theme_color_override(k, P["tx"])
	else:
		for k in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
			b.add_theme_color_override(k, Color.WHITE)
		if kind == "danger":
			grad_bg(b, 16, Color("#f43f5e"), Color("#be123c"), Color("#be123c"), 0.5, 1.0)
		else:
			brand_grad(b, 16, 0.55, 1.0)
	_press_anim(b)
	return b


static func _press_anim(b: Control) -> void:
	b.resized.connect(func() -> void: b.pivot_offset = b.size / 2.0)
	b.button_down.connect(func() -> void: b.scale = Vector2(0.97, 0.97))
	b.button_up.connect(func() -> void: b.scale = Vector2.ONE)


static func chip(text: String, on: bool) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_override("font", font(600))
	b.add_theme_font_size_override("font_size", 16)
	b.custom_minimum_size = Vector2(0, 40)
	var e := empty()
	for st in ["normal", "hover", "pressed", "focus"]:
		b.add_theme_stylebox_override(st, e)
	b.add_theme_stylebox_override("normal", flat(P["glass2"], 99, P["line"], 1, 0, Color.TRANSPARENT, Vector4(14, 5, 14, 5)))
	b.add_theme_stylebox_override("hover", b.get_theme_stylebox("normal"))
	b.add_theme_stylebox_override("pressed", b.get_theme_stylebox("normal"))
	var c: Color = Color.WHITE if on else P["tx"]
	for k in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		b.add_theme_color_override(k, c)
	if on:
		brand_grad(b, 20, 0.6, 1.0)
	return b


static func input_style() -> StyleBoxFlat:
	return flat(P["input"], 14, P["line"], 1, 0, Color.TRANSPARENT, Vector4(13, 11, 13, 11))


static func input_focus_style() -> StyleBoxFlat:
	var s := input_style()
	s.border_color = P["ac"]
	s.set_border_width_all(2)
	return s


static func line_edit(placeholder: String = "", secret: bool = false, kb: int = LineEdit.KEYBOARD_TYPE_DEFAULT) -> LineEdit:
	var e := LineEdit.new()
	e.placeholder_text = placeholder
	e.secret = secret
	e.virtual_keyboard_type = kb
	e.add_theme_font_override("font", font(500))
	e.add_theme_font_size_override("font_size", 17)
	e.add_theme_color_override("font_color", P["tx"])
	e.add_theme_color_override("font_placeholder_color", Color(P["mut"], 0.7))
	e.add_theme_color_override("caret_color", P["ac"])
	e.add_theme_stylebox_override("normal", input_style())
	e.add_theme_stylebox_override("focus", input_focus_style())
	e.custom_minimum_size = Vector2(0, 48)
	e.context_menu_enabled = true
	return e


static func text_area() -> TextEdit:
	var e := TextEdit.new()
	e.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	e.scroll_fit_content_height = false
	e.custom_minimum_size = Vector2(0, 92)
	e.add_theme_font_override("font", font(500))
	e.add_theme_font_size_override("font_size", 17)
	e.add_theme_color_override("font_color", P["tx"])
	e.add_theme_color_override("caret_color", P["ac"])
	e.add_theme_stylebox_override("normal", input_style())
	e.add_theme_stylebox_override("focus", input_focus_style())
	e.virtual_keyboard_enabled = true
	return e


static func option(items: Array, selected: int = 0) -> OptionButton:
	var o := OptionButton.new()
	for it in items:
		o.add_item(String(it))
	o.select(selected)
	o.focus_mode = Control.FOCUS_NONE
	o.add_theme_font_override("font", font(500))
	o.add_theme_font_size_override("font_size", 17)
	o.add_theme_color_override("font_color", P["tx"])
	o.add_theme_color_override("font_hover_color", P["tx"])
	o.add_theme_color_override("font_pressed_color", P["tx"])
	o.add_theme_color_override("font_focus_color", P["tx"])
	var sb := flat(P["input"], 14, P["line"], 1, 0, Color.TRANSPARENT, Vector4(13, 11, 13, 11))
	for st in ["normal", "hover", "pressed", "focus"]:
		o.add_theme_stylebox_override(st, sb)
	o.custom_minimum_size = Vector2(0, 48)
	var pm: PopupMenu = o.get_popup()
	pm.add_theme_font_override("font", font(500))
	pm.add_theme_font_size_override("font_size", 17)
	pm.add_theme_color_override("font_color", Color("#12203f"))
	pm.add_theme_color_override("font_hover_color", Color("#12203f"))
	pm.add_theme_stylebox_override("panel", flat(Color.WHITE, 12, Color(0, 0, 0, 0.1), 1, 8, Color(0, 0, 0, 0.3), Vector4(6, 6, 6, 6)))
	pm.add_theme_stylebox_override("hover", flat(Color(0.024, 0.714, 0.831, 0.2), 8))
	return o


static func circle_tex(px: int, c: Color) -> ImageTexture:
	var img := Image.create(px, px, false, Image.FORMAT_RGBA8)
	var r: float = px / 2.0
	for y in range(px):
		for x in range(px):
			var d: float = Vector2(x + 0.5 - r, y + 0.5 - r).length()
			var a: float = clampf(r - d, 0.0, 1.0)
			img.set_pixel(x, y, Color(c.r, c.g, c.b, c.a * a))
	return ImageTexture.create_from_image(img)


static func slider(minv: float, maxv: float, step: float, value: float) -> HSlider:
	var s := HSlider.new()
	s.min_value = minv
	s.max_value = maxv
	s.step = step
	s.value = value
	s.focus_mode = Control.FOCUS_NONE
	s.custom_minimum_size = Vector2(0, 32)
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	s.add_theme_stylebox_override("slider", flat(P["glass2"], 3, P["line"], 1, 0, Color.TRANSPARENT, Vector4(0, 4, 0, 4)))
	s.add_theme_stylebox_override("grabber_area", flat(P["ac"], 3, Color.TRANSPARENT, 0, 0, Color.TRANSPARENT, Vector4(0, 4, 0, 4)))
	s.add_theme_stylebox_override("grabber_area_highlight", flat(P["ac"], 3, Color.TRANSPARENT, 0, 0, Color.TRANSPARENT, Vector4(0, 4, 0, 4)))
	var gt: ImageTexture = circle_tex(48, P["ac"])
	s.add_theme_icon_override("grabber", gt)
	s.add_theme_icon_override("grabber_highlight", gt)
	s.add_theme_icon_override("grabber_disabled", gt)
	return s


static func icon(name: String, px: int, color: Variant = "tx") -> TextureRect:
	var t := TextureRect.new()
	t.texture = load("res://assets/icons/%s.svg" % name)
	t.custom_minimum_size = Vector2(px, px)
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	t.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	t.modulate = col(color)
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	t.pivot_offset = Vector2(px, px) / 2.0
	return t


static func spacer(h: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, h)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


static func hint(text: String) -> Label:
	var l := lbl(text, 14, 500, "mut", true)
	return l


## Draws the Bangladesh flag (green field + red disc) like the inline SVG in the HTML.
class Flag extends Control:
	func _init() -> void:
		custom_minimum_size = Vector2(24, 14)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color("#006a4e")
		sb.set_corner_radius_all(1)
		draw_style_box(sb, Rect2(Vector2.ZERO, size))
		draw_circle(Vector2(size.x * 13.0 / 30.0, size.y / 2.0), size.y * 5.4 / 18.0, Color("#f42a41"))
