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

## 随包字体子集。
## Web 平台拿不到任何系统字体 —— SystemFont 按名字逐个查会全部落空，
## 中文会整句渲染成方块。所以中文字形必须随包提供。
## 两个文件都是按本项目实际用到的字符子集化过的，合计约 320 KB：
##   CJK  —— Noto Sans SC Light（SIL OFL 1.1），934 字形
##   MONO —— Cascadia Mono Regular（MIT），116 字形，只有拉丁与符号
const FONT_CJK := DIR_FONT + "NotoSansSC-Light-subset.ttf"
const FONT_MONO := DIR_FONT + "CascadiaMono-subset.ttf"
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
static var _font_fallback: Font = null
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


## 等宽：键位行用它，「终端输出」的机械感与代码空间的设定一致。
## 拉丁取自随包的 Cascadia Mono，中文由 CJK 子集兜底。
static func mono_font() -> Font:
	if _font_mono == null:
		var m := _font_file(FONT_MONO)
		if m != null:
			m.fallbacks = [_fallback_font()]
			_font_mono = m
		else:
			# 随包字体缺失时才退回系统等宽
			var sf := SystemFont.new()
			sf.font_names = PackedStringArray([
				"JetBrains Mono", "Cascadia Mono", "Consolas", "Courier New", "monospace"
			])
			sf.fallbacks = [_fallback_font()]
			_font_mono = sf
	return _font_mono


## 细体：用于空灵氛围下的提示文字。
## 等宽字体自带「终端 / 代码」的机械感，和迷茫的氛围相反，所以另开一套。
static func soft_font() -> Font:
	if _font_soft == null:
		var f := _font_file(FONT_CJK)
		if f != null:
			# 它自己就含全部中文与标点，不需要再挂回退（也不该挂，会自引用）
			_font_soft = f
		else:
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



## 只取字体文件本身，不挂回退链 —— 回退由调用方决定，避免把字体挂成自己的回退。
static func _font_file(path: String) -> FontFile:
	if not ResourceLoader.exists(path):
		return null
	var r: Resource = load(path)
	if r is FontFile:
		return r
	return null


## 中文兜底：优先随包 CJK 子集，只有它缺失时才退回系统字体。
## 之所以不直接依赖 SystemFont —— Web 平台没有任何系统字体可用。
static func _fallback_font() -> Font:
	if _font_fallback == null:
		var f := _font_file(FONT_CJK)
		if f != null:
			_font_fallback = f
		else:
			var sf := SystemFont.new()
			sf.font_names = PackedStringArray([
				"Microsoft YaHei UI", "Microsoft YaHei", "SimHei", "Noto Sans CJK SC",
				"Source Han Sans SC", "PingFang SC", "sans-serif",
			])
			_font_fallback = sf
	return _font_fallback


static func _load_font(path: String) -> Font:
	var f := _font_file(path)
	if f != null:
		# Kenney Future 只有拉丁字形，中文会渲染成空白方块。
		# 挂一个中文字体做 fallback，标题字体才敢用来排中文。
		f.fallbacks = [_fallback_font()]
		return f
	return ThemeDB.fallback_font


## 供启动时自检：返回缺失素材清单（空数组表示全部就绪）
static func report_missing() -> Array[String]:
	return missing
