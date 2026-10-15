class_name CodeRain
extends RefCounted

## 赛博代码雨背景。
## 刻意不用粒子节点：这是纯粹的屏幕空间装饰，直接 draw_char 最省开销、最好控制。

const CHARS := "01<>{}/\\*+=;:_$#@&|^~!?%abcdef0123456789"

var columns: Array = []
var width: float = 960.0
var height: float = 540.0
var spacing: float = 22.0
var font: Font = null
var font_size: int = 15
var line_h: float = 20.0
var speed_scale: float = 1.0
var head_glow: float = 0.0


func setup(w: float, h: float, p_spacing: float = 22.0, p_font_size: int = 15) -> void:
	width = w
	height = h
	spacing = p_spacing
	font_size = p_font_size
	line_h = float(p_font_size) * 1.32
	font = Assets.mono_font()
	columns.clear()
	var count := int(width / spacing) + 1
	for i in count:
		columns.append(_make_column(float(i) * spacing + spacing * 0.5, true))


func _make_column(x: float, initial: bool) -> Dictionary:
	var tail := float(randi_range(8, 20))
	return {
		"x": x,
		"y": randf_range(-height, height) if not initial else randf_range(-height * 0.5, height),
		"base_speed": randf_range(38.0, 130.0),
		"tail": tail,
		"glyphs": _make_glyphs(int(tail) + 2),
		"bright": randf_range(0.55, 1.0),
		"swap_t": randf_range(0.0, 0.35),
	}


func _make_glyphs(n: int) -> Array:
	## 必须用普通 Array（引用类型）；PackedStringArray 是值类型，
	## 取出后修改不会回写字典，字符就永远不变了。
	var out: Array = []
	for i in n:
		out.append(CHARS.substr(randi() % CHARS.length(), 1))
	return out


func set_speed_scale(s: float) -> void:
	speed_scale = s
	for c in columns:
		c["speed"] = float(c["base_speed"]) * s


func update(delta: float) -> void:
	for c in columns:
		if not c.has("speed"):
			c["speed"] = float(c["base_speed"]) * speed_scale
		c["y"] = float(c["y"]) + float(c["speed"]) * delta
		c["swap_t"] = float(c["swap_t"]) - delta
		var glyphs: Array = c["glyphs"]
		if float(c["swap_t"]) <= 0.0:
			c["swap_t"] = randf_range(0.04, 0.18)
			var idx := randi() % glyphs.size()
			glyphs[idx] = CHARS.substr(randi() % CHARS.length(), 1)
		var tail := int(c["tail"])
		var bottom := height + float(tail) * line_h
		if float(c["y"]) - float(tail) * line_h > bottom:
			var nc := _make_column(float(c["x"]), false)
			nc["y"] = randf_range(-bottom * 0.8, -20.0)
			c["y"] = nc["y"]
			c["base_speed"] = nc["base_speed"]
			c["speed"] = float(nc["base_speed"]) * speed_scale
			c["tail"] = nc["tail"]
			c["glyphs"] = nc["glyphs"]
			c["bright"] = nc["bright"]


func draw(ci: CanvasItem, base_color: Color, alpha: float = 0.35) -> void:
	if font == null:
		return
	var tail_col := Pal.darken(base_color, 0.45)
	for c in columns:
		var glyphs: PackedStringArray = c["glyphs"]
		var x := float(c["x"])
		var y := float(c["y"])
		var bright := float(c["bright"])
		var n := mini(glyphs.size(), int(c["tail"]) + 1)
		for i in n:
			var gy := y - float(i) * line_h
			if gy < -line_h or gy > height + line_h:
				continue
			var f := 1.0 - float(i) / float(maxi(1, n))
			var col: Color
			if i == 0:
				col = Pal.lighten(base_color, 0.65)
				col.a = alpha * bright
			else:
				col = tail_col.lerp(base_color, f)
				col.a = alpha * bright * f * 0.9
			ci.draw_char(font, Vector2(x, gy), glyphs[i], font_size, col)
		if head_glow > 0.0:
			var hc := Pal.lighten(base_color, 0.8)
			hc.a = alpha * head_glow * bright
			ci.draw_circle(Vector2(x, y - line_h * 0.5), 2.2, hc)
