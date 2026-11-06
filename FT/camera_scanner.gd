class_name CameraScanner
extends Node
## Live QR scanning: Godot CameraServer (Android Camera2) -> GPU crop/zoom -> luminance readback ->
## pure-GDScript QRDecoder on a worker thread. Camera runs only while started (privacy, as in the HTML).

signal started
signal failed(reason: String)
signal code_found(text: String)

const DECODE_SIZE := 512
const DECODE_INTERVAL := 0.14

var facing: String = "environment"
var active: bool = false
var zoom: float = 1.0
var preview_material: ShaderMaterial
var diag: String = ""

var _feed: CameraFeed = null
var _tex_y: CameraTexture
var _tex_cbcr: CameraTexture
var _gray_vp: SubViewport
var _gray_rect: ColorRect
var _gray_mat: ShaderMaterial
var _timer: float = 0.0
var _busy: bool = false
var _decoding: bool = false
var _seq: int = 0
var _is_rgb: bool = false
var _first_frame: bool = false


func _ready() -> void:
	preview_material = ShaderMaterial.new()
	preview_material.shader = load("res://shaders/camera_color.gdshader")
	_gray_mat = ShaderMaterial.new()
	_gray_mat.shader = load("res://shaders/camera_gray.gdshader")
	_gray_vp = SubViewport.new()
	_gray_vp.size = Vector2i(DECODE_SIZE, DECODE_SIZE)
	_gray_vp.disable_3d = true
	_gray_vp.transparent_bg = false
	_gray_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(_gray_vp)
	_gray_rect = ColorRect.new()
	_gray_rect.size = Vector2(DECODE_SIZE, DECODE_SIZE)
	_gray_rect.material = _gray_mat
	_gray_vp.add_child(_gray_rect)
	set_process(false)
	get_tree().on_request_permissions_result.connect(_on_permission_result)


func start() -> void:
	if active:
		return
	active = true
	_seq += 1
	_first_frame = false
	_begin.call_deferred(_seq)


func stop() -> void:
	_seq += 1
	active = false
	set_process(false)
	_busy = false
	if _feed != null:
		if _feed.frame_changed.is_connected(_on_frame):
			_feed.frame_changed.disconnect(_on_frame)
		_feed.feed_is_active = false
		_feed = null
	_tex_y = null
	_tex_cbcr = null
	preview_material.set_shader_parameter("tex_y", null)
	preview_material.set_shader_parameter("tex_cbcr", null)
	_gray_mat.set_shader_parameter("tex_y", null)
	if CameraServer.monitoring_feeds:
		CameraServer.monitoring_feeds = false


func set_zoom(z: float) -> void:
	zoom = maxf(1.0, z)
	preview_material.set_shader_parameter("zoom", zoom)
	_gray_mat.set_shader_parameter("zoom", zoom)


func set_facing(f: String) -> void:
	facing = f


func _has_permission() -> bool:
	if OS.get_name() != "Android":
		return true
	return OS.request_permission("CAMERA")


func _on_permission_result(permission: String, granted: bool) -> void:
	if not active:
		return
	if permission.to_upper().ends_with("CAMERA"):
		if granted:
			_begin.call_deferred(_seq)
		else:
			active = false
			failed.emit("permission")


func _begin(seq: int) -> void:
	if seq != _seq or not active:
		return
	if not _has_permission():
		return  # waits for _on_permission_result
	CameraServer.monitoring_feeds = true
	var tries: int = 0
	while CameraServer.get_feed_count() == 0 and tries < 20:
		await get_tree().create_timer(0.15).timeout
		if seq != _seq or not active:
			return
		tries += 1
	var want: int = CameraFeed.FEED_FRONT if facing == "user" else CameraFeed.FEED_BACK
	var chosen: CameraFeed = null
	for f in CameraServer.feeds():
		if f.get_position() == want:
			chosen = f
			break
	if chosen == null and CameraServer.get_feed_count() > 0:
		chosen = CameraServer.feeds()[0]
	if chosen == null:
		active = false
		failed.emit("nocam")
		return
	_feed = chosen
	_pick_format(_feed)
	_tex_y = CameraTexture.new()
	_tex_y.camera_feed_id = _feed.get_id()
	_tex_y.which_feed = CameraServer.FEED_Y_IMAGE
	_tex_cbcr = CameraTexture.new()
	_tex_cbcr.camera_feed_id = _feed.get_id()
	_tex_cbcr.which_feed = CameraServer.FEED_CBCR_IMAGE
	_feed.frame_changed.connect(_on_frame)
	_feed.feed_is_active = true
	if not _feed.feed_is_active:
		active = false
		failed.emit("nocam")
		return
	_apply_params()
	set_process(true)
	started.emit()


func _pick_format(feed: CameraFeed) -> void:
	var fmts: Array = feed.formats
	var best: int = 0
	var best_score: float = 1e18
	for i in range(fmts.size()):
		var d: Dictionary = fmts[i]
		var w: int = int(d.get("width", 0))
		var h: int = int(d.get("height", 0))
		var fs: String = str(d.get("format", "")).to_upper()
		var score: float = absf(float(w * h) - 1280.0 * 720.0)
		if w * h > 1920 * 1088:
			score += 1e9
		if fs.find("YUV") == -1 and fs != "":
			score += 5e6
		if score < best_score:
			best_score = score
			best = i
	if fmts.size() > 0:
		feed.set_format(best, {})
		var d2: Dictionary = fmts[best]
		diag = "%dx%d %s" % [int(d2.get("width", 0)), int(d2.get("height", 0)), str(d2.get("format", ""))]


func _on_frame() -> void:
	if _feed == null:
		return
	if not _first_frame:
		_first_frame = true
		_apply_params()


func _apply_params() -> void:
	if _feed == null:
		return
	_is_rgb = _feed.get_datatype() == CameraFeed.FEED_RGB
	var fmts: Array = _feed.formats
	var w: float = 1280.0
	var h: float = 720.0
	if fmts.size() > 0:
		# selected format is not exposed; derive aspect from the texture once available
		pass
	var sz: Vector2i = Vector2i.ZERO
	if _tex_y != null:
		sz = Vector2i(_tex_y.get_width(), _tex_y.get_height())
	if sz.x > 0 and sz.y > 0:
		w = float(sz.x)
		h = float(sz.y)
	var rot_deg: float = rad_to_deg(_feed.feed_transform.get_rotation()) + float(AppConfig.CAMERA_ROTATION_OFFSET_DEG)
	var q: int = int(round(rot_deg / 90.0))
	q = ((q % 4) + 4) % 4
	var aspect: float = w / h
	if q % 2 == 1:
		aspect = h / w
	var mirror: bool = AppConfig.CAMERA_MIRROR_FRONT and facing == "user"
	for m in [preview_material, _gray_mat]:
		m.set_shader_parameter("tex_y", _tex_y)
		m.set_shader_parameter("is_rgb", _is_rgb)
		m.set_shader_parameter("rot_quarters", float(q))
		m.set_shader_parameter("img_aspect", aspect)
		m.set_shader_parameter("zoom", zoom)
	preview_material.set_shader_parameter("tex_cbcr", _tex_cbcr)
	preview_material.set_shader_parameter("mirror", mirror)
	diag = "%s · rot=%d° q=%d · %s" % [diag.get_slice(" · ", 0), int(rot_deg), q, "RGB" if _is_rgb else "YCbCr"]


func _process(delta: float) -> void:
	if not active or _feed == null or _busy or _decoding:
		return
	_timer += delta
	if _timer < DECODE_INTERVAL:
		return
	_timer = 0.0
	if not _first_frame:
		return
	_grab.call_deferred(_seq)


func _grab(seq: int) -> void:
	if _busy or seq != _seq or not active:
		return
	_busy = true
	_gray_vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	await RenderingServer.frame_post_draw
	if seq != _seq or not active:
		_busy = false
		return
	var img: Image = _gray_vp.get_texture().get_image()
	_busy = false
	if img == null or img.is_empty():
		return
	img.convert(Image.FORMAT_L8)
	var data: PackedByteArray = img.get_data()
	var w: int = img.get_width()
	var h: int = img.get_height()
	_decoding = true
	WorkerThreadPool.add_task(_decode_task.bind(data, w, h, seq))


func _decode_task(data: PackedByteArray, w: int, h: int, seq: int) -> void:
	var res: String = QRDecoder.decode(data, w, h, false, false)
	_decoded.call_deferred(res, seq)


func _decoded(res: String, seq: int) -> void:
	_decoding = false
	if seq != _seq or not active:
		return
	if res != "":
		code_found.emit(res)


## Decode a still image (gallery): several sizes like the HTML, inverted codes allowed, noise retry.
static func decode_image(img: Image) -> String:
	var src: Image = img.duplicate()
	if src.is_compressed():
		src.decompress()
	var w0: int = src.get_width()
	var h0: int = src.get_height()
	for m in [1600, 1000, 640, 400]:
		var s: float = minf(1.0, float(m) / float(maxi(w0, h0)))
		var w: int = maxi(1, int(round(w0 * s)))
		var h: int = maxi(1, int(round(h0 * s)))
		var t: Image = src.duplicate()
		if w != w0 or h != h0:
			t.resize(w, h, Image.INTERPOLATE_LANCZOS)
		if t.get_format() == Image.FORMAT_RGBA8:
			# composite over white (HTML: fillStyle #fff before drawImage)
			var bg: Image = Image.create(w, h, false, Image.FORMAT_RGBA8)
			bg.fill(Color.WHITE)
			bg.blend_rect(t, Rect2i(0, 0, w, h), Vector2i.ZERO)
			t = bg
		t.convert(Image.FORMAT_L8)
		var res: String = QRDecoder.decode(t.get_data(), w, h, true, m == 400)
		if res != "":
			return res
	return ""
