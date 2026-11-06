class_name HistoryView
extends VBoxContainer
## History tab: list of created/scanned items (tap to open in Scan result, x to delete, clear all).

signal item_selected(text: String)
signal clear_requested
signal toast_requested(msg: String)


func _ready() -> void:
	add_theme_constant_override("separation", 0)
	GameState.history_changed.connect(refresh)
	refresh()


func refresh() -> void:
	for c in get_children():
		c.queue_free()
	var card := UI.card()
	add_child(card)
	card.box.add_child(UI.lbl(I18n.t("history"), 21, 700, "tx"))
	card.box.add_child(UI.spacer(8))
	var hist: Array = GameState.history
	if hist.is_empty():
		card.box.add_child(UI.hint(I18n.t("empty")))
	for i in range(hist.size()):
		card.box.add_child(_item(i, hist[i]))
	card.box.add_child(UI.spacer(12))
	var clr := UI.btn(I18n.t("clear"), "danger")
	clr.pressed.connect(func() -> void:
		if not GameState.history.is_empty():
			clear_requested.emit())
	card.box.add_child(clr)


func _item(i: int, h: Dictionary) -> Control:
	var row := PanelContainer.new()
	row.add_theme_stylebox_override("panel", UI.flat(UI.P["res"], 14, UI.P["line"], 1, 0, Color.TRANSPARENT, Vector4(12, 8, 6, 8)))
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 6)
	row.add_child(hb)
	var txt: String = String(h.get("text", ""))
	var title: String = txt.substr(0, 80).replace("\n", " ")
	var kind: String = String(h.get("kind", "created"))
	var when: String = Time.get_datetime_string_from_unix_time(int(float(h.get("ts", 0)) / 1000.0) + int(Time.get_time_zone_from_system().get("bias", 0)) * 60, true)
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 0)
	col.mouse_filter = Control.MOUSE_FILTER_PASS
	var t1 := UI.lbl(title, 16, 700, "tx")
	t1.clip_text = true
	t1.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	t1.mouse_filter = Control.MOUSE_FILTER_PASS
	var t2 := UI.lbl("%s · %s" % [I18n.t(kind), when], 13, 500, "mut")
	t2.mouse_filter = Control.MOUSE_FILTER_PASS
	col.add_child(t1)
	col.add_child(t2)
	hb.add_child(col)
	var x := Button.new()
	x.text = "×"
	x.focus_mode = Control.FOCUS_NONE
	x.custom_minimum_size = Vector2(44, 44)
	x.add_theme_font_size_override("font_size", 28)
	for k in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		x.add_theme_color_override(k, UI.P["bad"])
	for st in ["normal", "hover", "pressed", "focus"]:
		x.add_theme_stylebox_override(st, UI.empty())
	x.pressed.connect(func() -> void: GameState.remove_history(i))
	hb.add_child(x)
	# tap on the row (not the x) opens the item; a drag scrolls instead
	var down_pos := [Vector2.ZERO, false]
	row.gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT:
			if ev.pressed:
				down_pos[0] = ev.global_position
				down_pos[1] = true
			elif down_pos[1]:
				down_pos[1] = false
				if ev.global_position.distance_to(down_pos[0]) < 14.0 and ev.position.x < row.size.x - 50.0:
					item_selected.emit(txt))
	var wrap := MarginContainer.new()
	wrap.add_theme_constant_override("margin_bottom", 8)
	wrap.add_child(row)
	return wrap
