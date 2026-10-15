extends Node2D

## 阶段 0：开始界面。
##
## 需求：先显示开始界面，点「开始游戏」后画面渐渐黑屏（本阶段负责），
## 再渐渐亮起进入正式游戏（由下一阶段从黑场淡入接管）。
##
## 文字刻意压到只剩标题与按钮两项 —— 没有标语、没有副标题、没有版本号。
## 与其写一句听起来很有道理的话，不如什么都不说。

signal finished

const VIEW := Vector2(960.0, 540.0)
const FADE_OUT_TIME := 2.4

enum St { TITLE, LEAVING }

var _st: int = St.TITLE
var _t: float = 0.0
var _st_t: float = 0.0
var _fade: float = 0.0
var _btn := Rect2(480.0 - 108.0, 336.0, 216.0, 58.0)
var _btn_hover := false
var _btn_glow := 0.0
var _armed := false
var _confirm_was_down := false

var _bands: Array = []
var _parts: CodeParticles = null
var _hud: DrawProxy = null


func _ready() -> void:
	Pal.set_phase(&"boot", 0.0)
	Pal.scan = 0.16
	Sfx.music("teach", 4.5)

	_parts = CodeParticles.new()
	for i in 6:
		_bands.append(_new_band(true))

	var layer := CanvasLayer.new()
	layer.layer = 10
	add_child(layer)
	_hud = DrawProxy.new()
	_hud.fn = _draw_hud
	layer.add_child(_hud)


## 雾带：一条很宽、很淡、上下渐隐的横向软带。
## 一开始用「漂浮光点」做雾，结果叠圆的色阶断层在大尺寸下非常明显，
## 看起来像一串肥皂泡；横向雾带没有这个问题，也更接近「雾」本身。
func _new_band(anywhere: bool) -> Dictionary:
	return {
		"y": randf_range(-60.0, VIEW.y) if anywhere else VIEW.y + randf_range(20.0, 160.0),
		"h": randf_range(110.0, 260.0),
		"a": randf_range(0.03, 0.085),
		"vx": randf_range(-16.0, 16.0),
		"vy": randf_range(-13.0, -3.5),
		"ph": randf_range(0.0, TAU),
		"sp": randf_range(0.08, 0.22),
	}


func _process(delta: float) -> void:
	_t += delta
	_st_t += delta
	_parts.update(delta)

	for b in _bands:
		b["y"] = float(b["y"]) + float(b["vy"]) * delta
		b["x"] = float(b.get("x", 0.0)) + float(b["vx"]) * delta + sin(_t * float(b["sp"]) + float(b["ph"])) * 6.0 * delta
		if float(b["y"]) + float(b["h"]) < -40.0:
			var nb := _new_band(false)
			for k in nb.keys():
				b[k] = nb[k]
			b["x"] = 0.0

	if _st == St.TITLE:
		var mp := get_viewport().get_mouse_position() if is_inside_tree() else Vector2.ZERO
		_btn_hover = _btn.has_point(mp)
		_btn_glow = lerpf(_btn_glow, 1.0 if _btn_hover else 0.0, clampf(delta * 2.2, 0.0, 1.0))
		if not _armed and _st_t > 2.2:
			_armed = true
		# 键盘/手柄走动作映射（自维护上升沿，程序化输入下也可靠）
		var confirm_down := Input.is_action_pressed("ui_confirm") or Input.is_action_pressed("attack")
		if _armed and confirm_down and not _confirm_was_down:
			_begin()
		_confirm_was_down = confirm_down
	else:
		_fade = clampf(_st_t / FADE_OUT_TIME, 0.0, 1.0)
		if _fade >= 1.0:
			emit_signal("finished")

	_hud.redraw()
	queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if _st != St.TITLE or not _armed:
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if _btn.has_point(event.position):
			_begin()
	elif event is InputEventKey and event.pressed and not event.echo:
		if event.keycode in [KEY_ENTER, KEY_SPACE, KEY_KP_ENTER]:
			_begin()


func _begin() -> void:
	if _st != St.TITLE:
		return
	_st = St.LEAVING
	_st_t = 0.0
	Sfx.play("ui_click", -14.0)
	# 一圈极淡的光晕，作为「开始」的唯一反馈
	_parts.burst_at(_btn.get_center(), 26, {
		"kind": CodeParticles.KIND_SPRITE, "tex": Assets.particle("light_02"),
		"speed": 70.0, "drag": 1.6, "life": 2.4,
		"size": 26.0, "end_size": 90.0, "color": Pal.a(Pal.main, 0.16),
	})


# ---------------------------------------------------------------- 绘制

func _draw() -> void:
	draw_rect(Rect2(0, 0, VIEW.x, VIEW.y), Pal.bg, true)
	# 横向雾带：每条用 sin 剖面叠 18 层横条，上下自然渐隐
	for b in _bands:
		var y := float(b["y"])
		var bh := float(b["h"])
		var a := float(b["a"])
		var xo := float(b.get("x", 0.0))
		var steps := 18
		for s in steps:
			var f := float(s) / float(steps - 1)
			var prof: float = sin(f * PI)
			var col := Pal.lighten(Pal.main, 0.22)
			col.a = a * prof * 0.55
			draw_rect(Rect2(xo - 60.0, y + f * bh, VIEW.x + 120.0, bh / float(steps) + 1.0), col, true)
	_parts.draw(self)


## 逐字排开并拉大字距，标题因此显得疏、静
func _draw_spaced(ci: CanvasItem, font: Font, cx: float, y: float, s: String,
		size: int, gap: float, col: Color) -> void:
	if font == null or s == "":
		return
	var total := 0.0
	var ws: Array = []
	for i in s.length():
		var w: float = font.get_string_size(s.substr(i, 1), HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
		ws.append(w)
		total += w
	total += gap * float(maxi(0, s.length() - 1))
	var x := cx - total * 0.5
	for i in s.length():
		ci.draw_string(font, Vector2(x, y), s.substr(i, 1), HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)
		x += float(ws[i]) + gap


func _draw_hud(ci: CanvasItem) -> void:
	var w := VIEW.x
	var h := VIEW.y
	var soft := Assets.soft_font()

	# 标题。Kenney Future 的小写会渲染成小型大写（Demo 会变成 DeMo），
	# 观感不对，所以标题改用系统细体并拉大字距 —— 更静、更疏。
	var appear := clampf((_t - 0.5) / 2.6, 0.0, 1.0)
	appear = appear * appear * (3.0 - 2.0 * appear)
	var breath := 0.94 + 0.06 * sin(_t * 0.55)
	var tc := Pal.main
	tc.a = appear * breath
	_draw_spaced(ci, soft, w * 0.5, h * 0.42, "Demo", 86, 16.0, tc)

	# 按钮：只有一条发丝般的边框，没有任何填充色块
	var btn_appear := clampf((_t - 1.8) / 1.8, 0.0, 1.0)
	if btn_appear > 0.01:
		var r := _btn
		var base := Pal.lighten(Pal.main, 0.1)
		var edge := base
		edge.a = btn_appear * (0.28 + 0.42 * _btn_glow)
		ci.draw_rect(r, edge, false, 1.0)
		var arm := 10.0 + 6.0 * _btn_glow
		var ac := base
		ac.a = btn_appear * (0.4 + 0.5 * _btn_glow)
		_corners(ci, r, arm, ac)

		var lc := Pal.text
		lc.a = btn_appear * (0.55 + 0.4 * _btn_glow)
		Tx.center(ci, soft, r.get_center().x, r.get_center().y + 8.0, "开始游戏", 21, lc)

	# 黑场
	if _fade > 0.0:
		ci.draw_rect(Rect2(0, 0, w, h), Color(0.0, 0.0, 0.0, pow(_fade, 0.85)), true)


func _corners(ci: CanvasItem, r: Rect2, arm: float, col: Color) -> void:
	var tl := r.position
	var tr := Vector2(r.end.x, r.position.y)
	var br := r.end
	var bl := Vector2(r.position.x, r.end.y)
	ci.draw_line(tl, tl + Vector2(arm, 0), col, 1.0)
	ci.draw_line(tl, tl + Vector2(0, arm), col, 1.0)
	ci.draw_line(tr, tr + Vector2(-arm, 0), col, 1.0)
	ci.draw_line(tr, tr + Vector2(0, arm), col, 1.0)
	ci.draw_line(br, br + Vector2(-arm, 0), col, 1.0)
	ci.draw_line(br, br + Vector2(0, -arm), col, 1.0)
	ci.draw_line(bl, bl + Vector2(arm, 0), col, 1.0)
	ci.draw_line(bl, bl + Vector2(0, -arm), col, 1.0)
