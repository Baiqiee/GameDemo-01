class_name DrawProxy
extends Node2D

## 一个把 _draw 转发给外部 Callable 的轻量代理节点。
## 用途：把「世界层」和「HUD 层」分开——HUD 挂在 CanvasLayer 下，
## 就不会被 Camera2D 的变换影响，省去每处手动重置变换的麻烦。

var fn: Callable = Callable()


func _draw() -> void:
	if fn.is_valid():
		fn.call(self)


func redraw() -> void:
	queue_redraw()
