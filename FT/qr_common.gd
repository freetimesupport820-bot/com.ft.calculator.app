class_name QRCommon
extends RefCounted
## Shared QR Code (ISO/IEC 18004) tables and helpers used by the pure-GDScript
## encoder (qr_encoder.gd) and decoder (qr_decoder.gd). No external plugin needed.

# ECC level index: 0 = L, 1 = M, 2 = Q, 3 = H
const ECC_CODEWORDS_PER_BLOCK: Array = [
	[-1, 7, 10, 15, 20, 26, 18, 20, 24, 30, 18, 20, 24, 26, 30, 22, 24, 28, 30, 28, 28, 28, 28, 30, 30, 26, 28, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30],
	[-1, 10, 16, 26, 18, 24, 16, 18, 22, 22, 26, 30, 22, 22, 24, 24, 28, 28, 26, 26, 26, 26, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28],
	[-1, 13, 22, 18, 26, 18, 24, 18, 22, 20, 24, 28, 26, 24, 20, 30, 24, 28, 28, 26, 30, 28, 30, 30, 30, 30, 28, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30],
	[-1, 17, 28, 22, 16, 22, 28, 26, 26, 24, 28, 24, 28, 22, 24, 24, 30, 28, 28, 26, 28, 30, 24, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30],
]
const NUM_ERROR_CORRECTION_BLOCKS: Array = [
	[-1, 1, 1, 1, 1, 1, 2, 2, 2, 2, 4, 4, 4, 4, 4, 6, 6, 6, 6, 7, 8, 8, 9, 9, 10, 12, 12, 12, 13, 14, 15, 16, 17, 18, 19, 19, 20, 21, 22, 24, 25],
	[-1, 1, 1, 1, 2, 2, 4, 4, 4, 5, 5, 5, 8, 9, 9, 10, 10, 11, 13, 14, 16, 17, 17, 18, 20, 21, 23, 25, 26, 28, 29, 31, 33, 35, 37, 38, 40, 43, 45, 47, 49],
	[-1, 1, 1, 2, 2, 4, 4, 6, 6, 8, 8, 8, 10, 12, 16, 12, 17, 16, 18, 21, 20, 23, 23, 25, 27, 29, 34, 34, 35, 38, 40, 43, 45, 48, 51, 53, 56, 59, 62, 65, 68],
	[-1, 1, 1, 2, 4, 4, 4, 5, 6, 8, 8, 11, 11, 16, 16, 18, 16, 19, 21, 25, 25, 25, 34, 30, 32, 35, 37, 40, 42, 45, 48, 51, 54, 57, 60, 63, 66, 70, 74, 77, 81],
]
## Format-info "ecc bits" for ECC index L,M,Q,H
const ECC_FORMAT_BITS: Array = [1, 0, 3, 2]

static var _exp: PackedByteArray
static var _log: PackedByteArray
static var _ready: bool = false


static func _static_init() -> void:
	_init_gf()


static func _init_gf() -> void:
	if _ready:
		return
	_exp = PackedByteArray()
	_exp.resize(512)
	_log = PackedByteArray()
	_log.resize(256)
	var x: int = 1
	for i in range(255):
		_exp[i] = x
		_log[x] = i
		x <<= 1
		if x & 0x100:
			x ^= 0x11D
	for i in range(255, 512):
		_exp[i] = _exp[i - 255]
	_ready = true


static func gf_mul(a: int, b: int) -> int:
	if a == 0 or b == 0:
		return 0
	return _exp[_log[a] + _log[b]]


static func gf_div(a: int, b: int) -> int:
	if a == 0:
		return 0
	return _exp[(_log[a] + 255 - _log[b]) % 255]


static func gf_exp(i: int) -> int:
	return _exp[i % 255]


static func gf_log(a: int) -> int:
	return _log[a]


static func get_num_raw_data_modules(ver: int) -> int:
	var result: int = (16 * ver + 128) * ver + 64
	if ver >= 2:
		var num_align: int = ver / 7 + 2
		result -= (25 * num_align - 10) * num_align - 55
		if ver >= 7:
			result -= 36
	return result


static func get_num_data_codewords(ver: int, ecc: int) -> int:
	return get_num_raw_data_modules(ver) / 8 - ECC_CODEWORDS_PER_BLOCK[ecc][ver] * NUM_ERROR_CORRECTION_BLOCKS[ecc][ver]


static func get_alignment_positions(ver: int) -> PackedInt32Array:
	var res := PackedInt32Array()
	if ver == 1:
		return res
	var num_align: int = ver / 7 + 2
	var size: int = ver * 4 + 17
	var step: int = 26 if ver == 32 else (ver * 4 + num_align * 2 + 1) / (num_align * 2 - 2) * 2
	var tmp: Array = []
	var pos: int = size - 7
	for i in range(num_align - 1):
		tmp.push_front(pos)
		pos -= step
	res.append(6)
	for p in tmp:
		res.append(p)
	return res


## Returns a size*size PackedByteArray where 1 marks a "function" module
## (finder, separator, timing, alignment, format/version info, dark module).
static func build_function_mask(ver: int) -> PackedByteArray:
	var size: int = ver * 4 + 17
	var m := PackedByteArray()
	m.resize(size * size)
	# timing
	for i in range(size):
		m[6 * size + i] = 1
		m[i * size + 6] = 1
	# finder + separators + format areas
	for r in range(9):
		for c in range(9):
			m[r * size + c] = 1
	for r in range(8):
		for c in range(size - 8, size):
			m[r * size + c] = 1
	for r in range(size - 8, size):
		for c in range(8):
			m[r * size + c] = 1
	# format info strips
	for i in range(8):
		m[8 * size + (size - 1 - i)] = 1
		m[(size - 1 - i) * size + 8] = 1
	# alignment
	var ap: PackedInt32Array = get_alignment_positions(ver)
	var n: int = ap.size()
	for i in range(n):
		for j in range(n):
			if (i == 0 and j == 0) or (i == 0 and j == n - 1) or (i == n - 1 and j == 0):
				continue
			for dr in range(-2, 3):
				for dc in range(-2, 3):
					m[(ap[i] + dr) * size + (ap[j] + dc)] = 1
	# version info
	if ver >= 7:
		for r in range(6):
			for c in range(size - 11, size - 8):
				m[r * size + c] = 1
				m[c * size + r] = 1
	return m


static func mask_bit(mask: int, r: int, c: int) -> bool:
	match mask:
		0: return (r + c) % 2 == 0
		1: return r % 2 == 0
		2: return c % 3 == 0
		3: return (r + c) % 3 == 0
		4: return (r / 2 + c / 3) % 2 == 0
		5: return (r * c) % 2 + (r * c) % 3 == 0
		6: return ((r * c) % 2 + (r * c) % 3) % 2 == 0
		7: return ((r + c) % 2 + (r * c) % 3) % 2 == 0
	return false


## 15-bit format word (with mask 0x5412 applied) for ecc index + mask.
static func format_bits(ecc: int, mask: int) -> int:
	var data: int = (ECC_FORMAT_BITS[ecc] << 3) | mask
	var rem: int = data
	for i in range(10):
		rem = (rem << 1) ^ ((rem >> 9) * 0x537)
	return ((data << 10) | rem) ^ 0x5412


static func version_bits(ver: int) -> int:
	var rem: int = ver
	for i in range(12):
		rem = (rem << 1) ^ ((rem >> 11) * 0x1F25)
	return (ver << 12) | rem


static func popcount(v: int) -> int:
	var n: int = 0
	while v:
		n += v & 1
		v >>= 1
	return n
