class_name Whisper
extends RefCounted

## 「絮语」—— 提示样式。
##
## 每条提示分两行，各有各的分工：
##
##   主句   —— 角色自己得出的结论。刻意不写主语：不用「我」，
##             也不用「它 / 主角」这类旁白口吻，更不加 [SYS]、「已解锁」
##             这类系统腔。读起来就是它在解体又重组之后，自己推出来的一句话。
##   键位行 —— 明确写出「按哪个键 → 触发什么动作」。用等宽字体、小一号、
##             更低的不透明度，读起来像它顺手记下的一条备注，而不是弹窗按钮。
##
## 两行都保留原来的呼吸感：居中偏上、逐字缓慢淡入、浮起稳定后停留，
## 最后整行均匀淡出并向上升一点。主句先出来，键位行晚半拍跟上。

const CX := 480.0
const BASE_Y := 166.0     ## 居中偏上
const SLOT_H := 92.0      ## 每条提示占的纵向高度
const KEY_DY := 40.0      ## 键位行相对主句基线的偏移

const FONT_SIZE := 23
const LETTER_GAP := 5.0
const DRIFT := 7.0        ## 入场时从下方浮起的距离

const KEYS_SIZE := 15
const KEYS_GAP := 2.5
const KEYS_DELAY := 0.6   ## 键位行比主句晚多久开始出现

const STAGGER := 0.075    ## 逐字入场间隔
const KEYS_STAGGER := 0.05
const RAMP := 1.05        ## 单字淡入时长
const FADE_OUT := 1.5

const MAX_ITEMS := 2

var items: Array = []
var _trash: Array = []


## opts:
##   text  —— 主句（通过第一个参数传）
##   keys  —— 键位行，形如 "空格键 → 向上跃起"
##   hold  —— 停留时长（会再乘 Pal.PACE）
func say(text: String, opts: Dictionary = {}) -> void:
	if text.strip_edges() == "":
		return
	var keys := String(opts.get("keys", ""))
	# 同一条只出现一次，避免反复坠落后刷屏
	for it in items:
		if String(it["text"]) == text and String(it["keys"]) == keys:
			it["age"] = 0.0
			it["state"] = 0
			it["alpha"] = 1.0
			return
	items.append({
		"text": text,
		"keys": keys,
		"age": 0.0,
		"state": 0,   # 0 入场 1 停留 2 淡出
		"hold": float(opts.get("hold", 5.0)) * Pal.PACE,
		"alpha": 1.0,
	})
	# 最多同时两条，旧的自然淡出
	while items.size() > MAX_ITEMS:
		var old: Dictionary = items.pop_front()
		old["state"] = 2
		old["age"] = 0.0
		old["alpha"] = 1.0
		_trash.append(old)
	if opts.has("sfx"):
		Sfx.play(String(opts["sfx"]), float(opts.get("sfx_db", -24.0)))


func update(delta: float) -> void:
	for it in items.duplicate():
		_tick(it, delta)
		if float(it["alpha"]) <= 0.001 and int(it["state"]) == 2:
			items.erase(it)
	for it in _trash.duplicate():
		_tick(it, delta)
		if float(it["alpha"]) <= 0.001:
			_trash.erase(it)


func _tick(it: Dictionary, delta: float) -> void:
	it["age"] = float(it["age"]) + delta
	var a := float(it["age"])
	match int(it["state"]):
		0:
			if a >= _intro_len(it):
				it["state"] = 1
				it["age"] = 0.0
		1:
			if a >= float(it["hold"]):
				it["state"] = 2
				it["age"] = 0.0
				it["alpha"] = 1.0
		2:
			it["alpha"] = maxf(0.0, 1.0 - a / FADE_OUT)


## 两行都铺完才算入场结束
func _intro_len(it: Dictionary) -> float:
	var n := String(it["text"]).length()
	var main := float(n) * STAGGER + RAMP
	var keys := String(it["keys"])
	if keys == "":
		return main
	var m := keys.length()
	return maxf(main, KEYS_DELAY + float(m) * KEYS_STAGGER + RAMP)


## 返回某个字的当前不透明度（含逐字错峰；淡出阶段由 alpha 统一控制）
func _char_alpha(it: Dictionary, idx: int, delay: float, stagger: float) -> float:
	if int(it["state"]) == 2:
		return 1.0
	var a := float(it["age"]) - delay - float(idx) * stagger
	return clampf(a / RAMP, 0.0, 1.0)


func draw(ci: CanvasItem) -> void:
	if items.is_empty() and _trash.is_empty():
		return
	var soft := Assets.soft_font()
	var mono := Assets.mono_font()
	if soft == null:
		return
	var all: Array = _trash.duplicate()
	all.append_array(items)

	# 先在文字后面铺一层极柔的暗雾。战斗场的网格、教学关的数据柱都会从
	# 提示背后穿过，不垫一层的话字会被切成一段一段。
	var strength := 0.0
	for it in all:
		strength = maxf(strength, _presence(it))
	if strength > 0.01:
		_backdrop(ci, BASE_Y - 56.0, BASE_Y + SLOT_H * float(all.size()) - 14.0, strength)

	var y := BASE_Y
	for it in all:
		_draw_item(ci, soft, mono, it, y)
		y += SLOT_H


## 单条提示当前的「存在感」，只用于决定暗雾铺多浓
func _presence(it: Dictionary) -> float:
	var a := float(it["alpha"])
	if int(it["state"]) == 0:
		a *= clampf(float(it["age"]) / 0.7, 0.0, 1.0)
	return a


## 纵向两端淡、中间实的横向暗雾。不用面板、不用描边，避免变成弹窗。
func _backdrop(ci: CanvasItem, top: float, bottom: float, strength: float) -> void:
	var h := bottom - top
	if h <= 1.0:
		return
	var steps := 26
	for i in steps:
		var f := float(i) / float(steps - 1)
		var a := 0.30 * sin(f * PI) * strength
		if a <= 0.002:
			continue
		ci.draw_rect(Rect2(0.0, top + h * f, CX * 2.0, h / float(steps) + 1.0),
			Color(0.0, 0.012, 0.02, a), true)


func _draw_item(ci: CanvasItem, soft: Font, mono: Font, it: Dictionary, y: float) -> void:
	var fade := float(it["alpha"])
	var text := String(it["text"])
	var main_col := Pal.lighten(Pal.main, 0.15)
	var m := _draw_run(ci, soft, text, y, FONT_SIZE, LETTER_GAP,
		it, 0.0, STAGGER, main_col, 0.82)

	var keys := String(it["keys"])
	var line_y := y + 12.0
	var line_w := m.y
	var line_a := m.x
	if keys != "" and mono != null:
		var k := _draw_run(ci, mono, keys, y + KEY_DY, KEYS_SIZE, KEYS_GAP,
			it, KEYS_DELAY, KEYS_STAGGER, Pal.lighten(Pal.accent, 0.14), 0.76)
		line_y = y + KEY_DY + 12.0
		line_w = k.y
		line_a = k.x

	# 文字下方一条极淡的细线，随时间收放，替代「光标」的存在感
	if line_a > 0.02:
		var lw := line_w * clampf(line_a, 0.0, 1.0)
		var lc := Pal.accent
		lc.a = 0.15 * line_a * fade
		ci.draw_rect(Rect2(CX - lw * 0.5, line_y, lw, 1.0), lc, true)


## 画一行「逐字淡入」的文字。返回 Vector2(整体不透明度, 总宽度)
func _draw_run(ci: CanvasItem, font: Font, text: String, y: float, size: int,
		gap: float, it: Dictionary, delay: float, stagger: float,
		col: Color, base_alpha: float) -> Vector2:
	var n := text.length()
	if n == 0 or font == null:
		return Vector2.ZERO
	var widths: Array = []
	var total := 0.0
	for i in n:
		var w := font.get_string_size(text.substr(i, 1), HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
		widths.append(w)
		total += w
	total += gap * float(maxi(0, n - 1))

	var fade := float(it["alpha"])
	var x := CX - total * 0.5
	var overall := 0.0
	for i in n:
		var a := _char_alpha(it, i, delay, stagger) * fade
		overall = maxf(overall, a)
		var ch := text.substr(i, 1)
		# 入场时从下方轻轻浮上来
		var dy := (1.0 - a) * DRIFT + (1.0 - fade) * -DRIFT * 0.6
		var c := col
		c.a = a * base_alpha
		if ch != " ":
			ci.draw_string(font, Vector2(x, y + dy), ch, HORIZONTAL_ALIGNMENT_LEFT, -1, size, c)
		x += float(widths[i]) + gap
	return Vector2(overall, total)


func clear() -> void:
	items.clear()
	_trash.clear()


func empty() -> bool:
	return items.is_empty() and _trash.is_empty()
