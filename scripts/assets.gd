class_name Assets
extends RefCounted

## 素材访问层。
## 全部素材都是 CC0（Kenney / OpenGameArt），已下载到 res://assets/。
## 关键约定：任何资源加载失败都返回 null，绘制端必须自行降级为程序化图形，
## 保证素材缺失时游戏仍然可玩、不白屏。

const DIR_SPRITE := "res://assets/sprites/"
const DIR_TILE := "res://assets/sprites/tiles/"
const DIR_PLAYER := "res://assets/sprites/player/"
const DIR_PARTICLE := "res://assets/sprites/particles/"
const DIR_UI := "res://assets/ui/"
const DIR_FONT := "res://assets/fonts/"
const DIR_BGM := "res://assets/audio/bgm/"
const DIR_SFX := "res://assets/audio/sfx/"

## 音效事件 → 文件名映射
const SFX_MAP := {
	"jump": "highUp.ogg",
	"jump_alt": "phaseJump1.ogg",
	"land": "impactSoft_medium_000.ogg",
	"footstep": "footstep_concrete_002.ogg",
	"dissolve": "laser2.ogg",
	"death": "lowFrequency_explosion_000.ogg",
	"unlock": "powerUp1.ogg",
	"punch_swing": "zap1.ogg",
	"punch_hit": "impactPunch_medium_000.ogg",
	"shatter": "impactMetal_medium_000.ogg",
	"enemy_spawn": "glitch_001.ogg",
	"enemy_spawn2": "glitch_002.ogg",
	"log_tick": "click_001.ogg",
	"confirm": "confirmation_001.ogg",
	"panel": "maximize_001.ogg",
	"error": "bong_001.ogg",
	"door_hum": "forceField_000.ogg",
	"door_open": "doorOpen_000.ogg",
	"portal": "phaserUp1.ogg",
	"white_out": "computerNoise_000.ogg",
	"wave": "maximize_002.ogg",
	"ui_click": "click_002.ogg",
}

const BGM_MAP := {
	"teach": "bgm_teach.ogg",
	"battle": "bgm_battle.mp3",
	"ending": "bgm_ending.ogg",
}

## 战斗/结局阶段使用的粒子精灵（Kenney particle pack）
const PARTICLE_SPRITES := [
	"star_01", "star_03", "star_05", "star_07", "star_09",
	"spark_01", "spark_03", "spark_05", "spark_07",
	"circle_02", "circle_04",
	"magic_02", "magic_04",
	"light_01", "light_03",
	"twirl_02", "symbol_01", "symbol_02",
	"flare_01", "trace_04", "trace_06", "smoke_04",
]

static var _tex_cache: Dictionary = {}
static var _stream_cache: Dictionary = {}
static var _font_title: Font = null
static var _font_mono: Font = null
static var _font_soft: Font = null
static var _font_title_narrow: Font = null
static var missing: Array[String] = []


static func tex(path: String) -> Texture2D:
	if _tex_cache.has(path):
		return _tex_cache[path]
	var t: Texture2D = null
	if ResourceLoader.exists(path):
		var r: Resource = load(path)
		if r is Texture2D:
			t = r
	if t == null and not missing.has(path):
		missing.append(path)
	_tex_cache[path] = t
	return t


static func player(name: String) -> Texture2D:
	return tex(DIR_PLAYER + name + ".png")


static func tile(name: String) -> Texture2D:
	return tex(DIR_TILE + name + ".png")


static func ui(name: String) -> Texture2D:
	return tex(DIR_UI + name + ".png")


static func particle(name: String) -> Texture2D:
	return tex(DIR_PARTICLE + name + ".png")


static func bg_tile(index: int) -> Texture2D:
	return tex(DIR_SPRITE + "bg/tile_%04d.png" % index)


## 行走循环的 11 帧（缺失时返回空数组，绘制端自行降级）
static func walk_frames() -> Array:
	var out: Array = []
	for i in range(1, 12):
		var t := player("p1_walk%02d" % i)
		if t != null:
			out.append(t)
	return out


static func stream(path: String) -> AudioStream:
	if _stream_cache.has(path):
		return _stream_cache[path]
	var s: AudioStream = null
	if ResourceLoader.exists(path):
		var r: Resource = load(path)
		if r is AudioStream:
			s = r
	if s == null and not missing.has(path):
		missing.append(path)
	_stream_cache[path] = s
	return s


static func sfx(event: String) -> AudioStream:
	if not SFX_MAP.has(event):
		return null
	return stream(DIR_SFX + SFX_MAP[event])


static func bgm(key: String) -> AudioStream:
	if not BGM_MAP.has(key):
		return null
	return stream(DIR_BGM + BGM_MAP[key])


static func title_font() -> Font:
	if _font_title == null:
		_font_title = _load_font(DIR_FONT + "Kenney Future.ttf")
	return _font_title


static func title_narrow_font() -> Font:
	if _font_title_narrow == null:
		_font_title_narrow = _load_font(DIR_FONT + "Kenney Future Narrow.ttf")
	return _font_title_narrow


static func mono_font() -> Font:
	if _font_mono == null:
		var sf := SystemFont.new()
		sf.font_names = PackedStringArray([
			"JetBrains Mono", "Cascadia Mono", "Consolas", "Courier New", "monospace"
		])
		_font_mono = sf
	return _font_mono


## 衬线/细体：用于空灵氛围下的提示文字。
## 等宽字体自带「终端 / 代码」的机械感，和迷茫的氛围相反，所以另开一套。
static func soft_font() -> Font:
	if _font_soft == null:
		var sf := SystemFont.new()
		sf.font_names = PackedStringArray([
			"Microsoft YaHei UI Light", "Microsoft YaHei Light", "Microsoft YaHei UI",
			"Microsoft YaHei", "Noto Sans CJK SC Light", "Noto Sans CJK SC",
			"Segoe UI Light", "Segoe UI", "sans-serif",
		])
		_font_soft = sf
	return _font_soft


## 角色图集：32x64 一帧，10 列 x 10 行。分层结构为 身体 + 服装 + 发型。
const HEROINE_DIR := "res://assets/sprites/heroine/"
const HERO_FRAME := Vector2i(32, 64)
const HERO_COLS := 10


static func heroine(name: String) -> Texture2D:
	return tex(HEROINE_DIR + name + ".png")


## 取图集里某一帧的源区域（配合 draw_texture_rect_region 使用，不必切图）
static func hero_frame(col: int, row: int) -> Rect2:
	return Rect2(float(col * HERO_FRAME.x), float(row * HERO_FRAME.y),
		float(HERO_FRAME.x), float(HERO_FRAME.y))



static func _load_font(path: String) -> Font:
	if ResourceLoader.exists(path):
		var r: Resource = load(path)
		if r is FontFile:
			# Kenney Future 只有拉丁字形，中文会渲染成空白方块。
			# 挂一个系统中文字体做 fallback，标题字体才敢用来排中文。
			var fb := SystemFont.new()
			fb.font_names = PackedStringArray([
				"Microsoft YaHei UI", "Microsoft YaHei", "SimHei", "Noto Sans CJK SC",
				"Source Han Sans SC", "PingFang SC", "sans-serif",
			])
			(r as FontFile).fallbacks = [fb]
			return r
		if r is Font:
			return r
	return ThemeDB.fallback_font


## 供启动时自检：返回缺失素材清单（空数组表示全部就绪）
static func report_missing() -> Array[String]:
	return missing
