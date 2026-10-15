extends Node2D

## 阶段 1：平台跳跃教学关。
##
## 需求映射：
##   · 主角初始为侧躺昏迷，苏醒站起后向右探索
##   · 初始仅能左右移动
##   · 第一次坠落 → 化为代码粒子飘至预设重生点 → 悄悄浮出一句它自己的结论
##   · 远距离平台坠落 → 得出水平速度的结论；再次坠落 → 得出「跳跃不清速度」的结论
##   · 抵达关卡尽头 → 镜头平滑升至主角头顶 → 交接给上帝视角战斗
##
## 文案原则：主角是人工智能。提示不写主语（既不用「我」，也不用「它」），
## 不用系统通知的口吻，读起来是它经历解体、重组之后自己推出来的一句话；
## 键位行单独用等宽字体给出「按哪个键 → 触发什么」。

signal finished
signal restart_requested

# ---------------------------------------------------------------- 常量

const VIEW := Vector2(960.0, 540.0)

const GRAVITY := 1450.0
const MAX_FALL := 980.0
const JUMP_V := -470.0        ## 滞空 = 2*470/1450 ≈ 0.648s
const WALK_SPEED := 155.0     ## 走跳射程 ≈ 100px
const RUN_SPEED := 320.0      ## 跑跳射程 ≈ 207px
const GROUND_ACCEL := 1600.0
const AIR_ACCEL := 1050.0
const FRICTION := 2300.0
const JUMP_CUT := 0.45
const COYOTE := 0.10
const JUMP_BUFFER := 0.12

const P_SIZE := Vector2(34.0, 88.0)

## 角色素材：32x64 一帧的图集，分层为 身体 + 服装 + 发型。
## 帧编号：图集 10 列 x 10 行，逐格扫描确认过的位置如下 ——
##   行2 = 侧视行走循环（10 帧）   行4 = 站立 / 起跳 / 下落   行5 列3 = 侧躺
## 换素材或改配色，只要这三个常量对得上，动作就能接上。
const HERO_SCALE := 2.3
const HERO_LAYERS := ["body_pale", "robe_gray", "hair_long_black"]
const HERO_WALK_ROW := 2
const HERO_WALK_COUNT := 10
const HERO_IDLE := Vector2i(0, 4)
const HERO_JUMP := Vector2i(1, 4)
const HERO_FALL := Vector2i(2, 4)
const HERO_LIE := Vector2i(3, 5)
## 物理固定步长。跳跃距离是靠「滞空时间 × 水平速度」倒推出来的，
## 如果直接用帧间隔积分，高帧率/低帧率下跳跃距离会飘，关卡数值就白算了。
const FIXED_DT := 1.0 / 60.0
const GROUND_Y := 380.0
const PLAT_H := 320.0
const DEATH_Y := 740.0
const LEVEL_END_X := 1580.0
const CAM_Y := 270.0

## 关卡平台：x + 宽度，顶面统一在 GROUND_Y。
## 缺口宽度是按「走跳射程 100px / 跑跳射程 207px」倒推的：
##   gap1 62  → 走跳可达，留 38px 容错（用来教跳跃）
##   gap2 70  → 走跳可达，留 30px 容错，比 gap1 紧一点
##   gap3 165 → 走跳必然够不到，必须跑跳（留 42px 容错）
const PLATFORMS := [
	{"x": 0.0, "w": 360.0},      # P1 苏醒平台
	{"x": 422.0, "w": 270.0},    # P2
	{"x": 762.0, "w": 264.0},    # P3
	{"x": 1191.0, "w": 450.0},   # P4 终点平台
]

## 三个关段的重生锚点
const ANCHORS := [150.0, 468.0, 808.0]

enum St { WAKE, PLAY, DISSOLVE, DRIFT, REGROUP, END_RISE, WIPE }

## 置 true 可打印跳跃/落地探针，用于排查关卡数值
const DEBUG_PROBE := false

# ---------------------------------------------------------------- 状态

var _st: int = St.WAKE
var _t: float = 0.0
var _st_t: float = 0.0

var _pos := Vector2.ZERO
var _vel := Vector2.ZERO
var _on_ground := false
var _facing := 1.0
var _coyote := 0.0
var _jump_buf := 0.0
var _jump_was_down := false
var _run_was_down := false
var _probe := 0
var _last_plat := 0
var _fall_count := [0, 0, 0]

var _can_jump := false
var _can_run := false
var _hinted_jump := false
var _hinted_run := false
var _refuse_flash := 0.0

var _anim_t := 0.0
var _foot_t := 0.0
var _accum := 0.0
var _world_squash := 1.0
var _visor_blend := 0.0
var _wipe: float = 0.0
## 收尾只允许发一次 finished，否则每帧都发会让主状态机连跳好几个阶段
var _done: bool = false

var _wake_roll := 0.0
var _wake_bob := 0.0
var _die_flash := 0.0
var _spawn_flash := 0.0

var _cam: Camera2D = null
var _cam_x := 480.0
var _cam_y := CAM_Y
var _cam_zoom := 1.0
var _world: DrawProxy = null
var _hud: DrawProxy = null

var _rain: CodeRain = null
var _parts: CodeParticles = null
var _whisper: Whisper = null
## 开场从黑场缓慢淡入（承接开始界面的渐黑）
var _fade_in: float = 1.0


func _ready() -> void:
	Pal.set_phase(&"teach", 3.0)
	Sfx.music("teach", 5.0)

	_parts = CodeParticles.new()
	_rain = CodeRain.new()
	_rain.setup(VIEW.x, VIEW.y, 52.0, 13)
	_rain.set_speed_scale(0.18)
	_whisper = Whisper.new()

	_cam = Camera2D.new()
	_cam.position = Vector2(_cam_x, _cam_y)
	_cam.zoom = Vector2.ONE
	add_child(_cam)
	_cam.make_current()

	_world = DrawProxy.new()
	_world.fn = _draw_world
	add_child(_world)

	var layer := CanvasLayer.new()
	layer.layer = 10
	add_child(layer)
	_hud = DrawProxy.new()
	_hud.fn = _draw_hud
	layer.add_child(_hud)

	_reset_player(ANCHORS[0])
	_st = St.WAKE
	_st_t = 0.0
	_wake_roll = 1.0


func _reset_player(x: float) -> void:
	_pos = Vector2(x, GROUND_Y - P_SIZE.y * 0.5)
	_vel = Vector2.ZERO
	_on_ground = true
	_facing = 1.0


# ---------------------------------------------------------------- 主循环

func _process(delta: float) -> void:
	_t += delta
	_refuse_flash = maxf(0.0, _refuse_flash - delta)
	_die_flash = maxf(0.0, _die_flash - delta * 2.4)
	_spawn_flash = maxf(0.0, _spawn_flash - delta * 2.0)
	_rain.update(delta)
	_parts.update(delta)
	_whisper.update(delta)
	_fade_in = maxf(0.0, _fade_in - delta / 3.4)

	# 逻辑用固定步长推进，视觉与相机用真实 delta
	_accum = minf(_accum + delta, 0.25)
	while _accum >= FIXED_DT:
		_accum -= FIXED_DT
		_tick_fixed(FIXED_DT)

	_update_camera(delta)
	_cam.position = Vector2(_cam_x, _cam_y)
	_cam.zoom = Vector2(_cam_zoom, _cam_zoom)
	_world.redraw()
	_hud.redraw()
	queue_redraw()


func _tick_fixed(dt: float) -> void:
	_st_t += dt
	match _st:
		St.WAKE:
			_tick_wake(dt)
		St.PLAY:
			_tick_play(dt)
		St.DISSOLVE:
			_tick_dissolve(dt)
		St.DRIFT:
			_tick_drift(dt)
		St.REGROUP:
			_tick_regroup(dt)
		St.END_RISE:
			_tick_end_rise(dt)
		St.WIPE:
			_tick_wipe(dt)


func _set_state(s: int) -> void:
	_st = s
	_st_t = 0.0


# ---------------------------------------------------------------- 苏醒

func _tick_wake(delta: float) -> void:
	# 苏醒被刻意拉得很长：侧躺 → 撑起 → 站定，全程约 6 秒
	if _st_t < 2.6:
		_wake_roll = 1.0
	elif _st_t < 5.4:
		_wake_roll = 1.0 - _ease_out_cubic((_st_t - 2.6) / 2.8)
	else:
		_wake_roll = 0.0
	_wake_bob = sin(_t * 9.0) * 0.5 * maxf(0.0, _wake_roll)

	# 侧躺期间身上明灭的代码碎片
	if _wake_roll > 0.35 and randf() < delta * 12.0:
		_parts.spawn({
			"x": _pos.x + randf_range(-22.0, 22.0),
			"y": GROUND_Y - randf_range(4.0, 34.0),
			"kind": CodeParticles.KIND_CHAR,
			"vx": randf_range(-8.0, 8.0), "vy": randf_range(-30.0, -10.0),
			"drag": 1.1, "life": randf_range(0.9, 1.9), "size": 13.0, "end_size": 9.0,
			"color": Pal.a(Pal.main, 0.6), "fade_pow": 1.4,
		})

	if _st_t >= 5.6 and _whisper.empty():
		_whisper.say("能去的地方，只有左右两侧", {
			"keys": "A / D 键 → 向左 / 向右移动",
			"hold": 3.6,
		})
	if _st_t >= 8.2:
		_set_state(St.PLAY)


# ---------------------------------------------------------------- 操作

func _tick_play(delta: float) -> void:
	var dir := 0.0
	if Input.is_action_pressed("move_left"):
		dir -= 1.0
	if Input.is_action_pressed("move_right"):
		dir += 1.0

	var want_run := Input.is_action_pressed("run")
	# 用自维护的上升沿而不是 is_action_just_pressed：
	# 后者依赖引擎内部的按键帧记录，程序化输入（自动化测试）下会漏触发。
	var run_down := want_run
	var run_edge := run_down and not _run_was_down
	_run_was_down = run_down
	if run_edge and not _can_run and dir != 0.0 and not _hinted_run:
		_hinted_run = true
		_refuse_flash = 1.0
		Sfx.play("error", -30.0)
	var running := _can_run and want_run and dir != 0.0

	var target := dir * (RUN_SPEED if running else WALK_SPEED)
	var accel := GROUND_ACCEL if _on_ground else AIR_ACCEL
	if dir != 0.0:
		_vel.x = move_toward(_vel.x, target, accel * delta)
		_facing = dir
	else:
		_vel.x = move_toward(_vel.x, 0.0, (FRICTION if _on_ground else FRICTION * 0.3) * delta)

	_jump_buf = maxf(0.0, _jump_buf - delta)
	var jump_down := Input.is_action_pressed("jump")
	var jump_edge := jump_down and not _jump_was_down
	var jump_release := (not jump_down) and _jump_was_down
	_jump_was_down = jump_down
	if jump_edge:
		if _can_jump:
			_jump_buf = JUMP_BUFFER
		elif not _hinted_jump:
			_hinted_jump = true
			_refuse_flash = 1.0
			Sfx.play("error", -30.0)
	if _jump_buf > 0.0 and _coyote > 0.0:
		_vel.y = JUMP_V
		_jump_buf = 0.0
		_coyote = 0.0
		_on_ground = false
		if DEBUG_PROBE:
			print("[GAME] 跳跃 @ x=%.1f y=%.1f" % [_pos.x, _pos.y])
		_probe = 46
		Sfx.play_varied("jump", -12.0, 0.08)
		_parts.burst_at(_pos + Vector2(0, P_SIZE.y * 0.5), 10, {
			"kind": CodeParticles.KIND_RECT, "speed": 90.0, "drag": 3.0,
			"life": 0.42, "size": 4.0, "end_size": 0.0, "color": Pal.a(Pal.accent, 0.8),
		})
	if jump_release and _vel.y < 0.0:
		_vel.y *= JUMP_CUT

	_move_and_collide(delta)

	if _probe > 0:
		_probe -= 1
		print("[GAME]   . x=%.1f y=%.1f vx=%.1f vy=%.1f gnd=%s" % [
			_pos.x, _pos.y, _vel.x, _vel.y, str(_on_ground)])

	var was_air := not _on_ground
	if _on_ground:
		_coyote = COYOTE
		if was_air:
			_land_effect()
			Sfx.play_varied("land", -16.0)
	else:
		_coyote = maxf(0.0, _coyote - delta)

	if _on_ground and absf(_vel.x) > 20.0:
		_foot_t -= delta * absf(_vel.x) / 130.0
		if _foot_t <= 0.0:
			_foot_t = 0.42
			Sfx.play_varied("footstep", -26.0, 0.15)

	_anim_t += delta * (absf(_vel.x) / 70.0)
	if _on_ground and absf(_vel.x) > 8.0 and randf() < delta * 14.0:
		_parts.spawn({
			"x": _pos.x + randf_range(-10.0, 10.0), "y": GROUND_Y - 2.0,
			"kind": CodeParticles.KIND_RECT, "vx": randf_range(-20.0, 20.0),
			"vy": randf_range(-40.0, -10.0), "drag": 2.0, "life": 0.4, "size": 3.0,
			"color": Pal.a(Pal.main, 0.55),
		})

	if _pos.y - P_SIZE.y * 0.5 > DEATH_Y:
		_start_death()

	if _pos.x >= LEVEL_END_X and _on_ground:
		_start_end_rise()


func _move_and_collide(delta: float) -> void:
	_vel.y = minf(MAX_FALL, _vel.y + GRAVITY * delta)
	var half := P_SIZE * 0.5
	var prev_bottom := _pos.y + half.y

	_pos.x += _vel.x * delta
	if _pos.x - half.x < 0.0:
		_pos.x = half.x
		_vel.x = 0.0

	_pos.y += _vel.y * delta
	_on_ground = false
	if _vel.y >= 0.0:
		var bottom := _pos.y + half.y
		for i in PLATFORMS.size():
			var p: Dictionary = PLATFORMS[i]
			var px: float = p["x"]
			var pw: float = p["w"]
			if _pos.x + half.x > px and _pos.x - half.x < px + pw:
				if prev_bottom <= GROUND_Y + 1.0 and bottom >= GROUND_Y:
					_pos.y = GROUND_Y - half.y
					_vel.y = 0.0
					_on_ground = true
					_last_plat = i
					if DEBUG_PROBE:
						print("[GAME] 落地 @ x=%.1f 平台%d" % [_pos.x, i])
					break


func _land_effect() -> void:
	_parts.burst_at(Vector2(_pos.x, GROUND_Y - 2.0), 12, {
		"kind": CodeParticles.KIND_RECT, "speed": 110.0, "angle": PI * 0.5,
		"drag": 3.4, "life": 0.4, "size": 4.0, "end_size": 0.0,
		"color": Pal.a(Pal.main, 0.75),
	})
	for i in 5:
		_parts.spawn({
			"x": _pos.x + randf_range(-14.0, 14.0), "y": GROUND_Y - 1.0,
			"kind": CodeParticles.KIND_CHAR, "vx": randf_range(-70.0, 70.0),
			"vy": randf_range(-60.0, -10.0), "drag": 2.4, "life": 0.5, "size": 13.0,
			"color": Pal.a(Pal.text, 0.6),
		})


# ---------------------------------------------------------------- 死亡与重生

func _start_death() -> void:
	_set_state(St.DISSOLVE)
	_die_flash = 1.0
	Pal.glitch = 0.6
	Sfx.play("dissolve", -8.0)
	Sfx.play("death", -10.0)

	var rect := Rect2(_pos.x - P_SIZE.x * 0.5, _pos.y - P_SIZE.y * 0.5, P_SIZE.x, P_SIZE.y)
	_parts.burst_from_rect(rect, 44, {
		"kind": CodeParticles.KIND_CHAR,
		"vx": 0.0, "vy": 0.0, "drag": 0.9,
		"life": 2.4, "size": 14.0, "end_size": 11.0,
		"color": Pal.a(Pal.lighten(Pal.main, 0.35), 0.95),
		"fade_pow": 1.1,
	})
	_parts.burst_at(_pos, 22, {
		"kind": CodeParticles.KIND_RECT, "speed": 130.0, "drag": 2.6,
		"life": 0.8, "size": 5.0, "end_size": 0.0, "color": Pal.a(Pal.accent, 0.9),
	})


func _tick_dissolve(delta: float) -> void:
	if fmod(_st_t, 0.09) < delta:
		_parts.spawn({
			"x": _pos.x + randf_range(-18.0, 18.0), "y": _pos.y + randf_range(-22.0, 22.0),
			"kind": CodeParticles.KIND_CHAR, "vy": randf_range(-40.0, -12.0),
			"drag": 0.9, "life": randf_range(1.8, 2.6), "size": 14.0,
			"color": Pal.a(Pal.main, 0.9),
		})
	if _st_t >= 1.1:
		_set_state(St.DRIFT)


func _tick_drift(delta: float) -> void:
	if fmod(_st_t, 0.16) < delta:
		_parts.spawn({
			"x": _pos.x + randf_range(-30.0, 30.0), "y": _pos.y + randf_range(-10.0, 30.0),
			"kind": CodeParticles.KIND_SPRITE, "tex": Assets.particle("spark_03"),
			"vy": randf_range(-60.0, -25.0), "drag": 0.8,
			"life": randf_range(0.7, 1.2), "size": randf_range(10.0, 22.0), "end_size": 0.0,
			"color": Pal.a(Pal.accent, 0.55), "spin": randf_range(-3.0, 3.0),
		})
	if _st_t >= 1.9:
		_regroup_start()


func _regroup_start() -> void:
	_set_state(St.REGROUP)
	var anchor := _anchor_for(_last_plat)
	var seg := _seg_for(_last_plat)
	_fall_count[seg] += 1
	_reset_player(anchor)

	# 让飘散的字符粒子全部聚向重生点
	var half := P_SIZE * 0.5
	_parts.seek_active_to(52, func() -> Vector2:
		return Vector2(
			anchor + randf_range(-half.x, half.x),
			GROUND_Y - half.y + randf_range(-half.y, half.y)), 5.6, 0.18)

	# 再从锚点上方补一批，保证「重组」有足够的料
	for k in 30:
		_parts.spawn({
			"x": anchor + randf_range(-90.0, 90.0),
			"y": GROUND_Y - randf_range(40.0, 150.0),
			"kind": CodeParticles.KIND_CHAR,
			"tx": anchor + randf_range(-half.x, half.x),
			"ty": GROUND_Y - half.y + randf_range(-half.y, half.y),
			"seek": 5.0, "seek_delay": randf_range(0.0, 0.3),
			"life": randf_range(0.7, 1.1), "size": 14.0, "end_size": 10.0,
			"color": Pal.a(Pal.lighten(Pal.main, 0.3), 0.95),
		})

	_emit_fall_hint(seg)


func _tick_regroup(delta: float) -> void:
	if _st_t >= 1.6 and _spawn_flash <= 0.0:
		_spawn_flash = 1.0
		Pal.flash = 0.22
		_parts.burst_at(Vector2(_pos.x, GROUND_Y - P_SIZE.y * 0.5), 18, {
			"kind": CodeParticles.KIND_RECT, "speed": 100.0, "drag": 3.0,
			"life": 0.55, "size": 4.0, "end_size": 0.0, "color": Pal.a(Pal.main, 0.85),
		})
	if _st_t >= 2.5:
		_set_state(St.PLAY)


func _anchor_for(plat: int) -> float:
	if plat <= 0:
		return ANCHORS[0]
	if plat == 1:
		return ANCHORS[1]
	return ANCHORS[2]


func _seg_for(plat: int) -> int:
	if plat <= 0:
		return 0
	if plat == 1:
		return 1
	return 2


## 弱引导：不报「已习得」，也不用系统通知的口吻。
## 只给一句很短、很像自言自语的话，够玩家自己琢磨出来就行。
func _emit_fall_hint(seg: int) -> void:
	var n: int = _fall_count[seg]
	if seg == 0 and n == 1:
		_can_jump = true
		Sfx.play("unlock", -18.0)
		_whisper.say("解体之后，有一段位移没有被抹掉", {
			"keys": "空格键 → 向上跃起",
			"hold": 4.8,
		})
	elif seg == 1:
		if n <= 2:
			_whisper.say("在边缘停下，距离不会自己缩短", {
				"keys": "空格键 → 向上跃起",
				"hold": 4.2,
			})
	elif seg == 2 and n == 1:
		_can_run = true
		Sfx.play("unlock", -18.0)
		_whisper.say("同样的起跳，落点由离开地面时的水平速度决定", {
			"keys": "按住 Shift 键 → 奔跑，水平速度持续上升",
			"hold": 5.0,
		})
	elif seg == 2 and n >= 2:
		Sfx.play("confirm", -22.0)
		_whisper.say("跳跃不会抹掉奔跑的速度", {
			"keys": "Shift 键长按助跑 + 空格键 → 起跳，飞得更远",
			"hold": 5.4,
		})


# ---------------------------------------------------------------- 交接给战斗

func _start_end_rise() -> void:
	_set_state(St.END_RISE)
	_vel = Vector2.ZERO
	Sfx.play("confirm", -20.0)


func _tick_end_rise(delta: float) -> void:
	var k := clampf(_st_t / 2.4, 0.0, 1.0)
	var e := _ease_in_out(k)
	# 镜头从主角身侧平滑升到头顶上方。这一段特意拖长，让「视角变了」这件事慢慢发生。
	_cam_y = lerpf(CAM_Y, -150.0, e)
	_cam_zoom = lerpf(1.0, 0.86, e)
	_world_squash = lerpf(1.0, 0.06, _ease_in_out(clampf((_st_t - 0.85) / 1.5, 0.0, 1.0)))
	_visor_blend = clampf((_st_t - 1.35) / 0.95, 0.0, 1.0)
	if _st_t >= 3.6:
		_set_state(St.WIPE)
		Pal.glitch = 0.7
		Sfx.play("white_out", -20.0)


func _tick_wipe(delta: float) -> void:
	_wipe = clampf(_st_t / 1.5, 0.0, 1.0)
	# 收尾只允许发一次 finished，否则每帧都发会让主状态机连跳好几个阶段
	if _st_t >= 1.5 and not _done:
		_done = true
		emit_signal("finished")


# ---------------------------------------------------------------- 镜头

func _update_camera(delta: float) -> void:
	if _st == St.END_RISE or _st == St.WIPE:
		return
	var target_x := clampf(_pos.x, VIEW.x * 0.5, 1700.0 - VIEW.x * 0.5)
	_cam_x = lerpf(_cam_x, target_x, 1.0 - pow(0.0015, delta))
	_cam_y = CAM_Y
	_cam_zoom = 1.0


# ---------------------------------------------------------------- 世界绘制

func _draw_world(ci: CanvasItem) -> void:
	var sy := maxf(0.02, _world_squash)
	ci.draw_set_transform(Vector2(0.0, GROUND_Y * (1.0 - sy)), 0.0, Vector2(1.0, sy))

	# 数据空间底纹：青色网格。靠近地面最清晰，往上淡出 ——
	# 让场景一眼读起来是「代码构成的空间」，而不是一片黑。
	var cy := GROUND_Y
	while cy > -240.0:
		var f := clampf(1.0 - (GROUND_Y - cy) / (GROUND_Y + 240.0), 0.0, 1.0)
		ci.draw_rect(Rect2(-400.0, cy, 2600.0, 1.0), Pal.a(Pal.grid, 0.05 + 0.24 * f), true)
		cy -= 52.0
	var cx := -384.0
	while cx < 2112.0:
		var vy := GROUND_Y
		while vy > -240.0:
			var f2 := clampf(1.0 - (GROUND_Y - vy) / (GROUND_Y + 240.0), 0.0, 1.0)
			ci.draw_rect(Rect2(cx, vy, 1.0, 52.0), Pal.a(Pal.grid, 0.05 + 0.20 * f2), true)
			vy -= 52.0
		cx += 64.0

	# 地形不再是草地：改成「悬浮的数据平台」，越往下越化进雾里。
	# 这是空灵感的关键 —— 物体没有明确的底边，而是消失在雾中。
	# 表面纹理全部程序化绘制，不再引用草地贴图 ——
	# Kenney 的 grass 是绿色，即使乘以青色调，绿通道仍压过蓝通道，
	# 远看会在顶面留一条发绿的边，和整体色相反着来。
	var top_h := 70.0

	for i in PLATFORMS.size():
		var p: Dictionary = PLATFORMS[i]
		var px: float = p["x"]
		var pw: float = p["w"]

		# 石板下方向上扩散的微光，让它看起来是浮着的
		var halo := Pal.a(Pal.main, 0.045)
		ci.draw_rect(Rect2(px - 18.0, GROUND_Y + 6.0, pw + 36.0, PLAT_H + 60.0), halo, true)

		# 底板：向下逐段变暗，最后完全融进背景
		var segs := 16
		for s in segs:
			var f := float(s) / float(segs - 1)
			var y := GROUND_Y + f * float(PLAT_H)
			var hh := float(PLAT_H) / float(segs) + 1.0
			var a := (1.0 - f * f) * 0.85
			var col := Pal.darken(Pal.sky, 0.35)
			col.a = a
			ci.draw_rect(Rect2(px, y, pw, hh), col, true)

		# 表面纹理：等距扫描线 + 断续短刻痕，色相完全跟着平台走
		var ty := GROUND_Y + 4.0
		while ty < GROUND_Y + top_h:
			var tf := 1.0 - (ty - GROUND_Y) / top_h
			ci.draw_rect(Rect2(px, ty, pw, 1.0), Pal.a(Pal.grid, 0.10 + 0.26 * tf), true)
			ty += 8.0
		var dx := px + 12.0
		while dx < px + pw - 20.0:
			ci.draw_rect(Rect2(dx, GROUND_Y + 22.0, 16.0, 2.0), Pal.a(Pal.accent, 0.18), true)
			dx += 52.0

		# 顶面：一条细亮线，外加一层薄薄的辉光
		ci.draw_rect(Rect2(px, GROUND_Y - 1.0, pw, 1.0), Pal.a(Pal.lighten(Pal.main, 0.4), 0.80), true)
		ci.draw_rect(Rect2(px, GROUND_Y, pw, 3.0), Pal.a(Pal.main, 0.12), true)
		# 顶面往下 12px 的承光带，让平台有厚度而不是一条线
		ci.draw_rect(Rect2(px, GROUND_Y + 4.0, pw, 12.0), Pal.a(Pal.lighten(Pal.main, 0.1), 0.10), true)

		# 平台的「数据柱」：从顶面向下延伸的青色细线，密度均匀、越往下越淡
		var dc := px + 16.0
		while dc < px + pw - 8.0:
			var dy := GROUND_Y + 6.0
			while dy < GROUND_Y + 138.0:
				var df := 1.0 - (dy - GROUND_Y) / 138.0
				ci.draw_rect(Rect2(dc, dy, 1.0, 13.0), Pal.a(Pal.main, 0.03 + 0.11 * df), true)
				dy += 26.0
			dc += 32.0

		# 极淡的横向刻痕，暗示它是「人造物」而非自然地形
		var gy := GROUND_Y + 22.0
		while gy < GROUND_Y + 150.0:
			var a2 := 0.06 * (1.0 - (gy - GROUND_Y) / 150.0)
			ci.draw_rect(Rect2(px + 6.0, gy, pw - 12.0, 1.0), Pal.a(Pal.grid, a2), true)
			gy += 26.0

	ci.draw_rect(Rect2(-400.0, GROUND_Y + PLAT_H, 2600.0, 900.0), Pal.a(Pal.bg, 0.96), true)


# ---------------------------------------------------------------- HUD 绘制

func _draw_hud(ci: CanvasItem) -> void:
	var w := VIEW.x
	var h := VIEW.y
	# 背景用极疏极慢的代码雨，只作为空气里的颗粒感，不抢主体
	_rain.draw(ci, Pal.main, 0.15)

	# 不再有阶段名、进度条、按键提示条 —— 弱引导要的是「什么都不说」
	_whisper.draw(ci)

	# 能力被拒绝时只给一次画面边缘的轻微呼吸，不给文字
	if _refuse_flash > 0.0:
		var a := clampf(_refuse_flash, 0.0, 1.0) * 0.10
		ci.draw_rect(Rect2(0, 0, w, 26), Pal.a(Pal.lighten(Pal.main, 0.4), a), true)
		ci.draw_rect(Rect2(0, h - 26, w, 26), Pal.a(Pal.lighten(Pal.main, 0.4), a), true)

	if _die_flash > 0.0:
		ci.draw_rect(Rect2(0, 0, w, h), Pal.a(Pal.main, 0.12 * _die_flash), true)
	if _spawn_flash > 0.0:
		ci.draw_rect(Rect2(0, 0, w, h), Pal.a(Pal.lighten(Pal.main, 0.6), 0.14 * _spawn_flash), true)

	if Pal.glitch > 0.01:
		var n := int(Pal.glitch * 6.0)
		for i in n:
			var gy := randf() * h
			var gh := randf_range(2.0, 12.0)
			ci.draw_rect(Rect2(randf_range(-40.0, 60.0), gy, w, gh),
				Pal.a(Pal.lighten(Pal.main, 0.5), 0.07), true)

	if _st == St.WIPE:
		var k := _wipe
		ci.draw_rect(Rect2(0, 0, w, h), Pal.a(Pal.bg, k * k), true)
		var band := h * k
		ci.draw_rect(Rect2(0, h * 0.5 - band * 0.5, w, band),
			Pal.a(Pal.lighten(Pal.main, 0.7), 0.16 * k), true)

	_draw_scanlines(ci)

	# 开场从黑场缓慢淡入（承接开始界面的渐黑），最后再压一层暗角
	if _fade_in > 0.001:
		ci.draw_rect(Rect2(0, 0, w, h), Color(0.0, 0.0, 0.0, minf(1.0, _fade_in)), true)
	_vignette(ci, w, h)


## 四边向内压暗，让画面四周「化掉」，是空灵感的重要来源
func _vignette(ci: CanvasItem, w: float, h: float) -> void:
	var steps := 9
	for i in steps:
		var f := float(i) / float(steps)
		var a := 0.031 * (1.0 - f)
		var inset := f * 92.0
		ci.draw_rect(Rect2(inset, inset, w - inset * 2.0, 26.0), Color(0, 0, 0, a), true)
		ci.draw_rect(Rect2(inset, h - inset - 26.0, w - inset * 2.0, 26.0), Color(0, 0, 0, a), true)
		ci.draw_rect(Rect2(inset, inset, 26.0, h - inset * 2.0), Color(0, 0, 0, a), true)
		ci.draw_rect(Rect2(w - inset - 26.0, inset, 26.0, h - inset * 2.0), Color(0, 0, 0, a), true)


func _draw_scanlines(ci: CanvasItem) -> void:
	var a := 0.025 * Pal.scan
	var y := 0.0
	while y < VIEW.y:
		ci.draw_rect(Rect2(0, y, VIEW.x, 1), Color(0, 0, 0, a), true)
		y += 3.0


# ---------------------------------------------------------------- 主角与粒子

func _draw() -> void:
	if _st == St.DISSOLVE:
		var k := 1.0 - clampf(_st_t / 0.5, 0.0, 1.0)
		if k > 0.0:
			draw_rect(Rect2(_pos.x - P_SIZE.x * 0.5, _pos.y - P_SIZE.y * 0.5, P_SIZE.x, P_SIZE.y),
				Pal.a(Pal.lighten(Pal.main, 0.7), 0.35 * k), true)
	elif _st != St.DRIFT:
		_draw_player()
	_parts.draw(self)


func _draw_player() -> void:
	var center := _pos
	var roll := _wake_roll * deg_to_rad(84.0)
	# 图集里角色脚底在帧底，把帧底对齐到碰撞盒底部
	var frame_center := Vector2(center.x, center.y + P_SIZE.y * 0.5 - Assets.HERO_FRAME.y * HERO_SCALE * 0.5)

	if _visor_blend > 0.05:
		var s := P_SIZE.x * 0.62
		var r := Rect2(center.x - s * 0.5, center.y - s * 0.5 + P_SIZE.y * 0.24, s, s)
		var c := Pal.main
		draw_rect(r, Pal.a(c, 0.45 * _visor_blend), true)
		draw_rect(r, Pal.a(Pal.lighten(c, 0.5), 0.85 * _visor_blend), false, 2.0)
		draw_rect(r.grow(3.0), Pal.a(c, 0.20 * _visor_blend), false, 1.0)

	if _visor_blend >= 0.99:
		return

	var mod := Pal.lighten(Pal.main, 0.30)
	mod.a = 1.0 - _visor_blend

	if roll != 0.0:
		# 侧躺 → 起身：整体绕自身旋转
		draw_set_transform(frame_center, -roll, Vector2.ONE)
		_draw_hero_layers_origin(HERO_LIE if _wake_roll > 0.75 else HERO_IDLE, mod)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	else:
		_draw_hero_layers(frame_center, _facing < 0.0, _hero_frame(), mod)

	# 接触阴影
	var shadow := Color(0, 0, 0, 0.42 * (1.0 - _visor_blend))
	draw_circle(Vector2(center.x, GROUND_Y - 1.0), 15.0, shadow)

	if _spawn_flash > 0.0:
		var rr := 26.0 * (1.0 - _spawn_flash) + 10.0
		draw_circle(Vector2(center.x, GROUND_Y - 2.0), rr,
			Pal.a(Pal.lighten(Pal.main, 0.5), 0.20 * _spawn_flash))


func _draw_hero_layers(center: Vector2, flip: bool, frame: Vector2i, mod: Color) -> void:
	draw_set_transform(center, 0.0, Vector2(-1.0 if flip else 1.0, 1.0))
	_draw_hero_layers_origin(frame, mod)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## 以原点为中心画三层。调用前自行设置好变换。
func _draw_hero_layers_origin(frame: Vector2i, mod: Color) -> void:
	var src := Assets.hero_frame(frame.x, frame.y)
	var size := Vector2(Assets.HERO_FRAME) * HERO_SCALE
	var rect := Rect2(-size.x * 0.5, -size.y * 0.5, size.x, size.y)
	for layer in HERO_LAYERS:
		var t := Assets.heroine(layer)
		if t != null:
			draw_texture_rect_region(t, rect, src, mod)
		else:
			# 素材缺失时的降级：一个细长的剪影
			draw_rect(Rect2(-size.x * 0.34, -size.y * 0.5, size.x * 0.68, size.y * 0.86),
				Pal.a(Pal.main, 0.7), true)


func _hero_frame() -> Vector2i:
	if _st == St.WAKE:
		return HERO_LIE if _wake_roll > 0.75 else HERO_IDLE
	if not _on_ground:
		return HERO_JUMP if _vel.y < 0.0 else HERO_FALL
	if absf(_vel.x) > 8.0:
		var n := HERO_WALK_COUNT
		return Vector2i(int(_anim_t) % n, HERO_WALK_ROW)
	return HERO_IDLE


# ---------------------------------------------------------------- 工具

func _ease_in_out(t: float) -> float:
	t = clampf(t, 0.0, 1.0)
	return 2.0 * t * t if t < 0.5 else 1.0 - pow(-2.0 * t + 2.0, 2.0) * 0.5


## 画一个「瞄准框」的四角括号
func _corner_brackets(r: Rect2, arm: float, col: Color, w: float) -> void:
	var tl := r.position
	var tr := Vector2(r.end.x, r.position.y)
	var br := r.end
	var bl := Vector2(r.position.x, r.end.y)
	draw_line(tl, tl + Vector2(arm, 0), col, w)
	draw_line(tl, tl + Vector2(0, arm), col, w)
	draw_line(tr, tr + Vector2(-arm, 0), col, w)
	draw_line(tr, tr + Vector2(0, arm), col, w)
	draw_line(br, br + Vector2(-arm, 0), col, w)
	draw_line(br, br + Vector2(0, -arm), col, w)
	draw_line(bl, bl + Vector2(arm, 0), col, w)
	draw_line(bl, bl + Vector2(0, -arm), col, w)


func _ease_out_cubic(t: float) -> float:
	t = clampf(t, 0.0, 1.0)
	return 1.0 - pow(1.0 - t, 3.0)
