class_name CreateView
extends VBoxContainer
## Create tab: type chips, dynamic form, colours/size/ECC, generate, result pane (port of the HTML "Create" view).

signal toast_requested(msg: String)

var cur_type: String = "text"
var fg_color: Color = Color("#0b1b3a")
var bg_color: Color = Color("#ffffff")
var size_px: int = 512
var ecc_idx: int = 1

var _pane1: UI.Card
var _pane2: UI.Card
var _chips_box: HBoxContainer
var _form_box: VBoxContainer
var _fields: Dictionary = {}
var _size_lbl: Label
var _qr_tex: TextureRect
var _info: Label
var _image: Image
var _last_text: String = ""

# interstitial pacing: ad on the 1st QR, 2 free QR codes, then an ad on the 4th, and so on.
# A missed ad stays due until it is really shown.
var _ad_due: bool = true
var _free_left: int = 0
var _ad_busy: bool = false


func _ready() -> void:
	add_theme_constant_override("separation", 0)
	_build()


func _build() -> void:
	for c in get_children():
		c.queue_free()
	_fields.clear()
	# ---------------- pane 1: form
	_pane1 = UI.card()
	add_child(_pane1)
	var scroll := ScrollContainer.new()
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	scroll.custom_minimum_size = Vector2(0, 46)
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_pane1.box.add_child(scroll)
	_chips_box = HBoxContainer.new()
	_chips_box.add_theme_constant_override("separation", 8)
	scroll.add_child(_chips_box)
	_render_chips()
	_form_box = VBoxContainer.new()
	_form_box.add_theme_constant_override("separation", 0)
	_pane1.box.add_child(_form_box)
	_render_form()
	# colours
	var g := GridContainer.new()
	g.columns = 2
	g.add_theme_constant_override("h_separation", 10)
	g.add_theme_constant_override("v_separation", 0)
	_pane1.box.add_child(UI.spacer(10))
	_pane1.box.add_child(g)
	g.add_child(_color_col(I18n.t("fg"), fg_color, func(c: Color) -> void: fg_color = c))
	g.add_child(_color_col(I18n.t("bg"), bg_color, func(c: Color) -> void: bg_color = c))
	# size
	_size_lbl = UI.lbl("%s: %d px" % [I18n.t("size"), size_px], 15, 500, "mut")
	_pane1.box.add_child(_gap(_size_lbl, 10, 4))
	var sl := UI.slider(256, 1024, 64, size_px)
	sl.value_changed.connect(func(v: float) -> void:
		size_px = int(v)
		_size_lbl.text = "%s: %d px" % [I18n.t("size"), size_px])
	_pane1.box.add_child(sl)
	# ecc
	_pane1.box.add_child(_gap(UI.lbl(I18n.t("ecc"), 15, 500, "mut"), 10, 4))
	var ecc := UI.option(["L – 7%", "M – 15%", "Q – 25%", "H – 30%"], ecc_idx)
	ecc.item_selected.connect(func(i: int) -> void: ecc_idx = i)
	_pane1.box.add_child(ecc)
	var gen := UI.btn(I18n.t("gen"), "pri")
	gen.pressed.connect(generate)
	_pane1.box.add_child(UI.spacer(14))
	_pane1.box.add_child(gen)
	# ---------------- pane 2: result
	_pane2 = UI.card()
	_pane2.visible = false
	add_child(_pane2)
	_pane2.box.add_child(UI.lbl(I18n.t("yours"), 21, 700, "tx"))
	_pane2.box.add_child(UI.spacer(10))
	var qrbox := PanelContainer.new()
	qrbox.add_theme_stylebox_override("panel", UI.flat(UI.P["card"], 20, UI.P["line"], 1, 14, Color(UI.P["ac2"], 0.28), Vector4(14, 14, 14, 14)))
	_pane2.box.add_child(qrbox)
	var cc := CenterContainer.new()
	qrbox.add_child(cc)
	_qr_tex = TextureRect.new()
	_qr_tex.custom_minimum_size = Vector2(300, 300)
	_qr_tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_qr_tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_qr_tex.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	cc.add_child(_qr_tex)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	_pane2.box.add_child(UI.spacer(10))
	_pane2.box.add_child(row)
	var save := UI.btn(I18n.t("save"), "pri")
	save.pressed.connect(save_png)
	row.add_child(save)
	var share := UI.btn(I18n.t("share"), "sec")
	share.pressed.connect(share_png)
	row.add_child(share)
	_info = UI.hint("")
	_pane2.box.add_child(_gap(_info, 6, 0))
	var edit := UI.btn("", "sec")
	var eh := HBoxContainer.new()
	eh.alignment = BoxContainer.ALIGNMENT_CENTER
	eh.add_theme_constant_override("separation", 8)
	eh.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	eh.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var arrow := UI.icon("back", 20, "tx")
	eh.add_child(arrow)
	eh.add_child(UI.lbl(I18n.t("edit"), 19, 700, "tx"))
	edit.add_child(eh)
	edit.pressed.connect(show_edit)
	_pane2.box.add_child(UI.spacer(10))
	_pane2.box.add_child(edit)
	var tw := arrow.create_tween().set_loops()  # nudge animation (icnudge)
	tw.tween_property(arrow, "position:x", arrow.position.x - 3.0, 0.8).set_trans(Tween.TRANS_SINE)
	tw.tween_property(arrow, "position:x", arrow.position.x, 0.8).set_trans(Tween.TRANS_SINE)
	if _image != null:
		_qr_tex.texture = ImageTexture.create_from_image(_image)


func _gap(c: Control, top: float, bottom: float) -> Control:
	var m := MarginContainer.new()
	m.add_theme_constant_override("margin_top", int(top))
	m.add_theme_constant_override("margin_bottom", int(bottom))
	m.add_child(c)
	return m


func _color_col(label: String, c: Color, on_change: Callable) -> Control:
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_child(_gap(UI.lbl(label, 15, 500, "mut"), 0, 4))
	var p := ColorPickerButton.new()
	p.color = c
	p.edit_alpha = false
	p.custom_minimum_size = Vector2(0, 44)
	p.focus_mode = Control.FOCUS_NONE
	var sb := UI.flat(UI.P["input"], 12, UI.P["line"], 1, 0, Color.TRANSPARENT, Vector4(6, 6, 6, 6))
	for st in ["normal", "hover", "pressed", "focus"]:
		p.add_theme_stylebox_override(st, sb)
	p.color_changed.connect(on_change)
	v.add_child(p)
	return v


func _render_chips() -> void:
	for c in _chips_box.get_children():
		c.queue_free()
	for k in Payload.ORDER:
		var b := UI.chip(I18n.type_name(k), k == cur_type)
		b.pressed.connect(func() -> void:
			cur_type = k
			_render_chips()
			_render_form())
		_chips_box.add_child(b)


func _render_form() -> void:
	for c in _form_box.get_children():
		c.queue_free()
	_fields.clear()
	for f in Payload.FIELDS[cur_type]:
		var id: String = f[0]
		var kind: String = f[1]
		var extra: Variant = f[2]
		match kind:
			"textarea":
				_form_box.add_child(_gap(UI.lbl(I18n.field(id), 15, 500, "mut"), 10, 4))
				var ta := UI.text_area()
				ta.text_changed.connect(func() -> void:
					if ta.text.length() > 1500:
						ta.text = ta.text.substr(0, 1500)
						ta.set_caret_column(ta.text.length()))
				_form_box.add_child(ta)
				_fields[id] = ta
			"select":
				_form_box.add_child(_gap(UI.lbl(I18n.field(id), 15, 500, "mut"), 10, 4))
				var o := UI.option(extra, 0)
				_form_box.add_child(o)
				_fields[id] = o
			"check":
				var cb := CheckBox.new()
				cb.text = " " + I18n.field(id)
				cb.focus_mode = Control.FOCUS_NONE
				cb.add_theme_font_override("font", UI.font(500))
				cb.add_theme_font_size_override("font_size", 15)
				for k in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color"]:
					cb.add_theme_color_override(k, UI.P["mut"])
				_form_box.add_child(_gap(cb, 10, 0))
				_fields[id] = cb
			_:
				_form_box.add_child(_gap(UI.lbl(I18n.field(id), 15, 500, "mut"), 10, 4))
				var kb: int = LineEdit.KEYBOARD_TYPE_DEFAULT
				if kind == "tel":
					kb = LineEdit.KEYBOARD_TYPE_PHONE
				elif kind == "email":
					kb = LineEdit.KEYBOARD_TYPE_EMAIL_ADDRESS
				elif id == "url":
					kb = LineEdit.KEYBOARD_TYPE_URL
				var le := UI.line_edit(String(extra), kind == "password", kb)
				_form_box.add_child(le)
				_fields[id] = le
	if _fields.has("sec") and _fields.has("pass"):
		var sec: OptionButton = _fields["sec"]
		sec.item_selected.connect(func(i: int) -> void:
			_fields["pass"].editable = sec.get_item_text(i) != "nopass")


func _read_form() -> Dictionary:
	var v: Dictionary = {}
	for id in _fields:
		var c: Control = _fields[id]
		if c is CheckBox:
			v[id] = c.button_pressed
		elif c is OptionButton:
			v[id] = c.get_item_text(c.selected)
		elif c is TextEdit:
			v[id] = c.text.strip_edges()
		else:
			v[id] = (c as LineEdit).text.strip_edges()
	return v


func generate() -> void:
	var v: Dictionary = _read_form()
	for k in Payload.required_fields(cur_type):
		if String(v.get(k, "")) == "":
			toast_requested.emit(I18n.t("needText"))
			return
	var text: String = Payload.build(cur_type, v)
	if absf(Payload.lum(fg_color) - Payload.lum(bg_color)) < 0.35:
		toast_requested.emit(I18n.t("lowC"))
	var q: QREncoder = QREncoder.encode(text, ecc_idx)
	if q == null:
		toast_requested.emit(I18n.t("tooLong"))
		return
	var tot: int = q.size + 8
	var cell: int = maxi(1, int(floor(float(size_px) / tot)))
	var px: int = cell * tot
	_image = Image.create(px, px, false, Image.FORMAT_RGBA8)
	_image.fill(bg_color)
	var fgc := Color(fg_color, 1.0)
	for r in range(q.size):
		for c in range(q.size):
			if q.is_dark(r, c):
				_image.fill_rect(Rect2i((c + 4) * cell, (r + 4) * cell, cell, cell), fgc)
	_qr_tex.texture = ImageTexture.create_from_image(_image)
	_last_text = text
	_info.text = "%d×%d · %dpx · %d chars" % [q.size, q.size, px, text.length()]
	GameState.add_history("created", text)
	_pane1.visible = false
	_pane2.visible = true
	_after_qr()


func get_state() -> Dictionary:
	return {"t": cur_type, "fg": fg_color, "bg": bg_color, "sz": size_px, "ecc": ecc_idx}


func set_state(s: Dictionary) -> void:
	cur_type = s.get("t", cur_type)
	fg_color = s.get("fg", fg_color)
	bg_color = s.get("bg", bg_color)
	size_px = s.get("sz", size_px)
	ecc_idx = s.get("ecc", ecc_idx)


func show_edit() -> void:
	_pane2.visible = false
	_pane1.visible = true


func is_on_result() -> bool:
	return _pane2 != null and _pane2.visible


func _after_qr() -> void:
	if _ad_busy:
		return
	if _ad_due:
		_ad_busy = true
		var ok: bool = await AdController.show_when_ready(5000)
		_ad_busy = false
		if ok:
			_ad_due = false
			_free_left = 2
	else:
		_free_left -= 1
		if _free_left <= 0:
			_ad_due = true


func save_png() -> void:
	if _image == null:
		return
	var bytes: PackedByteArray = _image.save_png_to_buffer()
	var fname: String = "FT-QR-%d.png" % int(Time.get_unix_time_from_system() * 1000.0)
	if OS.get_name() == "Android" or DisplayServer.has_feature(DisplayServer.FEATURE_NATIVE_DIALOG_FILE):
		var cb := func(ok: bool, paths: PackedStringArray, _filter: int) -> void:
			if not ok or paths.is_empty():
				return
			var f := FileAccess.open(paths[0], FileAccess.WRITE)
			if f:
				f.store_buffer(bytes)
				f.close()
				toast_requested.emit(I18n.t("saved"))
		var err: int = DisplayServer.file_dialog_show(I18n.t("save"), "", fname, false, DisplayServer.FILE_DIALOG_MODE_SAVE_FILE, PackedStringArray(["*.png"]), cb)
		if err == OK:
			return
	var path: String = "user://" + fname
	var f2 := FileAccess.open(path, FileAccess.WRITE)
	if f2:
		f2.store_buffer(bytes)
		f2.close()
		toast_requested.emit(I18n.t("saved"))


func share_png() -> void:
	if _image == null:
		return
	if NativeBridge.share(_image.save_png_to_buffer(), _last_text):
		return
	NativeBridge.copy(_last_text)
	toast_requested.emit(I18n.t("copied"))
