extends Node2D

## 阶段 4：白光转场与结局字幕。
##
## 需求映射：
##   · 碰到代码门后白光转场
##   · 出现代码粒子风格的字幕「感谢游玩 demo」
##   · 字幕停留不消失，右下角提供重开按钮
##
## 字幕做法说明：这里没有去采样字形像素，而是用「逐字编译成型」——
## 每个字先由乱码字符占据字格，到时刻再「啪」地编译成真字并炸出一圈粒子。
## 好处是任何情况下字幕都清晰可读，而且更贴合「系统输出日志」的设定。

signal finished
signal restart_requested

const VIEW := Vector2(960.0, 540.0)
const CREDIT := "感谢游玩"
const SUBTITLE := "D e m o"

const CHAR_SIZE := 62
const COMPILE_LEAD := 0.75     ## 每个字在成型前由乱码占据的时长
const PER_CHAR_STAGGER := 0.17
const ASSEMBLE_TAIL := 1.2

enum St { FLASH, ASSEMBLE, HOLD }

var _st: int = St.FLASH
var _t: float = 0.0
var _st_t: float = 0.0

var _white: float = 1.0
var _chars: Array = []          ## {ch, x, w, reveal_t, done}
var _line_x := 0.0
var _line_w := 0.0
var _assemble_end := 0.0
var _shed_t := 0.0
var _btn: Rect2 = Rect2(0.0, 0.0, 0.0, 0.0)
var _btn_hover := false
var _btn_glow := 0.0
var _pressed_t := -1.0
var _swarm_done := false

var _rain: CodeRain = null
var _parts: CodeParticles = null
var _hud: DrawProxy = null

var _font: Font = null


func _ready() -> void:
	Pal.set_phase(&"ending", 1.2)
	Sfx.music("ending", 2.0)

	_font = Assets.title_font()
	_rain = CodeRain.new()
	_rain.setup(VIEW.x, VIEW.y, 25.0, 14)
	_rain.set_speed_scale(0.32)
	_parts = CodeParticles.new()

	var layer := CanvasLayer.new()
	layer.layer = 10
	add_child(layer)
	_hud = DrawProxy.new()
	_hud.fn = _draw_hud
	layer.add_child(_hud)

	_layout()

	_btn = Rect2(VIEW.x - 268.0, VIEW.y - 92.0, 232.0, 56.0)

	# 转场后的第一批粒子：从屏幕中心炸开，作为「白光散去」的余韵
	_parts.burst_at(VIEW * 0.5, 46, {
		"kind": CodeParticles.KIND_CHAR, "speed": 320.0, "drag": 1.5,
		"life": 1.4, "size": 18.0, "end_size": 8.0,
		"color": Pal.a(Pal.main, 0.8),
	})


func _layout() -> void:
	_chars.clear()
	var total := 0.0
	var gap := float(CHAR_SIZE) * 0.08
	for i in CREDIT.length():
		var ch := CREDIT.substr(i, 1)
		var w := _font.get_char_size(ch.unicode_at(0), CHAR_SIZE).x
		if ch == " ":
			w = float(CHAR_SIZE) * 0.36
		_chars.append({"ch": ch, "w": w, "x": 0.0, "reveal_t": 0.0, "done": false})
		total += w + gap
	total -= gap
	_line_x = VIEW.x * 0.5 - total * 0.5
	_line_w = total
	var x := _line_x
	for c in _chars:
		c["x"] = x
		x += float(c["w"]) + gap

	# 每个字的成型时刻：从左到右依次编译
	for i in _chars.size():
		_chars[i]["reveal_t"] = float(i) * PER_CHAR_STAGGER + 0.45
	_assemble_end = float(_chars.size() - 1) * PER_CHAR_STAGGER + 0.45 + ASSEMBLE_TAIL


func _process(delta: float) -> void:
	_t += delta
	_st_t += delta
	_rain.update(delta)
	_parts.update(delta)

	_update_button(delta)

	match _st:
		St.FLASH:
			_white = maxf(0.0, 1.0 - _st_t / 1.35)
			if _st_t >= 1.5:
				_set_state(St.ASSEMBLE)
		St.ASSEMBLE:
			_white = 0.0
			_tick_assemble(delta)
		St.HOLD:
			_tick_hold(delta)

	_hud.redraw()
	queue_redraw()


func _set_state(s: int) -> void:
	_st = s
	_st_t = 0.0


# ---------------------------------------------------------------- 编译字幕

func _tick_assemble(delta: float) -> void:
	for c in _chars:
		if bool(c["done"]):
			continue
		var rt: float = c["reveal_t"]
		# 成型前：字格里不断刷随机乱码
		if _st_t < rt and _st_t > rt - COMPILE_LEAD and randf() < delta * 26.0:
			_parts.spawn({
				"x": float(c["x"]) + randf() * float(c["w"]),
				"y": VIEW.y * 0.5 - 24.0 + randf_range(-16.0, 16.0),
				"kind": CodeParticles.KIND_CHAR,
				"vx": randf_range(-22.0, 22.0), "vy": randf_range(-30.0, 30.0),
				"drag": 2.4, "life": randf_range(0.25, 0.6), "size": 18.0,
				"color": Pal.a(Pal.main, 0.65),
			})
		if _st_t >= rt:
			c["done"] = true
			_compile_burst(c)

	if _st_t >= _assemble_end:
		_set_state(St.HOLD)
		Sfx.play("confirm", -10.0)


func _compile_burst(c: Dictionary) -> void:
	Sfx.play_varied("zap", -16.0, 0.25)
	var cy := VIEW.y * 0.5 - 24.0
	var cw: float = c["w"]
	var cx: float = c["x"]
	_parts.burst_from_rect(Rect2(cx, cy - float(CHAR_SIZE) * 0.5, cw, float(CHAR_SIZE)), 10, {
		"kind": CodeParticles.KIND_CHAR,
		"vx": 0.0, "vy": 0.0, "drag": 2.4,
		"life": 0.55, "size": 18.0, "end_size": 6.0,
		"color": Pal.a(Pal.lighten(Pal.main, 0.5), 0.95),
	})
	_parts.burst_at(Vector2(cx + cw * 0.5, cy), 5, {
		"kind": CodeParticles.KIND_SPRITE, "tex": Assets.particle("spark_01"),
		"speed": 130.0, "drag": 3.2, "life": 0.45,
		"size": 34.0, "end_size": 3.0, "color": Pal.a(Pal.accent, 0.85), "spin": 3.0,
	})


func _tick_hold(delta: float) -> void:
	# 字幕稳定后：持续从字上剥落代码碎片，维持「由代码构成」的观感
	_shed_t -= delta
	if _shed_t <= 0.0:
		_shed_t = 0.045
		var c: Dictionary = _chars[randi() % _chars.size()]
		_parts.spawn({
			"x": float(c["x"]) + randf() * float(c["w"]),
			"y": VIEW.y * 0.5 - 24.0 + randf_range(-20.0, 20.0),
			"kind": CodeParticles.KIND_CHAR,
			"vx": randf_range(-18.0, 18.0), "vy": randf_range(-58.0, -18.0),
			"drag": 1.5, "life": randf_range(0.6, 1.5), "size": 15.0, "end_size": 5.0,
			"color": Pal.a(Pal.main, 0.55),
		})
	# 偶尔补几颗星芒
	if randf() < delta * 8.0:
		_parts.spawn({
			"x": randf_range(_line_x - 80.0, _line_x + _line_w + 80.0),
			"y": randf_range(VIEW.y * 0.5 - 70.0, VIEW.y * 0.5 + 40.0),
			"kind": CodeParticles.KIND_SPRITE, "tex": Assets.particle("star_03"),
			"vy": randf_range(-30.0, -8.0), "life": randf_range(0.8, 1.6),
			"size": randf_range(14.0, 34.0), "end_size": 2.0,
			"color": Pal.a(Pal.accent, 0.6), "spin": randf_range(-2.0, 2.0),
		})


# ---------------------------------------------------------------- 重开按钮

func _update_button(delta: float) -> void:
	if _st != St.HOLD:
		return
	var mp := get_viewport().get_mouse_position()
	_btn_hover = _btn.has_point(mp)
	_btn_glow = lerpf(_btn_glow, 1.0 if _btn_hover else 0.0, clampf(delta * 8.0, 0.0, 1.0))
	if _pressed_t >= 0.0:
		_pressed_t += delta
		if _pressed_t > 0.22:
			_pressed_t = -1.0
			emit_signal("restart_requested")


func _unhandled_input(event: InputEvent) -> void:
	if _st != St.HOLD:
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if _btn.has_point(event.position):
			_press_restart()
	elif event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_R or event.keycode == KEY_ENTER or event.keycode == KEY_SPACE:
			_press_restart()
	elif event is InputEventMouseMotion:
		pass


func _press_restart() -> void:
	if _pressed_t >= 0.0:
		return
	Sfx.play("ui_click", -8.0)
	Pal.flash = 0.4
	# 让重开也有一次粒子化的收尾
	_parts.burst_at(VIEW * 0.5, 60, {
		"kind": CodeParticles.KIND_CHAR, "speed": 420.0, "drag": 1.2,
		"life": 0.9, "size": 20.0, "end_size": 6.0,
		"color": Pal.a(Pal.main, 0.9),
	})
	_pressed_t = 0.0


# ---------------------------------------------------------------- 绘制

func _draw() -> void:
	draw_rect(Rect2(0, 0, VIEW.x, VIEW.y), Color.BLACK, true)
	_rain.draw(self, Pal.main, 0.065)
	_draw_credits()
	_parts.draw(self)


func _draw_credits() -> void:
	if _st == St.FLASH and _white > 0.99:
		return
	var mono := Assets.mono_font()
	var cy := VIEW.y * 0.5 - 24.0

	for c in _chars:
		var cx: float = c["x"]
		var cw: float = c["w"]
		var ch: String = c["ch"]
		if ch == " ":
			continue
		var done: bool = c["done"]
		if done:
			# 成型后的真字，带一点持续抖动，像信号还没完全稳定
			var jx := sin(_t * 13.0 + cx * 0.11) * 0.9
			var jy := cos(_t * 11.0 + cx * 0.07) * 0.9
			var a := 1.0
			if _st == St.FLASH:
				a = 1.0 - _white
			draw_string(_font, Vector2(cx + jx, cy + jy), ch, HORIZONTAL_ALIGNMENT_LEFT, -1, CHAR_SIZE,
				Pal.a(Pal.main, a))
			draw_string(_font, Vector2(cx + jx - 1.5, cy + jy), ch, HORIZONTAL_ALIGNMENT_LEFT, -1, CHAR_SIZE,
				Pal.a(Pal.lighten(Pal.main, 0.6), 0.30 * a))
		else:
			# 成型前的乱码：同一字格里刷随机字符
			var n := 2
			for k in n:
				var w := cw / float(n)
				var gcode := CodeParticles.GLYPHS.substr(
					int(_t * 22.0 + float(k) * 7.0 + cx) % CodeParticles.GLYPHS.length(), 1)
				var a2 := 0.30 + 0.25 * sin(_t * 18.0 + float(k))
				draw_string(mono, Vector2(cx + float(k) * w + 2.0, cy), gcode,
					HORIZONTAL_ALIGNMENT_LEFT, -1, int(float(CHAR_SIZE) * 0.72),
					Pal.a(Pal.dim, clampf(a2, 0.0, 1.0)))
			# 编译进度条
			if _st_t > float(c["reveal_t"]) - COMPILE_LEAD:
				var p := clampf((_st_t - (float(c["reveal_t"]) - COMPILE_LEAD)) / COMPILE_LEAD, 0.0, 1.0)
				draw_rect(Rect2(cx, cy + 16.0, cw * p, 2.0), Pal.a(Pal.accent, 0.55), true)

	if _st != St.HOLD:
		return

	# 副标题
	var t2 := 0.5 + 0.5 * sin(_t * 2.0)
	Tx.center(self, mono, VIEW.x * 0.5, cy + 62.0, SUBTITLE, 15, Pal.a(Pal.text, 0.35 + 0.15 * t2))
	# 字幕上方不再放任何说明性文字 —— 留白比解释更接近「空」

	# 字幕下方的扫描线
	var sweep := fmod(_t * 0.35, 1.0)
	var sx := _line_x + _line_w * sweep
	draw_rect(Rect2(sx - 30.0, cy - 44.0, 60.0, 2.0), Pal.a(Pal.lighten(Pal.main, 0.4), 0.5), true)
	draw_rect(Rect2(_line_x, cy + 42.0, _line_w, 1.0), Pal.a(Pal.dim, 0.8), true)

	# 素材署名（CC0 不强制署名，但写出来更好）
	draw_string(mono, Vector2(24.0, VIEW.y - 22.0),
		"素材 CC0：Kenney（精灵 / 音效 / 字体）· OpenGameArt（BGM）",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Pal.a(Pal.text, 0.28))


func _draw_hud(ci: CanvasItem) -> void:
	var w := VIEW.x
	var h := VIEW.y

	# 扫描线
	var a := 0.08 * Pal.scan
	var y := 0.0
	while y < h:
		ci.draw_rect(Rect2(0, y, w, 1), Color(0, 0, 0, a), true)
		y += 3.0

	# 顶部状态条
	var mono := Assets.mono_font()

	# 重开按钮
	if _st == St.HOLD:
		var pressed := _pressed_t >= 0.0
		var off := 2.0 if pressed else 0.0
		var r := Rect2(_btn.position.x, _btn.position.y + off, _btn.size.x, _btn.size.y)
		var base := Pal.lighten(Pal.main, 0.1)
		ci.draw_rect(r, Pal.a(Pal.panel, 0.9), true)
		ci.draw_rect(r, Pal.a(base, 0.6 + 0.4 * _btn_glow), false, 2.0)
		ci.draw_rect(r.grow(4.0), Pal.a(base, 0.12 + 0.16 * _btn_glow), false, 1.0)
		# 按钮上的代码装饰
		for i in 5:
			var bx := r.position.x + 10.0 + float(i) * (r.size.x - 20.0) / 4.0
			ci.draw_rect(Rect2(bx, r.position.y + 6.0, 1.0, r.size.y - 12.0),
				Pal.a(base, 0.14), true)
		var label := "重新开始"
		var lw := mono.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 19).x
		ci.draw_string(mono, Vector2(r.get_center().x - lw * 0.5, r.get_center().y + 6.0), label,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 19, Pal.a(Pal.lighten(base, 0.4), 0.6 + 0.4 * _btn_glow))
		Tx.center(ci, mono, r.get_center().x, r.end.y + 18.0, "CLICK  /  PRESS R", 11, Pal.a(Pal.text, 0.35))

	# 白光转场（从纯白淡出）
	if _white > 0.001:
		ci.draw_rect(Rect2(0, 0, w, h), Color(1, 1, 1, _white), true)
	# 复燃闪白
	if Pal.flash > 0.0:
		ci.draw_rect(Rect2(0, 0, w, h), Pal.a(Color.WHITE, 0.35 * Pal.flash), true)
