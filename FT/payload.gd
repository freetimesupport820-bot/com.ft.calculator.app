class_name Payload
extends RefCounted
## QR payload builders + classifier (port of TYPES / classify / parseWifi / wifiEsc / lum).

const ORDER: Array = ["text", "url", "wifi", "tel", "sms", "mail"]

## field = [id, kind, extra]
const FIELDS: Dictionary = {
	"text": [["text", "textarea", ""]],
	"url": [["url", "text", "https://"]],
	"wifi": [["ssid", "text", ""], ["pass", "password", ""], ["sec", "select", ["WPA", "WEP", "nopass"]], ["hid", "check", ""]],
	"tel": [["tel", "tel", ""]],
	"sms": [["tel", "tel", ""], ["msg", "textarea", ""]],
	"mail": [["to", "email", ""], ["sub", "text", ""], ["body", "textarea", ""]],
}
const REQUIRED: Dictionary = {
	"wifi": ["ssid"], "sms": ["tel"], "mail": ["to"],
}


static func required_fields(type_key: String) -> Array:
	if REQUIRED.has(type_key):
		return REQUIRED[type_key]
	return [FIELDS[type_key][0][0]]


static func wifi_esc(s: String) -> String:
	var out := ""
	for ch in s:
		if ch in ["\\", ";", ",", ":", "\""]:
			out += "\\"
		out += ch
	return out


static func digits_plus(s: String) -> String:
	var out := ""
	for ch in s:
		if (ch >= "0" and ch <= "9") or ch == "+":
			out += ch
	return out


static func build(type_key: String, v: Dictionary) -> String:
	match type_key:
		"text":
			return String(v.get("text", ""))
		"url":
			var u: String = String(v.get("url", ""))
			var re := RegEx.create_from_string("(?i)^[a-z][a-z0-9+.-]*:")
			return u if re.search(u) != null else "https://" + u
		"wifi":
			var sec: String = String(v.get("sec", "WPA"))
			return "WIFI:T:%s;S:%s;P:%s;H:%s;;" % [sec, wifi_esc(String(v.get("ssid", ""))), "" if sec == "nopass" else wifi_esc(String(v.get("pass", ""))), "true" if v.get("hid", false) else "false"]
		"tel":
			return "tel:" + digits_plus(String(v.get("tel", "")))
		"sms":
			return "SMSTO:%s:%s" % [digits_plus(String(v.get("tel", ""))), String(v.get("msg", ""))]
		"mail":
			return "mailto:%s?subject=%s&body=%s" % [String(v.get("to", "")), String(v.get("sub", "")).uri_encode(), String(v.get("body", "")).uri_encode()]
	return ""


static func classify(t: String) -> String:
	var l: String = t.to_lower()
	if l.begins_with("http://") or l.begins_with("https://"):
		return "url"
	if l.begins_with("wifi:"):
		return "wifi"
	if l.begins_with("tel:"):
		return "tel"
	if l.begins_with("sms:") or l.begins_with("smsto:"):
		return "sms"
	if l.begins_with("mailto:"):
		return "mail"
	return "text"


static func parse_wifi(t: String) -> String:
	return "SSID: %s\nPassword: %s\nSecurity: %s" % [_wifi_get(t, "S"), _wifi_get(t, "P"), _wifi_get(t, "T") if _wifi_get(t, "T") != "" else "-"]


static func _wifi_get(t: String, k: String) -> String:
	var re := RegEx.create_from_string("(?i)(?:^WIFI:|;)" + k + ":((?:\\\\.|[^;])*)")
	var m := re.search(t)
	if m == null:
		return ""
	var raw: String = m.get_string(1)
	var out := ""
	var i := 0
	while i < raw.length():
		if raw[i] == "\\" and i + 1 < raw.length():
			out += raw[i + 1]
			i += 2
		else:
			out += raw[i]
			i += 1
	return out


## Relative luminance (WCAG) of a Color - used for the low-contrast warning.
static func lum(c: Color) -> float:
	var f := func(x: float) -> float:
		return x / 12.92 if x <= 0.03928 else pow((x + 0.055) / 1.055, 2.4)
	return 0.2126 * f.call(c.r) + 0.7152 * f.call(c.g) + 0.0722 * f.call(c.b)
