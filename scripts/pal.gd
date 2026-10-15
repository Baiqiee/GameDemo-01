class_name Pal
extends RefCounted

## 全局色温系统 —— 蓝青色的赛博代码空间。
##
## 整套色相收在「青蓝 → 深蓝」这一段里，不引入任何暖色与紫红。
## 底色一律是接近黑的深蓝（数据空间没有环境光），网格用低饱和的青，
## 主体与高光用发亮的青白。四个阶段靠「青的纯度与亮度」拉开层次：
## 标题最淡、教学居中、战斗最密最亮、结局褪成近乎全白。
## 阶段切换时整体柔和过渡，不做硬切。
const PRESETS := {
	&"boot": {
		"bg": Color("01060b"), "sky": Color("04121b"), "grid": Color("0d3a4a"),
		"main": Color("a9f0ff"), "accent": Color("3fc9e6"), "warn": Color("7fe0f0"),
		"dim": Color("1b4553"), "text": Color("84c6d9"),
		"panel": Color(0.008, 0.043, 0.062, 0.86),
	},
	&"teach": {
		"bg": Color("020810"), "sky": Color("06141f"), "grid": Color("113c4d"),
		"main": Color("79e6f7"), "accent": Color("2fb4d6"), "warn": Color("9fe9f5"),
		"dim": Color("1e4c5c"), "text": Color("83c5d8"),
		"panel": Color(0.008, 0.047, 0.067, 0.80),
	},
	&"battle": {
		"bg": Color("010509"), "sky": Color("04121a"), "grid": Color("0f4a5c"),
		"main": Color("5fe0f5"), "accent": Color("1f9ec4"), "warn": Color("d6f7ff"),
		"dim": Color("14454f"), "text": Color("7fc0d2"),
		"panel": Color(0.006, 0.04, 0.055, 0.80),
	},
	&"ending": {
		"bg": Color("000000"), "sky": Color("03090d"), "grid": Color("102430"),
		"main": Color("e8fdff"), "accent": Color("a8e4f2"), "warn": Color("ffffff"),
		"dim": Color("2b4a55"), "text": Color("e8fdff"),
		"panel": Color(0.01, 0.035, 0.05, 0.72),
	},
}

## 全局节奏系数。需求要求「整体节奏明显放慢」，所有时长统一乘这个数，
## 免得逐处去改魔法数字。
const PACE := 1.75

static var bg: Color = PRESETS[&"boot"]["bg"]
static var sky: Color = PRESETS[&"boot"]["sky"]
static var grid: Color = PRESETS[&"boot"]["grid"]
static var main: Color = PRESETS[&"boot"]["main"]
static var accent: Color = PRESETS[&"boot"]["accent"]
static var warn: Color = PRESETS[&"boot"]["warn"]
static var dim: Color = PRESETS[&"boot"]["dim"]
static var text: Color = PRESETS[&"boot"]["text"]
static var panel: Color = PRESETS[&"boot"]["panel"]

## 屏幕效果强度（0..1）
static var flash: float = 0.0
static var glitch: float = 0.0
static var scan: float = 0.35

static var _keys := ["bg", "sky", "grid", "main", "accent", "warn", "dim", "text", "panel"]
static var _from: Dictionary = PRESETS[&"boot"]
static var _to: Dictionary = PRESETS[&"boot"]
static var _t: float = 1.0
static var _inv: float = 0.8
static var _cur_phase: StringName = &"boot"


static func set_phase(phase_name: StringName, dur: float = 0.8) -> void:
	if not PRESETS.has(phase_name):
		return
	_cur_phase = phase_name
	_from = _snapshot()
	_to = PRESETS[phase_name]
	if dur <= 0.0:
		_t = 1.0
		_apply(_to)
	else:
		_t = 0.0
		_inv = 1.0 / dur


static func current_phase() -> StringName:
	return _cur_phase


static func update(delta: float) -> void:
	if _t < 1.0:
		_t = minf(1.0, _t + delta * _inv)
		var e: float = 1.0 - pow(1.0 - _t, 3.0)
		var mixed := {}
		for k in _keys:
			mixed[k] = (_from[k] as Color).lerp(_to[k] as Color, e)
		_apply(mixed)
	if flash > 0.0:
		flash = maxf(0.0, flash - delta * 1.6)
	if glitch > 0.0:
		glitch = maxf(0.0, glitch - delta * 1.1)


static func _snapshot() -> Dictionary:
	var d := {}
	d["bg"] = bg
	d["sky"] = sky
	d["grid"] = grid
	d["main"] = main
	d["accent"] = accent
	d["warn"] = warn
	d["dim"] = dim
	d["text"] = text
	d["panel"] = panel
	return d


static func _apply(d: Dictionary) -> void:
	bg = d["bg"]
	sky = d["sky"]
	grid = d["grid"]
	main = d["main"]
	accent = d["accent"]
	warn = d["warn"]
	dim = d["dim"]
	text = d["text"]
	panel = d["panel"]


## 便捷：给任意颜色叠一个 alpha
static func a(c: Color, alpha: float) -> Color:
	return Color(c.r, c.g, c.b, alpha)


## 便捷：把颜色往白/黑推，用于发光描边
static func lighten(c: Color, amount: float) -> Color:
	return c.lerp(Color.WHITE, clampf(amount, 0.0, 1.0))


static func darken(c: Color, amount: float) -> Color:
	return c.lerp(Color.BLACK, clampf(amount, 0.0, 1.0))
