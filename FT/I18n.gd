extends Node
## Autoload "I18n": English / Bengali texts, ported 1:1 from the HTML prototype's T object.

signal language_changed

const T: Dictionary = {
	"en": {
		"tag": "Fast · Private · Offline",
		"create": "Create",
		"scan": "Scan",
		"history": "History",
		"about": "About",
		"fg": "QR colour",
		"bg": "Background",
		"size": "Size",
		"ecc": "Error correction",
		"gen": "Generate QR",
		"yours": "Your QR code",
		"save": "Save PNG",
		"share": "Share",
		"startCam": "Start camera",
		"stopCam": "Stop camera",
		"pick": "From gallery",
		"camHint": "Point the camera at a QR code, or pick an image from your gallery.",
		"result": "Scan result",
		"clear": "Clear all",
		"copy": "Copy",
		"open": "Open link",
		"again": "Scan again",
		"empty": "Nothing here yet.",
		"copied": "Copied",
		"edit": "Edit",
		"noTorch": "Flash is not available on this camera",
		"confirmClear": "Delete all history?",
		"confirmSub": "This cannot be undone.",
		"cancel": "Cancel",
		"del": "Delete",
		"saved": "Saved",
		"needText": "Please fill in the required field.",
		"noQR": "No QR code found in this image.",
		"camErr": "Camera unavailable. Use the gallery option instead.",
		"libErr": "QR engine failed to load. Check your connection.",
		"tooLong": "Too much data for a QR code.",
		"lowC": "Low contrast – the QR may not scan.",
		"created": "Created",
		"scanned": "Scanned",
		"cleared": "History cleared",
		"types": {
			"text": "Text",
			"url": "Link",
			"wifi": "Wi‑Fi",
			"tel": "Phone",
			"sms": "SMS",
			"mail": "Email",
		},
		"f": {
			"text": "Text",
			"url": "Website URL",
			"ssid": "Network name (SSID)",
			"pass": "Password",
			"sec": "Security",
			"hid": "Hidden network",
			"tel": "Phone number",
			"msg": "Message",
			"to": "To",
			"sub": "Subject",
			"body": "Body",
		},
	},
	"bn": {
		"tag": "দ্রুত · নিরাপদ · অফলাইন",
		"create": "তৈরি",
		"scan": "স্ক্যান",
		"history": "ইতিহাস",
		"about": "পরিচিতি",
		"fg": "QR এর রঙ",
		"bg": "ব্যাকগ্রাউন্ড",
		"size": "আকার",
		"ecc": "ত্রুটি সংশোধন",
		"gen": "QR তৈরি করুন",
		"yours": "আপনার QR কোড",
		"save": "PNG সেভ",
		"share": "শেয়ার",
		"startCam": "ক্যামেরা চালু",
		"stopCam": "ক্যামেরা বন্ধ",
		"pick": "গ্যালারি থেকে",
		"camHint": "QR কোডের দিকে ক্যামেরা ধরুন, অথবা গ্যালারি থেকে ছবি বাছুন।",
		"result": "স্ক্যানের ফলাফল",
		"clear": "সব মুছুন",
		"copy": "কপি",
		"open": "লিংক খুলুন",
		"again": "আবার স্ক্যান",
		"empty": "এখানে এখনো কিছু নেই।",
		"copied": "কপি হয়েছে",
		"edit": "সম্পাদনা",
		"noTorch": "এই ক্যামেরায় ফ্ল্যাশ নেই",
		"confirmClear": "সব ইতিহাস মুছে ফেলবেন?",
		"confirmSub": "এটি আর ফেরানো যাবে না।",
		"cancel": "বাতিল",
		"del": "মুছুন",
		"saved": "সেভ হয়েছে",
		"needText": "অনুগ্রহ করে প্রয়োজনীয় ঘরটি পূরণ করুন।",
		"noQR": "এই ছবিতে কোনো QR কোড পাওয়া যায়নি।",
		"camErr": "ক্যামেরা পাওয়া যাচ্ছে না। গ্যালারি ব্যবহার করুন।",
		"libErr": "QR ইঞ্জিন লোড হয়নি। ইন্টারনেট দেখুন।",
		"tooLong": "QR কোডের জন্য ডেটা অনেক বেশি।",
		"lowC": "কনট্রাস্ট কম – QR স্ক্যান নাও হতে পারে।",
		"created": "তৈরি",
		"scanned": "স্ক্যান",
		"cleared": "ইতিহাস মোছা হয়েছে",
		"types": {
			"text": "টেক্সট",
			"url": "লিংক",
			"wifi": "ওয়াই-ফাই",
			"tel": "ফোন",
			"sms": "এসএমএস",
			"mail": "ইমেইল",
		},
		"f": {
			"text": "টেক্সট",
			"url": "ওয়েবসাইট URL",
			"ssid": "নেটওয়ার্কের নাম (SSID)",
			"pass": "পাসওয়ার্ড",
			"sec": "সিকিউরিটি",
			"hid": "লুকানো নেটওয়ার্ক",
			"tel": "ফোন নম্বর",
			"msg": "বার্তা",
			"to": "প্রাপক",
			"sub": "বিষয়",
			"body": "বিস্তারিত",
		},
	},
}

var lang: String = "en"


func _ready() -> void:
	lang = String(GameState.get_value("ft_lang", "en"))
	if not T.has(lang):
		lang = "en"


func set_lang(l: String) -> void:
	lang = l
	GameState.set_value("ft_lang", l)
	language_changed.emit()


func toggle() -> void:
	set_lang("bn" if lang == "en" else "en")


func t(key: String) -> String:
	var d: Dictionary = T[lang]
	if d.has(key):
		return String(d[key])
	return String(T["en"].get(key, key))


func type_name(k: String) -> String:
	return String(T[lang]["types"][k])


func field(k: String) -> String:
	return String(T[lang]["f"][k])
