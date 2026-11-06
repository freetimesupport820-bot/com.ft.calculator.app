extends Node
## Autoload "GameState": encrypted local save (settings + history), runtime security guard.
## Replaces localStorage ("Store" in the HTML). No coins/economy exist in this app.

signal history_changed

const SAVE_PATH := "user://ft_state.sav"

var _data: Dictionary = {}
var history: Array = []  # [{kind, text, ts}] newest first


func _ready() -> void:
	_security_guard()
	_load()


## Environment lock: the game must run inside the official Godot native runtime
## (Android export or the editor). Anything else is shut down when checks are enabled.
func _security_guard() -> void:
	var native_ok: bool = OS.has_feature("android") or OS.has_feature("editor")
	if not native_ok:
		push_warning("Unsupported runtime for this build.")
		if AppConfig.SECURITY_CHECKS_ENABLED:
			get_tree().quit()


func _key() -> String:
	# Obfuscation-level key (the real protection is the encrypted PCK); NOT a secret.
	return (AppConfig.PACKAGE_NAME + "|FT-STATE|" + AppConfig.VERSION_NAME.get_slice(".", 0)).sha256_text()


func _load() -> void:
	_data = {}
	if FileAccess.file_exists(SAVE_PATH):
		var f := FileAccess.open_encrypted_with_pass(SAVE_PATH, FileAccess.READ, _key())
		if f:
			var parsed: Variant = JSON.parse_string(f.get_as_text())
			f.close()
			if parsed is Dictionary:
				_data = parsed
	var h: Variant = _data.get("ft_hist", [])
	history = h if h is Array else []


func _save() -> void:
	_data["ft_hist"] = history
	var f := FileAccess.open_encrypted_with_pass(SAVE_PATH, FileAccess.WRITE, _key())
	if f:
		f.store_string(JSON.stringify(_data))
		f.close()


func get_value(k: String, d: Variant = null) -> Variant:
	return _data.get(k, d)


func set_value(k: String, v: Variant) -> void:
	_data[k] = v
	_save()


func add_history(kind: String, text: String) -> void:
	var out: Array = []
	for h in history:
		if not (h.get("kind") == kind and h.get("text") == text):
			out.append(h)
	out.push_front({"kind": kind, "text": text, "ts": int(Time.get_unix_time_from_system() * 1000.0)})
	history = out.slice(0, AppConfig.HISTORY_MAX)
	_save()
	history_changed.emit()


func remove_history(i: int) -> void:
	if i >= 0 and i < history.size():
		history.remove_at(i)
		_save()
		history_changed.emit()


func clear_history() -> void:
	history = []
	_save()
	history_changed.emit()
