class_name AboutView
extends VBoxContainer
## About + Privacy Policy tab (text ported 1:1 from the HTML).

const PRIVACY: Array = [
	["p", "[b]Effective date:[/b] November 2026 · [b]Developer:[/b] MD SHAHIN ALOM RASEL (FREE TIME), Bangladesh."],
	["h", "1. Summary"],
	["p", "F T - CREATE QR & SCANNING does not require an account and does not send the QR codes you create or scan to our servers. All QR generation and decoding happens on your device."],
	["h", "2. Information we handle"],
	["p", "• [b]Camera:[/b] used only while the scanner is open on screen. It is released immediately when you leave the Scan page, open the gallery, or a code is found. Video frames are processed in memory on your device and are never recorded, stored or uploaded."],
	["p", "• [b]Images you pick:[/b] read locally only to find a QR code; not uploaded."],
	["p", "• [b]History:[/b] the text of codes you create or scan is saved only on your device so you can reuse it. You can delete items one by one or clear everything in the History tab. Uninstalling the app removes it."],
	["p", "• [b]Files you save/share:[/b] PNG images are saved or shared only when you choose to."],
	["h", "3. Wi-Fi and sensitive content"],
	["p", "If you create a Wi-Fi QR code, the network name and password are stored in your local history. Do not share such QR codes with people you do not trust, and clear history on shared devices."],
	["h", "4. Advertising and third parties"],
	["p", "The app may show ads through Google AdMob. AdMob may collect device identifiers (such as the advertising ID), IP address and general usage data to serve and measure ads, under Google’s own policy: [url=https://policies.google.com/privacy]policies.google.com/privacy[/url]. We do not receive or sell your QR content. You can reset or disable your advertising ID in your device settings."],
	["h", "5. Opening links"],
	["p", "Scanning a code never opens it automatically. If it contains a link, you choose whether to open it. Be careful with links from unknown sources; the destination site has its own privacy practices."],
	["h", "6. Children"],
	["p", "The app is not directed to children under 13 and we do not knowingly collect personal data from children."],
	["h", "7. Security"],
	["p", "Data stays on your device and is protected by your device’s own security. No method of storage is perfectly secure."],
	["h", "8. Your choices"],
	["p", "You can deny camera permission (you can still scan from images), delete history at any time, and uninstall the app to remove all local data."],
	["h", "9. Changes"],
	["p", "We may update this policy; the effective date will change and the new text will appear in this section."],
	["h", "10. Contact"],
	["p", "Questions or requests: [url=mailto:free.time.support.820@email.com]free.time.support.820@email.com[/url]\nMD SHAHIN ALOM RASEL · FREE TIME · BANGLADESH"],
]


func _ready() -> void:
	add_theme_constant_override("separation", 14)
	var a := UI.card()
	add_child(a)
	a.box.add_child(UI.lbl(I18n.t("about"), 21, 700, "tx"))
	a.box.add_child(UI.spacer(8))
	a.box.add_child(_kv("App:", AppConfig.APP_NAME))
	a.box.add_child(_kv("Developer:", AppConfig.DEVELOPER))
	var c := _kv("Country:", AppConfig.COUNTRY)
	var flag := UI.Flag.new()
	flag.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	c.add_child(flag)
	a.box.add_child(c)
	a.box.add_child(_kv("Organization:", AppConfig.ORGANIZATION))
	var ct := HBoxContainer.new()
	ct.add_theme_constant_override("separation", 6)
	ct.add_child(UI.lbl("Contact:", 16, 700, "tx"))
	var mail := RichTextLabel.new()
	_style_rtl(mail, 16)
	mail.text = "[url=mailto:%s]%s[/url]" % [AppConfig.CONTACT_EMAIL, AppConfig.CONTACT_EMAIL]
	ct.add_child(mail)
	a.box.add_child(ct)
	a.box.add_child(UI.spacer(8))
	a.box.add_child(UI.hint("Create QR codes for text, links, Wi-Fi, phone, SMS and email, and scan any QR code with your camera or from an image. Everything works on your device."))
	var p := UI.card()
	add_child(p)
	p.box.add_child(UI.lbl("Privacy Policy", 21, 700, "tx"))
	p.box.add_child(UI.spacer(6))
	for it in PRIVACY:
		var r := RichTextLabel.new()
		_style_rtl(r, 15 if it[0] == "p" else 17)
		r.text = ("[b]%s[/b]" % it[1]) if it[0] == "h" else String(it[1])
		var m := MarginContainer.new()
		m.add_theme_constant_override("margin_top", 10 if it[0] == "h" else 4)
		m.add_child(r)
		p.box.add_child(m)
	var fl := UI.Flag.new()
	var fm := MarginContainer.new()
	fm.add_theme_constant_override("margin_top", 6)
	fm.add_child(fl)
	p.box.add_child(fm)


func _kv(k: String, v: String) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 6)
	h.add_child(UI.lbl(k, 16, 700, "tx"))
	var l := UI.lbl(v, 16, 500, "tx", k != "Country:")
	h.add_child(l)
	return h


func _style_rtl(r: RichTextLabel, size: int) -> void:
	r.bbcode_enabled = true
	r.fit_content = true
	r.scroll_active = false
	r.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	r.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	r.add_theme_font_override("normal_font", UI.font(500))
	r.add_theme_font_override("bold_font", UI.font(700))
	r.add_theme_font_size_override("normal_font_size", size)
	r.add_theme_font_size_override("bold_font_size", size)
	r.add_theme_color_override("default_color", UI.P["tx"])
	r.add_theme_color_override("font_selected_color", UI.P["tx"])
	r.add_theme_color_override("selection_color", Color(UI.P["ac"], 0.3))
	r.meta_clicked.connect(func(m: Variant) -> void: OS.shell_open(String(m)))
	r.mouse_filter = Control.MOUSE_FILTER_PASS
