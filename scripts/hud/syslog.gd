class_name SysLog
extends RefCounted

## 系统日志 UI。
## 需求要求「以淡入系统日志风格提示」，所以这里的每一条都是：
##   淡入 + 打字机逐字输出 + 带时间戳 + 带光标 + 停留后淡出。
## 能力解锁类消息标记为 important，加高亮边框并停留更久。

const X := 26.0
const Y := 68.0
const LINE_H := 23.0
const MAX_LINES := 6
const CHARS_PER_SEC := 34.0
const FADE_IN := 0.28
const FADE_OUT := 0.45

var lines: Array = []
var clock: float = 0.0
var tick_cb: Callable = Callable()


func push(text: String, opts: Dictionary = {}) -> void:
	var l := {
		"text": text,
		"tag": String(opts.get("tag", "SYS")),
		"color": opts.get("color", null),
		"important": bool(opts.get("important", false)),
		"shown": 0.0,
		"hold": float(opts.get("hold", 4.2 if opts.get("important", false) else 3.0)),
		"alpha": 0.0,
		"state": 0,  # 0=淡入/打字 1=停留 2=淡出
		"age": 0.0,
		"seed": randf() * 10.0,
	}
	lines.append(l)
	while lines.size() > MAX_LINES:
		lines.pop_front()
	if opts.has("sfx"):
		Sfx.play(String(opts["sfx"]), float(opts.get("sfx_db", -14.0)))
	else:
		Sfx.play("panel", -18.0)


func clear() -> void:
	lines.clear()


func update(delta: float) -> void:
	clock += delta
	var remove: Array = []
	for l in lines:
		l["age"] = float(l["age"]) + delta
		var total := float(l["text"].length())
		match int(l["state"]):
			0:
				l["alpha"] = minf(1.0, float(l["alpha"]) + delta / FADE_IN)
				var before := int(l["shown"])
				l["shown"] = minf(total, float(l["shown"]) + delta * CHARS_PER_SEC)
				if int(l["shown"]) != before and tick_cb.is_valid():
					tick_cb.call()
				if float(l["shown"]) >= total and float(l["alpha"]) >= 1.0:
					l["state"] = 1
			1:
				if float(l["age"]) >= total / CHARS_PER_SEC + float(l["hold"]):
					l["state"] = 2
			2:
				l["alpha"] = float(l["alpha"]) - delta / FADE_OUT
				if float(l["alpha"]) <= 0.0:
					remove.append(l)
	for l in remove:
		lines.erase(l)


func draw(ci: CanvasItem) -> void:
	if lines.is_empty():
		return
	var mono := Assets.mono_font()
	if mono == null:
		return
	var fs := 14
	var y := Y
	# 背景面板按可见行数裁一张半透明底，保证在杂乱背景上依然可读
	var panel_w := 0.0
	for l in lines:
		var s := _line_text(l, true)
		panel_w = maxf(panel_w, mono.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x)
	panel_w = clampf(panel_w + 58.0, 300.0, 620.0)
	var panel_h := float(lines.size()) * LINE_H + 22.0
	ci.draw_rect(Rect2(X - 12, Y - 22, panel_w, panel_h), Pal.a(Pal.panel, 0.82), true)
	# 左侧竖线 + 上下括号
	ci.draw_rect(Rect2(X - 12, Y - 22, 2.0, panel_h), Pal.a(Pal.main, 0.75), true)
	ci.draw_rect(Rect2(X - 12, Y - 22, panel_w, 1.0), Pal.a(Pal.dim, 0.8), true)
	ci.draw_rect(Rect2(X - 12, Y - 22 + panel_h - 1.0, panel_w, 1.0), Pal.a(Pal.dim, 0.8), true)

	for l in lines:
		var a := float(l["alpha"])
		if a <= 0.003:
			y += LINE_H
			continue
		var imp := bool(l["important"])
		var base := Pal.text
		if l["color"] != null:
			base = l["color"]
		elif l["tag"] == "WARN":
			base = Pal.warn
		elif imp:
			base = Pal.lighten(Pal.accent, 0.15)

		# 时间戳
		var ts := _stamp()
		var tc := Pal.text
		tc.a = 0.34 * a
		ci.draw_string(mono, Vector2(X, y), ts, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, tc)

		# 前缀
		var pc := Pal.accent
		pc.a = 0.9 * a
		var prefix: String = "%s >> " % String(l["tag"])
		var px := X + 62.0
		ci.draw_string(mono, Vector2(px, y), prefix, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, pc)

		# 正文（打字机）
		var tw := mono.get_string_size(prefix, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var body := String(l["text"]).substr(0, int(l["shown"]))
		var bc := base
		bc.a = a
		ci.draw_string(mono, Vector2(px + tw, y), body, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, bc)

		# 光标
		if int(l["state"]) == 0:
			var bw := mono.get_string_size(body, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			var blink := (sin(float(l["age"]) * 14.0 + float(l["seed"])) + 1.0) * 0.5
			var cc := Pal.lighten(Pal.main, 0.4)
			cc.a = a * (0.35 + 0.65 * blink)
			ci.draw_rect(Rect2(px + tw + bw + 2, y - 11, 8, 14), cc, true)

		# 重要提示描一条左侧高亮
		if imp and int(l["state"]) == 1:
			var ha := a * (0.25 + 0.25 * sin(float(l["age"]) * 5.0))
			ci.draw_rect(Rect2(X - 12, y - 15, 2.0, LINE_H - 4), Pal.a(Pal.lighten(Pal.accent, 0.4), ha), true)
		y += LINE_H


func _line_text(l: Dictionary, full: bool) -> String:
	var body: String = String(l["text"]) if full else String(l["text"]).substr(0, int(l["shown"]))
	return "%s %s >> %s" % [_stamp(), String(l["tag"]), body]


func _stamp() -> String:
	var m := int(clock) / 60
	var s := int(clock) % 60
	var d := int((clock - floor(clock)) * 10.0)
	return "[%02d:%02d.%d]" % [m, s, d]


func visible_height() -> float:
	return float(lines.size()) * LINE_H + 22.0
