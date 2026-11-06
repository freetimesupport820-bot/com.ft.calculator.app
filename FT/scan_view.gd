class_name ScanView
extends VBoxContainer
## Scan tab: live camera (Camera2 via CameraServer) with zoom/flip/torch-light, gallery decode, result card.

signal toast_requested(msg: String)
signal screen_light_requested(on: bool)
signal history_changed_by_scan

var skip_cam_once: bool = false
var scanner: CameraScanner

var _cam_card: UI.Card
var _res_card: UI.Card
var _cam_box: Control
var _cam_rect: ColorRect
var _frame_rect: ColorRect
var _scan_line: TextureRect
var _torch_btn: Button
var _flip_btn: Button
var _zoom_row: HBoxContainer
var _zoom: HSlider
var _cam_msg: Label
var _cam_btn: Button
var _pick_btn: Button
var _r_type: Label
var _r_text: Label
var _r_act: GridContainer
var _cam_on: bool = false
var _resume_cam: bool = false
var _screen_light: bool = false
var _line_tween: Tween
var _decoding_gallery: bool = false


func _ready() -> void:
	add_theme_constant_override("separation", 0)
	scanner = CameraScanner.new()
	add_child(scanner)
	scanner.started.connect(_on_started)
	scanner.failed.connect(_on_failed)
	scanner.code_found.connect(_on_code)
	_build()


func _build() -> void:
	_cam_card = UI.card()
	add_child(_cam_card)
	# square camera box
	var arc := Control.new()
	arc.visible = false
	arc.resized.connect(func() -> void:
		if absf(arc.custom_minimum_size.y - arc.size.x) > 0.5:
			arc.custom_minimum_size.y = arc.size.x)
	arc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_cam_card.box.add_child(arc)
	_cam_box = Control.new()
	_cam_box.clip_contents = true
	_cam_box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	arc.add_child(_cam_box)
	var black := Panel.new()
	black.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	black.add_theme_stylebox_override("panel", UI.flat(Color.BLACK, 20))
	_cam_box.add_child(black)
	_cam_rect = ColorRect.new()
	_cam_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_cam_rect.material = scanner.preview_material
	_cam_box.add_child(_cam_rect)
	_cam_rect.resized.connect(func() -> void: scanner.preview_material.set_shader_parameter("rect_size", _cam_rect.size))
	_frame_rect = ColorRect.new()
	_frame_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_frame_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var fm := ShaderMaterial.new()
	fm.shader = load("res://shaders/frame.gdshader")
	fm.set_shader_parameter("glow_color", UI.P["ac"])
	_frame_rect.material = fm
	_cam_box.add_child(_frame_rect)
	_frame_rect.resized.connect(func() -> void:
		fm.set_shader_parameter("rect_size", _frame_rect.size)
		_restart_line())
	# animated scan line
	var gt := GradientTexture1D.new()
	var gr := Gradient.new()
	gr.offsets = PackedFloat32Array([0.0, 0.35, 0.65, 1.0])
	gr.colors = PackedColorArray([Color(UI.P["ac"], 0.0), UI.P["ac"], UI.P["ac3"], Color(UI.P["ac3"], 0.0)])
	gt.gradient = gr
	gt.width = 128
	_scan_line = TextureRect.new()
	_scan_line.texture = gt
	_scan_line.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_scan_line.stretch_mode = TextureRect.STRETCH_SCALE
	_scan_line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_scan_line.size = Vector2(10, 4)
	_cam_box.add_child(_scan_line)
	# camera buttons (bottom-right)
	var ctl := VBoxContainer.new()
	ctl.add_theme_constant_override("separation", 10)
	ctl.anchor_left = 1.0
	ctl.anchor_right = 1.0
	ctl.anchor_top = 1.0
	ctl.anchor_bottom = 1.0
	ctl.offset_left = -4 - 46
	ctl.offset_right = -4
	ctl.offset_top = -12 - 102
	ctl.offset_bottom = -12
	_cam_box.add_child(ctl)
	_torch_btn = _round_btn("bolt")
	_torch_btn.pressed.connect(_toggle_torch)
	ctl.add_child(_torch_btn)
	_flip_btn = _round_btn("flip")
	_flip_btn.pressed.connect(_flip_cam)
	ctl.add_child(_flip_btn)
	# zoom row
	_zoom_row = HBoxContainer.new()
	_zoom_row.add_theme_constant_override("separation", 10)
	_zoom_row.visible = false
	var zo := _small_btn("zoom_out")
	zo.pressed.connect(func() -> void: _zoom_by(-0.5))
	_zoom = UI.slider(1.0, 4.0, 0.1, 1.0)
	_zoom.value_changed.connect(func(v: float) -> void: scanner.set_zoom(v))
	var zi := _small_btn("zoom_in")
	zi.pressed.connect(func() -> void: _zoom_by(0.5))
	_zoom_row.add_child(zo)
	_zoom_row.add_child(_zoom)
	_zoom_row.add_child(zi)
	var zm := MarginContainer.new()
	zm.add_theme_constant_override("margin_top", 12)
	zm.add_theme_constant_override("margin_bottom", 10)
	zm.add_child(_zoom_row)
	_cam_card.box.add_child(zm)
	_cam_msg = UI.hint(I18n.t("camHint"))
	_cam_card.box.add_child(_cam_msg)
	_cam_btn = UI.btn(I18n.t("startCam"), "pri")
	_cam_btn.visible = false
	_cam_btn.pressed.connect(start_cam)
	var cbm := MarginContainer.new()
	cbm.add_theme_constant_override("margin_bottom", 10)
	cbm.add_theme_constant_override("margin_top", 6)
	cbm.add_child(_cam_btn)
	_cam_card.box.add_child(cbm)
	_pick_btn = UI.btn(I18n.t("pick"), "sec")
	_pick_btn.pressed.connect(_pick_gallery)
	_cam_card.box.add_child(_pick_btn)
	# result card
	_res_card = UI.card()
	_res_card.visible = false
	var rm := MarginContainer.new()
	rm.add_theme_constant_override("margin_top", 14)
	rm.add_child(_res_card)
	add_child(rm)
	_res_card.box.add_child(UI.lbl(I18n.t("result"), 21, 700, "tx"))
	_res_card.box.add_child(UI.spacer(10))
	var tag_holder := HBoxContainer.new()
	var tag_panel := PanelContainer.new()
	tag_panel.add_theme_stylebox_override("panel", UI.empty())
	tag_holder.add_child(tag_panel)
	_r_type = UI.lbl("", 13, 600, Color.WHITE)
	var tm := MarginContainer.new()
	tm.add_theme_constant_override("margin_left", 9)
	tm.add_theme_constant_override("margin_right", 9)
	tm.add_theme_constant_override("margin_top", 1)
	tm.add_theme_constant_override("margin_bottom", 1)
	tm.add_child(_r_type)
	tag_panel.add_child(tm)
	UI.grad_bg(tag_panel, 8, UI.P["ac"], UI.P["ac2"], UI.P["ac2"], 0.5, 0.0)
	_res_card.box.add_child(tag_holder)
	var rp := PanelContainer.new()
	rp.add_theme_stylebox_override("panel", UI.flat(UI.P["res"], 14, UI.P["line"], 1, 0, Color.TRANSPARENT, Vector4(12, 8, 12, 8)))
	_r_text = UI.lbl("", 15, 500, "tx", true)
	rp.add_child(_r_text)
	var rpm := MarginContainer.new()
	rpm.add_theme_constant_override("margin_top", 8)
	rpm.add_theme_constant_override("margin_bottom", 8)
	rpm.add_child(rp)
	_res_card.box.add_child(rpm)
	_r_act = GridContainer.new()
	_r_act.columns = 2
	_r_act.add_theme_constant_override("h_separation", 10)
	_r_act.add_theme_constant_override("v_separation", 10)
	_res_card.box.add_child(_r_act)


func _round_btn(icon_name: String) -> Button:
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(46, 46)
	var sb := UI.flat(Color(0.04, 0.055, 0.157, 0.6), 23, Color(1, 1, 1, 0.55), 1)
	for st in ["normal", "hover", "pressed", "focus"]:
		b.add_theme_stylebox_override(st, sb)
	var cc := CenterContainer.new()
	cc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	cc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cc.add_child(UI.icon(icon_name, 24, Color.WHITE))
	b.add_child(cc)
	return b


func _small_btn(icon_name: String) -> Button:
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(40, 40)
	var sb := UI.flat(UI.P["navbg"], 20, UI.P["line"], 1)
	for st in ["normal", "hover", "pressed", "focus"]:
		b.add_theme_stylebox_override(st, sb)
	var ic := UI.icon(icon_name, 20, "tx")
	ic.position = Vector2(10, 10)
	b.add_child(ic)
	return b


func _restart_line() -> void:
	if _line_tween != null:
		_line_tween.kill()
	var s: Vector2 = _frame_rect.size
	if s.x < 10:
		return
	var inset: float = 0.18
	var x0: float = s.x * inset
	var w: float = s.x * (1.0 - 2.0 * inset)
	var y0: float = s.y * inset
	var y1: float = s.y * (1.0 - inset) - 4.0
	_scan_line.size = Vector2(w * 0.88, 4)
	_scan_line.position = Vector2(x0 + w * 0.06, y0)
	_line_tween = _scan_line.create_tween().set_loops()
	_line_tween.tween_property(_scan_line, "position:y", y1, 2.0).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_line_tween.tween_property(_scan_line, "position:y", y0, 2.0).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


# ------------------------------------------------------------ tab lifecycle
func on_enter() -> void:
	if skip_cam_once:
		skip_cam_once = false
		_cam_btn.visible = true
		return
	_res_card.get_parent().visible = false
	if scanner.facing != "environment":
		scanner.set_facing("environment")
	start_cam()


func on_leave() -> void:
	scanner.set_facing("environment")
	if _cam_on:
		stop_cam()


func start_cam() -> void:
	_cam_on = true
	_cam_rect.visible = false
	_cam_box.get_parent().visible = true
	_cam_msg.visible = false
	_cam_btn.visible = false
	_zoom_row.visible = true
	_zoom.value = 1.0
	scanner.set_zoom(1.0)
	scanner.start()


func stop_cam() -> void:
	_cam_on = false
	scanner.stop()
	_set_screen_light(false)
	_torch_btn.modulate = Color.WHITE
	_cam_box.get_parent().visible = false
	_zoom_row.visible = false
	_cam_btn.visible = true
	_cam_msg.visible = true


func _on_started() -> void:
	_cam_rect.visible = true


func _on_failed(reason: String) -> void:
	toast_requested.emit(I18n.t("camErr"))
	stop_cam()


func _on_code(text: String) -> void:
	stop_cam()
	NativeBridge.vibrate(60)
	show_result(text, false)


func _toggle_torch() -> void:
	# Godot's CameraServer has no torch control. Rear camera: not available (toast). Front camera: screen light.
	if scanner.facing == "user" and _cam_on:
		_set_screen_light(not _screen_light)
		return
	toast_requested.emit(I18n.t("noTorch"))


func _set_screen_light(on: bool) -> void:
	if on == _screen_light:
		return
	_screen_light = on
	_torch_btn.modulate = Color("#f59e0b") if on else Color.WHITE
	screen_light_requested.emit(on)


func _flip_cam() -> void:
	var f: String = "user" if scanner.facing == "environment" else "environment"
	var ic: Control = _flip_btn.get_child(0).get_child(0)
	var tw := create_tween()
	ic.rotation = 0.0
	tw.tween_property(ic, "rotation", TAU, 0.6).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_set_screen_light(false)
	scanner.stop()
	scanner.set_facing(f)
	start_cam()


func _zoom_by(d: float) -> void:
	_zoom.value = clampf(_zoom.value + d, _zoom.min_value, _zoom.max_value)


# ------------------------------------------------------------ gallery
func _pick_gallery() -> void:
	if _cam_on:
		stop_cam()
	var cb := func(ok: bool, paths: PackedStringArray, _f: int) -> void:
		if ok and not paths.is_empty():
			_scan_file(paths[0])
	var err: int = DisplayServer.file_dialog_show(I18n.t("pick"), "", "", false, DisplayServer.FILE_DIALOG_MODE_OPEN_FILE, PackedStringArray(["image/*"]), cb)
	if err != OK:
		toast_requested.emit(I18n.t("noQR"))


func _scan_file(path: String) -> void:
	if _decoding_gallery:
		return
	var bytes: PackedByteArray = FileAccess.get_file_as_bytes(path)
	if bytes.is_empty():
		toast_requested.emit(I18n.t("noQR"))
		return
	var img := Image.new()
	var err: int = ERR_FILE_UNRECOGNIZED
	if bytes.size() > 8 and bytes[0] == 0x89 and bytes[1] == 0x50:
		err = img.load_png_from_buffer(bytes)
	elif bytes.size() > 3 and bytes[0] == 0xFF and bytes[1] == 0xD8:
		err = img.load_jpg_from_buffer(bytes)
	elif bytes.size() > 12 and bytes[0] == 0x52 and bytes[1] == 0x49:
		err = img.load_webp_from_buffer(bytes)
	elif bytes.size() > 2 and bytes[0] == 0x42 and bytes[1] == 0x4D:
		err = img.load_bmp_from_buffer(bytes)
	else:
		err = img.load_png_from_buffer(bytes)
		if err != OK:
			err = img.load_jpg_from_buffer(bytes)
	if err != OK or img.is_empty():
		toast_requested.emit(I18n.t("noQR"))
		return
	_decoding_gallery = true
	var result: Array = [""]
	var task: int = WorkerThreadPool.add_task(func() -> void: result[0] = CameraScanner.decode_image(img))
	while not WorkerThreadPool.is_task_completed(task):
		await get_tree().process_frame
	WorkerThreadPool.wait_for_task_completion(task)
	_decoding_gallery = false
	if String(result[0]) != "":
		show_result(String(result[0]), false)
	else:
		toast_requested.emit(I18n.t("noQR"))


# ------------------------------------------------------------ result
func show_result(text: String, from_hist: bool) -> void:
	var kind: String = Payload.classify(text)
	_res_card.visible = true
	_res_card.get_parent().visible = true
	_r_type.text = I18n.type_name(kind)
	var shown: String = Payload.parse_wifi(text) if kind == "wifi" else text
	_r_text.text = shown
	for c in _r_act.get_children():
		c.queue_free()
	var copy := UI.btn(I18n.t("copy"), "pri")
	copy.pressed.connect(func() -> void:
		NativeBridge.copy(shown)
		toast_requested.emit(I18n.t("copied")))
	_r_act.add_child(copy)
	if kind == "url":
		var open := UI.btn(I18n.t("open"), "sec")
		open.pressed.connect(func() -> void: NativeBridge.open_url(text))
		_r_act.add_child(open)
	var again := UI.btn(I18n.t("again"), "sec")
	again.pressed.connect(func() -> void:
		_res_card.get_parent().visible = false
		start_cam())
	_r_act.add_child(again)
	if not from_hist:
		GameState.add_history("scanned", text)


# ------------------------------------------------------------ app lifecycle (camera only while visible)
func on_app_paused() -> void:
	_resume_cam = _cam_on
	if _cam_on:
		stop_cam()


func on_app_resumed(on_scan_tab: bool) -> void:
	if _resume_cam and on_scan_tab:
		_resume_cam = false
		start_cam()
