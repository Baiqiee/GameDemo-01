class_name CodeParticles
extends RefCounted

## 「代码粒子」系统 —— 本 Demo 的视觉核心。
##
## 刻意不用 GPUParticles2D：这里需要的是「按字形解散 / 汇聚重组」
## 这种把粒子当作对象来编程的模型，而不是引擎的发射器模型。
## 对象池 + 手绘，反而更短、更可控。
##
## 三种粒子形态：
##   KIND_CHAR  —— 代码字符（主角解散、字幕拼字）
##   KIND_RECT  —— 小方块（马赛克敌人、数据碎片）
##   KIND_SPRITE—— Kenney 粒子贴图（火花、星芒、光晕）

const KIND_CHAR := 0
const KIND_RECT := 1
const KIND_SPRITE := 2

const MAX := 1400
const GLYPHS := "01<>{}/\\*+=;:_$#@&|^~!?%"

var _pool: Array = []
var _cursor: int = 0
var active_count: int = 0


func _init() -> void:
	_pool.resize(MAX)
	for i in MAX:
		_pool[i] = _blank()


func _blank() -> Dictionary:
	return {
		"active": false, "kind": KIND_RECT,
		"px": 0.0, "py": 0.0, "pz": 0.0,
		"vx": 0.0, "vy": 0.0, "vz": 0.0, "ax": 0.0, "ay": 0.0,
		"drag": 0.0, "life": 0.0, "maxlife": 1.0,
		"size": 3.0, "end_size": 0.0,
		"col": Color.WHITE, "col_end": Color.WHITE,
		"alpha": 1.0, "fade_pow": 1.0,
		"glyph": "0", "rot": 0.0, "vrot": 0.0,
		"tx": 0.0, "ty": 0.0, "seek": 0.0, "seek_t": 0.0,
		"tex": null, "spin": 0.0,
	}


## 通用生成：cfg 里没给的字段沿用默认值
func spawn(cfg: Dictionary) -> void:
	var idx := -1
	for k in MAX:
		var i := (_cursor + k) % MAX
		if not bool(_pool[i]["active"]):
			idx = i
			break
	if idx < 0:
		idx = _cursor
	_cursor = (idx + 1) % MAX
	var d: Dictionary = _pool[idx]
	_apply(d, cfg)
	d["active"] = true
	d["life"] = 0.0
	active_count += 1


func _apply(d: Dictionary, cfg: Dictionary) -> void:
	var x := float(cfg.get("x", 0.0))
	var y := float(cfg.get("y", 0.0))
	var col: Color = cfg.get("color", Color.WHITE)
	d["kind"] = int(cfg.get("kind", KIND_RECT))
	d["px"] = x
	d["py"] = y
	d["pz"] = float(cfg.get("z", 0.0))
	d["vx"] = float(cfg.get("vx", 0.0))
	d["vy"] = float(cfg.get("vy", 0.0))
	d["vz"] = float(cfg.get("vz", 0.0))
	d["ax"] = float(cfg.get("ax", 0.0))
	d["ay"] = float(cfg.get("ay", 0.0))
	d["drag"] = float(cfg.get("drag", 0.0))
	d["maxlife"] = maxf(0.05, float(cfg.get("life", 1.0)))
	d["size"] = float(cfg.get("size", 3.0))
	d["end_size"] = float(cfg.get("end_size", 0.0))
	d["col"] = col
	d["col_end"] = cfg.get("color_end", col)
	d["alpha"] = float(cfg.get("alpha", 1.0))
	d["fade_pow"] = float(cfg.get("fade_pow", 1.0))
	d["glyph"] = String(cfg.get("glyph", GLYPHS.substr(randi() % GLYPHS.length(), 1)))
	d["rot"] = float(cfg.get("rot", 0.0))
	d["vrot"] = float(cfg.get("vrot", 0.0))
	d["tx"] = float(cfg.get("tx", x))
	d["ty"] = float(cfg.get("ty", y))
	d["seek"] = float(cfg.get("seek", 0.0))
	d["seek_t"] = float(cfg.get("seek_delay", 0.0))
	d["tex"] = cfg.get("tex", null)
	d["spin"] = float(cfg.get("spin", 0.0))


## 在矩形范围内铺一层字符粒子（用于「主角化为代码」）
func burst_from_rect(rect: Rect2, amount: int, cfg: Dictionary = {}) -> void:
	for i in amount:
		var c := cfg.duplicate()
		c["x"] = rect.position.x + randf() * rect.size.x
		c["y"] = rect.position.y + randf() * rect.size.y
		c["kind"] = int(cfg.get("kind", KIND_CHAR))
		spawn(c)


## 从一个点向四周炸开
func burst_at(pos: Vector2, amount: int, cfg: Dictionary = {}) -> void:
	var speed := float(cfg.get("speed", 120.0))
	for i in amount:
		var ang := float(cfg.get("angle", 0.0)) + randf_range(-PI, PI)
		var sp := speed * randf_range(0.35, 1.25)
		var c := cfg.duplicate()
		c["x"] = pos.x
		c["y"] = pos.y
		c["vx"] = cos(ang) * sp
		c["vy"] = sin(ang) * sp
		c["kind"] = int(cfg.get("kind", KIND_RECT))
		spawn(c)


## 扇形的定向喷射（用于挥拳、冲击波）
func burst_cone(pos: Vector2, dir: float, spread: float, amount: int, cfg: Dictionary = {}) -> void:
	var speed := float(cfg.get("speed", 160.0))
	for i in amount:
		var ang := dir + randf_range(-spread, spread)
		var sp := speed * randf_range(0.4, 1.3)
		var c := cfg.duplicate()
		c["x"] = pos.x
		c["y"] = pos.y
		c["vx"] = cos(ang) * sp
		c["vy"] = sin(ang) * sp
		spawn(c)


## 让当前存活的若干粒子各自飞向一个目标点 —— 用于「汇聚重组」。
## target_fn 每次调用返回一个 Vector2，可以带随机抖动，让重组不是一个死点。
func seek_active_to(limit: int, target_fn: Callable, seek: float = 5.5, delay_max: float = 0.2) -> int:
	var moved := 0
	for i in MAX:
		if moved >= limit:
			break
		var d: Dictionary = _pool[i]
		if not bool(d["active"]):
			continue
		var t: Vector2 = target_fn.call()
		d["tx"] = t.x
		d["ty"] = t.y
		d["seek"] = seek
		d["seek_delay"] = randf_range(0.0, delay_max)
		d["drag"] = 0.0
		d["ay"] = 0.0
		moved += 1
	return moved


func update(delta: float) -> void:
	var live := 0
	for i in MAX:
		var d: Dictionary = _pool[i]
		if not bool(d["active"]):
			continue
		var life := float(d["life"]) + delta
		if life >= float(d["maxlife"]):
			d["active"] = false
			continue
		d["life"] = life
		var sz := float(d["seek_t"])
		if sz > 0.0:
			d["seek_t"] = sz - delta
		elif float(d["seek"]) > 0.0:
			# 向目标汇聚：用「位置插值 + 惯性衰减」做出吸附感
			var k := clampf(float(d["seek"]) * delta, 0.0, 1.0)
			var px := float(d["px"])
			var py := float(d["py"])
			d["px"] = px + (float(d["tx"]) - px) * k
			d["py"] = py + (float(d["ty"]) - py) * k
			d["vx"] = float(d["vx"]) * (1.0 - k)
			d["vy"] = float(d["vy"]) * (1.0 - k)
		var vx := float(d["vx"]) + float(d["ax"]) * delta
		var vy := float(d["vy"]) + float(d["ay"]) * delta
		var dg := float(d["drag"])
		if dg > 0.0:
			var f := clampf(1.0 - dg * delta, 0.0, 1.0)
			vx *= f
			vy *= f
		d["vx"] = vx
		d["vy"] = vy
		d["px"] = float(d["px"]) + vx * delta
		d["py"] = float(d["py"]) + vy * delta
		d["pz"] = float(d["pz"]) + float(d["vz"]) * delta
		if float(d["vrot"]) != 0.0:
			d["rot"] = float(d["rot"]) + float(d["vrot"]) * delta
		live += 1
	active_count = live


func draw(ci: CanvasItem) -> void:
	var mono: Font = null
	for i in MAX:
		var d: Dictionary = _pool[i]
		if not bool(d["active"]):
			continue
		var t := clampf(float(d["life"]) / float(d["maxlife"]), 0.0, 1.0)
		var fade := pow(1.0 - t, float(d["fade_pow"]))
		var col: Color = (d["col"] as Color).lerp(d["col_end"] as Color, t)
		col.a = fade * float(d["alpha"])
		if col.a <= 0.004:
			continue
		var px := float(d["px"])
		var py := float(d["py"])
		var sz := lerpf(float(d["size"]), float(d["end_size"]), t)
		match int(d["kind"]):
			KIND_CHAR:
				if mono == null:
					mono = Assets.mono_font()
				var fsz := maxi(8, int(sz))
				var g := String(d["glyph"])
				if float(d["rot"]) == 0.0:
					ci.draw_char(mono, Vector2(px, py), g, fsz, col)
				else:
					ci.draw_set_transform(Vector2(px, py), float(d["rot"]), Vector2.ONE)
					ci.draw_char(mono, Vector2(-sz * 0.34, sz * 0.36), g, fsz, col)
					ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
			KIND_SPRITE:
				var tex: Texture2D = d["tex"]
				if tex == null:
					ci.draw_circle(Vector2(px, py), sz * 0.5, col)
				else:
					var sp := float(d["spin"])
					var ang := float(d["rot"])
					if sp != 0.0:
						ang += float(d["life"]) * sp
					var half := sz * 0.5
					if ang == 0.0:
						ci.draw_texture_rect(tex, Rect2(px - half, py - half, sz, sz), false, col)
					else:
						ci.draw_set_transform(Vector2(px, py), ang, Vector2.ONE)
						ci.draw_texture_rect(tex, Rect2(-half, -half, sz, sz), false, col)
						ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
			_:
				if float(d["rot"]) == 0.0:
					ci.draw_rect(Rect2(px - sz * 0.5, py - sz * 0.5, sz, sz), col, true)
				else:
					ci.draw_set_transform(Vector2(px, py), float(d["rot"]), Vector2.ONE)
					ci.draw_rect(Rect2(-sz * 0.5, -sz * 0.5, sz, sz), col, true)
					ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## 投影绘制 —— 走廊阶段专用。
## proj(px, py, pz) 返回 Vector3(屏幕x, 屏幕y, 相机空间深度)，深度 <= 1 视为在相机后方。
## 粒子尺寸按 1/深度 缩放，于是远处的代码碎片自然变小。
func draw_projected(ci: CanvasItem, proj: Callable) -> void:
	var mono: Font = null
	for i in MAX:
		var d: Dictionary = _pool[i]
		if not bool(d["active"]):
			continue
		var t := clampf(float(d["life"]) / float(d["maxlife"]), 0.0, 1.0)
		var fade := pow(1.0 - t, float(d["fade_pow"]))
		var col: Color = (d["col"] as Color).lerp(d["col_end"] as Color, t)
		col.a = fade * float(d["alpha"])
		if col.a <= 0.006:
			continue
		var s: Vector3 = proj.call(float(d["px"]), float(d["py"]), float(d["pz"]))
		if s.z <= 1.0:
			continue
		var k: float = 640.0 / s.z
		var sz: float = float(d["size"]) * k
		if sz < 0.7 or sz > 320.0:
			continue
		if int(d["kind"]) == KIND_CHAR:
			if mono == null:
				mono = Assets.mono_font()
			ci.draw_char(mono, Vector2(s.x - sz * 0.3, s.y + sz * 0.34), String(d["glyph"]),
				maxi(8, int(sz)), col)
		else:
			ci.draw_rect(Rect2(s.x - sz * 0.5, s.y - sz * 0.5, sz, sz), col, true)


func clear() -> void:
	for i in MAX:
		_pool[i]["active"] = false
	active_count = 0
