class_name NativeBridge
extends RefCounted
## Thin wrappers around Android features that Godot does not expose directly.
## Everything degrades gracefully (returns false) when a call is not possible.


static func vibrate(ms: int) -> void:
	Input.vibrate_handheld(ms)


static func copy(text: String) -> void:
	DisplayServer.clipboard_set(text)


static func open_url(url: String) -> void:
	OS.shell_open(url)


static func _activity() -> Object:
	if OS.get_name() != "Android" or not Engine.has_singleton("AndroidRuntime"):
		return null
	return Engine.get_singleton("AndroidRuntime").getActivity()


## Opens the Android share sheet. Image is shared through MediaStore (no FileProvider needed);
## falls back to text sharing. Returns true if a share sheet was requested.
static func share(png_bytes: PackedByteArray, text: String) -> bool:
	var act: Object = _activity()
	if act == null:
		return false
	var Intent = JavaClassWrapper.wrap("android.content.Intent")
	if Intent == null:
		return false
	var intent = Intent.Intent()
	intent.setAction("android.intent.action.SEND")
	var shared_image: bool = false
	if png_bytes.size() > 0:
		var uri_str: String = _insert_image(act, png_bytes)
		if uri_str != "":
			var Uri = JavaClassWrapper.wrap("android.net.Uri")
			var uri = Uri.parse(uri_str)
			intent.setType("image/png")
			intent.putExtra("android.intent.extra.STREAM", uri)
			intent.addFlags(1)  # FLAG_GRANT_READ_URI_PERMISSION
			shared_image = true
	if not shared_image:
		intent.setType("text/plain")
		intent.putExtra("android.intent.extra.TEXT", text)
	var chooser = Intent.createChooser(intent, "QR")
	if chooser == null:
		return false
	act.startActivity(chooser)
	return true


static func _insert_image(act: Object, png: PackedByteArray) -> String:
	var BitmapFactory = JavaClassWrapper.wrap("android.graphics.BitmapFactory")
	var Media = JavaClassWrapper.wrap("android.provider.MediaStore$Images$Media")
	if BitmapFactory == null or Media == null:
		return ""
	var bmp = BitmapFactory.decodeByteArray(png, 0, png.size())
	if bmp == null:
		return ""
	var res = Media.insertImage(act.getContentResolver(), bmp, "FT-QR-" + str(Time.get_ticks_msec()), "FT QR")
	return String(res) if res != null else ""
