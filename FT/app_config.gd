class_name AppConfig
extends RefCounted
## Central build-time constants. CI (build.yml) may overwrite the AdMob IDs from GitHub Secrets.

const APP_NAME := "F T - CREATE QR & SCANNING"
const PACKAGE_NAME := "com.ft.create.qr.and.scanning.app"
const VERSION_NAME := "1.0.0"
const DEVELOPER := "MD SHAHIN ALOM RASEL"
const COUNTRY := "BANGLADESH"
const ORGANIZATION := "FREE TIME"
const CONTACT_EMAIL := "free.time.support.820@email.com"

# SECURITY_MODE = TEST -> checks disabled (test APK runs anywhere). PLAY_STORE -> enabled.
const SECURITY_MODE := "TEST"
const SECURITY_CHECKS_ENABLED := false

# Google AdMob. Defaults are Google's official TEST ids (safe for development).
const ADMOB_BANNER_ID := "ca-app-pub-3940256099942544/6300978111"
const ADMOB_INTERSTITIAL_ID := "ca-app-pub-3940256099942544/1033173712"

# Camera preview calibration (device-dependent; see build-summary.txt)
const CAMERA_ROTATION_OFFSET_DEG := 0
const CAMERA_MIRROR_FRONT := false

const HISTORY_MAX := 60
