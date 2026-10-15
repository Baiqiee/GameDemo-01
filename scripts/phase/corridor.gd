extends Node2D

## 阶段 3：2D 第一人称走廊。
##
## 需求映射：
##   · 战斗结束后镜头回到主角身上 → 切换为 2D 第一人称视角
##   · 环境是一条单点透视走廊，代码门在正前方
##   · A/D 原地转身，W 往前走
##   · 角色碰到代码门 → 白光转场
##
## 实现说明：这是一个自己写的极简第一人称相机 —— 把世界点 (X, Y, Z) 用
## 偏航角转到相机空间，再按 focal/depth 做单点透视投影。
## 没有引入真正的 3D 相机，因为这里只需要一条直走廊，
## 自己算反而更短、更容易和 2D 界面混排。

signal finished
signal restart_requested

const VIEW := Vector2(960.0, 540.0)

const HW := 210.0            ## 走廊半宽
const HH := 195.0            ## 走廊半高
const FOCAL := 640.0
const HORIZON := 258.0       ## 地平线屏幕 y

const Z_START := 240.0
const DOOR_Z := 2400.0
const CONTACT_Z := DOOR_Z - 135.0
const FWD_SPEED := 330.0
const YAW_SPEED := 1.55
const YAW_MAX := 0.72
const SIDE_MAX := HW - 46.0

enum St { WALK, FLASH, DONE }

var _st: int = St.WALK
var _t: float = 0.0
var _st_t: float = 0.0

var _x: float = 0.0
var _z: float = Z_START
var _yaw: float = 0.0
var _bob: float = 0.0
var _speed_now: float = 0.0
var _flash: float = 0.0
var _door_pulse: float = 0.0
var _door_charge: float = 0.0
var _hint_done := false
var _foot_t := 0.0

var _rain: CodeRain = null
var _parts: CodeParticles = null
var _hud: DrawProxy = null
var _whisper: Whisper = null


func _ready() -> void:
	Pal.set_phase(&"ending", 1.6)
	Sfx.music("ending", 2.2)

	_rain = CodeRain.new()
	_rain.setup(VIEW.x, VIEW.y, 30.0, 13)
	_rain.set_speed_scale(0.42)

	_parts = CodeParticles.new()
	_whisper = Whisper.new()

	var layer := CanvasLayer.new()
	layer.layer = 10
	add_child(layer)
	_hud = DrawProxy.new()
	_hud.fn = _draw_hud
	layer.add_child(_hud)


func _process(delta: float) -> void:
	_t += delta
	_st_t += delta
	_door_pulse += delta
	_rain.update(delta)
	_parts.update(delta)
	_whisper.update(delta)

	match _st:
		St.WALK:
			_tick_walk(delta)
		St.FLASH:
			_flash = clampf(_st_t / 0.42, 0.0, 1.0)
			if _st_t > 0.62:
				_set_state(St.DONE)
				emit_signal("finished")
		St.DONE:
			pass

	_hud.redraw()
	queue_redraw()


func _set_state(s: int) -> void:
	_st = s
	_st_t = 0.0


# ---------------------------------------------------------------- 行走

func _tick_walk(delta: float) -> void:
	# A/D 转身
	var turn := 0.0
	if Input.is_action_pressed("move_left"):
		turn -= 1.0
	if Input.is_action_pressed("move_right"):
		turn += 1.0
	_yaw = clampf(_yaw + turn * YAW_SPEED * delta, -YAW_MAX, YAW_MAX)

	# W/C 前后
	var fwd := 0.0
	if Input.is_action_pressed("move_up"):
		fwd += 1.0
	if Input.is_action_pressed("move_down"):
		fwd -= 1.0

	var moving := absf(fwd) > 0.01
	_speed_now = FWD_SPEED * (1.0 if moving else 0.0)

	if moving:
		# 世界空间前进方向由偏航角决定
		var dx := sin(_yaw) * fwd
		var dz := cos(_yaw) * fwd
		var nx := _x + dx * FWD_SPEED * delta
		var nz := _z + dz * FWD_SPEED * delta
		# 撞到侧墙时沿墙滑行，不会卡住
		if absf(nx) > SIDE_MAX:
			nx = signf(nx) * SIDE_MAX
			nz = _z + dz * FWD_SPEED * delta
		_x = nx
		_z = clampf(nz, 40.0, DOOR_Z + 40.0)

		_bob += delta * 9.0
		_foot_t -= delta
		if _foot_t <= 0.0:
			_foot_t = 0.46
			Sfx.play_varied("footstep", -24.0, 0.18)
	else:
		_bob += delta * 1.4

	# 走近时门开始充能
	var d := DOOR_Z - _z
	_door_charge = clampf(1.0 - d / 1400.0, 0.0, 1.0)

	if not _hint_done and _z > Z_START + 260.0:
		_hint_done = true
		_whisper.say("出口在正前方，没有别的路", {
			"keys": "W 键 → 前进　　A / D 键 → 原地转身",
			"hold": 5.0,
		})

	# 走廊里漂浮的代码粒子
	if randf() < delta * 40.0:
		_parts.spawn({
			"x": randf_range(-HW * 0.9, HW * 0.9),
			"y": randf_range(-HH * 0.8, HH * 0.8),
			"z": _z + randf_range(60.0, 900.0),
			"kind": CodeParticles.KIND_RECT,
			"vx": randf_range(-14.0, 14.0), "vy": randf_range(-22.0, 22.0),
			"vz": randf_range(-90.0, -20.0),
			"drag": 0.0, "life": randf_range(0.6, 1.4), "size": randf_range(2.5, 5.0),
			"color": Pal.a(Pal.main, 0.7),
		})

	# 碰到代码门 → 白光
	if _z >= CONTACT_Z:
		_set_state(St.FLASH)
		Pal.flash = 0.6
		Sfx.play("door_open", -6.0)
		Sfx.play("white_out", -8.0)
		Sfx.play("portal", -6.0)
		for i in 60:
			_parts.spawn({
				"x": randf_range(-120.0, 120.0), "y": randf_range(-140.0, 140.0),
				"z": DOOR_Z - randf_range(0.0, 120.0),
				"kind": CodeParticles.KIND_CHAR,
				"vx": randf_range(-300.0, 300.0), "vy": randf_range(-300.0, 300.0),
				"vz": randf_range(-600.0, -200.0),
				"drag": 1.2, "life": randf_range(0.5, 1.0), "size": 16.0, "end_size": 6.0,
				"color": Pal.a(Color.WHITE, 0.95),
			})


# ---------------------------------------------------------------- 投影

## 世界点 → 相机空间并投影。返回 Vector3(屏幕x, 屏幕y, 相机空间深度)。
## 深度为负代表在相机后方 —— 这里**不**把它丢掉，而是照常算出投影值，
## 交给近裁剪面算法去插值裁剪，否则大偏航角下墙面会瞬间塌成一个点。
func _project(p: Vector3) -> Vector3:
	var dx := p.x - _x
	var dy := p.y
	var dz := p.z - _z
	var s := sin(_yaw)
	var c := cos(_yaw)
	var depth := dx * s + dz * c
	var right := dx * c - dz * s
	if absf(depth) < 0.02:
		depth = 0.02 if depth >= 0.0 else -0.02
	var sx := VIEW.x * 0.5 + right / depth * FOCAL
	var sy := HORIZON + dy / depth * FOCAL
	return Vector3(sx, sy, depth)


func _proj3(px: float, py: float, pz: float) -> Vector3:
	return _project(Vector3(px, py, pz))


func _proj2(px: float, py: float, pz: float) -> Vector2:
	var r := _project(Vector3(px, py, pz))
	return Vector2(r.x, r.y)


## Sutherland–Hodgman：把多边形对近裁剪面 (depth >= NEAR) 裁剪
func _clip_near(pts: Array, near: float = 2.0) -> PackedVector2Array:
	var out := PackedVector2Array()
	var n := pts.size()
	if n < 3:
		return out
	for i in n:
		var a: Vector3 = pts[i]
		var b: Vector3 = pts[(i + 1) % n]
		var a_in := a.z >= near
		var b_in := b.z >= near
		if a_in:
			out.append(Vector2(a.x, a.y))
		if a_in != b_in:
			var t := (near - a.z) / (b.z - a.z)
			out.append(Vector2(a.x + (b.x - a.x) * t, a.y + (b.y - a.y) * t))
	return out


# ---------------------------------------------------------------- 绘制

func _draw() -> void:
	draw_rect(Rect2(0, 0, VIEW.x, VIEW.y), Pal.bg, true)
	_rain.draw(self, Pal.main, 0.14)
	_draw_corridor()
	_draw_door()
	_draw_arms()
	_parts.draw_projected(self, _proj_particle)


## 供粒子系统使用的投影回调
func _proj_particle(px: float, py: float, pz: float) -> Vector3:
	return _project(Vector3(px, py, pz))


func _draw_corridor() -> void:
	var z0 := _z + 6.0
	var z1 := _z + 9000.0

	var floor_col := Pal.a(Pal.darken(Pal.grid, 0.45), 1.0)
	var ceil_col := Pal.a(Pal.darken(Pal.grid, 0.68), 1.0)
	var wall_col := Pal.a(Pal.darken(Pal.grid, 0.58), 1.0)

	_poly4(_proj3(-HW, HH, z0), _proj3(HW, HH, z0), _proj3(HW, HH, z1), _proj3(-HW, HH, z1), floor_col)
	_poly4(_proj3(-HW, -HH, z0), _proj3(HW, -HH, z0), _proj3(HW, -HH, z1), _proj3(-HW, -HH, z1), ceil_col)
	_poly4(_proj3(-HW, -HH, z0), _proj3(-HW, HH, z0), _proj3(-HW, HH, z1), _proj3(-HW, -HH, z1), wall_col)
	_poly4(_proj3(HW, -HH, z0), _proj3(HW, HH, z0), _proj3(HW, HH, z1), _proj3(HW, -HH, z1), wall_col)

	# 地板与天花的纵向分隔线（向灭点收束）
	var gcol := Pal.a(Pal.grid, 0.85)
	var gx := -HW
	while gx <= HW + 0.1:
		_line3(_proj3(gx, HH, z0), _proj3(gx, HH, _z + 2600.0), gcol, 1.0)
		_line3(_proj3(gx, -HH, z0), _proj3(gx, -HH, _z + 2600.0), Pal.a(Pal.grid, 0.4), 1.0)
		gx += HW / 4.0

	# 墙面竖向分隔线（近密远疏，靠投影天然得到这个效果）
	var zz := floorf(_z / 120.0) * 120.0
	var lcol := Pal.a(Pal.grid, 0.55)
	while zz < _z + 2600.0:
		if zz > _z + 8.0:
			_line3(_proj3(-HW, -HH, zz), _proj3(-HW, HH, zz), lcol, 1.0)
			_line3(_proj3(HW, -HH, zz), _proj3(HW, HH, zz), lcol, 1.0)
			# 地板横向网格
			_line3(_proj3(-HW, HH, zz), _proj3(HW, HH, zz), Pal.a(Pal.grid, 0.42), 1.0)
		zz += 120.0

	# 走廊中段的发光环，强化纵深。
	# 注意别用整圈贴边的半径 —— 投影后会变成一圈横跨全屏的亮线，像镜头污点。
	# 收小到走廊横截面的六成左右，才是「通道一层层收进去」的感觉。
	var ring_z := _z + 420.0
	if ring_z < DOOR_Z - 200.0:
		for spec in [[0.60, 0.20, 1.0], [0.80, 0.11, 1.0]]:
			var rr: float = float(spec[0])
			var ra: float = float(spec[1])
			var rw: float = float(spec[2])
			var rc := Pal.a(Pal.main, ra)
			var pts := PackedVector2Array()
			var n := 36
			for i in n + 1:
				var a := float(i) / float(n) * TAU
				pts.append(_proj2(cos(a) * HW * rr, sin(a) * HH * rr, ring_z))
			if pts.size() >= 2:
				draw_polyline(pts, rc, rw)

	# 尽头之外的暗背景，避免远处出现空洞
	var c := _proj2(0.0, 0.0, _z + 6000.0)
	draw_rect(Rect2(c.x - 2.0, c.y - 2.0, 4.0, 4.0), Pal.a(Pal.darken(Pal.grid, 0.75), 1.0), true)


## 画一条三维线段，同时做近裁剪 —— 否则大偏航角下会甩出错误的射线
func _line3(a: Vector3, b: Vector3, col: Color, w: float) -> void:
	var near := 2.0
	var a_in := a.z >= near
	var b_in := b.z >= near
	if not a_in and not b_in:
		return
	var pa := Vector2(a.x, a.y)
	var pb := Vector2(b.x, b.y)
	if a_in != b_in:
		var t := (near - a.z) / (b.z - a.z)
		var ip := Vector2(a.x + (b.x - a.x) * t, a.y + (b.y - a.y) * t)
		if a_in:
			pb = ip
		else:
			pa = ip
	draw_line(pa, pb, col, w)


func _poly4(a: Vector3, b: Vector3, c: Vector3, d: Vector3, col: Color) -> void:
	var pts := _clip_near([a, b, c, d], 2.0)
	if pts.size() < 3:
		return
	var cols := PackedColorArray()
	for i in pts.size():
		cols.append(col)
	draw_polygon(pts, cols)


func _draw_door() -> void:
	var dw := 96.0
	var dh := 142.0
	var p0 := _proj2(-dw, -dh, DOOR_Z)
	var p1 := _proj2(dw, -dh, DOOR_Z)
	var p2 := _proj2(dw, dh, DOOR_Z)
	var p3 := _proj2(-dw, dh, DOOR_Z)
	if absf(p0.x - p1.x) < 1.0 and absf(p0.y - p3.y) < 1.0:
		return

	var pulse := 0.5 + 0.5 * sin(_door_pulse * 3.0)
	var glow := 0.55 + 0.45 * pulse + _door_charge * 0.45

	# 门内：由字符组成的流动面
	var mono := Assets.mono_font()
	var cols := 7
	var rows := 11
	for ix in cols:
		for iy in rows:
			var fx := lerpf(-dw + 6.0, dw - 6.0, float(ix) / float(cols - 1))
			var fy := lerpf(-dh + 8.0, dh - 8.0, float(iy) / float(rows - 1))
			var sp := _proj2(fx, fy, DOOR_Z)
			var wob := sin(_door_pulse * 2.2 + float(ix) * 0.7 + float(iy) * 1.3)
			var ch := CodeParticles.GLYPHS.substr(
				(ix * 5 + iy * 11 + int(_door_pulse * 9.0)) % CodeParticles.GLYPHS.length(), 1)
			var a := clampf((0.35 + 0.45 * wob + _door_charge * 0.4), 0.05, 1.0) * glow
			var sz := clampi(int(14.0 * FOCAL / maxf(1.0, DOOR_Z - _z) * 1.6), 9, 44)
			draw_char(mono, Vector2(sp.x - sz * 0.3, sp.y + sz * 0.35), ch, sz,
				Pal.a(Pal.lighten(Pal.main, 0.45), a * 0.85))

	# 门框
	var frame := PackedVector2Array([p0, p1, p2, p3])
	draw_polyline(PackedVector2Array([p0, p1, p2, p3, p0]),
		Pal.a(Pal.lighten(Pal.main, 0.55), clampf(0.7 + 0.3 * pulse, 0.0, 1.0)), 3.0)
	# 外扩光晕（用几层放大的矩形近似）
	var ctr := (p0 + p2) * 0.5
	var hw := absf(p1.x - p0.x) * 0.5
	var hh2 := absf(p3.y - p0.y) * 0.5
	for k in 3:
		var g := 1.0 + float(k + 1) * 0.28
		draw_rect(Rect2(ctr.x - hw * g, ctr.y - hh2 * g, hw * 2.0 * g, hh2 * 2.0 * g),
			Pal.a(Pal.main, 0.05 * glow * (1.0 - float(k) * 0.28)), false, 2.0)
	# 中央能量核
	draw_circle(ctr, 5.0 + pulse * 4.0 + _door_charge * 6.0,
		Pal.a(Pal.lighten(Pal.main, 0.7), 0.5 * glow))

	# 距离读数
	if hw > 3.0:
		var title := Assets.title_font()
		var label := "CODE GATE  %03d" % int(maxf(0.0, DOOR_Z - _z))
		Tx.center(self, title, ctr.x, p0.y - 14.0, label, 16, Pal.a(Pal.lighten(Pal.main, 0.3), 0.55))


## 第一人称手臂与拳头。全部程序化，不依赖素材。
## 刻意做得很轻：这里的主角是走廊和门，手臂只是个「我在场」的暗示，
## 做亮做重会变成一坨白色方块，反而破坏空灵感。
func _draw_arms() -> void:
	var w := VIEW.x
	var h := VIEW.y
	var sway := sin(_bob) * (5.0 + _speed_now * 0.010)
	var rise := cos(_bob * 2.0) * (2.0 + _speed_now * 0.003)
	var dark := Pal.darken(Pal.main, 0.78)

	for s in [-1.0, 1.0]:
		var side: float = float(s)
		var steps := 18
		for i in steps:
			var k := float(i) / float(steps - 1)
			var px := lerpf(w * 0.5 + side * 136.0, w * 0.5 + side * 32.0, k) + sway * k * 1.6
			var py := lerpf(h + 26.0 + rise, h * 0.80 + rise * 0.5, k)
			var sz := lerpf(40.0, 21.0, k)
			var col := dark.lerp(Pal.main, k * 0.30)
			col.a = 0.30 + 0.18 * k
			draw_rect(Rect2(px - sz * 0.5, py - sz * 0.5, sz, sz * 0.9), col, true)
			# 手背上一道很淡的数据纹路
			if i % 5 == 0:
				draw_rect(Rect2(px - sz * 0.5, py - sz * 0.5, sz, 1.0),
					Pal.a(Pal.lighten(Pal.main, 0.4), 0.10), true)

	# 右拳：收到最低调，只留一个轮廓
	var fx := w * 0.5 + 40.0 + sway
	var fy := h * 0.815 + rise * 0.5
	var fsz := 26.0
	var fcol := dark.lerp(Pal.main, 0.22)
	fcol.a = 0.42
	draw_rect(Rect2(fx - fsz * 0.5, fy - fsz * 0.5, fsz, fsz), fcol, true)
	draw_rect(Rect2(fx - fsz * 0.5, fy - fsz * 0.5, fsz, fsz), Pal.a(Pal.main, 0.20), false, 1.0)


# ---------------------------------------------------------------- HUD

func _draw_hud(ci: CanvasItem) -> void:
	var w := VIEW.x
	var h := VIEW.y

	# 不显示阶段名、距离读数、偏航角、按键说明 —— 玩家只需要看见「前面有扇门」。
	# 准星也收成四个极短的刻度，像还没聚焦的视点。
	var cx := w * 0.5
	var cy := HORIZON
	var rc := Pal.a(Pal.main, 0.26 + 0.34 * _door_charge)
	ci.draw_line(Vector2(cx - 11, cy), Vector2(cx - 6, cy), rc, 1.0)
	ci.draw_line(Vector2(cx + 6, cy), Vector2(cx + 11, cy), rc, 1.0)
	ci.draw_line(Vector2(cx, cy - 11), Vector2(cx, cy - 6), rc, 1.0)
	ci.draw_line(Vector2(cx, cy + 6), Vector2(cx, cy + 11), rc, 1.0)

	_whisper.draw(ci)

	# 扫描线 + 暗角，和其它阶段统一
	var a := 0.045 * Pal.scan
	var y := 0.0
	while y < h:
		ci.draw_rect(Rect2(0, y, w, 1), Color(0, 0, 0, a), true)
		y += 3.0
	_vignette(ci, w, h)

	# 走近门时的整体提亮
	if _door_charge > 0.0:
		ci.draw_rect(Rect2(0, 0, w, h), Pal.a(Pal.lighten(Pal.main, 0.6), 0.08 * _door_charge), true)

	# 白光转场
	if _st == St.FLASH or _st == St.DONE:
		ci.draw_rect(Rect2(0, 0, w, h), Pal.a(Color.WHITE, _flash), true)


func _vignette(ci: CanvasItem, w: float, h: float) -> void:
	var steps := 9
	for i in steps:
		var f := float(i) / float(steps)
		var a := 0.034 * (1.0 - f)
		var inset := f * 92.0
		ci.draw_rect(Rect2(inset, inset, w - inset * 2.0, 26.0), Color(0, 0, 0, a), true)
		ci.draw_rect(Rect2(inset, h - inset - 26.0, w - inset * 2.0, 26.0), Color(0, 0, 0, a), true)
		ci.draw_rect(Rect2(inset, inset, 26.0, h - inset * 2.0), Color(0, 0, 0, a), true)
		ci.draw_rect(Rect2(w - inset - 26.0, inset, 26.0, h - inset * 2.0), Color(0, 0, 0, a), true)
