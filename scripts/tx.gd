class_name Tx
extends RefCounted

## 文本绘制封装。
##
## 存在的理由：Godot 的 draw_string 在 width 传负数时会**忽略 alignment**，
## 文本一律从 pos 往右排。于是所有「居中」「右对齐」的写法都会失效并溢出屏幕。
## 这里先用字体量一下宽度，再自己算起点，绕开这个坑。

static func left(ci: CanvasItem, font: Font, x: float, y: float, s: String, size: int, col: Color) -> void:
	ci.draw_string(font, Vector2(x, y), s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)


static func center(ci: CanvasItem, font: Font, cx: float, y: float, s: String, size: int, col: Color) -> void:
	if font == null:
		return
	var w: float = font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	ci.draw_string(font, Vector2(cx - w * 0.5, y), s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)


static func right(ci: CanvasItem, font: Font, rx: float, y: float, s: String, size: int, col: Color) -> void:
	if font == null:
		return
	var w: float = font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	ci.draw_string(font, Vector2(rx - w, y), s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)


static func width_of(font: Font, s: String, size: int) -> float:
	if font == null:
		return 0.0
	return font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
