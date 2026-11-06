class_name QRDecoder
extends RefCounted
## Pure GDScript QR decoder (replaces jsQR / BarcodeDetector of the HTML prototype).
## Input: 8-bit grayscale pixels. Output: decoded text or "" when no QR code was found.
## Pipeline: adaptive binarise -> finder patterns -> alignment pattern -> perspective sampling
## -> format info (BCH) -> de-mask -> de-interleave -> Reed-Solomon -> segment parsing.

const ALNUM := "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ $%*+-./:"


## Main entry point. `try_invert` also tries light-on-dark codes (HTML: "attemptBoth").
static func decode(gray: PackedByteArray, w: int, h: int, try_invert: bool = false, deep: bool = false) -> String:
	if w < 21 or h < 21 or gray.size() < w * h:
		return ""
	var bin: PackedByteArray = _binarize(gray, w, h, false)
	var res: String = _decode_bin(bin, w, h)
	if res != "":
		return res
	if try_invert:
		var inv := PackedByteArray()
		inv.resize(w * h)
		for i in range(w * h):
			inv[i] = 1 - bin[i]
		res = _decode_bin(inv, w, h)
	if res == "" and deep:
		# noisy / blurred photos: smooth once (and once more, stronger) and retry
		for k in [2, 3]:
			var img: Image = Image.create_from_data(w, h, false, Image.FORMAT_L8, gray)
			img.resize(maxi(8, w / k), maxi(8, h / k), Image.INTERPOLATE_TRILINEAR)
			img.resize(w, h, Image.INTERPOLATE_BILINEAR)
			var sm: PackedByteArray = img.get_data()
			var b2: PackedByteArray = _binarize(sm, w, h, false)
			res = _decode_bin(b2, w, h)
			if res == "" and try_invert:
				for i in range(w * h):
					b2[i] = 1 - b2[i]
				res = _decode_bin(b2, w, h)
			if res != "":
				break
	return res


# ------------------------------------------------------------------ binarisation
static func _binarize(gray: PackedByteArray, w: int, h: int, _inv: bool) -> PackedByteArray:
	var img: Image = Image.create_from_data(w, h, false, Image.FORMAT_L8, gray)
	var f: int = maxi(16, mini(w, h) / 10)
	var small: Image = img.duplicate()
	small.resize(maxi(2, w / f), maxi(2, h / f), Image.INTERPOLATE_TRILINEAR)
	small.resize(w, h, Image.INTERPOLATE_BILINEAR)
	var mean: PackedByteArray = small.get_data()
	# global percentiles (sampled) -> "certainly dark" level, so big black areas are not lost
	var hist := PackedInt32Array()
	hist.resize(256)
	var n: int = 0
	var i: int = 0
	var total_px: int = w * h
	while i < total_px:
		hist[gray[i]] += 1
		n += 1
		i += 5
	var acc: int = 0
	var lo: int = 0
	var hi: int = 255
	var got_lo: bool = false
	for v in range(256):
		acc += hist[v]
		if not got_lo and acc * 100 >= n * 2:
			lo = v
			got_lo = true
		if acc * 100 >= n * 98:
			hi = v
			break
	var dark_thr: int = lo + int((hi - lo) * 0.3)
	var bin := PackedByteArray()
	bin.resize(total_px)
	for k in range(total_px):
		var g: int = gray[k]
		bin[k] = 1 if (g < int(mean[k]) - 7 or (g < dark_thr and hi - lo > 40)) else 0
	return bin


# ------------------------------------------------------------------ finder patterns
static func _decode_bin(bin: PackedByteArray, w: int, h: int) -> String:
	var cands: Array = _find_finders(bin, w, h)
	if cands.size() < 3:
		return ""
	var triples: Array = _select_triples(cands)
	var tries: int = 0
	for t in triples:
		var r: String = _decode_triple(bin, w, h, t)
		if r != "":
			return r
		tries += 1
		if tries >= 4:
			break
	return ""


static func _ratio_ok(c: PackedInt32Array) -> bool:
	var total: int = 0
	for i in range(5):
		if c[i] == 0:
			return false
		total += c[i]
	if total < 7:
		return false
	var m: float = total / 7.0
	var v: float = m / 2.0
	return absf(m - c[0]) < v and absf(m - c[1]) < v and absf(3.0 * m - c[2]) < 3.0 * v and absf(m - c[3]) < v and absf(m - c[4]) < v


## Cross-check along axis (dx,dy) through (x,y). Returns centre coordinate along the axis or -1.0.
static func _cross_check(bin: PackedByteArray, w: int, h: int, x: int, y: int, dx: int, dy: int, max_count: int, orig_total: int) -> float:
	var c := PackedInt32Array([0, 0, 0, 0, 0])
	var px: int = x
	var py: int = y
	while px >= 0 and py >= 0 and px < w and py < h and bin[py * w + px] == 1:
		c[2] += 1
		px -= dx
		py -= dy
	if px < 0 or py < 0 or px >= w or py >= h:
		return -1.0
	while px >= 0 and py >= 0 and px < w and py < h and bin[py * w + px] == 0 and c[1] <= max_count:
		c[1] += 1
		px -= dx
		py -= dy
	if px < 0 or py < 0 or px >= w or py >= h or c[1] > max_count:
		return -1.0
	while px >= 0 and py >= 0 and px < w and py < h and bin[py * w + px] == 1 and c[0] <= max_count:
		c[0] += 1
		px -= dx
		py -= dy
	if c[0] > max_count:
		return -1.0
	px = x + dx
	py = y + dy
	while px < w and py < h and bin[py * w + px] == 1:
		c[2] += 1
		px += dx
		py += dy
	if px >= w or py >= h:
		return -1.0
	while px < w and py < h and bin[py * w + px] == 0 and c[3] < max_count:
		c[3] += 1
		px += dx
		py += dy
	if px >= w or py >= h or c[3] >= max_count:
		return -1.0
	while px < w and py < h and bin[py * w + px] == 1 and c[4] < max_count:
		c[4] += 1
		px += dx
		py += dy
	if c[4] >= max_count:
		return -1.0
	var total: int = c[0] + c[1] + c[2] + c[3] + c[4]
	if 5 * absi(total - orig_total) >= 2 * orig_total:
		return -1.0
	if not _ratio_ok(c):
		return -1.0
	var end: int = (py if dy != 0 else px)
	return float(end - c[4] - c[3]) - c[2] / 2.0


static func _find_finders(bin: PackedByteArray, w: int, h: int) -> Array:
	var found: Array = []  # each: [cx, cy, module, count]
	var step: int = 1 if h < 300 else 2
	var counts := PackedInt32Array([0, 0, 0, 0, 0])
	var y: int = 0
	while y < h:
		counts[0] = 0
		counts[1] = 0
		counts[2] = 0
		counts[3] = 0
		counts[4] = 0
		var cs: int = 0
		var base: int = y * w
		for x in range(w):
			var px: int = bin[base + x]
			if px == 1:
				if (cs & 1) == 1:
					cs += 1
				counts[cs] += 1
			else:
				if (cs & 1) == 0:
					if cs == 4:
						if _ratio_ok(counts):
							_handle_candidate(bin, w, h, counts, x, y, found)
						counts[0] = counts[2]
						counts[1] = counts[3]
						counts[2] = counts[4]
						counts[3] = 1
						counts[4] = 0
						cs = 3
					else:
						cs += 1
						counts[cs] += 1
				else:
					counts[cs] += 1
		if cs == 4 and _ratio_ok(counts):
			_handle_candidate(bin, w, h, counts, w, y, found)
		y += step
	return found


static func _handle_candidate(bin: PackedByteArray, w: int, h: int, counts: PackedInt32Array, end_x: int, y: int, found: Array) -> void:
	var total: int = counts[0] + counts[1] + counts[2] + counts[3] + counts[4]
	var cx: float = float(end_x - counts[4] - counts[3]) - counts[2] / 2.0
	var icx: int = int(cx)
	if icx < 0 or icx >= w:
		return
	var cy: float = _cross_check(bin, w, h, icx, y, 0, 1, counts[2] * 2, total)
	if cy < 0.0:
		return
	var icy: int = int(cy)
	if icy < 0 or icy >= h:
		return
	var cx2: float = _cross_check(bin, w, h, icx, icy, 1, 0, counts[2] * 2, total)
	if cx2 < 0.0:
		return
	var module: float = total / 7.0
	for f in found:
		if absf(f[0] - cx2) <= module and absf(f[1] - cy) <= module and absf(f[2] - module) <= module:
			var n: int = f[3]
			f[0] = (f[0] * n + cx2) / (n + 1)
			f[1] = (f[1] * n + cy) / (n + 1)
			f[2] = (f[2] * n + module) / (n + 1)
			f[3] = n + 1
			return
	found.append([cx2, cy, module, 1])


static func _select_triples(cands: Array) -> Array:
	var good: Array = []
	for c in cands:
		if c[3] >= 2:
			good.append(c)
	if good.size() < 3:
		good = cands.duplicate()
	good.sort_custom(func(a, b): return a[3] > b[3])
	if good.size() > 9:
		good = good.slice(0, 9)
	var out: Array = []
	var n: int = good.size()
	for i in range(n):
		for j in range(i + 1, n):
			for k in range(j + 1, n):
				var tri: Array = _score_triple(good[i], good[j], good[k])
				if tri.size() > 0:
					out.append(tri)
	out.sort_custom(func(a, b): return a[0] < b[0])
	var res: Array = []
	for o in out:
		res.append(o[1])
	return res


## Returns [score, [TL, TR, BL]] or [] when the three points do not form a plausible QR corner.
static func _score_triple(a: Array, b: Array, c: Array) -> Array:
	var ms: Array = [a[2], b[2], c[2]]
	var mn: float = minf(ms[0], minf(ms[1], ms[2]))
	var mx: float = maxf(ms[0], maxf(ms[1], ms[2]))
	if mx > mn * 1.7:
		return []
	var dab: float = Vector2(a[0] - b[0], a[1] - b[1]).length_squared()
	var dac: float = Vector2(a[0] - c[0], a[1] - c[1]).length_squared()
	var dbc: float = Vector2(b[0] - c[0], b[1] - c[1]).length_squared()
	var tl: Array
	var p1: Array
	var p2: Array
	var d_hyp: float
	var d1: float
	var d2: float
	if dbc >= dab and dbc >= dac:
		tl = a
		p1 = b
		p2 = c
		d_hyp = dbc
		d1 = dab
		d2 = dac
	elif dac >= dab and dac >= dbc:
		tl = b
		p1 = a
		p2 = c
		d_hyp = dac
		d1 = dab
		d2 = dbc
	else:
		tl = c
		p1 = a
		p2 = b
		d_hyp = dab
		d1 = dac
		d2 = dbc
	var l1: float = sqrt(d1)
	var l2: float = sqrt(d2)
	if l1 < 1.0 or l2 < 1.0:
		return []
	var cosang: float = absf((d1 + d2 - d_hyp) / (2.0 * l1 * l2))
	var ratio: float = absf(l1 - l2) / maxf(l1, l2)
	if cosang > 0.35 or ratio > 0.4:
		return []
	var module: float = (a[2] + b[2] + c[2]) / 3.0
	if (l1 + l2) / 2.0 / module < 9.0:
		return []
	var cross: float = (p1[0] - tl[0]) * (p2[1] - tl[1]) - (p1[1] - tl[1]) * (p2[0] - tl[0])
	var tr: Array = p1
	var bl: Array = p2
	if cross < 0.0:
		tr = p2
		bl = p1
	var score: float = cosang + ratio + (mx - mn) / mx
	return [score, [tl, tr, bl, module]]


# ------------------------------------------------------------------ geometry
static func _decode_triple(bin: PackedByteArray, w: int, h: int, t: Array) -> String:
	var tl: Array = t[0]
	var tr: Array = t[1]
	var bl: Array = t[2]
	var m: float = t[3]
	var d_tr: float = Vector2(tr[0] - tl[0], tr[1] - tl[1]).length()
	var d_bl: float = Vector2(bl[0] - tl[0], bl[1] - tl[1]).length()
	var dim0: int = int(round((d_tr + d_bl) / 2.0 / m)) + 7
	var dim: int = dim0
	match dim & 3:
		0: dim += 1
		2: dim -= 1
		3: dim += 2
	var order: Array = [dim, dim + 4, dim - 4]
	for d in order:
		if d < 21 or d > 177:
			continue
		var r: String = _try_dimension(bin, w, h, tl, tr, bl, m, d)
		if r != "":
			return r
	return ""


static func _try_dimension(bin: PackedByteArray, w: int, h: int, tl: Array, tr: Array, bl: Array, m: float, dim: int) -> String:
	var ver: int = (dim - 17) / 4
	var ux: float = (tr[0] - tl[0]) / (dim - 7.0)
	var uy: float = (tr[1] - tl[1]) / (dim - 7.0)
	var vx: float = (bl[0] - tl[0]) / (dim - 7.0)
	var vy: float = (bl[1] - tl[1]) / (dim - 7.0)
	var br_x: float = tr[0] + bl[0] - tl[0]
	var br_y: float = tr[1] + bl[1] - tl[1]
	var src: Array = [Vector2(3.5, 3.5), Vector2(dim - 3.5, 3.5), Vector2(3.5, dim - 3.5), Vector2(dim - 3.5, dim - 3.5)]
	var dst: Array = [Vector2(tl[0], tl[1]), Vector2(tr[0], tr[1]), Vector2(bl[0], bl[1]), Vector2(br_x, br_y)]
	var module_px: float = (Vector2(ux, uy).length() + Vector2(vx, vy).length()) / 2.0
	if ver >= 2:
		var u: float = (dim - 10.0)
		var est := Vector2(tl[0] + ux * u + vx * u, tl[1] + uy * u + vy * u)
		var al: Vector2 = _find_alignment(bin, w, h, est, module_px)
		if al.x >= 0.0:
			src[3] = Vector2(dim - 6.5, dim - 6.5)
			dst[3] = al
	var hm: Array = _homography(src, dst)
	if hm.is_empty():
		return ""
	var matrix: PackedByteArray = _sample(bin, w, h, hm, dim)
	if matrix.is_empty():
		return ""
	var r: String = _decode_matrix(matrix, dim)
	if r != "":
		return r
	# retry with the parallelogram estimate for the 4th corner
	if ver >= 2 and src[3].x != dim - 3.5:
		src[3] = Vector2(dim - 3.5, dim - 3.5)
		dst[3] = Vector2(br_x, br_y)
		hm = _homography(src, dst)
		if not hm.is_empty():
			matrix = _sample(bin, w, h, hm, dim)
			if not matrix.is_empty():
				return _decode_matrix(matrix, dim)
	return ""


static func _find_alignment(bin: PackedByteArray, w: int, h: int, est: Vector2, module_px: float) -> Vector2:
	var best := Vector2(-1.0, -1.0)
	var best_d: float = 1e18
	for allow in [4.0, 8.0]:
		var r: int = int(ceil(allow * module_px))
		var x0: int = maxi(0, int(est.x) - r)
		var x1: int = mini(w - 1, int(est.x) + r)
		var y0: int = maxi(0, int(est.y) - r)
		var y1: int = mini(h - 1, int(est.y) + r)
		var counts := PackedInt32Array([0, 0, 0, 0, 0])
		for y in range(y0, y1 + 1):
			counts[0] = 0
			counts[1] = 0
			counts[2] = 0
			counts[3] = 0
			counts[4] = 0
			var cs: int = 0
			for x in range(x0, x1 + 2):
				var px: int = 0
				if x <= x1:
					px = bin[y * w + x]
				if px == 1:
					if (cs & 1) == 1:
						cs += 1
					counts[cs] += 1
				else:
					if (cs & 1) == 0:
						if cs == 4:
							if _align_ratio_ok(counts, module_px):
								var cx: float = float(x - counts[4] - counts[3]) - counts[2] / 2.0
								var total: int = counts[0] + counts[1] + counts[2] + counts[3] + counts[4]
								var cy: float = _cross_check_align(bin, w, h, int(cx), y, total)
								if cy >= 0.0:
									var d: float = Vector2(cx - est.x, cy - est.y).length()
									if d < best_d:
										best_d = d
										best = Vector2(cx, cy)
							counts[0] = counts[2]
							counts[1] = counts[3]
							counts[2] = counts[4]
							counts[3] = 1
							counts[4] = 0
							cs = 3
						else:
							cs += 1
							counts[cs] += 1
					else:
						counts[cs] += 1
		if best.x >= 0.0:
			return best
	return best


static func _align_ratio_ok(c: PackedInt32Array, module_px: float) -> bool:
	var v: float = module_px * 0.8
	for i in range(5):
		if c[i] == 0 or absf(c[i] - module_px) > v:
			return false
	return true


static func _cross_check_align(bin: PackedByteArray, w: int, h: int, x: int, y: int, orig_total: int) -> float:
	var c := PackedInt32Array([0, 0, 0, 0, 0])
	var py: int = y
	if x < 0 or x >= w:
		return -1.0
	while py >= 0 and bin[py * w + x] == 1:
		c[2] += 1
		py -= 1
	if py < 0:
		return -1.0
	while py >= 0 and bin[py * w + x] == 0 and c[1] <= orig_total:
		c[1] += 1
		py -= 1
	if py < 0:
		return -1.0
	while py >= 0 and bin[py * w + x] == 1 and c[0] <= orig_total:
		c[0] += 1
		py -= 1
	py = y + 1
	while py < h and bin[py * w + x] == 1:
		c[2] += 1
		py += 1
	if py >= h:
		return -1.0
	while py < h and bin[py * w + x] == 0 and c[3] <= orig_total:
		c[3] += 1
		py += 1
	if py >= h:
		return -1.0
	while py < h and bin[py * w + x] == 1 and c[4] <= orig_total:
		c[4] += 1
		py += 1
	var total: int = c[0] + c[1] + c[2] + c[3] + c[4]
	if 5 * absi(total - orig_total) >= 2 * orig_total:
		return -1.0
	for i in range(5):
		if c[i] == 0:
			return -1.0
	return float(py - c[4] - c[3]) - c[2] / 2.0


## 3x3 projective matrix mapping src[i] -> dst[i] (4 correspondences), row-major [a..i]. Empty when degenerate.
static func _homography(src: Array, dst: Array) -> Array:
	var a: Array = []
	for i in range(8):
		a.append([0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0])
	for i in range(4):
		var x: float = src[i].x
		var y: float = src[i].y
		var u: float = dst[i].x
		var v: float = dst[i].y
		a[i * 2] = [x, y, 1.0, 0.0, 0.0, 0.0, -u * x, -u * y, u]
		a[i * 2 + 1] = [0.0, 0.0, 0.0, x, y, 1.0, -v * x, -v * y, v]
	for col in range(8):
		var piv: int = col
		for r in range(col + 1, 8):
			if absf(a[r][col]) > absf(a[piv][col]):
				piv = r
		if absf(a[piv][col]) < 1e-12:
			return []
		var tmp: Array = a[col]
		a[col] = a[piv]
		a[piv] = tmp
		var pv: float = a[col][col]
		for k in range(col, 9):
			a[col][k] /= pv
		for r in range(8):
			if r != col:
				var f: float = a[r][col]
				if f != 0.0:
					for k in range(col, 9):
						a[r][k] -= f * a[col][k]
	var out: Array = []
	for i in range(8):
		out.append(a[i][8])
	out.append(1.0)
	return out


static func _sample(bin: PackedByteArray, w: int, h: int, hm: Array, dim: int) -> PackedByteArray:
	var m := PackedByteArray()
	m.resize(dim * dim)
	var offs: Array = [Vector2(0.5, 0.5), Vector2(0.28, 0.5), Vector2(0.72, 0.5), Vector2(0.5, 0.28), Vector2(0.5, 0.72)]
	for r in range(dim):
		for c in range(dim):
			var votes: int = 0
			for o in offs:
				var mx: float = c + o.x
				var my: float = r + o.y
				var den: float = hm[6] * mx + hm[7] * my + hm[8]
				if absf(den) < 1e-9:
					return PackedByteArray()
				var px: int = int((hm[0] * mx + hm[1] * my + hm[2]) / den)
				var py: int = int((hm[3] * mx + hm[4] * my + hm[5]) / den)
				if px < 0 or py < 0 or px >= w or py >= h:
					return PackedByteArray()
				votes += bin[py * w + px]
			m[r * dim + c] = 1 if votes >= 3 else 0
	return m


# ------------------------------------------------------------------ matrix -> text
static func _read_format(m: PackedByteArray, dim: int) -> Array:
	var f1: int = 0
	for i in range(6):
		f1 |= m[i * dim + 8] << i
	f1 |= m[7 * dim + 8] << 6
	f1 |= m[8 * dim + 8] << 7
	f1 |= m[8 * dim + 7] << 8
	for i in range(9, 15):
		f1 |= m[8 * dim + (14 - i)] << i
	var f2: int = 0
	for i in range(8):
		f2 |= m[8 * dim + (dim - 1 - i)] << i
	for i in range(8, 15):
		f2 |= m[(dim - 15 + i) * dim + 8] << i
	var best_d: int = 99
	var best_ecc: int = 0
	var best_mask: int = 0
	for e in range(4):
		for k in range(8):
			var code: int = QRCommon.format_bits(e, k)
			var d: int = mini(QRCommon.popcount(code ^ f1), QRCommon.popcount(code ^ f2))
			if d < best_d:
				best_d = d
				best_ecc = e
				best_mask = k
	if best_d > 3:
		return []
	return [best_ecc, best_mask]


static func _decode_matrix(m: PackedByteArray, dim: int) -> String:
	var fmt: Array = _read_format(m, dim)
	if fmt.is_empty():
		return ""
	var ecc: int = fmt[0]
	var mask: int = fmt[1]
	var ver: int = (dim - 17) / 4
	var fn: PackedByteArray = QRCommon.build_function_mask(ver)
	# read codewords in zigzag order
	var raw_cw: int = QRCommon.get_num_raw_data_modules(ver) / 8
	var cws := PackedByteArray()
	cws.resize(raw_cw)
	var bit_i: int = 0
	var right: int = dim - 1
	while right >= 1:
		if right == 6:
			right = 5
		for vert in range(dim):
			for j in range(2):
				var x: int = right - j
				var upward: bool = ((right + 1) & 2) == 0
				var y: int = (dim - 1 - vert) if upward else vert
				if fn[y * dim + x] == 0 and bit_i < raw_cw * 8:
					var bit: int = m[y * dim + x]
					if QRCommon.mask_bit(mask, y, x):
						bit ^= 1
					if bit:
						cws[bit_i >> 3] |= 1 << (7 - (bit_i & 7))
					bit_i += 1
		right -= 2
	# de-interleave
	var num_blocks: int = QRCommon.NUM_ERROR_CORRECTION_BLOCKS[ecc][ver]
	var ecc_len: int = QRCommon.ECC_CODEWORDS_PER_BLOCK[ecc][ver]
	var num_short: int = num_blocks - raw_cw % num_blocks
	var short_len: int = raw_cw / num_blocks
	var blocks: Array = []
	var dlens: Array = []
	for i in range(num_blocks):
		var dl: int = short_len - ecc_len + (0 if i < num_short else 1)
		dlens.append(dl)
		var b := PackedByteArray()
		b.resize(dl + ecc_len)
		blocks.append(b)
	var pos: int = 0
	var max_dl: int = short_len - ecc_len + 1
	for i in range(max_dl):
		for j in range(num_blocks):
			if i < dlens[j]:
				blocks[j][i] = cws[pos]
				pos += 1
	for i in range(ecc_len):
		for j in range(num_blocks):
			blocks[j][dlens[j] + i] = cws[pos]
			pos += 1
	var data := PackedByteArray()
	for j in range(num_blocks):
		var blk: PackedByteArray = blocks[j]
		if not _rs_correct(blk, ecc_len):
			return ""
		data.append_array(blk.slice(0, dlens[j]))
	return _parse_segments(data, ver)


static func _rs_syndromes(cw: PackedByteArray, nsym: int) -> PackedInt32Array:
	var s := PackedInt32Array()
	s.resize(nsym)
	for i in range(nsym):
		var a: int = QRCommon.gf_exp(i)
		var y: int = 0
		for c in cw:
			y = QRCommon.gf_mul(y, a) ^ c
		s[i] = y
	return s


static func _rs_correct(cw: PackedByteArray, nsym: int) -> bool:
	var synd: PackedInt32Array = _rs_syndromes(cw, nsym)
	var any: bool = false
	for v in synd:
		if v != 0:
			any = true
			break
	if not any:
		return true
	# Berlekamp-Massey (ascending coefficients)
	var C: Array = [1]
	var B: Array = [1]
	var L: int = 0
	var mm: int = 1
	var b: int = 1
	for n in range(nsym):
		var d: int = synd[n]
		for i in range(1, L + 1):
			if i < C.size():
				d ^= QRCommon.gf_mul(C[i], synd[n - i])
		if d == 0:
			mm += 1
		else:
			var coef: int = QRCommon.gf_div(d, b)
			if 2 * L <= n:
				var T: Array = C.duplicate()
				while C.size() < B.size() + mm:
					C.append(0)
				for i in range(B.size()):
					C[i + mm] ^= QRCommon.gf_mul(coef, B[i])
				L = n + 1 - L
				B = T
				b = d
				mm = 1
			else:
				while C.size() < B.size() + mm:
					C.append(0)
				for i in range(B.size()):
					C[i + mm] ^= QRCommon.gf_mul(coef, B[i])
				mm += 1
	if L * 2 > nsym:
		return false
	var n_len: int = cw.size()
	# Chien search: error at power p (index n-1-p) when Lambda(alpha^-p) == 0
	var err_pows: Array = []
	for p in range(n_len):
		var x_inv: int = QRCommon.gf_exp((255 - (p % 255)) % 255)
		var val: int = 0
		var xp: int = 1
		for i in range(C.size()):
			val ^= QRCommon.gf_mul(C[i], xp)
			xp = QRCommon.gf_mul(xp, x_inv)
		if val == 0:
			err_pows.append(p)
	if err_pows.size() != L:
		return false
	# Omega = S(x) * Lambda(x) mod x^nsym
	var omega: Array = []
	for i in range(nsym):
		var acc: int = 0
		for j in range(mini(i, C.size() - 1) + 1):
			acc ^= QRCommon.gf_mul(C[j], synd[i - j])
		omega.append(acc)
	for p in err_pows:
		var xk: int = QRCommon.gf_exp(p)
		var xk_inv: int = QRCommon.gf_exp((255 - (p % 255)) % 255)
		var num: int = 0
		var pw: int = 1
		for i in range(omega.size()):
			num ^= QRCommon.gf_mul(omega[i], pw)
			pw = QRCommon.gf_mul(pw, xk_inv)
		var den: int = 0
		pw = 1  # xk_inv^(k-1) for odd k, starting k=1
		for k in range(1, C.size(), 2):
			den ^= QRCommon.gf_mul(C[k], pw)
			pw = QRCommon.gf_mul(pw, QRCommon.gf_mul(xk_inv, xk_inv))
		if den == 0:
			return false
		var mag: int = QRCommon.gf_mul(xk, QRCommon.gf_div(num, den))
		cw[n_len - 1 - p] ^= mag
	var chk: PackedInt32Array = _rs_syndromes(cw, nsym)
	for v in chk:
		if v != 0:
			return false
	return true


static func _parse_segments(data: PackedByteArray, ver: int) -> String:
	var total_bits: int = data.size() * 8
	var pos: int = 0
	var out := PackedByteArray()
	var eci: int = -1
	var cc_num: int = 10 if ver <= 9 else (12 if ver <= 26 else 14)
	var cc_alnum: int = 9 if ver <= 9 else (11 if ver <= 26 else 13)
	var cc_byte: int = 8 if ver <= 9 else 16
	while pos + 4 <= total_bits:
		var mode: int = _bits(data, pos, 4)
		pos += 4
		if mode == 0:
			break
		match mode:
			1:
				if pos + cc_num > total_bits:
					return ""
				var n: int = _bits(data, pos, cc_num)
				pos += cc_num
				while n >= 3:
					if pos + 10 > total_bits:
						return ""
					var v: int = _bits(data, pos, 10)
					pos += 10
					if v >= 1000:
						return ""
					out.append_array(("%03d" % v).to_ascii_buffer())
					n -= 3
				if n == 2:
					if pos + 7 > total_bits:
						return ""
					var v2: int = _bits(data, pos, 7)
					pos += 7
					out.append_array(("%02d" % v2).to_ascii_buffer())
				elif n == 1:
					if pos + 4 > total_bits:
						return ""
					var v1: int = _bits(data, pos, 4)
					pos += 4
					out.append_array(("%d" % v1).to_ascii_buffer())
			2:
				if pos + cc_alnum > total_bits:
					return ""
				var n2: int = _bits(data, pos, cc_alnum)
				pos += cc_alnum
				var s := ""
				while n2 >= 2:
					if pos + 11 > total_bits:
						return ""
					var v: int = _bits(data, pos, 11)
					pos += 11
					if v >= 45 * 45:
						return ""
					s += ALNUM[v / 45] + ALNUM[v % 45]
					n2 -= 2
				if n2 == 1:
					if pos + 6 > total_bits:
						return ""
					var v3: int = _bits(data, pos, 6)
					pos += 6
					if v3 >= 45:
						return ""
					s += ALNUM[v3]
				out.append_array(s.to_ascii_buffer())
			4:
				if pos + cc_byte > total_bits:
					return ""
				var n3: int = _bits(data, pos, cc_byte)
				pos += cc_byte
				if pos + n3 * 8 > total_bits:
					return ""
				for i in range(n3):
					out.append(_bits(data, pos, 8))
					pos += 8
			7:
				if pos + 8 > total_bits:
					return ""
				var first: int = _bits(data, pos, 8)
				if (first & 0x80) == 0:
					eci = first
					pos += 8
				elif (first & 0xC0) == 0x80:
					if pos + 16 > total_bits:
						return ""
					eci = _bits(data, pos, 16) & 0x3FFF
					pos += 16
				else:
					if pos + 24 > total_bits:
						return ""
					eci = _bits(data, pos, 24) & 0x1FFFFF
					pos += 24
			3:
				pos += 16
			5:
				pass
			9:
				pos += 8
			_:
				return ""  # kanji / unknown mode is not supported
	if out.is_empty():
		return ""
	if eci == 3:
		return _latin1(out)
	var txt: String = out.get_string_from_utf8()
	if txt.to_utf8_buffer() == out:
		return txt
	return _latin1(out)


static func _latin1(b: PackedByteArray) -> String:
	var s := ""
	for v in b:
		s += char(v)
	return s


static func _bits(data: PackedByteArray, pos: int, n: int) -> int:
	var v: int = 0
	for i in range(n):
		var p: int = pos + i
		v = (v << 1) | ((data[p >> 3] >> (7 - (p & 7))) & 1)
	return v
