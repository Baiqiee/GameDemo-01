extends Node2D

## REBOOT — 赛博代码空间短流程游戏主控
## 职责：输入兜底注册、阶段状态机、阶段间的顺序切换。
## 每个阶段是一个自包含的脚本类（Node2D），完成时发出 finished 信号。

const PHASE_BOOT := preload("res://scripts/phase/boot.gd")
const PHASE_TEACH := preload("res://scripts/phase/teach.gd")
const PHASE_BATTLE := preload("res://scripts/phase/battle.gd")
const PHASE_CORRIDOR := preload("res://scripts/phase/corridor.gd")
const PHASE_ENDING := preload("res://scripts/phase/ending.gd")

## 就地初始化，不要放到 _ready() 里 —— 外部（截图 / 自动化工具）会在
## add_child 之后、_ready 之前就读 phase_count()，那时拿到 0 会导致
## 「直接从第 N 阶段开始」静默失效。
var _order: Array[GDScript] = [PHASE_BOOT, PHASE_TEACH, PHASE_BATTLE, PHASE_CORRIDOR, PHASE_ENDING]
var _index: int = 0
var _phase: Node = null


func _ready() -> void:
	# 2D MSAA 在 Web 的 GLES3 后端上不支持，开着只会在浏览器控制台刷警告，
	# 所以项目设置里默认关掉，桌面端在这里重新打开。
	if not OS.has_feature("web"):
		get_viewport().msaa_2d = Viewport.MSAA_2X
	_ensure_input_actions()
	var sfx := Sfx.new()
	sfx.name = "Sfx"
	add_child(sfx)
	_enter(0)


func _process(delta: float) -> void:
	Pal.update(delta)
	if Input.is_action_just_pressed("restart"):
		_enter(0)


## ---- 供外部（自动化测试）查询的只读入口 ----

func phase_index() -> int:
	return _index


func phase_node() -> Node:
	return _phase


func phase_count() -> int:
	return _order.size()


func _ensure_input_actions() -> void:
	## project.godot 里已写入 Input Map；这里做兜底注册，
	## 避免映射缺失导致整个游戏完全无法操作。
	var key_map := {
		"move_left": [KEY_A, KEY_LEFT],
		"move_right": [KEY_D, KEY_RIGHT],
		"move_up": [KEY_W, KEY_UP],
		"move_down": [KEY_S, KEY_DOWN],
		"jump": [KEY_SPACE],
		"run": [KEY_SHIFT],
		"restart": [KEY_R],
		"ui_confirm": [KEY_SPACE, KEY_ENTER],
	}
	for action_name in key_map.keys():
		if not InputMap.has_action(action_name):
			InputMap.add_action(action_name)
		if InputMap.action_get_events(action_name).is_empty():
			for kc in key_map[action_name]:
				var ev := InputEventKey.new()
				ev.physical_keycode = kc
				InputMap.action_add_event(action_name, ev)
	if not InputMap.has_action("attack"):
		InputMap.add_action("attack")
	if InputMap.action_get_events("attack").is_empty():
		var mb := InputEventMouseButton.new()
		mb.button_index = MOUSE_BUTTON_LEFT
		InputMap.action_add_event("attack", mb)


func _enter(idx: int) -> void:
	if is_instance_valid(_phase):
		_phase.queue_free()
		_phase = null
	_index = clampi(idx, 0, _order.size() - 1)
	var script: GDScript = _order[_index]
	var inst: Node = script.new()
	inst.name = "Phase_%d" % _index
	_phase = inst
	add_child(inst)
	if inst.has_signal("finished"):
		inst.connect("finished", _on_phase_finished)
	if inst.has_signal("restart_requested"):
		inst.connect("restart_requested", _on_restart_requested)


func _on_phase_finished() -> void:
	_enter((_index + 1) % _order.size())


func _on_restart_requested() -> void:
	_enter(0)
