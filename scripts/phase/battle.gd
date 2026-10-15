extends Node2D

## 阶段 2：上帝视角战斗。
##
## 需求映射：
##   · 镜头平滑升至主角头顶后切换为正俯视，四周持续生成「代码马赛克」敌人
##   · 敌人从多方向围攻；主角被碰到即死（一击必死）
##   · 第一次死亡 → 浮出它自己的结论，并明确写出「鼠标左键 → 朝光标方向挥出」
##     （不用「握紧拳头」这类动作形容，直接说清按哪个键、会发生什么）
##   · 三波共约 15 只，全灭后镜头平移至代码门，停 2 秒再回到主角 → 交接给第一人称

signal finished
signal restart_requested

const VIEW := Vector2(960.0, 540.0)

## 竞技场比屏幕大，镜头才有「平移」的余量
const ARENA := Vector2(960.0, 1020.0)
const WALL := 26.0
const DOOR := Rect2(480.0 - 62.0, 150.0 - 86.0, 124.0, 172.0)

const PLAYER_SPAWN := Vector2(480.0, 700.0)
const PLAYER_HALF := 15.0
const PLAYER_SPEED := 205.0
const PLAYER_ACCEL := 1500.0
const PLAYER_FRICTION := 2000.0

const WAVES := [4, 5, 6]
const ENEMY_HALF := 13.0
const ENEMY_SPEED_MIN := 62.0
const ENEMY_SPEED_MAX := 104.0
const SPAWN_TELEGRAPH := 0.85
## 固定步长：保证不同帧率下移动速度与碰撞判定一致
const FIXED_DT := 1.0 / 60.0

const ATK_RANGE := 52.0
const ATK_REACH := 34.0        ## 拳心相对角色的前伸距离
const ATK_CHARGE := 0.16
const ATK_ACTIVE := 0.12
const ATK_COOLDOWN := 0.40

enum St { FIGHT, DYING, CAM_DOOR, DOOR_WAIT, CAM_BACK, DIVE, DONE }

var _st: int = St.FIGHT
var _t: float = 0.0
var _st_t: float = 0.0
var _accum: float = 0.0

var _ppos := PLAYER_SPAWN
var _pvel := Vector2.ZERO
var _aim := Vector2.RIGHT
var _can_attack := false
var _atk_phase := 0     ## 0=空闲 1=蓄力 2=挥出
var _atk_t := 0.0
var _atk_cd := 0.0
var _atk_was_down := false
var _mouse_moved := false
var _died_once := false
var _death_count := 0
var _invuln := 0.0

var _enemies: Array = []
var _spawn_queue: Array = []
var _wave: int = 0
var _wave_cd: float = 0.0
var _killed: int = 0
var _total := 0
var _alive := false
## 同上：收尾信号必须只发一次
var _done: bool = false

var _cam: Camera2D = null
var _cam_pos := Vector2(480.0, 700.0)
var _cam_zoom := 1.0
var _cam_target := Vector2(480.0, 700.0)
var _cam_zoom_target := 1.0
var _cam_lerp := 2.2

var _flash := 0.0
var _hit_stop := 0.0
var _door_pulse := 0.0
var _victory_bloom := 0.0

var _world: DrawProxy = null
var _hud: DrawProxy = null
var _rain: CodeRain = null
var _parts: CodeParticles = null
var _whisper: Whisper = null
var _fx_layer: CanvasLayer = null


func _ready() -> void:
	Pal.set_phase(&"battle", 1.0)
	Sfx.music("battle", 1.6)

	_total = 0
	for w in WAVES:
		_total += int(w)

	_parts = CodeParticles.new()
	_rain = CodeRain.new()
	_rain.setup(VIEW.x, VIEW.y, 26.0, 14)
	_rain.set_speed_scale(1.35)
	_rain.head_glow = 0.9

	_whisper = Whisper.new()

	_cam = Camera2D.new()
	_cam.position = _cam_pos
	add_child(_cam)
	_cam.make_current()

	_world = DrawProxy.new()
	_world.fn = _draw_world
	add_child(_world)

	_fx_layer = CanvasLayer.new()
	_fx_layer.layer = 10
	add_child(_fx_layer)
	_hud = DrawProxy.new()
	_hud.fn = _draw_hud
	_fx_layer.add_child(_hud)

	_start_wave(0)


func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_mouse_moved = true


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_mouse_moved = true


# ---------------------------------------------------------------- 主循环

func _process(delta: float) -> void:
	# 命中定格：让挥拳有打击感
	if _hit_stop > 0.0:
		_hit_stop -= delta
		delta *= 0.15

	_t += delta
	_flash = maxf(0.0, _flash - delta * 2.6)
	_door_pulse += delta
	_rain.update(delta)
	_parts.update(delta)
	_whisper.update(delta)

	# 逻辑固定步长
	_accum = minf(_accum + delta, 0.25)
	while _accum >= FIXED_DT:
		_accum -= FIXED_DT
		_tick_fixed(FIXED_DT)

	_tick_camera(delta)
	_world.redraw()
	_hud.redraw()
	queue_redraw()


func _tick_fixed(dt: float) -> void:
	_st_t += dt
	match _st:
		St.FIGHT:
			_tick_fight(dt)
		St.DYING:
			_tick_dying(dt)
		St.CAM_DOOR:
			_tick_cam_door(dt)
		St.DOOR_WAIT:
			_tick_door_wait(dt)
		St.CAM_BACK:
			_tick_cam_back(dt)
		St.DIVE:
			_tick_dive(dt)
		St.DONE:
			pass


func _set_state(s: int) -> void:
	_st = s
	_st_t = 0.0


# ---------------------------------------------------------------- 战斗

func _tick_fight(delta: float) -> void:
	_alive = true
	_invuln = maxf(0.0, _invuln - delta)

	# ---- 移动（俯视四向：WASD）----
	var mv := Vector2.ZERO
	if Input.is_action_pressed("move_left"):
		mv.x -= 1.0
	if Input.is_action_pressed("move_right"):
		mv.x += 1.0
	if Input.is_action_pressed("move_up"):
		mv.y -= 1.0
	if Input.is_action_pressed("move_down"):
		mv.y += 1.0
	if mv.length() > 0.0:
		mv = mv.normalized()
		_pvel = _pvel.move_toward(mv * PLAYER_SPEED, PLAYER_ACCEL * delta)
	else:
		_pvel = _pvel.move_toward(Vector2.ZERO, PLAYER_FRICTION * delta)
	_ppos += _pvel * delta
	_ppos.x = clampf(_ppos.x, WALL + PLAYER_HALF, ARENA.x - WALL - PLAYER_HALF)
	_ppos.y = clampf(_ppos.y, WALL + PLAYER_HALF, ARENA.y - WALL - PLAYER_HALF)
	if _pvel.length() > 8.0 and randf() < delta * 18.0:
		_parts.spawn({
			"x": _ppos.x + randf_range(-10.0, 10.0), "y": _ppos.y + randf_range(-10.0, 10.0),
			"kind": CodeParticles.KIND_RECT, "vx": -_pvel.x * 0.12, "vy": -_pvel.y * 0.12,
			"drag": 3.0, "life": 0.4, "size": 3.5, "color": Pal.a(Pal.main, 0.6),
		})

	# ---- 瞄准 ----
	_update_aim()

	# ---- 攻击 ----
	_atk_cd = maxf(0.0, _atk_cd - delta)
	var atk_down := Input.is_action_pressed("attack")
	var atk_edge := atk_down and not _atk_was_down
	_atk_was_down = atk_down
	if _atk_phase == 0:
		if atk_edge and _can_attack and _atk_cd <= 0.0:
			_atk_phase = 1
			_atk_t = 0.0
			Sfx.play("punch_swing", -10.0)
			# 从身体抽离代码流向拳头 —— 需求里的「聚集自身代码在拳头上」
			var fist := _ppos + _aim * ATK_REACH
			for i in 16:
				_parts.spawn({
					"x": _ppos.x + randf_range(-12.0, 12.0), "y": _ppos.y + randf_range(-12.0, 12.0),
					"kind": CodeParticles.KIND_CHAR,
					"tx": fist.x + randf_range(-7.0, 7.0), "ty": fist.y + randf_range(-7.0, 7.0),
					"seek": 9.0, "seek_delay": randf_range(0.0, 0.09),
					"life": ATK_CHARGE + 0.16, "size": 14.0, "end_size": 8.0,
					"color": Pal.a(Pal.lighten(Pal.main, 0.35), 0.95),
				})
	elif _atk_phase == 1:
		_atk_t += delta
		if _atk_t >= ATK_CHARGE:
			_atk_phase = 2
			_atk_t = 0.0
			_do_punch()
	elif _atk_phase == 2:
		_atk_t += delta
		if _atk_t >= ATK_ACTIVE:
			_atk_phase = 0
			_atk_cd = ATK_COOLDOWN

	# ---- 敌人生成与推进 ----
	_tick_spawn_queue(delta)
	_tick_enemies(delta)

	# ---- 波次推进 ----
	if _enemies.is_empty() and _spawn_queue.is_empty():
		if _wave + 1 >= WAVES.size():
			_start_victory()
		else:
			# 波间留一点喘息时间，否则压迫感会退化成纯粹的疲劳
			if _wave_cd <= 0.0:
				_wave_cd = 1.2
			_wave_cd -= delta
			if _wave_cd <= 0.0:
				_start_wave(_wave + 1)


func _update_aim() -> void:
	if _mouse_moved:
		var m := get_global_mouse_position()
		var d := m - _ppos
		if d.length() > 4.0:
			_aim = d.normalized()
	else:
		# 键鼠之外的兜底：自动朝最近敌人，保证「没鼠标也能打」
		var best: float = 1e9
		var bd := _aim
		for e in _enemies:
			var d: Vector2 = e["pos"] - _ppos
			var l := d.length()
			if l < best:
				best = l
				bd = d.normalized()
		if best < 1e8:
			_aim = bd


func _do_punch() -> void:
	var fist := _ppos + _aim * ATK_REACH
	Sfx.play_varied("punch_hit", -8.0, 0.1)
	_parts.burst_cone(fist, _aim.angle(), 0.75, 16, {
		"kind": CodeParticles.KIND_RECT, "speed": 220.0, "drag": 5.0,
		"life": 0.34, "size": 5.0, "end_size": 0.0, "color": Pal.a(Pal.accent, 0.95),
	})
	_parts.burst_at(fist, 12, {
		"kind": CodeParticles.KIND_CHAR, "speed": 130.0, "drag": 4.0,
		"life": 0.45, "size": 15.0, "end_size": 9.0,
		"color": Pal.a(Pal.lighten(Pal.main, 0.4), 0.95),
	})
	var hit := false
	for e in _enemies.duplicate():
		var ep: Vector2 = e["pos"]
		if ep.distance_to(fist) <= ATK_RANGE + ENEMY_HALF:
			_kill_enemy(e)
			hit = true
	if hit:
		_hit_stop = 0.09
		_flash = 0.55


func _kill_enemy(e: Dictionary) -> void:
	_enemies.erase(e)
	_killed += 1
	Sfx.play_varied("shatter", -9.0, 0.14)
	# 马赛克崩解
	var ep: Vector2 = e["pos"]
	for b in e["blocks"]:
		var off: Vector2 = b["off"]
		_parts.spawn({
			"x": ep.x + off.x, "y": ep.y + off.y,
			"kind": CodeParticles.KIND_RECT,
			"vx": off.x * 5.5 + randf_range(-40.0, 40.0),
			"vy": off.y * 5.5 + randf_range(-40.0, 40.0),
			"drag": 2.6, "life": randf_range(0.5, 0.95),
			"size": float(b["size"]), "end_size": 0.0,
			"rot": 0.0, "vrot": randf_range(-6.0, 6.0),
			"color": Pal.a(Pal.lighten(Pal.main, float(b["bright"])), 0.95),
		})
	for i in 10:
		_parts.spawn({
			"x": ep.x + randf_range(-14.0, 14.0), "y": ep.y + randf_range(-14.0, 14.0),
			"kind": CodeParticles.KIND_CHAR,
			"vx": randf_range(-120.0, 120.0), "vy": randf_range(-120.0, 120.0),
			"drag": 2.2, "life": randf_range(0.4, 0.8), "size": 15.0, "end_size": 9.0,
			"color": Pal.a(Pal.text, 0.9),
		})
	_parts.burst_at(ep, 6, {
		"kind": CodeParticles.KIND_SPRITE, "tex": Assets.particle("spark_05"),
		"speed": 150.0, "drag": 3.0, "life": 0.4,
		"size": 30.0, "end_size": 4.0, "color": Pal.a(Pal.warn, 0.8), "spin": 4.0,
	})


func _start_wave(i: int) -> void:
	_wave = i
	var count: int = WAVES[i]
	_spawn_queue.clear()
	for k in count:
		_spawn_queue.append(randf_range(0.15, 1.5) + float(k) * 0.28)
	_wave_cd = 0.0
	Sfx.play("wave", -8.0)
	# 弱引导：波次不提示，让敌人自己出现


func _tick_spawn_queue(delta: float) -> void:
	if _spawn_queue.is_empty():
		return
	var i := _spawn_queue.size() - 1
	while i >= 0:
		_spawn_queue[i] = float(_spawn_queue[i]) - delta
		if float(_spawn_queue[i]) <= 0.0:
			_spawn_queue.remove_at(i)
			_spawn_enemy()
		i -= 1


func _spawn_enemy() -> void:
	# 从竞技场四边生成，形成「多方向围攻」
	var side := randi() % 4
	var p := Vector2.ZERO
	var m := WALL + ENEMY_HALF + 8.0
	match side:
		0:
			p = Vector2(randf_range(m, ARENA.x - m), WALL + m)
		1:
			p = Vector2(ARENA.x - m, randf_range(m, ARENA.y - m))
		2:
			p = Vector2(randf_range(m, ARENA.x - m), ARENA.y - m)
		_:
			p = Vector2(WALL + m, randf_range(m, ARENA.y - m))

	_enemies.append({
		"pos": p,
		"vel": Vector2.ZERO,
		"speed": randf_range(ENEMY_SPEED_MIN, ENEMY_SPEED_MAX),
		"blocks": _make_mosaic(),
		"t": randf_range(0.0, 6.0),
		"spawn_t": 0.0,
		"wob": randf_range(-1.0, 1.0),
	})
	Sfx.play_varied("enemy_spawn", -18.0, 0.2)
	_parts.burst_at(p, 10, {
		"kind": CodeParticles.KIND_RECT, "speed": 70.0, "drag": 4.0,
		"life": 0.5, "size": 4.0, "end_size": 0.0, "color": Pal.a(Pal.main, 0.7),
	})


## 一只敌人 = 一组错位的小方块，这就是「代码构成的马赛克生物」
func _make_mosaic() -> Array:
	var n := randi_range(11, 17)
	var out: Array = []
	for i in n:
		var ang := randf() * TAU
		var r := randf() * ENEMY_HALF * 1.25
		out.append({
			"off": Vector2(cos(ang), sin(ang)) * r,
			"size": randf_range(4.0, 9.0),
			"phase": randf_range(0.0, TAU),
			"bright": randf_range(0.0, 0.55),
			"spd": randf_range(4.0, 11.0),
		})
	return out


func _tick_enemies(delta: float) -> void:
	for e in _enemies:
		e["t"] = float(e["t"]) + delta
		e["spawn_t"] = minf(1.0, float(e["spawn_t"]) + delta / 0.35)
		var ep: Vector2 = e["pos"]
		var to := _ppos - ep
		var dir := to.normalized() if to.length() > 0.01 else Vector2.RIGHT
		# 轻微横向摆动，让包围更有「生物感」，也避免全部走直线
		var perp := Vector2(-dir.y, dir.x)
		var sway := sin(float(e["t"]) * 1.7 + float(e["wob"]) * 6.0) * 0.35
		var want := (dir + perp * sway).normalized() * float(e["speed"])
		e["vel"] = (e["vel"] as Vector2).lerp(want, clampf(delta * 4.0, 0.0, 1.0))
		e["pos"] = ep + (e["vel"] as Vector2) * delta
		var np: Vector2 = e["pos"]
		np.x = clampf(np.x, WALL, ARENA.x - WALL)
		np.y = clampf(np.y, WALL, ARENA.y - WALL)
		e["pos"] = np

		if _st == St.FIGHT and _invuln <= 0.0:
			if np.distance_to(_ppos) <= PLAYER_HALF + ENEMY_HALF * 1.15:
				_start_death()
				return

		# 移动拖尾
		if randf() < delta * 26.0:
			_parts.spawn({
				"x": np.x + randf_range(-10.0, 10.0), "y": np.y + randf_range(-10.0, 10.0),
				"kind": CodeParticles.KIND_RECT, "vx": randf_range(-16.0, 16.0), "vy": randf_range(-16.0, 16.0),
				"drag": 3.0, "life": 0.35, "size": 3.0, "color": Pal.a(Pal.main, 0.35),
			})


# ---------------------------------------------------------------- 死亡

func _start_death() -> void:
	_set_state(St.DYING)
	_alive = false
	_death_count += 1
	_flash = 1.0
	Pal.glitch = 0.7
	Sfx.play("death", -7.0)
	Sfx.play("dissolve", -12.0)

	var rect := Rect2(_ppos.x - PLAYER_HALF, _ppos.y - PLAYER_HALF, PLAYER_HALF * 2.0, PLAYER_HALF * 2.0)
	_parts.burst_from_rect(rect, 40, {
		"kind": CodeParticles.KIND_CHAR, "drag": 1.1,
		"life": 2.2, "size": 15.0, "end_size": 11.0,
		"color": Pal.a(Pal.lighten(Pal.main, 0.35), 0.95), "fade_pow": 1.1,
	})
	_parts.burst_at(_ppos, 24, {
		"kind": CodeParticles.KIND_RECT, "speed": 190.0, "drag": 2.8,
		"life": 0.8, "size": 5.0, "end_size": 0.0, "color": Pal.a(Pal.accent, 0.95),
	})

	if not _died_once:
		_died_once = true
		# 需求：第一次死亡之后解锁鼠标左键攻击
		_can_attack = true
		Sfx.play("unlock", -6.0)
		_whisper.say("接触就会解体。得趁它靠近之前，先把代码推出去", {
			"keys": "鼠标左键 → 朝光标方向聚拢代码并挥出，击中即击碎",
			"hold": 6.4,
		})


func _tick_dying(delta: float) -> void:
	if _st_t >= 0.9:
		# 重生点固定在战斗场中央下方
		_ppos = PLAYER_SPAWN
		_pvel = Vector2.ZERO
		_invuln = 1.1
		_parts.burst_at(_ppos, 26, {
			"kind": CodeParticles.KIND_RECT, "speed": 120.0, "drag": 3.6,
			"life": 0.6, "size": 4.5, "end_size": 0.0, "color": Pal.a(Pal.main, 0.9),
		})
		Pal.flash = 0.25
		_set_state(St.FIGHT)


# ---------------------------------------------------------------- 收尾镜头

func _start_victory() -> void:
	_set_state(St.CAM_DOOR)
	_victory_bloom = 1.0
	_enemies.clear()
	_spawn_queue.clear()
	Sfx.play("confirm", -6.0)
	Sfx.play("portal", -10.0)
	_parts.burst_at(_ppos, 40, {
		"kind": CodeParticles.KIND_SPRITE, "tex": Assets.particle("star_05"),
		"speed": 260.0, "drag": 1.6, "life": 1.2,
		"size": 40.0, "end_size": 2.0, "color": Pal.a(Pal.warn, 0.9), "spin": 5.0,
	})
	_cam_lerp = 1.8


func _tick_cam_door(delta: float) -> void:
	# 镜头平移到代码门，并稍微推近
	_cam_target = Vector2(480.0, 268.0)
	_cam_zoom_target = 1.18
	if _st_t >= 1.6:
		_set_state(St.DOOR_WAIT)
		Sfx.play("door_open", -8.0)


func _tick_door_wait(delta: float) -> void:
	# 需求：在门前停 2 秒
	_cam_target = Vector2(480.0, 268.0)
	_cam_zoom_target = 1.18
	# 门持续吐代码粒子
	if randf() < delta * 90.0:
		var dx := randf_range(DOOR.position.x, DOOR.end.x)
		_parts.spawn({
			"x": dx, "y": DOOR.position.y + randf_range(0.0, DOOR.size.y),
			"kind": CodeParticles.KIND_CHAR,
			"vx": randf_range(-10.0, 10.0), "vy": randf_range(-46.0, -12.0),
			"drag": 0.9, "life": randf_range(0.5, 1.1), "size": 15.0, "end_size": 10.0,
			"color": Pal.a(Pal.lighten(Pal.main, 0.4), 0.9),
		})
	if _st_t >= 2.0:
		_set_state(St.CAM_BACK)
		_cam_zoom_target = 1.0
		_cam_lerp = 2.0


func _tick_cam_back(delta: float) -> void:
	# 镜头平移回主角身上
	_cam_target = _ppos + Vector2(0.0, -10.0)
	if _st_t >= 1.35:
		_set_state(St.DIVE)
		Sfx.play("portal", -12.0)


func _tick_dive(delta: float) -> void:
	var k := clampf(_st_t / 0.9, 0.0, 1.0)
	var e := k * k
	_cam_target = _ppos + Vector2(0.0, -6.0)
	_cam_zoom_target = lerpf(1.0, 3.1, e)
	_cam_lerp = 6.0
	_flash = maxf(_flash, e * 0.9)
	if k >= 1.0 and not _done:
		_done = true
		Pal.flash = 0.5
		emit_signal("finished")


func _tick_camera(delta: float) -> void:
	if _st == St.FIGHT or _st == St.DYING:
		_cam_target = _ppos + Vector2(0.0, -22.0)
		_cam_zoom_target = 1.0
	_cam_target.x = clampf(_cam_target.x, VIEW.x * 0.5 / _cam_zoom, ARENA.x - VIEW.x * 0.5 / _cam_zoom)
	_cam_target.y = clampf(_cam_target.y, VIEW.y * 0.5 / _cam_zoom, ARENA.y - VIEW.y * 0.5 / _cam_zoom)
	var k := clampf(delta * _cam_lerp, 0.0, 1.0)
	_cam_pos = _cam_pos.lerp(_cam_target, k)
	_cam_zoom = lerpf(_cam_zoom, _cam_zoom_target, clampf(delta * 2.0, 0.0, 1.0))
	_cam.position = _cam_pos
	_cam.zoom = Vector2(_cam_zoom, _cam_zoom)


# ---------------------------------------------------------------- 世界绘制

func _draw_world(ci: CanvasItem) -> void:
	# 地板
	ci.draw_rect(Rect2(0, 0, ARENA.x, ARENA.y), Pal.a(Pal.darken(Pal.bg, 0.3), 1.0), true)
	_draw_floor_grid(ci)
	_draw_walls(ci)
	_draw_door(ci)
	_draw_enemies(ci)
	_draw_player(ci)
	_parts.draw(ci)


func _draw_floor_grid(ci: CanvasItem) -> void:
	var step := 60.0
	var x := 0.0
	var i := 0
	while x <= ARENA.x:
		var major := i % 4 == 0
		ci.draw_rect(Rect2(x, 0, 1.0, ARENA.y), Pal.a(Pal.grid, 0.72 if major else 0.36), true)
		x += step
		i += 1
	var y := 0.0
	var j := 0
	while y <= ARENA.y:
		var major := j % 4 == 0
		ci.draw_rect(Rect2(0, y, ARENA.x, 1.0), Pal.a(Pal.grid, 0.72 if major else 0.36), true)
		y += step
		j += 1

	# 缓慢滚动的数据脉冲带，避免静态网格太死
	var pulse_y := fmod(_t * 46.0, ARENA.y + 200.0) - 100.0
	ci.draw_rect(Rect2(0, pulse_y, ARENA.x, 2.0), Pal.a(Pal.accent, 0.22), true)
	var pulse_x := fmod(_t * 33.0, ARENA.x + 200.0) - 100.0
	ci.draw_rect(Rect2(pulse_x, 0, 2.0, ARENA.y), Pal.a(Pal.accent, 0.18), true)

	# 中央的「出生区」标记
	var r := 96.0
	for k in 28:
		var a := float(k) / 28.0 * TAU + _t * 0.35
		var p := PLAYER_SPAWN + Vector2(cos(a), sin(a)) * r
		ci.draw_rect(Rect2(p.x - 2.0, p.y - 2.0, 4.0, 4.0), Pal.a(Pal.main, 0.35), true)


func _draw_walls(ci: CanvasItem) -> void:
	var c := Pal.a(Pal.main, 0.30)
	ci.draw_rect(Rect2(0, 0, ARENA.x, WALL), Pal.a(Pal.darken(Pal.main, 0.72), 0.85), true)
	ci.draw_rect(Rect2(0, ARENA.y - WALL, ARENA.x, WALL), Pal.a(Pal.darken(Pal.main, 0.72), 0.85), true)
	ci.draw_rect(Rect2(0, 0, WALL, ARENA.y), Pal.a(Pal.darken(Pal.main, 0.72), 0.85), true)
	ci.draw_rect(Rect2(ARENA.x - WALL, 0, WALL, ARENA.y), Pal.a(Pal.darken(Pal.main, 0.72), 0.85), true)
	# 内沿亮线
	ci.draw_rect(Rect2(0, WALL, ARENA.x, 2.0), c, true)
	ci.draw_rect(Rect2(0, ARENA.y - WALL - 2.0, ARENA.x, 2.0), c, true)
	ci.draw_rect(Rect2(WALL, 0, 2.0, ARENA.y), c, true)
	ci.draw_rect(Rect2(ARENA.x - WALL - 2.0, 0, 2.0, ARENA.y), c, true)
	# 墙体上的数据刻度（压得很淡，只当纹理看，不要读成调试数字）
	var mono := Assets.mono_font()
	var y := WALL + 40.0
	while y < ARENA.y - WALL:
		ci.draw_string(mono, Vector2(6.0, y), "%04d" % int(y), HORIZONTAL_ALIGNMENT_LEFT, -1, 10,
			Pal.a(Pal.main, 0.13))
		Tx.right(ci, mono, ARENA.x - 6.0, y, "%04d" % int(y), 10, Pal.a(Pal.main, 0.05))
		y += 120.0


func _draw_door(ci: CanvasItem) -> void:
	var pulse := 0.5 + 0.5 * sin(_door_pulse * 3.2)
	var active := _st == St.CAM_DOOR or _st == St.DOOR_WAIT or _st == St.CAM_BACK
	var glow := 0.55 + 0.45 * pulse + (0.5 if active else 0.0)

	# 门外扩的光晕
	ci.draw_rect(DOOR.grow(18.0 + pulse * 6.0), Pal.a(Pal.main, 0.08 * glow), true)
	ci.draw_rect(DOOR.grow(6.0), Pal.a(Pal.main, 0.16 * glow), true)
	# 门框
	ci.draw_rect(DOOR, Pal.a(Pal.bg, 0.92), true)
	var fc := Pal.lighten(Pal.main, 0.35)
	fc.a = clampf(0.7 + 0.3 * pulse, 0.0, 1.0)
	ci.draw_rect(DOOR, fc, false, 3.0)
	ci.draw_rect(DOOR.grow(-5.0), Pal.a(Pal.accent, 0.5), false, 1.0)

	# 门内的代码粒子流：由字符组成的下落柱
	var mono := Assets.mono_font()
	var cols := 9
	var cw := DOOR.size.x / float(cols)
	for c in cols:
		var cx := DOOR.position.x + cw * (float(c) + 0.5)
		var off := fmod(_t * (44.0 + float(c) * 11.0), DOOR.size.y + 36.0)
		for k in 7:
			var cy := DOOR.position.y + fmod(off + float(k) * 26.0, DOOR.size.y + 36.0) - 18.0
			if cy < DOOR.position.y or cy > DOOR.end.y:
				continue
			var ch := CodeParticles.GLYPHS.substr((c * 7 + k * 3 + int(_t * 6.0)) % CodeParticles.GLYPHS.length(), 1)
			var a := 0.85 - float(k) * 0.11
			ci.draw_char(mono, Vector2(cx - 5.0, cy), ch, 15,
				Pal.a(Pal.lighten(Pal.main, 0.45), clampf(a, 0.0, 1.0) * glow))
	# 中央能量核
	var core := DOOR.get_center()
	var cr := 12.0 + pulse * 5.0
	ci.draw_circle(core, cr, Pal.a(Pal.lighten(Pal.main, 0.7), 0.35 * glow))
	ci.draw_circle(core, cr * 0.45, Pal.a(Color.WHITE, 0.55 * glow))

	var title := Assets.title_font()
	Tx.center(ci, title, DOOR.get_center().x, DOOR.position.y - 22.0, "CODE GATE", 20, Pal.a(Pal.lighten(Pal.main, 0.3), 0.85))


func _draw_enemies(ci: CanvasItem) -> void:
	for e in _enemies:
		var ep: Vector2 = e["pos"]
		var tt: float = e["t"]
		var sp: float = float(e["spawn_t"])
		# 生成时的形变：从中心「编译」成型
		var scale_in := 0.4 + 0.6 * sp
		# 外圈轮廓
		ci.draw_circle(ep, ENEMY_HALF * 1.5 * scale_in, Pal.a(Pal.main, 0.10 * sp))
		for b in e["blocks"]:
			var off: Vector2 = b["off"]
			var jitter := Vector2(
				sin(tt * float(b["spd"]) + float(b["phase"])),
				cos(tt * float(b["spd"]) * 0.83 + float(b["phase"]))) * 2.4
			var p := ep + (off + jitter) * scale_in
			var s: float = float(b["size"]) * scale_in
			var col := Pal.main.lerp(Pal.lighten(Pal.main, 0.6), float(b["bright"]))
			col.a = 0.55 + 0.45 * sp
			ci.draw_rect(Rect2(p.x - s * 0.5, p.y - s * 0.5, s, s), col, true)
		# 内核
		ci.draw_rect(Rect2(ep.x - 4.0, ep.y - 4.0, 8.0, 8.0), Pal.a(Pal.lighten(Pal.main, 0.5), 0.9 * sp), true)


func _draw_player(ci: CanvasItem) -> void:
	if _st == St.DYING:
		# 消散后原地留一个熄灭的框
		var k := 1.0 - clampf(_st_t / 0.5, 0.0, 1.0)
		if k > 0.0:
			ci.draw_rect(Rect2(_ppos.x - PLAYER_HALF, _ppos.y - PLAYER_HALF, PLAYER_HALF * 2.0, PLAYER_HALF * 2.0),
				Pal.a(Pal.lighten(Pal.main, 0.6), 0.4 * k), true)
		return

	var blink := 1.0
	if _invuln > 0.0:
		blink = 0.35 + 0.65 * (0.5 + 0.5 * sin(_t * 30.0))

	# 脚下发光的边框方块（需求：主角是脚下带发光边框的小方块）
	var r := Rect2(_ppos.x - PLAYER_HALF, _ppos.y - PLAYER_HALF, PLAYER_HALF * 2.0, PLAYER_HALF * 2.0)
	ci.draw_rect(r.grow(9.0), Pal.a(Pal.main, 0.10 * blink), true)
	ci.draw_rect(r, Pal.a(Pal.darken(Pal.main, 0.75), 0.85 * blink), true)
	ci.draw_rect(r, Pal.a(Pal.lighten(Pal.main, 0.55), 0.95 * blink), false, 2.5)
	ci.draw_rect(r.grow(4.0), Pal.a(Pal.main, 0.35 * blink), false, 1.0)
	# 内核
	ci.draw_rect(Rect2(_ppos.x - 5.0, _ppos.y - 5.0, 10.0, 10.0),
		Pal.a(Pal.lighten(Pal.main, 0.7), 0.9 * blink), true)

	# 朝向指示
	var tip := _ppos + _aim * (PLAYER_HALF + 9.0)
	ci.draw_line(_ppos + _aim * PLAYER_HALF, tip, Pal.a(Pal.lighten(Pal.main, 0.4), 0.8), 2.0)

	# 拳头：蓄力时收缩，挥出时炸开
	var fist := _ppos + _aim * ATK_REACH
	if _atk_phase == 1:
		var k := clampf(_atk_t / ATK_CHARGE, 0.0, 1.0)
		var fr := lerpf(4.0, 16.0, k)
		ci.draw_circle(fist, fr, Pal.a(Pal.lighten(Pal.main, 0.6), 0.55 * k))
		ci.draw_circle(fist, fr * 0.4, Pal.a(Color.WHITE, 0.8 * k))
		ci.draw_circle(fist, fr + 6.0, Pal.a(Pal.main, 0.20 * k), false, 2.0)
	elif _atk_phase == 2:
		var k := clampf(_atk_t / ATK_ACTIVE, 0.0, 1.0)
		var fr := lerpf(46.0, 10.0, k)
		var a := (1.0 - k) * 0.85
		var arc := _aim.angle()
		var pts := PackedVector2Array()
		var n := 20
		for i in n + 1:
			var ang := arc - 1.05 + 2.1 * float(i) / float(n)
			pts.append(fist + Vector2(cos(ang), sin(ang)) * fr)
		if pts.size() >= 3:
			ci.draw_polyline(pts, Pal.a(Pal.lighten(Pal.main, 0.6), a), 5.0)
		ci.draw_circle(fist, 12.0 * (1.0 - k) + 4.0, Pal.a(Color.WHITE, a))
		ci.draw_circle(fist, ATK_RANGE * (0.55 + 0.45 * k), Pal.a(Pal.main, a * 0.25), false, 2.0)


# ---------------------------------------------------------------- HUD

func _draw_hud(ci: CanvasItem) -> void:
	var w := VIEW.x
	var h := VIEW.y
	_rain.draw(ci, Pal.main, 0.08)

	# 去掉阶段名、波次计数、死亡次数、按键说明 —— 只留一行「还剩多少」
	# 的极简暗示，让玩家自己感到压力，而不是被数字告知。
	_whisper.draw(ci)
	_draw_remaining(ci, w, h)

	_draw_threat_arrows(ci, w, h)

	if _flash > 0.0:
		ci.draw_rect(Rect2(0, 0, w, h), Pal.a(Pal.lighten(Pal.main, 0.5), 0.11 * _flash), true)
	if _invuln > 0.0:
		ci.draw_rect(Rect2(0, 0, w, h), Pal.a(Pal.accent, 0.035 * _invuln), true)
	if Pal.glitch > 0.01:
		var n := int(Pal.glitch * 6.0)
		for i in n:
			ci.draw_rect(Rect2(randf_range(-60.0, 40.0), randf() * h, w, randf_range(2.0, 12.0)),
				Pal.a(Pal.lighten(Pal.main, 0.5), 0.08), true)

	if _st == St.DIVE:
		var kk := clampf((_st_t - 0.9) / 0.9, 0.0, 1.0)
		ci.draw_rect(Rect2(0, 0, w, h), Pal.a(Color.WHITE, kk), true)

	_draw_scanlines(ci)

	# 暗角，和平台段保持同一套视觉语言
	_vignette(ci, w, h)


## 剩余敌人：底部一排极小光点，已消散的留空位。
## 不用数字、不用进度条 —— 只给一个「还剩几口气」的模糊感知。
func _draw_remaining(ci: CanvasItem, w: float, h: float) -> void:
	var n := _total
	if n <= 0:
		return
	var gap := 14.0
	var total_w := gap * float(n - 1)
	var x := w * 0.5 - total_w * 0.5
	var y := h - 30.0
	for i in n:
		var alive := i >= _killed
		var c := Pal.main
		if alive:
			c.a = 0.42 + 0.18 * sin(_door_pulse * 1.5 + float(i) * 0.7)
			ci.draw_circle(Vector2(x, y), 2.6, c)
		else:
			c.a = 0.10
			ci.draw_circle(Vector2(x, y), 1.6, c)
		x += gap


func _vignette(ci: CanvasItem, w: float, h: float) -> void:
	var steps := 9
	for i in steps:
		var f := float(i) / float(steps)
		var a := 0.033 * (1.0 - f)
		var inset := f * 92.0
		ci.draw_rect(Rect2(inset, inset, w - inset * 2.0, 26.0), Color(0, 0, 0, a), true)
		ci.draw_rect(Rect2(inset, h - inset - 26.0, w - inset * 2.0, 26.0), Color(0, 0, 0, a), true)
		ci.draw_rect(Rect2(inset, inset, 26.0, h - inset * 2.0), Color(0, 0, 0, a), true)
		ci.draw_rect(Rect2(w - inset - 26.0, inset, 26.0, h - inset * 2.0), Color(0, 0, 0, a), true)


func _draw_threat_arrows(ci: CanvasItem, w: float, h: float) -> void:
	# 屏幕外的敌人用一条朝外的短线提示方向，避免被从视野外偷袭
	var c := Vector2(w * 0.5, h * 0.5)
	for e in _enemies:
		var ep: Vector2 = e["pos"]
		var scr := c + (ep - _cam_pos) * _cam_zoom
		if scr.x > 40.0 and scr.x < w - 40.0 and scr.y > 60.0 and scr.y < h - 40.0:
			continue
		var d := scr - c
		if d.length() < 1.0:
			continue
		var ang := d.angle()
		var edge := Vector2(clampf(scr.x, 24.0, w - 24.0), clampf(scr.y, 64.0, h - 24.0))
		ci.draw_line(edge - Vector2(cos(ang), sin(ang)) * 16.0, edge, Pal.a(Pal.warn, 0.8), 3.0)


func _hint(text: String, keys: String, dur: float) -> void:
	_whisper.say(text, {"keys": keys, "hold": dur})


func _draw_scanlines(ci: CanvasItem) -> void:
	var a := 0.07 * Pal.scan
	var y := 0.0
	while y < VIEW.y:
		ci.draw_rect(Rect2(0, y, VIEW.x, 1), Color(0, 0, 0, a), true)
		y += 3.0
