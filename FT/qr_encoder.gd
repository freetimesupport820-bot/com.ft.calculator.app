class_name QREncoder
extends RefCounted
## Pure GDScript QR encoder (byte mode, UTF-8) - port of the behaviour of qrcode-generator 1.4.4
## used by the HTML prototype: qrcode(0, ecc).addData(text) -> smallest version that fits.

const ECC_L := 0
const ECC_M := 1
const ECC_Q := 2
const ECC_H := 3

var version: int = 0
var size: int = 0
var ecc: int = 1
var mask: int = 0
var modules: PackedByteArray  # 1 = dark
var _func: PackedByteArray


static func ecc_from_letter(letter: String) -> int:
	match letter:
		"L": return 0
		"M": return 1
		"Q": return 2
		"H": return 3
	return 1


## Returns a QREncoder on success, or null when the data does not fit (HTML: "Too much data").
static func encode(text: String, ecc_level: int, force_mask: int = -1) -> QREncoder:
	var data: PackedByteArray = text.to_utf8_buffer()
	var ver: int = 1
	var cap_bits: int = 0
	var found: bool = false
	while ver <= 40:
		var cc_bits: int = 8 if ver <= 9 else 16
		cap_bits = QRCommon.get_num_data_codewords(ver, ecc_level) * 8
		var used: int = 4 + cc_bits + data.size() * 8
		if used <= cap_bits and data.size() < (1 << cc_bits):
			found = true
			break
		ver += 1
	if not found:
		return null
	var q := QREncoder.new()
	q.version = ver
	q.ecc = ecc_level
	q.size = ver * 4 + 17
	q._build(data, cap_bits, force_mask)
	return q


func is_dark(r: int, c: int) -> bool:
	return modules[r * size + c] == 1


func _build(data: PackedByteArray, cap_bits: int, force_mask: int = -1) -> void:
	# --- bit stream ---
	var bits: Array = []  # array of 0/1 ints
	_append_bits(bits, 4, 4)  # byte mode
	_append_bits(bits, data.size(), 8 if version <= 9 else 16)
	for b in data:
		_append_bits(bits, b, 8)
	_append_bits(bits, 0, mini(4, cap_bits - bits.size()))
	while bits.size() % 8 != 0:
		bits.append(0)
	var codewords := PackedByteArray()
	for i in range(0, bits.size(), 8):
		var v: int = 0
		for k in range(8):
			v = (v << 1) | bits[i + k]
		codewords.append(v)
	var pad: int = 0xEC
	while codewords.size() < cap_bits / 8:
		codewords.append(pad)
		pad = 0x11 if pad == 0xEC else 0xEC
	var final_cw: PackedByteArray = _add_ecc_and_interleave(codewords)
	# --- matrix ---
	_func = QRCommon.build_function_mask(version)
	modules = PackedByteArray()
	modules.resize(size * size)
	_draw_function_patterns()
	_draw_codewords(final_cw)
	# choose best mask
	var best_mask: int = 0
	var best_pen: int = 1 << 60
	for m in range(8):
		if force_mask >= 0 and m != force_mask:
			continue
		_apply_mask(m)
		_draw_format_bits(m)
		var pen: int = _penalty()
		if pen < best_pen:
			best_pen = pen
			best_mask = m
		_apply_mask(m)  # undo (xor)
	mask = best_mask
	_apply_mask(best_mask)
	_draw_format_bits(best_mask)


static func _append_bits(arr: Array, val: int, count: int) -> void:
	for i in range(count - 1, -1, -1):
		arr.append((val >> i) & 1)


func _rs_generator(degree: int) -> PackedByteArray:
	var result := PackedByteArray()
	result.resize(degree)
	result[degree - 1] = 1
	var root: int = 1
	for i in range(degree):
		for j in range(degree):
			result[j] = QRCommon.gf_mul(result[j], root)
			if j + 1 < degree:
				result[j] ^= result[j + 1]
		root = QRCommon.gf_mul(root, 2)
	return result


func _rs_remainder(data: PackedByteArray, gen: PackedByteArray) -> PackedByteArray:
	var degree: int = gen.size()
	var result := PackedByteArray()
	result.resize(degree)
	for b in data:
		var factor: int = b ^ result[0]
		for j in range(degree - 1):
			result[j] = result[j + 1]
		result[degree - 1] = 0
		for j in range(degree):
			result[j] ^= QRCommon.gf_mul(gen[j], factor)
	return result


func _add_ecc_and_interleave(data: PackedByteArray) -> PackedByteArray:
	var num_blocks: int = QRCommon.NUM_ERROR_CORRECTION_BLOCKS[ecc][version]
	var block_ecc_len: int = QRCommon.ECC_CODEWORDS_PER_BLOCK[ecc][version]
	var raw_cw: int = QRCommon.get_num_raw_data_modules(version) / 8
	var num_short: int = num_blocks - raw_cw % num_blocks
	var short_len: int = raw_cw / num_blocks
	var gen: PackedByteArray = _rs_generator(block_ecc_len)
	var blocks: Array = []
	var k: int = 0
	for i in range(num_blocks):
		var dat_len: int = short_len - block_ecc_len + (0 if i < num_short else 1)
		var dat: PackedByteArray = data.slice(k, k + dat_len)
		k += dat_len
		var ecc_bytes: PackedByteArray = _rs_remainder(dat, gen)
		if i < num_short:
			dat.append(0)  # placeholder so all blocks have equal length
		dat.append_array(ecc_bytes)
		blocks.append(dat)
	var result := PackedByteArray()
	for i in range(blocks[0].size()):
		for j in range(blocks.size()):
			if i != short_len - block_ecc_len or j >= num_short:
				result.append(blocks[j][i])
	return result


func _set_func(r: int, c: int, dark: bool) -> void:
	modules[r * size + c] = 1 if dark else 0


func _draw_function_patterns() -> void:
	for i in range(size):
		_set_func(6, i, i % 2 == 0)
		_set_func(i, 6, i % 2 == 0)
	_draw_finder(3, 3)
	_draw_finder(size - 4, 3)
	_draw_finder(3, size - 4)
	var ap: PackedInt32Array = QRCommon.get_alignment_positions(version)
	var n: int = ap.size()
	for i in range(n):
		for j in range(n):
			if (i == 0 and j == 0) or (i == 0 and j == n - 1) or (i == n - 1 and j == 0):
				continue
			_draw_alignment(ap[j], ap[i])
	_draw_format_bits(0)
	_draw_version()


func _draw_finder(cx: int, cy: int) -> void:
	for dy in range(-4, 5):
		for dx in range(-4, 5):
			var dist: int = maxi(absi(dx), absi(dy))
			var xx: int = cx + dx
			var yy: int = cy + dy
			if xx >= 0 and xx < size and yy >= 0 and yy < size:
				_set_func(yy, xx, dist != 2 and dist != 4)


func _draw_alignment(cx: int, cy: int) -> void:
	for dy in range(-2, 3):
		for dx in range(-2, 3):
			_set_func(cy + dy, cx + dx, maxi(absi(dx), absi(dy)) != 1)


func _draw_format_bits(m: int) -> void:
	var bits: int = QRCommon.format_bits(ecc, m)
	for i in range(6):
		_set_func(i, 8, ((bits >> i) & 1) != 0)
	_set_func(7, 8, ((bits >> 6) & 1) != 0)
	_set_func(8, 8, ((bits >> 7) & 1) != 0)
	_set_func(8, 7, ((bits >> 8) & 1) != 0)
	for i in range(9, 15):
		_set_func(8, 14 - i, ((bits >> i) & 1) != 0)
	for i in range(8):
		_set_func(8, size - 1 - i, ((bits >> i) & 1) != 0)
	for i in range(8, 15):
		_set_func(size - 15 + i, 8, ((bits >> i) & 1) != 0)
	_set_func(size - 8, 8, true)  # dark module


func _draw_version() -> void:
	if version < 7:
		return
	var bits: int = QRCommon.version_bits(version)
	for i in range(18):
		var bit: bool = ((bits >> i) & 1) != 0
		var a: int = size - 11 + i % 3
		var b: int = i / 3
		_set_func(b, a, bit)
		_set_func(a, b, bit)


func _draw_codewords(data: PackedByteArray) -> void:
	var i: int = 0
	var right: int = size - 1
	while right >= 1:
		if right == 6:
			right = 5
		for vert in range(size):
			for j in range(2):
				var x: int = right - j
				var upward: bool = ((right + 1) & 2) == 0
				var y: int = (size - 1 - vert) if upward else vert
				if _func[y * size + x] == 0 and i < data.size() * 8:
					modules[y * size + x] = 1 if ((data[i >> 3] >> (7 - (i & 7))) & 1) != 0 else 0
					i += 1
		right -= 2


func _apply_mask(m: int) -> void:
	for y in range(size):
		for x in range(size):
			if _func[y * size + x] == 0 and QRCommon.mask_bit(m, y, x):
				modules[y * size + x] ^= 1


func _penalty() -> int:
	var result: int = 0
	var n: int = size
	# N1: runs of 5+ same-colour modules in rows and columns; N3: finder-like patterns
	for pass_i in range(2):
		for a in range(n):
			var run_color: int = -1
			var run_len: int = 0
			for b in range(n):
				var v: int = modules[(a * n + b) if pass_i == 0 else (b * n + a)]
				if v == run_color:
					run_len += 1
					if run_len == 5:
						result += 3
					elif run_len > 5:
						result += 1
				else:
					run_color = v
					run_len = 1
			result += _finder_penalty_line(a, pass_i)
	# N2: 2x2 blocks
	for y in range(n - 1):
		for x in range(n - 1):
			var c: int = modules[y * n + x]
			if c == modules[y * n + x + 1] and c == modules[(y + 1) * n + x] and c == modules[(y + 1) * n + x + 1]:
				result += 3
	# N4: dark/light balance
	var dark: int = 0
	for v in modules:
		dark += v
	var total: int = n * n
	var k: int = (absi(dark * 20 - total * 10) + total - 1) / total - 1
	result += maxi(k, 0) * 10
	return result


## N3: patterns 1:1:3:1:1 with 4 light modules on either side, scanned on one row/column.
func _finder_penalty_line(a: int, pass_i: int) -> int:
	var n: int = size
	var pen: int = 0
	var line := PackedByteArray()
	line.resize(n)
	for b in range(n):
		line[b] = modules[(a * n + b) if pass_i == 0 else (b * n + a)]
	# pattern: dark,light,dark,dark,dark,light,dark = 1011101
	for s in range(n - 6):
		if line[s] == 1 and line[s + 1] == 0 and line[s + 2] == 1 and line[s + 3] == 1 and line[s + 4] == 1 and line[s + 5] == 0 and line[s + 6] == 1:
			var left_ok: bool = true
			var right_ok: bool = true
			for t in range(1, 5):
				if s - t >= 0 and line[s - t] == 1:
					left_ok = false
				if s + 6 + t < n and line[s + 6 + t] == 1:
					right_ok = false
			if left_ok or right_ok:
				pen += 40
	return pen
