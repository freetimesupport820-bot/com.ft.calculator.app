extends Node
## Autoload "AdController" (Module A): native AdMob via Poing Studios godot-admob-plugin (v5.1.0).
## Replaces the AppMint browser bridge. Everything is deferred, null-checked and error-handled so a
## failing ad (or the "Given view not a child of FrameLayout" class of native crashes) never kills the app.

signal banner_height_changed(height_units: float)
signal diagnostics_changed(text: String)

var enabled: bool = false
var banner_ok: bool = false
var last: String = "-"

var _banner: AdView = null
var _inter: InterstitialAd = null
var _inter_loading: bool = false
var _inter_shown_flag: bool = false
var _consent_done: bool = false
var _sdk_ready: bool = false
var _stop_banner: bool = false
var _retry_delay: float = 5.0
var _hid_at: int = 0
var _watchdog: Timer
var _banner_retry: Timer
var _form: ConsentForm = null


func _ready() -> void:
	if OS.get_name() != "Android":
		last = "ads disabled (not Android)"
		return
	enabled = true
	_watchdog = Timer.new()
	_watchdog.wait_time = 10.0
	_watchdog.timeout.connect(_on_watchdog)
	add_child(_watchdog)
	_banner_retry = Timer.new()
	_banner_retry.one_shot = true
	_banner_retry.timeout.connect(_ensure_banner)
	add_child(_banner_retry)
	# never touch native views before the first frames are drawn
	_start_deferred.call_deferred()


func _start_deferred() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().create_timer(0.6).timeout
	_request_consent()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_PAUSED:
		_hid_at = Time.get_ticks_msec()
	elif what == NOTIFICATION_APPLICATION_RESUMED:
		if _sdk_ready and not _stop_banner and (not banner_ok or Time.get_ticks_msec() - _hid_at > 20000):
			_ensure_banner.call_deferred()


# ---------------------------------------------------------------- UMP consent (EEA / UK / others)
func _request_consent() -> void:
	var req := ConsentRequestParameters.new()
	req.tag_for_under_age_of_consent = false
	UserMessagingPlatform.consent_information.update(req, _on_consent_info_ok, _on_consent_info_fail)


func _on_consent_info_ok() -> void:
	if UserMessagingPlatform.consent_information.get_is_consent_form_available():
		UserMessagingPlatform.load_consent_form(_on_form_loaded, _on_form_failed)
	else:
		_after_consent()


func _on_consent_info_fail(err: FormError) -> void:
	last = "consent update failed"
	_report()
	_after_consent()


func _on_form_loaded(form: ConsentForm) -> void:
	_form = form
	var st = UserMessagingPlatform.consent_information.get_consent_status()
	if st == UserMessagingPlatform.consent_information.ConsentStatus.REQUIRED:
		form.show(_on_form_dismissed)
	else:
		_after_consent()


func _on_form_failed(err: FormError) -> void:
	last = "consent form failed"
	_report()
	_after_consent()


func _on_form_dismissed(err: FormError) -> void:
	_after_consent()


func _after_consent() -> void:
	if _consent_done:
		return
	_consent_done = true
	MobileAds.initialize()
	_sdk_ready = true
	_watchdog.start()
	_ensure_banner.call_deferred()
	_load_interstitial.call_deferred()


# ---------------------------------------------------------------- banner (top of screen)
func _ensure_banner() -> void:
	if not enabled or not _sdk_ready or _stop_banner:
		return
	if is_instance_valid(_banner) and banner_ok:
		return
	if _banner != null:
		_banner.destroy()
		_banner = null
	banner_ok = false
	_banner = AdView.new(AppConfig.ADMOB_BANNER_ID, AdSize.BANNER, AdPosition.TOP)
	if _banner == null:
		return
	var l := AdListener.new()
	l.on_ad_loaded = _on_banner_loaded
	l.on_ad_failed_to_load = _on_banner_failed
	l.on_ad_impression = func() -> void:
		banner_ok = true
	_banner.ad_listener = l
	_banner.load_ad(AdRequest.new())
	last = "banner: loading"
	_report()


func _on_banner_loaded() -> void:
	banner_ok = true
	_retry_delay = 5.0
	last = "banner: shown"
	_report()
	await get_tree().process_frame
	if _banner == null:
		return
	var px: int = _banner.get_height_in_pixels()
	var win_w: float = float(DisplayServer.window_get_size().x)
	var vis_w: float = get_viewport().get_visible_rect().size.x
	var factor: float = win_w / maxf(vis_w, 1.0)
	if px > 0:
		banner_height_changed.emit(float(px) / maxf(factor, 0.01))


func _on_banner_failed(err: LoadAdError) -> void:
	banner_ok = false
	last = "banner failed: " + (err.message if err else "?")
	_report()
	# exponential back-off (5s .. 60s) instead of a tight retry loop
	_banner_retry.start(_retry_delay)
	_retry_delay = minf(_retry_delay * 2.0, 60.0)


func _on_watchdog() -> void:
	if _sdk_ready and not banner_ok and not _stop_banner and _banner_retry.is_stopped():
		_ensure_banner()


# ---------------------------------------------------------------- interstitial
func _load_interstitial() -> void:
	if not enabled or not _sdk_ready or _inter_loading or _inter != null:
		return
	_inter_loading = true
	var cb := InterstitialAdLoadCallback.new()
	cb.on_ad_failed_to_load = func(err: LoadAdError) -> void:
		_inter_loading = false
		last = "interstitial load failed: " + (err.message if err else "?")
		_report()
	cb.on_ad_loaded = func(ad: InterstitialAd) -> void:
		_inter_loading = false
		_inter = ad
		var fs := FullScreenContentCallback.new()
		fs.on_ad_showed_full_screen_content = func() -> void:
			_inter_shown_flag = true
		fs.on_ad_dismissed_full_screen_content = func() -> void:
			_release_interstitial()
		fs.on_ad_failed_to_show_full_screen_content = func(_e: AdError) -> void:
			_release_interstitial()
		_inter.full_screen_content_callback = fs
		last = "interstitial: ready"
		_report()
	InterstitialAdLoader.new().load(AppConfig.ADMOB_INTERSTITIAL_ID, AdRequest.new(), cb)


func _release_interstitial() -> void:
	if _inter != null:
		_inter.destroy()
		_inter = null
	_load_interstitial.call_deferred()


## Resolves true only if an interstitial was really shown. Waits up to `ms` for it to be ready.
func show_when_ready(ms: int) -> bool:
	if not enabled or not _sdk_ready:
		return false
	if _inter == null:
		_load_interstitial()
	var t0: int = Time.get_ticks_msec()
	while (_inter == null or not _inter.can_show_ad()) and Time.get_ticks_msec() - t0 < ms:
		await get_tree().create_timer(0.25).timeout
	if _inter == null or not _inter.can_show_ad():
		last = "interstitial not ready"
		_report()
		return false
	_inter_shown_flag = false
	_inter.show()
	var t1: int = Time.get_ticks_msec()
	while not _inter_shown_flag and Time.get_ticks_msec() - t1 < 2000:
		await get_tree().create_timer(0.1).timeout
	last = "interstitial: " + ("shown" if _inter_shown_flag else "not shown")
	_report()
	return _inter_shown_flag


func _report() -> void:
	diagnostics_changed.emit("Ads: AdMob (native) · banner=%s · last: %s" % [str(banner_ok), last])


func diagnostics() -> String:
	return "Ads: " + ("AdMob (native) · banner=%s · last: %s" % [str(banner_ok), last] if enabled else last)
