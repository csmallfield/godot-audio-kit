# SPDX-License-Identifier: Apache-2.0
## One patch setting as a labelled slider with a typed-in value: linear or
## logarithmic (frequencies, times), whole numbers or not. Emits `changed`
## as the slider moves and when a value is typed (typed values may go past
## the slider's range).
@tool
class_name AKParamSlider
extends HBoxContainer

## While dragging (and after typing), with the new value.
signal changed(value: float)

## The value's range and how the slider maps to it.
var min_value := 0.0
var max_value := 1.0
## Slider position maps to the value logarithmically (min must be above 0).
var log_scale := false
## Round to whole numbers.
var integer := false
var unit := ""

var _label: Label
var _slider: HSlider
var _edit: LineEdit
var _value := 0.0
var _quiet := false


## A slider for `text` over [lo, hi]. `opts`: log (bool), integer (bool),
## unit (String), width (label width in px).
static func make(text: String, lo: float, hi: float, value: float, opts := {}) -> AKParamSlider:
	var s := AKParamSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.log_scale = bool(opts.get("log", false)) and lo > 0.0
	s.integer = bool(opts.get("integer", false))
	s.unit = String(opts.get("unit", ""))
	s._label.text = text
	s._label.custom_minimum_size.x = float(opts.get("width", 92))
	s.tooltip_text = String(opts.get("tip", ""))
	s.set_value(value)
	return s


func _init() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_label = Label.new()
	_label.clip_text = true
	add_child(_label)
	_slider = HSlider.new()
	_slider.min_value = 0.0
	_slider.max_value = 1.0
	_slider.step = 0.0005
	_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_slider.custom_minimum_size.x = 80
	_slider.value_changed.connect(_on_slider)
	add_child(_slider)
	_edit = LineEdit.new()
	_edit.custom_minimum_size.x = 64
	_edit.alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_edit.text_submitted.connect(func(t: String) -> void: _typed(t))
	_edit.focus_exited.connect(func() -> void: _typed(_edit.text))
	add_child(_edit)


func get_value() -> float:
	return _value


## Show `v` without emitting.
func set_value(v: float) -> void:
	_value = _clean(v)
	_quiet = true
	_slider.value = to_position(_value)
	_quiet = false
	_edit.text = _fmt(_value)


## Act as the user would: move to `v` and emit.
func set_value_from_user(v: float) -> void:
	set_value(v)
	changed.emit(_value)


## Slider position (0..1) for a value.
func to_position(v: float) -> float:
	if max_value <= min_value:
		return 0.0
	if log_scale:
		return clampf(log(maxf(v, min_value) / min_value) / log(max_value / min_value), 0.0, 1.0)
	return clampf((v - min_value) / (max_value - min_value), 0.0, 1.0)


## Value for a slider position (0..1).
func from_position(p: float) -> float:
	if log_scale:
		return min_value * pow(max_value / min_value, p)
	return lerpf(min_value, max_value, p)


func _on_slider(p: float) -> void:
	if _quiet:
		return
	_value = _clean(from_position(p))
	_edit.text = _fmt(_value)
	changed.emit(_value)


func _typed(t: String) -> void:
	var s := t.strip_edges().trim_suffix(unit).strip_edges()
	if not s.is_valid_float():
		_edit.text = _fmt(_value)
		return
	# Typed values may leave the slider's range (an extreme setting on purpose).
	var v := s.to_float()
	if is_equal_approx(v, _value):
		return
	_value = roundf(v) if integer else v
	_quiet = true
	_slider.value = to_position(_value)
	_quiet = false
	_edit.text = _fmt(_value)
	changed.emit(_value)


func _clean(v: float) -> float:
	if integer:
		return roundf(v)
	# Three significant digits from the slider keep the text tidy.
	if v == 0.0:
		return 0.0
	var e := floorf(log(absf(v)) / log(10.0)) - 2.0
	# Divide by an exact power of ten, so 0.55 comes out as the literal 0.55.
	if e < 0.0:
		var inv := pow(10.0, -e)
		return roundf(v * inv) / inv
	var mag := pow(10.0, e)
	return roundf(v / mag) * mag


func _fmt(v: float) -> String:
	if integer:
		return "%d%s" % [int(v), unit]
	var a := absf(v)
	var t := ("%.0f" % v) if a >= 100.0 else (("%.2f" % v) if a >= 1.0 else ("%.3f" % v))
	if t.contains("."):
		t = t.rstrip("0").trim_suffix(".")
	if t == "-0":
		t = "0"
	return t + unit
