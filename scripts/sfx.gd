class_name Sfx
extends Node

## 音频管理：一个音效播放器池 + 一条 BGM 轨（带交叉淡入淡出）。
## 素材全部来自 CC0 音源；若某个音效文件缺失，play() 静默跳过，不报错、不中断游戏。

const POOL_SIZE := 14

static var _inst: Sfx = null

var _pool: Array[AudioStreamPlayer] = []
var _music: AudioStreamPlayer = null
var _music_key: String = ""
var _music_tween: Tween = null
var muted: bool = false


func _ready() -> void:
	_inst = self
	process_mode = Node.PROCESS_MODE_ALWAYS
	for i in POOL_SIZE:
		var p := AudioStreamPlayer.new()
		p.bus = "Master"
		add_child(p)
		_pool.append(p)
	_music = AudioStreamPlayer.new()
	_music.bus = "Master"
	_music.volume_db = -80.0
	add_child(_music)


func _play(event: String, vol_db: float = 0.0, pitch: float = 1.0) -> void:
	if muted:
		return
	var s := Assets.sfx(event)
	if s == null:
		return
	var player: AudioStreamPlayer = null
	for p in _pool:
		if not p.playing:
			player = p
			break
	if player == null:
		# 全部占用时抢占最早创建的那一个
		player = _pool[0]
	player.stream = s
	player.volume_db = vol_db
	player.pitch_scale = clampf(pitch, 0.35, 3.0)
	player.play()


## 随机音高播放，避免重复音效过于机械
func _play_varied(event: String, vol_db: float = 0.0, spread: float = 0.12) -> void:
	_play(event, vol_db, randf_range(1.0 - spread, 1.0 + spread))


func _music_to(key: String, fade: float) -> void:
	if _music_key == key and _music != null and _music.playing:
		return
	var s := Assets.bgm(key)
	if s == null:
		return
	if s is AudioStreamOggVorbis:
		(s as AudioStreamOggVorbis).loop = true
	elif s is AudioStreamMP3:
		(s as AudioStreamMP3).loop = true
	elif s is AudioStreamWAV:
		(s as AudioStreamWAV).loop_mode = AudioStreamWAV.LOOP_FORWARD
	_music_key = key
	if _music_tween != null and _music_tween.is_valid():
		_music_tween.kill()
	_music.volume_db = -60.0
	_music.stream = s
	_music.play()
	_music_tween = create_tween()
	_music_tween.tween_property(_music, "volume_db", -12.0, maxf(0.05, fade))


func _music_stop(fade: float) -> void:
	_music_key = ""
	if _music == null or not _music.playing:
		return
	if _music_tween != null and _music_tween.is_valid():
		_music_tween.kill()
	_music_tween = create_tween()
	_music_tween.tween_property(_music, "volume_db", -60.0, maxf(0.05, fade))
	_music_tween.tween_callback(_music.stop)


func _set_muted(v: bool) -> void:
	muted = v
	if _music != null:
		_music.volume_db = -80.0 if v else (-12.0 if _music_key != "" else -80.0)


# ---- 静态门面 ----

static func play(event: String, vol_db: float = 0.0, pitch: float = 1.0) -> void:
	if _inst != null:
		_inst._play(event, vol_db, pitch)


static func play_varied(event: String, vol_db: float = 0.0, spread: float = 0.12) -> void:
	if _inst != null:
		_inst._play_varied(event, vol_db, spread)


static func music(key: String, fade: float = 1.2) -> void:
	if _inst != null:
		_inst._music_to(key, fade)


static func stop_music(fade: float = 0.8) -> void:
	if _inst != null:
		_inst._music_stop(fade)


static func set_muted(v: bool) -> void:
	if _inst != null:
		_inst._set_muted(v)


static func toggle_muted() -> bool:
	if _inst != null:
		_inst._set_muted(not _inst.muted)
		return _inst.muted
	return false
