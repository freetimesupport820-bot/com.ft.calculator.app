extends Control
## Main scene: header, 4 tabs (Create / Scan / History / About), bottom nav, toast, confirm modal,
## animated background orbs, screen-light overlay, keyboard padding and Android back handling.

const TABS: Array = ["create", "scan", "history", "about"]

var cur: String = "create"
var theme_mode: String = "auto"

var _root: Control
var _bg_layer: Control
var _light: ColorRect
var _ui: Control
var _top_pad: Control
var _scroll: ScrollContainer
var _kb_pad: Control
var _views: Dictionary = {}
var _nav_btns: Dictionary = {}
var _toast: PanelContainer
var _toast_lbl: Label
var _toast_tw: Tween
var _logo_taps: int = 0
var _logo_timer: Timer
var _banner_h: float = 0.0
var _screen_light_on: bool = false
var _modal: Control = null
var _scan_state: bool = false


func _ready() -> void:
	get_tree().set_auto_accept_quit(false)
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme_mode = String(GameState.get_value("ft_theme", "auto"))
	_apply_palette()
	_logo_timer = Timer.new()
	_logo_timer.one_shot = true
	_logo_timer.wait_time = 1.5
	_logo_timer.timeout.connect(func() -> void: _logo_taps = 0)
	add_child(_logo_timer)
	AdController.banner_height_changed.connect(_on_banner_height)
	_build_all()
	_go("create", true)


func _apply_palette() -> void:
	var d: bool = false
	match theme_mode:
		"dark":
			d = true
		"light":
			d = false
		_:
			d = DisplayServer.is_dark_mode() if DisplayServer.is_dark_mode_supported() else false
	UI.set_dark(d)
	RenderingServer.set_default_clear_color(UI.P["bg1"])


# ------------------------------------------------------------ build
func _build_all() -> void:
	var state: Dictionary = {}
	if _views.has("create") and is_instance_valid(_views["create"]):
		state = _views["create"].get_state()
	if _views.has("scan") and is_instance_valid(_views["scan"]):
		_views["scan"].on_leave()
	for c in get_children():
		if c is Timer:
			continue
		c.queue_free()
	_views.clear()
	_nav_btns.clear()
	_modal = null
	_build_background()
	_ui = VBoxContainer.new()
	_ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_ui.add_theme_constant_override("separation", 0)
	add_child(_ui)
	_top_pad = UI.spacer(_banner_h + 8.0)
	_ui.add_child(_top_pad)
	_ui.add_child(_build_header())
	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_ui.add_child(_scroll)
	var vb := VBoxContainer.new()
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb.add_theme_constant_override("separation", 0)
	_scroll.add_child(vb)
	var mc := MarginContainer.new()
	mc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for s in ["left", "right"]:
		mc.add_theme_constant_override("margin_" + s, 16)
	mc.add_theme_constant_override("margin_top", 6)
	mc.add_theme_constant_override("margin_bottom", 18)
	vb.add_child(mc)
	var holder := VBoxContainer.new()
	holder.add_theme_constant_override("separation", 0)
	mc.add_child(holder)
	var cv := CreateView.new()
	cv.set_state(state)
	var sv := ScanView.new()
	var hv := HistoryView.new()
	var av := AboutView.new()
	_views = {"create": cv, "scan": sv, "history": hv, "about": av}
	for k in TABS:
		holder.add_child(_views[k])
		_views[k].visible = false
	cv.toast_requested.connect(show_toast)
	sv.toast_requested.connect(show_toast)
	sv.screen_light_requested.connect(_set_screen_light)
	hv.item_selected.connect(_open_from_history)
	hv.clear_requested.connect(_confirm_clear)
	_kb_pad = UI.spacer(0)
	_ui.add_child(_kb_pad)
	_ui.add_child(_build_nav())
	_build_toast()


func _build_background() -> void:
	_bg_layer = Control.new()
	_bg_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_bg_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_bg_layer)
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.5, 1.0])
	g.colors = PackedColorArray([UI.P["bg1"], UI.P["bg2"], UI.P["bg3"]])
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill_from = Vector2(0, 0)
	gt.fill_to = Vector2(1, 1)
	gt.width = 64
	gt.height = 64
	var tr := TextureRect.new()
	tr.texture = gt
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_SCALE
	tr.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bg_layer.add_child(tr)
	# soft orbs (radial gradient textures, slowly drifting)
	var specs: Array = [["o1", Vector2(0.15, 0.1), 460.0], ["o2", Vector2(0.9, 0.45), 520.0], ["o3", Vector2(0.2, 0.9), 480.0]]
	for i in range(specs.size()):
		var rg := Gradient.new()
		var c: Color = UI.P[specs[i][0]]
		rg.offsets = PackedFloat32Array([0.0, 1.0])
		rg.colors = PackedColorArray([Color(c, UI.P["oa"] * 0.55), Color(c, 0.0)])
		var t := GradientTexture2D.new()
		t.gradient = rg
		t.fill = GradientTexture2D.FILL_RADIAL
		t.fill_from = Vector2(0.5, 0.5)
		t.fill_to = Vector2(1.0, 0.5)
		t.width = 128
		t.height = 128
		var o := TextureRect.new()
		o.texture = t
		o.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		o.stretch_mode = TextureRect.STRETCH_SCALE
		o.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var sz: float = specs[i][2]
		o.size = Vector2(sz, sz)
		o.anchor_left = specs[i][1].x
		o.anchor_right = specs[i][1].x
		o.anchor_top = specs[i][1].y
		o.anchor_bottom = specs[i][1].y
		o.offset_left = -sz / 2.0
		o.offset_right = sz / 2.0
		o.offset_top = -sz / 2.0
		o.offset_bottom = sz / 2.0
		_bg_layer.add_child(o)
		var tw := o.create_tween().set_loops()
		var dx: float = 40.0 * (1.0 if i % 2 == 0 else -1.0)
		tw.tween_property(o, "position:x", o.position.x + dx, 9.0 + i * 2.0).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		tw.tween_property(o, "position:x", o.position.x, 9.0 + i * 2.0).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_light = ColorRect.new()
	_light.color = Color.WHITE
	_light.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_light.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_light.visible = _screen_light_on
	_bg_layer.add_child(_light)


func _build_header() -> Control:
	var m := MarginContainer.new()
	m.add_theme_constant_override("margin_left", 16)
	m.add_theme_constant_override("margin_right", 16)
	m.add_theme_constant_override("margin_top", 4)
	m.add_theme_constant_override("margin_bottom", 6)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	m.add_child(h)
	var logo := PanelContainer.new()
	logo.custom_minimum_size = Vector2(46, 46)
	logo.add_theme_stylebox_override("panel", UI.empty())
	UI.brand_grad(logo, 14, 0.55, 1.0)
	var ic := UI.icon("logo_qr", 28, Color.WHITE)
	ic.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	logo.add_child(ic)
	logo.mouse_filter = Control.MOUSE_FILTER_STOP
	logo.gui_input.connect(_on_logo_input)
	h.add_child(logo)
	var tv := VBoxContainer.new()
	tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tv.add_theme_constant_override("separation", -4)
	var t := UI.lbl(AppConfig.APP_NAME, 17, 800, "ac")
	t.clip_text = true
	t.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	tv.add_child(t)
	tv.add_child(UI.lbl(I18n.t("tag"), 13, 500, "mut"))
	h.add_child(tv)
	var tb := _pill_btn()
	var mode_icon: String = "theme_sun" if theme_mode == "light" else ("theme_moon" if theme_mode == "dark" else "theme_auto")
	var ti := UI.icon(mode_icon, 22, "tx")
	ti.position = Vector2(11, 9)
	tb.add_child(ti)
	tb.custom_minimum_size = Vector2(44, 40)
	tb.pressed.connect(_cycle_theme)
	h.add_child(tb)
	var lb := _pill_btn()
	lb.text = "বাংলা" if I18n.lang == "en" else "English"
	lb.add_theme_font_override("font", UI.font(700))
	lb.add_theme_font_size_override("font_size", 15)
	for k in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		lb.add_theme_color_override(k, UI.P["tx"])
	lb.custom_minimum_size = Vector2(76, 40)
	lb.pressed.connect(func() -> void:
		I18n.toggle()
		_rebuild())
	h.add_child(lb)
	return m


func _pill_btn() -> Button:
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	var sb := UI.flat(UI.P["glass2"], 20, UI.P["line"], 1)
	for st in ["normal", "hover", "pressed", "focus"]:
		b.add_theme_stylebox_override(st, sb)
	return b


func _build_nav() -> Control:
	var pc := PanelContainer.new()
	pc.add_theme_stylebox_override("panel", UI.flat(UI.P["navbg"], 0, UI.P["line"], 1, 12, UI.P["shadow"], Vector4(6, 6, 6, 6)))
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 4)
	pc.add_child(h)
	for k in TABS:
		var b := Button.new()
		b.focus_mode = Control.FOCUS_NONE
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.custom_minimum_size = Vector2(0, 60)
		for st in ["normal", "hover", "pressed", "focus"]:
			b.add_theme_stylebox_override(st, UI.empty())
		var v := VBoxContainer.new()
		v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		v.alignment = BoxContainer.ALIGNMENT_CENTER
		v.add_theme_constant_override("separation", 0)
		v.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var ic := UI.icon("nav_" + k, 26, "mut")
		ic.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		var l := UI.lbl(I18n.t(k), 13, 700, "mut", false, HORIZONTAL_ALIGNMENT_CENTER)
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v.add_child(ic)
		v.add_child(l)
		b.add_child(v)
		b.pressed.connect(_go.bind(k, false))
		h.add_child(b)
		_nav_btns[k] = [ic, l]
	return pc


func _build_toast() -> void:
	_toast = PanelContainer.new()
	_toast.add_theme_stylebox_override("panel", UI.flat(Color(0.07, 0.09, 0.2, 0.94), 16, Color(1, 1, 1, 0.2), 1, 10, Color(0, 0, 0, 0.4), Vector4(18, 10, 18, 10)))
	_toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toast_lbl = UI.lbl("", 16, 600, Color.WHITE, true, HORIZONTAL_ALIGNMENT_CENTER)
	_toast_lbl.custom_minimum_size = Vector2(160, 0)
	_toast.add_child(_toast_lbl)
	_toast.modulate.a = 0.0
	_toast.anchor_left = 0.5
	_toast.anchor_right = 0.5
	_toast.anchor_top = 1.0
	_toast.anchor_bottom = 1.0
	_toast.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_toast.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_toast.offset_bottom = -96
	_toast.offset_top = -96
	add_child(_toast)


func _rebuild() -> void:
	var was: String = cur
	_apply_palette()
	_build_all()
	_go(was, true)


# ------------------------------------------------------------ navigation
func _go(k: String, force: bool) -> void:
	if k == cur and not force and _views[k].visible:
		return
	var prev: String = cur
	if prev == "scan" and k != "scan" and _views.has("scan"):
		_views["scan"].on_leave()
	cur = k
	for t in TABS:
		_views[t].visible = (t == k)
		var on: bool = t == k
		var col: Color = UI.P["ac"] if on else UI.P["mut"]
		_nav_btns[t][0].modulate = col
		_nav_btns[t][1].add_theme_color_override("font_color", col)
	_scroll.scroll_vertical = 0
	if k == "scan":
		_views["scan"].on_enter()
	elif k == "history":
		_views["history"].refresh()


func _open_from_history(text: String) -> void:
	_views["scan"].skip_cam_once = true
	_go("scan", true)
	_views["scan"].show_result(text, true)


func _confirm_clear() -> void:
	_show_confirm(I18n.t("confirmClear"), I18n.t("confirmSub"), I18n.t("del"), func() -> void:
		GameState.clear_history()
		show_toast(I18n.t("cleared")))


func _show_confirm(title: String, sub: String, ok_label: String, on_ok: Callable) -> void:
	if _modal != null:
		return
	_modal = ColorRect.new()
	_modal.color = Color(0.012, 0.024, 0.082, 0.62)
	_modal.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_modal)
	var close := func() -> void:
		if _modal != null:
			_modal.queue_free()
			_modal = null
	_modal.gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and ev.pressed:
			close.call())
	var cc := CenterContainer.new()
	cc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	cc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_modal.add_child(cc)
	var box := PanelContainer.new()
	box.custom_minimum_size = Vector2(minf(size.x * 0.88, 360.0), 0)
	box.add_theme_stylebox_override("panel", UI.flat(UI.P["navbg"], 26, UI.P["line"], 1, 30, Color(0, 0, 0, 0.5), Vector4(22, 22, 22, 22)))
	cc.add_child(box)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	box.add_child(v)
	v.add_child(UI.lbl(title, 21, 700, "tx", true, HORIZONTAL_ALIGNMENT_CENTER))
	v.add_child(UI.lbl(sub, 15, 500, "mut", true, HORIZONTAL_ALIGNMENT_CENTER))
	v.add_child(UI.spacer(12))
	var g := HBoxContainer.new()
	g.add_theme_constant_override("separation", 10)
	var no := UI.btn(I18n.t("cancel"), "sec")
	no.pressed.connect(close)
	var yes := UI.btn(ok_label, "danger")
	yes.pressed.connect(func() -> void:
		close.call()
		on_ok.call())
	g.add_child(no)
	g.add_child(yes)
	v.add_child(g)


# ------------------------------------------------------------ theme / light / toast
func _cycle_theme() -> void:
	var order: Array = ["auto", "light", "dark"]
	theme_mode = order[(order.find(theme_mode) + 1) % 3]
	GameState.set_value("ft_theme", theme_mode)
	_rebuild()


func _set_screen_light(on: bool) -> void:
	_screen_light_on = on
	if _light != null:
		_light.visible = on
	if on:
		DisplayServer.screen_set_keep_on(true)


func show_toast(msg: String) -> void:
	if _toast == null:
		return
	_toast_lbl.text = msg
	if _toast_tw != null:
		_toast_tw.kill()
	_toast.modulate.a = 1.0
	_toast_tw = create_tween()
	_toast_tw.tween_interval(1.8)
	_toast_tw.tween_property(_toast, "modulate:a", 0.0, 0.3)


func _on_logo_input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
		_logo_taps += 1
		_logo_timer.start()
		if _logo_taps >= 5:
			_logo_taps = 0
			show_toast(AdController.diagnostics())


func _on_banner_height(h: float) -> void:
	_banner_h = h
	if _top_pad != null:
		_top_pad.custom_minimum_size.y = h + 8.0


# ------------------------------------------------------------ keyboard / lifecycle / back
func _process(_d: float) -> void:
	if _kb_pad == null or OS.get_name() != "Android":
		return
	var kb: int = DisplayServer.virtual_keyboard_get_height()
	var factor: float = float(DisplayServer.window_get_size().x) / maxf(get_viewport_rect().size.x, 1.0)
	var want: float = float(kb) / maxf(factor, 0.01)
	if absf(_kb_pad.custom_minimum_size.y - want) > 1.0:
		_kb_pad.custom_minimum_size.y = want


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_APPLICATION_PAUSED:
			if _views.has("scan"):
				_views["scan"].on_app_paused()
		NOTIFICATION_APPLICATION_RESUMED:
			if _views.has("scan"):
				_views["scan"].on_app_resumed(cur == "scan")
			if theme_mode == "auto":
				var d: bool = DisplayServer.is_dark_mode() if DisplayServer.is_dark_mode_supported() else false
				if d != UI.dark:
					_rebuild()
		NOTIFICATION_WM_GO_BACK_REQUEST:
			_on_back()
		NOTIFICATION_WM_CLOSE_REQUEST:
			get_tree().quit()


func _on_back() -> void:
	if _modal != null:
		_modal.queue_free()
		_modal = null
	elif cur == "create" and _views["create"].is_on_result():
		_views["create"].show_edit()
	elif cur != "create":
		_go("create", false)
	else:
		get_tree().quit()
