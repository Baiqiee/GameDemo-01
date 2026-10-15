# Demo

一个短小的 2D 游戏 Demo。Godot 4.7 + GL Compatibility，960×540，纯 GDScript，无插件依赖。

主角是一个人工智能实体。它在一次解体中醒来，只剩左右两个方向可用；每摔死一次，
就从自己的残骸里捞回一点新动作。平台跳跃 → 上帝视角战斗 → 2D 第一人称走廊 → 结局，
完整流程两三分钟。

## 运行

需要 Godot 4.7。

编辑器里：用 Godot 打开本目录，按 <kbd>F5</kbd>。

命令行：

```bash
godot --path .
```

## 操作

| 按键 | 作用 | 何时可用 |
|---|---|---|
| <kbd>A</kbd> / <kbd>D</kbd> | 向左 / 向右移动 | 全程 |
| <kbd>空格</kbd> | 跳跃 | 第一次坠落之后 |
| <kbd>Shift</kbd> 长按 | 奔跑，水平速度持续上升 | 远距离平台坠落之后 |
| 鼠标左键 | 朝光标方向聚拢代码并挥出 | 战斗第一次死亡之后 |
| <kbd>W</kbd> / <kbd>A</kbd> / <kbd>D</kbd> | 第一人称走廊：前进 / 原地转身 | 走廊段 |
| <kbd>R</kbd> | 重新开始 | 全程 |

## 引导设计

提示刻意做得很轻。不写主语（既不用「我」，也不写「它」），不用系统通知的口吻
（没有时间戳、没有 `[SYS]` 前缀、没有「已解锁」）。它只在角色**死过一次**之后浮出来，
读起来是它自己从残骸里推出来的一句话；紧跟一行等宽字体的键位，明确写出哪个键触发什么。

```
解体之后，有一段位移没有被抹掉
    空格键 → 向上跃起
```

## 目录

```
main.tscn              唯一入口
scripts/
  main.gd              阶段状态机
  pal.gd               全局色温：蓝青色代码空间，四阶段之间平滑过渡
  assets.gd            素材访问层，任何素材缺失都返回 null，由绘制端降级
  sfx.gd               音效池 + BGM 交叉淡入
  tx.gd                文字居中 / 右对齐（draw_string 的 width 传负数会忽略对齐参数）
  fx/                  代码雨、代码粒子、绘制代理
  hud/whisper.gd       提示系统：双行「结论 + 键位」，居中偏上，逐字缓慢淡入
  phase/               boot / teach / battle / corridor / ending
assets/                精灵、瓦片、粒子、UI、音效、BGM、字体
```

五个阶段：`boot` 标题页 → `teach` 平台跳跃 → `battle` 上帝视角战斗 →
`corridor` 2D 第一人称 → `ending` 结局。

关卡数值是按「滞空时间 × 水平速度」倒推的，物理跑固定步长（`1/60`），
所以不同帧率下跳跃距离一致。

## 素材

全部为 CC0，可商用、无需署名：

- **角色** — [MV Platformer Female (32x64)](https://opengameart.org/)（OpenGameArt）。
  32×64 图集，身体 / 服装 / 发型分层，可在引擎里自由叠色。
- **瓦片、UI、音效** — [Kenney](https://kenney.nl/)：platformer-art-deluxe、
  particle-pack、ui-pack、interface-sounds、impact-sounds、digital-audio、sci-fi-sounds
- **背景音乐** — OpenGameArt（CC0）
- **字体** — Kenney Future（CC0）。该字体无中文字形，代码里挂了系统 CJK 字体做回退

`assets/` 下保留了少量当前没有调用点的素材：`sprites/player/`、`sprites/bg/`、`ui/`
以及大部分粒子贴图。访问函数还在，但没有任何地方调用它们，想精简可以直接删。
