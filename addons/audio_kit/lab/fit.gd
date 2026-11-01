# SPDX-License-Identifier: Apache-2.0
@tool
## Minimisers for fitting a patch to a recording (AKSampleMatch), after
## scipy's: Nelder-Mead and Powell (Brent line searches). `f` takes a
## PackedFloat64Array and returns a float; both return {x, fun, evals}.
class_name AKFit
extends RefCounted


static func nelder_mead(f: Callable, x0: PackedFloat64Array, maxiter := 600, xatol := 1e-4, fatol := 1e-4) -> Dictionary:
	var n := x0.size()
	var sim: Array[PackedFloat64Array] = [x0.duplicate()]
	for k in n:
		var y := x0.duplicate()
		y[k] = y[k] * 1.05 if y[k] != 0.0 else 0.00025
		sim.append(y)
	var fs := PackedFloat64Array()
	for s in sim:
		fs.append(f.call(s))
	var evals := n + 1
	for _it in maxiter:
		_order(sim, fs)
		var xd := 0.0
		var fd := 0.0
		for i in range(1, n + 1):
			fd = maxf(fd, absf(fs[0] - fs[i]))
			for k in n:
				xd = maxf(xd, absf(sim[i][k] - sim[0][k]))
		if xd <= xatol and fd <= fatol:
			break
		var xbar := PackedFloat64Array()
		xbar.resize(n)
		for i in n:
			for k in n:
				xbar[k] += sim[i][k] / n
		var xr := _lerp(xbar, sim[n], -1.0)
		var fr: float = f.call(xr)
		evals += 1
		var shrink := false
		if fr < fs[0]:
			var xe := _lerp(xbar, sim[n], -2.0)
			var fe: float = f.call(xe)
			evals += 1
			if fe < fr:
				sim[n] = xe
				fs[n] = fe
			else:
				sim[n] = xr
				fs[n] = fr
		elif fr < fs[n - 1]:
			sim[n] = xr
			fs[n] = fr
		else:
			if fr < fs[n]:
				var xc := _lerp(xbar, sim[n], -0.5)
				var fc: float = f.call(xc)
				evals += 1
				if fc <= fr:
					sim[n] = xc
					fs[n] = fc
				else:
					shrink = true
			else:
				var xcc := _lerp(xbar, sim[n], 0.5)
				var fcc: float = f.call(xcc)
				evals += 1
				if fcc < fs[n]:
					sim[n] = xcc
					fs[n] = fcc
				else:
					shrink = true
			if shrink:
				for i in range(1, n + 1):
					sim[i] = _lerp(sim[0], sim[i], 0.5)
					fs[i] = f.call(sim[i])
					evals += 1
	_order(sim, fs)
	return {x = sim[0], fun = fs[0], evals = evals}


## a + t (b - a)
static func _lerp(a: PackedFloat64Array, b: PackedFloat64Array, t: float) -> PackedFloat64Array:
	var o := a.duplicate()
	for i in o.size():
		o[i] = a[i] + t * (b[i] - a[i])
	return o


static func _order(sim: Array[PackedFloat64Array], fs: PackedFloat64Array) -> void:
	var idx := range(fs.size())
	idx.sort_custom(func(a: int, b: int) -> bool: return fs[a] < fs[b])
	var s2: Array[PackedFloat64Array] = []
	var f2 := PackedFloat64Array()
	for i: int in idx:
		s2.append(sim[i])
		f2.append(fs[i])
	for i in idx.size():
		sim[i] = s2[i]
		fs[i] = f2[i]


## Powell's method: line searches along a set of directions, the best improving one replaced by the
## overall move. `stop` (optional) is polled between line searches.
static func powell(f: Callable, x0: PackedFloat64Array, maxiter := 1000, xtol := 1e-4, ftol := 1e-4, stop := Callable()) -> Dictionary:
	var n := x0.size()
	var dirs: Array[PackedFloat64Array] = []
	for i in n:
		var d := PackedFloat64Array()
		d.resize(n)
		d[i] = 1.0
		dirs.append(d)
	var x := x0.duplicate()
	var fval: float = f.call(x)
	var x1 := x.duplicate()
	var counter := [1]
	var g := func(v: PackedFloat64Array) -> float:
		counter[0] += 1
		return f.call(v)
	for _it in maxiter:
		var fx := fval
		var big := 0
		var delta := 0.0
		for i in n:
			if stop.is_valid() and stop.call():
				return {x = x, fun = fval, evals = counter[0]}
			var fx2 := fval
			var r := _line(g, x, dirs[i], xtol * 100.0)
			fval = r.fun
			x = r.x
			if fx2 - fval > delta:
				delta = fx2 - fval
				big = i
		if 2.0 * (fx - fval) <= ftol * (absf(fx) + absf(fval)) + 1e-20:
			break
		var d1 := x.duplicate()
		for i in n:
			d1[i] = x[i] - x1[i]
		x1 = x.duplicate()
		var x2 := x.duplicate()
		for i in n:
			x2[i] = x[i] + d1[i]
		var fx2b: float = g.call(x2)
		if fx > fx2b:
			var t := 2.0 * (fx + fx2b - 2.0 * fval)
			var tmp := fx - fval - delta
			t *= tmp * tmp
			tmp = fx - fx2b
			t -= delta * tmp * tmp
			if t < 0.0:
				var r := _line(g, x, d1, xtol * 100.0)
				fval = r.fun
				x = r.x
				var any := false
				for v in r.d:
					any = any or v != 0.0
				if any:
					dirs[big] = dirs[n - 1]
					dirs[n - 1] = r.d
	return {x = x, fun = fval, evals = counter[0]}


## The minimum of f along d from x: {x, fun, d (the step taken)}.
static func _line(f: Callable, x: PackedFloat64Array, d: PackedFloat64Array, tol: float) -> Dictionary:
	var along := func(a: float) -> float:
		var p := x.duplicate()
		for i in p.size():
			p[i] = x[i] + a * d[i]
		return f.call(p)
	var r := brent(along, tol)
	var step := d.duplicate()
	var p := x.duplicate()
	for i in p.size():
		step[i] = r.x * d[i]
		p[i] = x[i] + step[i]
	return {x = p, fun = r.fun, d = step}


## Brent's minimisation of a function of one variable, bracketed from 0 and 1 as scipy's.
static func brent(f: Callable, tol := 1.48e-8, maxiter := 500) -> Dictionary:
	# Bracket (scipy's bracket(): golden steps, parabolic extrapolation up to 110x).
	const G := 1.618034
	const GROW := 110.0
	var xa := 0.0
	var xb := 1.0
	var fa: float = f.call(xa)
	var fb: float = f.call(xb)
	if fa < fb:
		var t := xa
		xa = xb
		xb = t
		t = fa
		fa = fb
		fb = t
	var xc := xb + G * (xb - xa)
	var fc: float = f.call(xc)
	var it := 0
	while fc < fb and it < 50:
		it += 1
		var tmp1 := (xb - xa) * (fb - fc)
		var tmp2 := (xb - xc) * (fb - fa)
		var val := tmp2 - tmp1
		var denom := 2.0 * (1e-21 if absf(val) < 1e-21 else val)
		var w := xb - ((xb - xc) * tmp2 - (xb - xa) * tmp1) / denom
		var wlim := xb + GROW * (xc - xb)
		var fw: float
		if (w - xc) * (xb - w) > 0.0:
			fw = f.call(w)
			if fw < fc:
				xa = xb
				xb = w
				fa = fb
				fb = fw
				break
			elif fw > fb:
				xc = w
				fc = fw
				break
			w = xc + G * (xc - xb)
			fw = f.call(w)
		elif (w - wlim) * (wlim - xc) >= 0.0:
			w = wlim
			fw = f.call(w)
		elif (w - wlim) * (xc - w) > 0.0:
			fw = f.call(w)
			if fw < fc:
				xb = xc
				xc = w
				w = xc + G * (xc - xb)
				fb = fc
				fc = fw
				fw = f.call(w)
		else:
			w = xc + G * (xc - xb)
			fw = f.call(w)
		xa = xb
		xb = xc
		xc = w
		fa = fb
		fb = fc
		fc = fw
	# Brent's method within [a, b] around xb.
	const CG := 0.3819660
	var a := minf(xa, xc)
	var b := maxf(xa, xc)
	var x := xb
	var wv := xb
	var v := xb
	var fx := fb
	var fwv := fb
	var fv := fb
	var dd := 0.0
	var e := 0.0
	for _i in maxiter:
		var tol1 := tol * absf(x) + 1e-11
		var tol2 := 2.0 * tol1
		var xm := 0.5 * (a + b)
		if absf(x - xm) < tol2 - 0.5 * (b - a):
			break
		var u: float
		if absf(e) <= tol1:
			e = (a - x) if x >= xm else (b - x)
			dd = CG * e
		else:
			var r := (x - wv) * (fx - fv)
			var q := (x - v) * (fx - fwv)
			var p := (x - v) * q - (x - wv) * r
			q = 2.0 * (q - r)
			if q > 0.0:
				p = -p
			q = absf(q)
			var etemp := e
			e = dd
			if absf(p) >= absf(0.5 * q * etemp) or p <= q * (a - x) or p >= q * (b - x):
				e = (a - x) if x >= xm else (b - x)
				dd = CG * e
			else:
				dd = p / q
				u = x + dd
				if u - a < tol2 or b - u < tol2:
					dd = tol1 if xm - x >= 0.0 else -tol1
		u = x + dd if absf(dd) >= tol1 else (x + tol1 if dd >= 0.0 else x - tol1)
		var fu: float = f.call(u)
		if fu > fx:
			if u < x:
				a = u
			else:
				b = u
			if fu <= fwv or wv == x:
				v = wv
				fv = fwv
				wv = u
				fwv = fu
			elif fu <= fv or v == x or v == wv:
				v = u
				fv = fu
		else:
			if u >= x:
				a = x
			else:
				b = x
			v = wv
			fv = fwv
			wv = x
			fwv = fx
			x = u
			fx = fu
	return {x = x, fun = fx}


## Straight-line interpolation of (xs, ys) at x, held flat past the ends (as numpy's interp).
static func interp(x: float, xs: PackedFloat64Array, ys: PackedFloat64Array) -> float:
	if x <= xs[0]:
		return ys[0]
	for i in range(1, xs.size()):
		if x <= xs[i]:
			return ys[i - 1] + (ys[i] - ys[i - 1]) * (x - xs[i - 1]) / (xs[i] - xs[i - 1])
	return ys[ys.size() - 1]


## The patch EQ effect's response at f (its low shelf, peak and high shelf), as a complex number.
static func eq_response(e: Dictionary, f: float, sr: float) -> Vector2:
	var h := _shelf(float(e.low_hz), float(e.low_db), false, f, sr)
	h = _mul(h, _peak(float(e.mid_hz), float(e.mid_db), float(e.mid_q), f, sr))
	return _mul(h, _shelf(float(e.high_hz), float(e.high_db), true, f, sr))


static func _mul(a: Vector2, b: Vector2) -> Vector2:
	return Vector2(a.x * b.x - a.y * b.y, a.x * b.y + a.y * b.x)


static func _biquad(b: Array, a: Array, f: float, sr: float) -> Vector2:
	var z := Vector2(cos(-TAU * f / sr), sin(-TAU * f / sr))
	var z2 := _mul(z, z)
	var num: Vector2 = Vector2(b[0], 0) + z * float(b[1]) + z2 * float(b[2])
	var den: Vector2 = Vector2(a[0], 0) + z * float(a[1]) + z2 * float(a[2])
	return _mul(num, Vector2(den.x, -den.y)) / den.length_squared()


static func _shelf(f0: float, g: float, high: bool, f: float, sr: float) -> Vector2:
	var A := pow(10.0, g / 40.0)
	var w := TAU * f0 / sr
	var cw := cos(w)
	var t := sqrt(A) * sin(w) * sqrt(2.0)
	if not high:
		return _biquad([A * ((A + 1) - (A - 1) * cw + t), 2 * A * ((A - 1) - (A + 1) * cw), A * ((A + 1) - (A - 1) * cw - t)],
			[(A + 1) + (A - 1) * cw + t, -2 * ((A - 1) + (A + 1) * cw), (A + 1) + (A - 1) * cw - t], f, sr)
	return _biquad([A * ((A + 1) + (A - 1) * cw + t), -2 * A * ((A - 1) + (A + 1) * cw), A * ((A + 1) + (A - 1) * cw - t)],
		[(A + 1) - (A - 1) * cw + t, 2 * ((A - 1) - (A + 1) * cw), (A + 1) - (A - 1) * cw - t], f, sr)


static func _peak(f0: float, g: float, q: float, f: float, sr: float) -> Vector2:
	var A := pow(10.0, g / 40.0)
	var w := TAU * f0 / sr
	var al := sin(w) / (2.0 * q)
	return _biquad([1 + al * A, -2 * cos(w), 1 - al * A], [1 + al / A, -2 * cos(w), 1 - al / A], f, sr)
