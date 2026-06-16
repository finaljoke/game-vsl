# Bot 驱动器 + 遥测管线 实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 给这款 VS-like 原型加一条「bot 自动游玩 → headless 快进 → 确定性种子 → 结构化遥测导出」管线，把取样从分钟级人力变成秒级自动化，并补齐当前完全缺失的「威胁/防御」观测轴。

**Architecture:** 四个单元各一职责——`RunHarness`(新 autoload，编排：读命令行、驱动 bot、自动选卡、设种子/快进、检测终局、收尾退出)、`DebugMetrics`(扩现有：补威胁轴订阅 + getters + 自定义监视器)、`RunRecorder`(新 autoload，纯序列化：tick CSV / event JSONL / summary.json)、`player.gd`(+几行注入钩子)。无 `--bot` 命令行参数时全链路惰性，真人游玩零改变。

**Tech Stack:** Godot 4.6.3 / GDScript、autoload 单例、`OS.get_cmdline_user_args()`、`Engine.time_scale`、`FileAccess`/`DirAccess`、全局 `seed()`、gdUnit4 测试。

**确定性依据(实现前必读):** `enemy_spawner.gd` 与 `card_pool.gd` 全程用全局 `randi()/randf()`,所以「一句 `seed(N)`」即可让整局可复现。两次同 `--seed --bot --cards --fast` 的跑必须产出相等的 summary 关键字段——这是验收 #3。

**关键参数集中表(下文多处引用,改这里即可):**

| 常量 | 值 | 用途 |
|---|---|---|
| `RunHarness.PERCEPTION_RADIUS` | `220.0` | kite 感知半径(px) |
| `RunHarness.CENTER_PULL_GAIN` | `0.004` | kite 避墙(拉回中心)增益 |
| `RunHarness.DEFAULT_FAST` | `3.0` | `--fast` 缺省 |
| `RunHarness.DEFAULT_INTERVAL` | `1.0` | tick CSV 采样周期(游戏秒) |
| `DebugMetrics.DANGER_THRESHOLD` | `0.25` | hp_pct 低于此判定"危险" |
| `DebugMetrics.NEAR_RADIUS` | `140.0` | enemies_near 统计半径(px) |
| 竞技场 | `1280×720`,中心 `(640,360)` | 来自 `data/arenas/default.tres`,kite 避墙用 |

---

## 文件结构

**新增:**
- `autoloads/run_harness.gd` — 编排器。命令行解析、bot 移动驱动、自动选卡、生命周期(种子/快进/终局/退出)。含两个纯静态函数 `compute_kite_dir` / `choose_card` 供单测。
- `autoloads/run_recorder.gd` — 纯序列化。tick CSV、event JSONL、summary.json。含纯静态 `format_row` / `tick_header` 供单测。
- `tests/test_run_harness.gd` — kite 向量、选卡优先级、命令行解析、hitstop 跳过。
- `tests/test_run_recorder.gd` — CSV 表头/行格式、输出路径解析。
- `telemetry/` — 输出目录(运行时 `DirAccess` 自建,`.gitignore` 不入库)。

**修改:**
- `scenes/player/player.gd` — `_physics_process` 注入钩子(+1 字段,改 1 行)。
- `autoloads/debug_metrics.gd` — 补威胁轴订阅(enemy_hit/player_hit) + HP/危险轮询 + getters/snapshot + 自定义监视器。
- `autoloads/game_feel.gd` — `_trigger_hitstop` 在 `RunHarness.active` 时跳过(确定性),恢复到 `RunHarness.base_time_scale` 而非写死 1.0。
- `scenes/ui/level_up_ui.gd` — `_on_level_up` 开头加 `if RunHarness.active: return`(避免第二次 `pick()` 破坏种子)。
- `project.godot` — 注册 `RunRecorder`、`RunHarness` 两个 autoload(列在 `DebugMetrics` 之后:它们 `_ready` 要连 GameManager/GameFeel/CardPool 信号,必须晚于这些)。
- `.gitignore` — 加 `telemetry/`。

**autoload 顺序约束(关键):** `RunRecorder` 必须排在 `RunHarness` 之前(harness `_ready` 会调 `RunRecorder.begin`);二者都必须排在 `GameManager/GameFeel/CardPool/DebugMetrics` 之后(要连它们的信号 / 读它们的 getter)。种子无需 harness 置顶——首个 `randi()` 发生在主场景 `_ready` 之后的首次 spawn/pick,晚于所有 autoload `_ready`,故 harness 在 `_ready` 里 `seed()` 即足够。

---

## 设计说明(实现者必读,避免踩坑)

1. **注入钩子哨兵值** `Vector2.INF`:IEEE 下 `INF == INF` 为真,故 `bot_input != Vector2.INF` 能可靠区分"真人(默认)"与"bot 覆写"。

2. **hitstop 与确定性(本计划对 spec §7/验收#5 的细化):** 原 `_trigger_hitstop` 用 `ignore_time_scale=true` 的实时计时器,其窗口内物理帧数依赖真机 wall-clock → 跨机/跨跑不确定。boss 死亡(3 小+1 终)会触发。**修法:bot 模式(`RunHarness.active`)直接跳过 hitstop**(headless 下顿帧无视觉意义,且消除不确定源);人类模式保留顿帧但恢复到 `RunHarness.base_time_scale`(惰性时=1.0)。这比 spec 原方案(仅改恢复值)更安全。

3. **director 事件不入 event log(对 spec §6 的修正):** spec §6 列了 `director{type,count}`,但 spawner 无对应信号,捕获它需改 `enemy_spawner.gd`——而 spec §10 文件清单**不含** spawner。为保持 spawner 零改动,v1 event log 用 `boss_incoming`(已有信号,同样是威胁尖峰标记)替代 director。事件类型 v1:`level_up / player_hit / boss_incoming / death / victory`。`player_hit` 高频出现于爆发波,定位"因"足够。

4. **rates 用"差分总量"而非"窗口重置":** `RunRecorder` 每 tick 读 `DebugMetrics` 的累计 getter 并与上 tick 差分算 /s,与 `DebugMetrics` 自己的 5s 控制台窗口解耦,二者互不干扰。

5. **游戏时间口径:** `Engine.time_scale` 会缩放 `_process(delta)` 的 delta,累加 delta 得到的是**游戏秒**;故所有 /s 速率在 fast=1 与 fast=3 下口径一致。

6. **res:// 可写:** 从源码 `--path .` 跑(非导出 .pck)时 `res://` 即项目目录,可写。输出落 `res://telemetry/`。

---

## Task 1: RunHarness 骨架 + 两个纯函数 + 注册 autoload

建立 `RunHarness` autoload,先只放 `active`/`base_time_scale` 状态与两个**纯静态**决策函数(kite 向量、选卡优先级),并注册到 project.godot。其他文件随后即可引用 `RunHarness.active`。本任务不接管任何运行时驱动。

**Files:**
- Create: `autoloads/run_harness.gd`
- Modify: `project.godot:18-27`(`[autoload]` 段)
- Test: `tests/test_run_harness.gd`

- [ ] **Step 1: 写失败测试(kite + 选卡两个纯函数)**

创建 `tests/test_run_harness.gd`:

```gdscript
# tests/test_run_harness.gd
extends GdUnitTestSuite

const Harness := preload("res://autoloads/run_harness.gd")

# ── kite 向量:远离敌群 + 避墙拉回中心 ─────────────────────────────────────
func test_kite_flees_single_enemy_on_left() -> void:
	# 玩家在中心,敌人在左侧 → 应朝右(正 x)逃
	var dir := Harness.compute_kite_dir(Vector2(640, 360), [Vector2(540, 360)], Vector2(640, 360), 220.0)
	assert_float(dir.x).is_greater(0.0)

func test_kite_flees_single_enemy_on_right() -> void:
	var dir := Harness.compute_kite_dir(Vector2(640, 360), [Vector2(740, 360)], Vector2(640, 360), 220.0)
	assert_float(dir.x).is_less(0.0)

func test_kite_ignores_enemy_beyond_perception() -> void:
	# 敌人在感知半径外 + 玩家在中心 → 无斥力,无偏心 → 零向量
	var dir := Harness.compute_kite_dir(Vector2(640, 360), [Vector2(640, 50)], Vector2(640, 360), 220.0)
	assert_vector(dir).is_equal(Vector2.ZERO)

func test_kite_pulls_back_to_center_near_wall() -> void:
	# 无敌人但玩家贴右墙 → 应朝左(负 x)被拉回中心
	var dir := Harness.compute_kite_dir(Vector2(1200, 360), [], Vector2(640, 360), 220.0)
	assert_float(dir.x).is_less(0.0)

func test_kite_returns_unit_vector_when_nonzero() -> void:
	var dir := Harness.compute_kite_dir(Vector2(640, 360), [Vector2(540, 360)], Vector2(640, 360), 220.0)
	assert_float(dir.length()).is_equal_approx(1.0, 0.001)

# ── 选卡优先级表 ─────────────────────────────────────────────────────────
func test_choose_card_prefers_exact_id_higher_in_profile() -> void:
	var offered := [
		{"id": "perk_speed", "type": "perk"},
		{"id": "perk_hp", "type": "perk"},
	]
	var profile := ["perk_hp", "type:perk"]
	var picked := Harness.choose_card(offered, profile)
	assert_str(picked["id"]).is_equal("perk_hp")

func test_choose_card_matches_by_type_when_no_exact_id() -> void:
	var offered := [
		{"id": "knife_2", "type": "upgrade"},
		{"id": "perk_speed", "type": "perk"},
	]
	var profile := ["perk_hp", "type:upgrade"]
	var picked := Harness.choose_card(offered, profile)
	assert_str(picked["id"]).is_equal("knife_2")

func test_choose_card_falls_back_to_first_when_no_match() -> void:
	var offered := [
		{"id": "perk_xp", "type": "perk"},
		{"id": "perk_damage", "type": "perk"},
	]
	var profile := ["type:evolution"]
	var picked := Harness.choose_card(offered, profile)
	assert_str(picked["id"]).is_equal("perk_xp")

func test_default_profile_is_nonempty() -> void:
	assert_int(Harness.DEFAULT_PROFILE.size()).is_greater(0)
```

- [ ] **Step 2: 跑测试确认失败**

Run: `& "C:\Dev\GAME\Godot\Godot_v4.6.3-stable_win64_console.exe" --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/test_run_harness.gd`
（CLI 必须用 `_console.exe`（GUI 版抓不到 stdout/退出码）。gdUnit headless **必须**加 `--ignoreHeadlessMode`，否则直接 abort 退出码 103;`-s`/`-a` 路径用 `res://` 前缀。以上来自 memory「Godot 开发环境配置」,下同。）
Expected: FAIL —— `Harness` 没有 `compute_kite_dir` / `choose_card` / `DEFAULT_PROFILE`。

- [ ] **Step 3: 写 run_harness.gd 骨架(只含状态 + 两个纯函数)**

创建 `autoloads/run_harness.gd`:

```gdscript
# autoloads/run_harness.gd
# Bot 驱动 + 遥测编排器。无 --bot 命令行参数时完全惰性(active=false),真人游玩零影响。
# 职责:读命令行配置、每物理帧驱动 bot 移动、监听升级自动选卡、设种子/快进、检测终局收尾退出。
#
# 本文件含两个纯静态函数(compute_kite_dir / choose_card),不依赖场景,便于单测。
extends Node

# ── 可调参数(集中) ────────────────────────────────────────────────────────
const PERCEPTION_RADIUS: float = 220.0   # kite 感知半径(px):此半径内敌人产生斥力
const CENTER_PULL_GAIN: float = 0.004    # kite 避墙:离中心越远拉回越强
const DEFAULT_FAST: float = 3.0          # --fast 缺省(同种子 diff 验确定性后可升降)
const DEFAULT_INTERVAL: float = 1.0      # tick CSV 采样周期(游戏秒)
const NEAR_RADIUS: float = 140.0         # 传给 player.bot 的近敌半径(预留,DebugMetrics 另有同名)

# 选卡优先级表(命名 profile)。matcher: 精确卡 id,或 "type:<type>" 匹配卡型。
# default = 生存优先(先保命再进攻),给 bot 一套稳定可活满全程的 build。以后外置到 data/bot_profiles/。
const DEFAULT_PROFILE: Array = [
	"perk_hp", "synergy_lifesteal", "perk_heal",
	"type:evolution", "type:synergy", "type:upgrade",
	"type:weapon", "type:perk",
]
const PROFILES: Dictionary = {"default": DEFAULT_PROFILE}

# ── 运行时状态(Task 7 填充驱动逻辑;此处先声明,供其他文件引用) ────────────────
var active: bool = false                 # 是否 bot 模式(无 --bot 时恒 false → 全链路惰性)
var base_time_scale: float = 1.0         # 快进基线;game_feel hitstop 恢复到这里而非写死 1.0

# ── 纯静态决策函数(无场景依赖,单测覆盖) ──────────────────────────────────────

# kite 移动方向:Σ(远离半径内敌人,越近越强) + (拉回竞技场中心,避墙)。归一化;无净向量返回 ZERO。
static func compute_kite_dir(player_pos: Vector2, enemy_positions: Array, arena_center: Vector2, perception_radius: float) -> Vector2:
	var repulse := Vector2.ZERO
	for ep in enemy_positions:
		var to_player: Vector2 = player_pos - ep
		var d := to_player.length()
		if d > perception_radius or d <= 0.001:
			continue
		# 越近权重越大(d→0 时趋近 1,d→radius 时趋近 0)
		repulse += to_player.normalized() * (1.0 - d / perception_radius)
	var center_pull := (arena_center - player_pos) * CENTER_PULL_GAIN
	var dir := repulse + center_pull
	if dir.length() < 0.001:
		return Vector2.ZERO
	return dir.normalized()

# 从 offered 里按 profile 顺序取最高优先命中;无命中取第 0 张兜底(保证一定有解,防暂停卡死)。
static func choose_card(offered: Array, profile: Array) -> Dictionary:
	for matcher in profile:
		for card in offered:
			if _card_matches(card, String(matcher)):
				return card
	return offered[0] if not offered.is_empty() else {}

static func _card_matches(card: Dictionary, matcher: String) -> bool:
	if matcher.begins_with("type:"):
		return String(card.get("type", "")) == matcher.substr(5)
	return String(card.get("id", "")) == matcher
```

- [ ] **Step 4: 注册 autoload(RunHarness)**

编辑 `project.godot`,在 `[autoload]` 段 `DebugMetrics` 行**之后**插入 `RunHarness`(Task 6 再在其前插 `RunRecorder`)。把:

```
DebugMetrics="*res://autoloads/debug_metrics.gd"
SoundManager="*uid://bg6usvpgisg7x"
```

改为:

```
DebugMetrics="*res://autoloads/debug_metrics.gd"
RunHarness="*res://autoloads/run_harness.gd"
SoundManager="*uid://bg6usvpgisg7x"
```

- [ ] **Step 5: 跑测试确认通过**

Run: `& "C:\Dev\GAME\Godot\Godot_v4.6.3-stable_win64_console.exe" --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/test_run_harness.gd`
Expected: PASS —— 8 个用例全绿。

- [ ] **Step 6: 提交**

```bash
git add autoloads/run_harness.gd tests/test_run_harness.gd project.godot
git commit -m "feat(telemetry): RunHarness 骨架 + kite/选卡纯函数 + 注册 autoload"
```

---

## Task 2: player.gd 注入钩子

给玩家加一个 `bot_input` 字段;`_physics_process` 在其非哨兵值时用它替代键盘输入。默认 `Vector2.INF` = 真人路径,行为与现在完全一致。

**Files:**
- Modify: `scenes/player/player.gd:36-37`(加字段)、`scenes/player/player.gd:66-68`(改输入源)
- Test: `tests/test_player.gd`(追加用例)

- [ ] **Step 1: 写失败测试**

在 `tests/test_player.gd` **末尾**追加(先读该文件头部确认它用 `extends GdUnitTestSuite` 且有 `_player` 夹具;若无夹具则按本用例内联实例化):

```gdscript
# ── Bot 注入钩子 ───────────────────────────────────────────────────────────
func test_bot_input_overrides_movement() -> void:
	var scene := load("res://scenes/player/player.tscn") as PackedScene
	var p := auto_free(scene.instantiate() as Player)
	add_child(p)
	await get_tree().process_frame
	p.bot_input = Vector2(1, 0)
	p._physics_process(0.016)
	assert_float(p.velocity.x).is_greater(0.0)
	assert_float(p.velocity.y).is_equal_approx(0.0, 0.001)

func test_default_bot_input_is_inf_sentinel() -> void:
	var scene := load("res://scenes/player/player.tscn") as PackedScene
	var p := auto_free(scene.instantiate() as Player)
	add_child(p)
	await get_tree().process_frame
	# 默认 INF = 真人路径;无按键时 Input.get_vector 返回 ZERO → 速度 ZERO
	assert_bool(p.bot_input == Vector2.INF).is_true()
	p._physics_process(0.016)
	assert_float(p.velocity.length()).is_equal_approx(0.0, 0.001)
```

- [ ] **Step 2: 跑测试确认失败**

Run: `& "C:\Dev\GAME\Godot\Godot_v4.6.3-stable_win64_console.exe" --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/test_player.gd`
Expected: FAIL —— `Player` 无 `bot_input` 属性(`Invalid set/get`)。

- [ ] **Step 3: 加字段**

在 `scenes/player/player.gd`,把:

```gdscript
@onready var hurt_box: Area2D = $HurtBox
@onready var _sprite: Sprite2D = $Sprite2D
```

改为(在其上方插入字段):

```gdscript
# Bot 注入钩子:默认 INF=真人(走键盘);RunHarness 每物理帧覆写为移动向量。详见 autoloads/run_harness.gd。
var bot_input: Vector2 = Vector2.INF

@onready var hurt_box: Area2D = $HurtBox
@onready var _sprite: Sprite2D = $Sprite2D
```

- [ ] **Step 4: 改输入源**

在 `_physics_process`,把:

```gdscript
func _physics_process(delta: float) -> void:
	var dir := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	velocity = dir * SPEED * speed_mult
```

改为:

```gdscript
func _physics_process(delta: float) -> void:
	var dir := bot_input if bot_input != Vector2.INF else \
		Input.get_vector("move_left", "move_right", "move_up", "move_down")
	velocity = dir * SPEED * speed_mult
```

- [ ] **Step 5: 跑测试确认通过**

Run: `& "C:\Dev\GAME\Godot\Godot_v4.6.3-stable_win64_console.exe" --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/test_player.gd`
Expected: PASS —— 新增 2 用例通过,既有 player 用例不回归。

- [ ] **Step 6: 提交**

```bash
git add scenes/player/player.gd tests/test_player.gd
git commit -m "feat(telemetry): player 注入钩子 bot_input(默认 INF=真人惰性)"
```

---

## Task 3: game_feel hitstop 确定性修复

`_trigger_hitstop` 在 bot 模式跳过(消除实时计时器引入的不确定性);人类模式保留顿帧但恢复到 `RunHarness.base_time_scale` 而非写死 1.0。

**Files:**
- Modify: `autoloads/game_feel.gd:166-169`
- Test: `tests/test_run_harness.gd`(追加 hitstop 用例)

- [ ] **Step 1: 写失败测试**

在 `tests/test_run_harness.gd` 末尾追加:

```gdscript
# ── hitstop 在 bot 模式跳过(确定性) ───────────────────────────────────────
func test_hitstop_skipped_when_harness_active() -> void:
	var prev_active := RunHarness.active
	var prev_scale := Engine.time_scale
	RunHarness.active = true
	RunHarness.base_time_scale = 3.0
	Engine.time_scale = 3.0
	GameFeel._trigger_hitstop(0.05)
	# bot 模式应直接跳过,不把 time_scale 砸到 0.05
	assert_float(Engine.time_scale).is_equal_approx(3.0, 0.001)
	# 还原,避免污染其他用例
	RunHarness.active = prev_active
	RunHarness.base_time_scale = 1.0
	Engine.time_scale = prev_scale
```

- [ ] **Step 2: 跑测试确认失败**

Run: `& "C:\Dev\GAME\Godot\Godot_v4.6.3-stable_win64_console.exe" --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/test_run_harness.gd`
Expected: FAIL —— 现 `_trigger_hitstop` 无条件设 `Engine.time_scale = 0.05`,断言 3.0 失败。

- [ ] **Step 3: 改 _trigger_hitstop**

在 `autoloads/game_feel.gd`,把:

```gdscript
func _trigger_hitstop(duration: float) -> void:
	Engine.time_scale = 0.05
	var t := get_tree().create_timer(duration, false, true, true)
	t.timeout.connect(func() -> void: Engine.time_scale = 1.0)
```

改为:

```gdscript
func _trigger_hitstop(duration: float) -> void:
	# bot/headless 模式跳过:顿帧用实时计时器,其窗口内物理帧数依赖真机 wall-clock,会破坏确定性。
	# 且 headless 下顿帧无视觉意义。详见 RunHarness。
	if RunHarness.active:
		return
	Engine.time_scale = 0.05
	var t := get_tree().create_timer(duration, false, true, true)
	# 恢复到快进基线(惰性时=1.0)而非写死 1.0,避免冲掉 --fast。
	t.timeout.connect(func() -> void: Engine.time_scale = RunHarness.base_time_scale)
```

- [ ] **Step 4: 跑测试确认通过**

Run: `& "C:\Dev\GAME\Godot\Godot_v4.6.3-stable_win64_console.exe" --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/test_run_harness.gd`
Expected: PASS。

- [ ] **Step 5: 提交**

```bash
git add autoloads/game_feel.gd tests/test_run_harness.gd
git commit -m "fix(game_feel): hitstop bot 模式跳过 + 恢复到 base_time_scale(确定性/快进兼容)"
```

---

## Task 4: level_up_ui 早退守卫

bot 模式下选卡由 RunHarness 单点解决;`level_up_ui._on_level_up` 必须早退,否则它会**独立再 `pick()` 一次**(第二次 `randi()` 破坏种子复现)。

**Files:**
- Modify: `scenes/ui/level_up_ui.gd:67-72`
- Test: `tests/test_run_harness.gd`(追加 UI 早退用例)

- [ ] **Step 1: 写失败测试**

在 `tests/test_run_harness.gd` 末尾追加:

```gdscript
# ── level_up_ui 在 bot 模式早退(不二次 pick) ───────────────────────────────
func test_level_up_ui_early_returns_when_harness_active() -> void:
	var prev_active := RunHarness.active
	RunHarness.active = true
	var scene := load("res://scenes/ui/level_up_ui.tscn") as PackedScene
	var ui := auto_free(scene.instantiate())
	add_child(ui)
	await get_tree().process_frame
	ui._on_level_up()
	# 早退:不显示、不出卡
	assert_bool(ui.visible).is_false()
	assert_int(ui._current_cards.size()).is_equal(0)
	RunHarness.active = prev_active
```

- [ ] **Step 2: 跑测试确认失败**

Run: `& "C:\Dev\GAME\Godot\Godot_v4.6.3-stable_win64_console.exe" --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/test_run_harness.gd`
Expected: FAIL —— 现 `_on_level_up` 会设 `visible=true` 并 `pick()` 填 `_current_cards`,断言 0 张失败。

- [ ] **Step 3: 加守卫**

在 `scenes/ui/level_up_ui.gd`,把:

```gdscript
func _on_level_up() -> void:
	visible = true
	_player = get_tree().get_first_node_in_group("player") as Player
	_current_cards = CardPool.pick(_player)
	_build_cards(_current_cards)
	_update_footer()
```

改为:

```gdscript
func _on_level_up() -> void:
	# bot 模式:选卡由 RunHarness 单点解决(唯一一次 pick)。UI 早退,避免第二次 pick() 破坏种子复现。
	if RunHarness.active:
		return
	visible = true
	_player = get_tree().get_first_node_in_group("player") as Player
	_current_cards = CardPool.pick(_player)
	_build_cards(_current_cards)
	_update_footer()
```

- [ ] **Step 4: 跑测试确认通过**

Run: `& "C:\Dev\GAME\Godot\Godot_v4.6.3-stable_win64_console.exe" --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/test_run_harness.gd`
Expected: PASS。

- [ ] **Step 5: 提交**

```bash
git add scenes/ui/level_up_ui.gd tests/test_run_harness.gd
git commit -m "feat(telemetry): level_up_ui bot 模式早退(单点 pick 保种子)"
```

---

## Task 5: DebugMetrics 补威胁轴

给现有观测仪补「威胁/防御」轴:订阅 `enemy_hit`(输出伤害)与 `player_hit`(承受伤害),每帧轮询玩家 HP 累计危险时长 / 最低血量,统计存活/近身敌人数,暴露 getters + `snapshot()`,并注册 `Performance` 自定义监视器供编辑器实时看图。

**Files:**
- Modify: `autoloads/debug_metrics.gd`(全文扩展)
- Test: `tests/test_debug_metrics.gd`(新建)

- [ ] **Step 1: 写失败测试(新建)**

创建 `tests/test_debug_metrics.gd`:

```gdscript
# tests/test_debug_metrics.gd
extends GdUnitTestSuite

# DebugMetrics 是 autoload 单例(全局可达)。这些用例直接调它的信号处理器/getter,
# 不依赖完整场景。每个用例先清零,避免跨用例污染累计值。

func before_test() -> void:
	DebugMetrics.reset_metrics()

func test_enemy_hit_accumulates_dmg_dealt() -> void:
	DebugMetrics._on_enemy_hit(10.0, Vector2.ZERO, null)
	DebugMetrics._on_enemy_hit(5.0, Vector2.ZERO, null)
	assert_float(DebugMetrics.get_dmg_dealt_total()).is_equal_approx(15.0, 0.001)

func test_player_hit_accumulates_dmg_taken() -> void:
	DebugMetrics._on_player_hit(8.0)
	DebugMetrics._on_player_hit(2.0)
	assert_float(DebugMetrics.get_dmg_taken_total()).is_equal_approx(10.0, 0.001)

func test_enemy_died_accumulates_kills() -> void:
	DebugMetrics._on_enemy_died(Vector2.ZERO, null)
	DebugMetrics._on_enemy_died(Vector2.ZERO, null)
	assert_int(DebugMetrics.get_kills_total()).is_equal(2)

func test_danger_accumulates_when_hp_low() -> void:
	# 直接喂 HP 采样:低于 25% 阈值 → 危险时长累加
	DebugMetrics._sample_hp(20.0, 100.0, 0.5)   # hp_pct=0.20 < 0.25 → +0.5s
	DebugMetrics._sample_hp(20.0, 100.0, 0.5)   # 再 +0.5s
	assert_float(DebugMetrics.get_danger_total()).is_equal_approx(1.0, 0.001)

func test_danger_not_accumulated_when_hp_high() -> void:
	DebugMetrics._sample_hp(80.0, 100.0, 0.5)   # hp_pct=0.80 ≥ 0.25 → 不累加
	assert_float(DebugMetrics.get_danger_total()).is_equal_approx(0.0, 0.001)

func test_hp_pct_min_tracks_lowest() -> void:
	DebugMetrics._sample_hp(80.0, 100.0, 0.1)
	DebugMetrics._sample_hp(15.0, 100.0, 0.1)
	DebugMetrics._sample_hp(50.0, 100.0, 0.1)
	assert_float(DebugMetrics.get_hp_pct_min()).is_equal_approx(0.15, 0.001)

func test_snapshot_has_both_axes() -> void:
	var snap := DebugMetrics.snapshot()
	# 进攻轴 + 威胁轴关键键齐全
	for key in ["kills_total", "dmg_dealt_total", "dmg_taken_total", "healed_total",
			"danger_total", "hp", "hp_pct", "hp_pct_min", "level", "enemies_alive", "enemies_near"]:
		assert_bool(snap.has(key)).is_true()
```

- [ ] **Step 2: 跑测试确认失败**

Run: `& "C:\Dev\GAME\Godot\Godot_v4.6.3-stable_win64_console.exe" --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/test_debug_metrics.gd`
Expected: FAIL —— `DebugMetrics` 无 `reset_metrics` / `_on_enemy_hit` / `_on_player_hit` / `_sample_hp` / getters / `snapshot`。

- [ ] **Step 3: 扩展 debug_metrics.gd**

把 `autoloads/debug_metrics.gd` 整文件替换为:

```gdscript
# autoloads/debug_metrics.gd
# 平衡观测仪表(可移除)。订阅 GameFeel 信号,维护「进攻轴 + 威胁轴」两套累计值,
# 每 LOG_INTERVAL 秒打印一行聚合;并对外暴露 getters/snapshot(供 RunRecorder 落盘)
# 及 Performance 自定义监视器(编辑器 Debugger→Monitors 实时看图)。本身不改任何数值。
#
# 移除方式:删本文件 + 去掉 project.godot [autoload] 里的 DebugMetrics 行即可。
extends Node

const ENABLED: bool = true          # 关闭即惰性(不订阅、不打印)
const LOG_INTERVAL: float = 5.0     # 聚合打印周期(秒,按游戏内 PLAYING 时间)
const SHOW_OVERLAY: bool = false    # 额外在屏幕左上角显示实时面板
const DANGER_THRESHOLD: float = 0.25  # hp_pct 低于此判定"危险"
const NEAR_RADIUS: float = 140.0    # enemies_near 统计半径(px)

# ── 进攻轴累计 ──────────────────────────────────────────────────────────────
var _kills_total: int = 0
var _dmg_dealt_total: float = 0.0
var _healed_total: float = 0.0
var _levelups_total: int = 0
var _level: int = 1
# ── 威胁轴累计 ──────────────────────────────────────────────────────────────
var _dmg_taken_total: float = 0.0
var _danger_total: float = 0.0      # hp_pct<阈值 的累计游戏秒
var _hp: float = 0.0
var _hp_pct: float = 1.0
var _hp_pct_min: float = 1.0
# ── 窗口(每 interval 重置,仅给控制台行) ─────────────────────────────────────
var _kills_window: int = 0
var _healed_window: float = 0.0
var _dmg_taken_window: float = 0.0
# ── 计时(仅 PLAYING 态累加,避免选卡暂停污染速率) ────────────────────────────
var _elapsed: float = 0.0
var _since_log: float = 0.0
var _last_levelup_t: float = 0.0

var _player_node: Player = null
var _overlay: Label = null

func _ready() -> void:
	if not ENABLED:
		set_process(false)
		return
	# 选卡时 get_tree().paused=true;用 ALWAYS 让仪表自身不被暂停(再靠状态门控速率)。
	process_mode = Node.PROCESS_MODE_ALWAYS
	GameFeel.enemy_hit.connect(_on_enemy_hit)
	GameFeel.enemy_died.connect(_on_enemy_died)
	GameFeel.player_hit.connect(_on_player_hit)
	GameFeel.player_leveled_up.connect(_on_player_leveled_up)
	GameFeel.player_healed.connect(_on_player_healed)
	_register_monitors()
	if SHOW_OVERLAY:
		_setup_overlay()
	print("[DebugMetrics] ON — 每 %.0fs 聚合一次(进攻+威胁两轴)" % LOG_INTERVAL)

# 清零所有累计(供测试/重开)。
func reset_metrics() -> void:
	_kills_total = 0
	_dmg_dealt_total = 0.0
	_healed_total = 0.0
	_levelups_total = 0
	_level = 1
	_dmg_taken_total = 0.0
	_danger_total = 0.0
	_hp = 0.0
	_hp_pct = 1.0
	_hp_pct_min = 1.0
	_kills_window = 0
	_healed_window = 0.0
	_dmg_taken_window = 0.0
	_elapsed = 0.0
	_since_log = 0.0
	_last_levelup_t = 0.0

# ── 信号处理 ────────────────────────────────────────────────────────────────
func _on_enemy_hit(amount: float, _position: Vector2, _enemy: Node2D) -> void:
	_dmg_dealt_total += amount

func _on_enemy_died(_position: Vector2, _enemy: Node2D) -> void:
	_kills_total += 1
	_kills_window += 1

func _on_player_hit(amount: float) -> void:
	_dmg_taken_total += amount
	_dmg_taken_window += amount

func _on_player_healed(amount: float) -> void:
	_healed_total += amount
	_healed_window += amount

func _on_player_leveled_up(level: int) -> void:
	_levelups_total += 1
	_level = level
	var gap := _elapsed - _last_levelup_t
	_last_levelup_t = _elapsed
	print("[DebugMetrics] 升级 → Lv%d  距上次 %.1fs (t=%.0fs)" % [level, gap, _elapsed])

# ── 每帧:轮询 HP + 累计危险/最低血(仅 PLAYING) ────────────────────────────
func _process(delta: float) -> void:
	if not _is_playing():
		return
	_elapsed += delta
	_since_log += delta
	var p := _get_player()
	if p != null:
		_sample_hp(p.hp, p.max_hp, delta)
	if _since_log >= LOG_INTERVAL:
		_log_aggregate()
		_since_log = 0.0
		_kills_window = 0
		_healed_window = 0.0
		_dmg_taken_window = 0.0
	if _overlay != null:
		_overlay.text = _overlay_text()

# HP 采样(纯逻辑,便于单测):更新当前血量/百分比,累计危险时长与最低血。
func _sample_hp(hp: float, max_hp: float, delta: float) -> void:
	_hp = hp
	_hp_pct = (hp / max_hp) if max_hp > 0.0 else 0.0
	if _hp_pct < _hp_pct_min:
		_hp_pct_min = _hp_pct
	if _hp_pct < DANGER_THRESHOLD:
		_danger_total += delta

# ── getters / snapshot(供 RunRecorder) ─────────────────────────────────────
func get_kills_total() -> int: return _kills_total
func get_dmg_dealt_total() -> float: return _dmg_dealt_total
func get_dmg_taken_total() -> float: return _dmg_taken_total
func get_healed_total() -> float: return _healed_total
func get_danger_total() -> float: return _danger_total
func get_hp() -> float: return _hp
func get_hp_pct() -> float: return _hp_pct
func get_hp_pct_min() -> float: return _hp_pct_min
func get_level() -> int: return _level
func get_elapsed() -> float: return _elapsed

func get_enemies_alive() -> int:
	return get_tree().get_nodes_in_group("enemies").size()

func get_enemies_near() -> int:
	var p := _get_player()
	if p == null:
		return 0
	var n := 0
	for e in get_tree().get_nodes_in_group("enemies"):
		if e is Node2D and p.global_position.distance_to(e.global_position) <= NEAR_RADIUS:
			n += 1
	return n

func snapshot() -> Dictionary:
	return {
		"kills_total": _kills_total,
		"dmg_dealt_total": _dmg_dealt_total,
		"dmg_taken_total": _dmg_taken_total,
		"healed_total": _healed_total,
		"danger_total": _danger_total,
		"hp": _hp,
		"hp_pct": _hp_pct,
		"hp_pct_min": _hp_pct_min,
		"level": _level,
		"enemies_alive": get_enemies_alive(),
		"enemies_near": get_enemies_near(),
	}

# ── Performance 自定义监视器(编辑器实时看图;headless 无害) ────────────────────
func _register_monitors() -> void:
	_add_monitor("vsl/kills_total", get_kills_total)
	_add_monitor("vsl/dmg_taken_total", get_dmg_taken_total)
	_add_monitor("vsl/hp_pct", get_hp_pct)
	_add_monitor("vsl/enemies_near", get_enemies_near)

func _add_monitor(id: String, callable: Callable) -> void:
	if not Performance.has_custom_monitor(id):
		Performance.add_custom_monitor(id, callable)

# ── 控制台聚合行(进攻 + 威胁) ───────────────────────────────────────────────
func _log_aggregate() -> void:
	var kps := float(_kills_window) / LOG_INTERVAL
	var dmg_taken_ps := _dmg_taken_window / LOG_INTERVAL
	var heal_ps := _healed_window / LOG_INTERVAL
	var lvl_pm := (float(_levelups_total) / _elapsed * 60.0) if _elapsed > 0.0 else 0.0
	print("[DebugMetrics] t=%5.0fs | 击杀 %.1f/s(累计%d) | 升级 %.2f/min | 受伤 %.1f/s | HP %.0f%%(最低%.0f%%) | 嗜血 %.2f/s | tscale %.2f"
			% [_elapsed, kps, _kills_total, lvl_pm, dmg_taken_ps, _hp_pct * 100.0, _hp_pct_min * 100.0, heal_ps, Engine.time_scale])

func _is_playing() -> bool:
	return GameManager.current_state == GameManager.State.PLAYING

func _get_player() -> Player:
	if _player_node == null or not is_instance_valid(_player_node):
		_player_node = get_tree().get_first_node_in_group("player") as Player
	return _player_node

func _overlay_text() -> String:
	return "t=%.0fs\nkills %d\nhp %.0f%% (min %.0f%%)\ndmg_taken %.0f\nnear %d\ntscale %.2f" % [
			_elapsed, _kills_total, _hp_pct * 100.0, _hp_pct_min * 100.0,
			_dmg_taken_total, get_enemies_near(), Engine.time_scale]

func _setup_overlay() -> void:
	var canvas := CanvasLayer.new()
	canvas.layer = 11
	add_child(canvas)
	_overlay = Label.new()
	_overlay.position = Vector2(8, 8)
	_overlay.add_theme_color_override("font_color", Color(0.6, 1.0, 0.6))
	_overlay.add_theme_constant_override("outline_size", 3)
	_overlay.add_theme_color_override("font_outline_color", Color.BLACK)
	canvas.add_child(_overlay)
```

- [ ] **Step 4: 跑测试确认通过**

Run: `& "C:\Dev\GAME\Godot\Godot_v4.6.3-stable_win64_console.exe" --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/test_debug_metrics.gd`
Expected: PASS —— 7 用例全绿。

- [ ] **Step 5: 提交**

```bash
git add autoloads/debug_metrics.gd tests/test_debug_metrics.gd
git commit -m "feat(telemetry): DebugMetrics 补威胁轴(受伤/危险/最低血/近敌) + getters/snapshot + 监视器"
```

---

## Task 6: RunRecorder(纯序列化)

新 autoload,把 `DebugMetrics.snapshot()` 每 interval 差分成一行 tick CSV;订阅离散事件写 event JSONL;终局写 summary.json。含纯静态 `tick_header` / `format_row` 供单测;输出目录 `telemetry/` 运行时自建。

**Files:**
- Create: `autoloads/run_recorder.gd`
- Modify: `project.godot`(`[autoload]` 段,`RunRecorder` 排在 `RunHarness` **之前**)
- Test: `tests/test_run_recorder.gd`(新建)

- [ ] **Step 1: 写失败测试(新建)**

创建 `tests/test_run_recorder.gd`:

```gdscript
# tests/test_run_recorder.gd
extends GdUnitTestSuite

const Recorder := preload("res://autoloads/run_recorder.gd")

# ── CSV 表头/行:字段顺序与数量一致 ─────────────────────────────────────────
func test_tick_header_field_count() -> void:
	var fields := Recorder.tick_header().split(",")
	assert_int(fields.size()).is_equal(13)

func test_tick_header_order() -> void:
	var expected := "t,level,kills_total,kills_ps,dmg_dealt_ps,dmg_taken_ps,hp,hp_pct,danger_ps,enemies_alive,enemies_near,healed_ps,time_scale"
	assert_str(Recorder.tick_header()).is_equal(expected)

func test_format_row_joins_values_in_order() -> void:
	var row := Recorder.format_row([1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13])
	assert_str(row).is_equal("1,2,3,4,5,6,7,8,9,10,11,12,13")

func test_format_row_field_count_matches_header() -> void:
	var row := Recorder.format_row([0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12])
	assert_int(row.split(",").size()).is_equal(Recorder.tick_header().split(",").size())

# ── 输出路径解析:相对名补 res:// 前缀,已带前缀的保持 ─────────────────────────
func test_resolve_path_adds_res_prefix() -> void:
	assert_str(Recorder.resolve_base_path("telemetry/run_42")).is_equal("res://telemetry/run_42")

func test_resolve_path_keeps_existing_res_prefix() -> void:
	assert_str(Recorder.resolve_base_path("res://telemetry/run_42")).is_equal("res://telemetry/run_42")

func test_resolve_path_keeps_user_prefix() -> void:
	assert_str(Recorder.resolve_base_path("user://run_42")).is_equal("user://run_42")
```

- [ ] **Step 2: 跑测试确认失败**

Run: `& "C:\Dev\GAME\Godot\Godot_v4.6.3-stable_win64_console.exe" --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/test_run_recorder.gd`
Expected: FAIL —— `Recorder` 无 `tick_header` / `format_row` / `resolve_base_path`。

- [ ] **Step 3: 写 run_recorder.gd**

创建 `autoloads/run_recorder.gd`:

```gdscript
# autoloads/run_recorder.gd
# 纯序列化单元。RunHarness 调 begin() 启动;之后每 interval 把 DebugMetrics.snapshot() 差分成一行
# tick CSV,并订阅离散事件写 event JSONL;终局 RunHarness 调 finalize() 写 summary.json 并关文件。
# 不启用(begin 未调用)时不开任何文件、信号处理器全部 no-op。
extends Node

# tick CSV 列顺序(与 format_row 入参顺序严格对应)。
const TICK_COLUMNS: Array = [
	"t", "level", "kills_total", "kills_ps", "dmg_dealt_ps", "dmg_taken_ps",
	"hp", "hp_pct", "danger_ps", "enemies_alive", "enemies_near", "healed_ps", "time_scale",
]
# 只把"显著"受击写进 event log。接触伤害每物理帧 emit 一次 player_hit(~60/s,每次极小),
# 若全写会让 events 膨胀到十万行;阈值过滤后只留弹道/爆炸等爆发威胁(定位"因"的有用标记)。
# 接触 trickle 的总量仍由 tick CSV 的 dmg_taken_ps 曲线完整反映,不丢信息。
const PLAYER_HIT_LOG_MIN: float = 5.0

var _recording: bool = false
var _base_path: String = ""
var _csv: FileAccess = null
var _events: FileAccess = null
var _interval: float = 1.0
var _elapsed: float = 0.0          # 游戏秒(仅 PLAYING 累加)
var _since_tick: float = 0.0
var _prev: Dictionary = {}         # 上 tick 的 snapshot(差分算 /s)
var _prev_t: float = 0.0
var _config: Dictionary = {}
var _build: Array = []             # 选卡序列(picked id),写进 summary.build
var _hp_pct_sum: float = 0.0       # hp_pct 累加(算 summary.hp_pct_avg)
var _hp_pct_n: int = 0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	# 订阅自身能独立采的事件(其余由 RunHarness 主动喂)。未 recording 时处理器 no-op。
	GameFeel.player_hit.connect(_on_player_hit)
	GameFeel.boss_incoming.connect(_on_boss_incoming)

# ── 纯静态(单测) ───────────────────────────────────────────────────────────
static func tick_header() -> String:
	return ",".join(TICK_COLUMNS)

static func format_row(values: Array) -> String:
	var parts: Array = []
	for v in values:
		parts.append(str(v))
	return ",".join(parts)

# 相对名补 res:// 前缀;已带 res://|user:// 的保持。
static func resolve_base_path(out: String) -> String:
	if out.begins_with("res://") or out.begins_with("user://"):
		return out
	return "res://" + out

# ── 生命周期(RunHarness 调用) ───────────────────────────────────────────────
func begin(out: String, interval: float, config: Dictionary) -> void:
	_base_path = resolve_base_path(out)
	_interval = interval
	_config = config
	_ensure_dir(_base_path)
	_csv = FileAccess.open(_base_path + ".tick.csv", FileAccess.WRITE)
	if _csv != null:
		_csv.store_line(tick_header())
	_events = FileAccess.open(_base_path + ".events.jsonl", FileAccess.WRITE)
	_prev = DebugMetrics.snapshot()
	_prev_t = 0.0
	_elapsed = 0.0
	_since_tick = 0.0
	_recording = true

func _ensure_dir(base_path: String) -> void:
	var abs := ProjectSettings.globalize_path(base_path)
	var dir := abs.get_base_dir()
	DirAccess.make_dir_recursive_absolute(dir)

func _process(delta: float) -> void:
	if not _recording or not _is_playing():
		return
	_elapsed += delta
	_since_tick += delta
	if _since_tick >= _interval:
		_write_tick()
		_since_tick = 0.0

func _write_tick() -> void:
	var s := DebugMetrics.snapshot()
	var dt := maxf(_elapsed - _prev_t, 0.001)
	var kills_ps := (float(s["kills_total"]) - float(_prev["kills_total"])) / dt
	var dmg_dealt_ps := (float(s["dmg_dealt_total"]) - float(_prev["dmg_dealt_total"])) / dt
	var dmg_taken_ps := (float(s["dmg_taken_total"]) - float(_prev["dmg_taken_total"])) / dt
	var healed_ps := (float(s["healed_total"]) - float(_prev["healed_total"])) / dt
	var danger_ps := (float(s["danger_total"]) - float(_prev["danger_total"])) / dt
	var row := format_row([
		"%.1f" % _elapsed,
		int(s["level"]),
		int(s["kills_total"]),
		"%.2f" % kills_ps,
		"%.2f" % dmg_dealt_ps,
		"%.2f" % dmg_taken_ps,
		"%.1f" % float(s["hp"]),
		"%.3f" % float(s["hp_pct"]),
		"%.3f" % danger_ps,
		int(s["enemies_alive"]),
		int(s["enemies_near"]),
		"%.2f" % healed_ps,
		"%.2f" % Engine.time_scale,
	])
	if _csv != null:
		_csv.store_line(row)
	_hp_pct_sum += float(s["hp_pct"])
	_hp_pct_n += 1
	_prev = s
	_prev_t = _elapsed

# ── 事件(部分自订阅,部分 RunHarness 主动喂) ────────────────────────────────
func log_levelup(level: int, picked_id: String, offered_ids: Array) -> void:
	_build.append(picked_id)
	_write_event({"type": "level_up", "level": level, "picked": picked_id, "offered": offered_ids})

func _on_player_hit(amount: float) -> void:
	if not _recording or amount < PLAYER_HIT_LOG_MIN:
		return   # 接触 trickle(每帧极小)不写,只留显著爆发威胁;总量靠 CSV dmg_taken_ps
	_write_event({"type": "player_hit", "amount": amount,
			"hp_after": DebugMetrics.get_hp(), "enemies_near": DebugMetrics.get_enemies_near()})

func _on_boss_incoming() -> void:
	if not _recording:
		return
	_write_event({"type": "boss_incoming"})

func _write_event(data: Dictionary) -> void:
	if _events == null:
		return
	data["t"] = snappedf(_elapsed, 0.1)
	_events.store_line(JSON.stringify(data))

# 终局:写 summary.json,关文件,停止记录。outcome ∈ {victory, death, timeout}。
func finalize(outcome: String) -> void:
	if not _recording:
		return
	_write_event({"type": outcome, "level": DebugMetrics.get_level()})
	var summary := {
		"outcome": outcome,
		"survived_s": snappedf(_elapsed, 0.1),
		"final_level": DebugMetrics.get_level(),
		"kills": DebugMetrics.get_kills_total(),
		"dmg_dealt_total": snappedf(DebugMetrics.get_dmg_dealt_total(), 0.1),
		"dmg_taken_total": snappedf(DebugMetrics.get_dmg_taken_total(), 0.1),
		"hp_pct_avg": snappedf(_hp_pct_sum / maxi(_hp_pct_n, 1), 0.001),
		"hp_pct_min": snappedf(DebugMetrics.get_hp_pct_min(), 0.001),
		"danger_total_s": snappedf(DebugMetrics.get_danger_total(), 0.1),
		"build": _build,
		"seed": _config.get("seed", 0),
		"config": _config,
	}
	var f := FileAccess.open(_base_path + ".summary.json", FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(summary, "\t"))
		f.close()
	if _csv != null:
		_csv.close()
		_csv = null
	if _events != null:
		_events.close()
		_events = null
	_recording = false

func _is_playing() -> bool:
	return GameManager.current_state == GameManager.State.PLAYING
```

- [ ] **Step 4: 注册 autoload(RunRecorder 排在 RunHarness 之前)**

编辑 `project.godot`,把 Task 1 改后的:

```
DebugMetrics="*res://autoloads/debug_metrics.gd"
RunHarness="*res://autoloads/run_harness.gd"
SoundManager="*uid://bg6usvpgisg7x"
```

改为:

```
DebugMetrics="*res://autoloads/debug_metrics.gd"
RunRecorder="*res://autoloads/run_recorder.gd"
RunHarness="*res://autoloads/run_harness.gd"
SoundManager="*uid://bg6usvpgisg7x"
```

- [ ] **Step 5: 跑测试确认通过**

Run: `& "C:\Dev\GAME\Godot\Godot_v4.6.3-stable_win64_console.exe" --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/test_run_recorder.gd`
Expected: PASS —— 7 用例全绿。

- [ ] **Step 6: 提交**

```bash
git add autoloads/run_recorder.gd tests/test_run_recorder.gd project.godot
git commit -m "feat(telemetry): RunRecorder 纯序列化(tick CSV / event JSONL / summary.json)"
```

---

## Task 7: RunHarness 接管驱动(命令行/bot/选卡/生命周期)

给 Task 1 的骨架补运行时:`_ready` 解析命令行 → 设种子/快进 → 连终局信号 → 启动 RunRecorder;`_physics_process` 每帧驱动 bot 移动;监听 `level_up_triggered` 自动选卡;`victory/game_over/maxtime` 触发收尾退出。

**Files:**
- Modify: `autoloads/run_harness.gd`(在骨架上追加 `_ready`/`_physics_process`/handlers/解析)
- Test: `tests/test_run_harness.gd`(追加命令行解析用例)

- [ ] **Step 1: 写失败测试(命令行解析纯函数)**

在 `tests/test_run_harness.gd` 末尾追加:

```gdscript
# ── 命令行解析 ───────────────────────────────────────────────────────────────
func test_parse_args_defaults_when_no_bot() -> void:
	var cfg := RunHarness.parse_args([])
	assert_bool(cfg["active"]).is_false()

func test_parse_args_reads_bot_and_seed() -> void:
	var cfg := RunHarness.parse_args(["--bot=kite", "--seed=42"])
	assert_bool(cfg["active"]).is_true()
	assert_str(cfg["bot"]).is_equal("kite")
	assert_int(cfg["seed"]).is_equal(42)

func test_parse_args_defaults_fast_and_cards() -> void:
	var cfg := RunHarness.parse_args(["--bot=still"])
	assert_float(cfg["fast"]).is_equal_approx(3.0, 0.001)
	assert_str(cfg["cards"]).is_equal("default")

func test_parse_args_reads_fast_out_maxtime() -> void:
	var cfg := RunHarness.parse_args(["--bot=kite", "--fast=5", "--out=telemetry/run_x", "--maxtime=30"])
	assert_float(cfg["fast"]).is_equal_approx(5.0, 0.001)
	assert_str(cfg["out"]).is_equal("telemetry/run_x")
	assert_float(cfg["maxtime"]).is_equal_approx(30.0, 0.001)
```

- [ ] **Step 2: 跑测试确认失败**

Run: `& "C:\Dev\GAME\Godot\Godot_v4.6.3-stable_win64_console.exe" --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/test_run_harness.gd`
Expected: FAIL —— `RunHarness` 无 `parse_args`。

- [ ] **Step 3: 给 run_harness.gd 追加运行时逻辑**

在 `autoloads/run_harness.gd` **末尾**(Task 1 写的纯函数之后)追加:

```gdscript

# ── 运行时状态(Task 7) ──────────────────────────────────────────────────────
var _bot_mode: String = "kite"
var _profile: Array = DEFAULT_PROFILE
var _out: String = "telemetry/run"
var _maxtime: float = 0.0                # 0 = 不设上限(只靠自然终局)
var _player: Player = null
var _arena_center: Vector2 = Vector2(640, 360)  # 1280×720 中心;_ready 再从 arena 校正
var _finished: bool = false

# 命令行解析(纯函数,单测)。无 --bot → active=false。返回配置字典。
static func parse_args(user_args: Array) -> Dictionary:
	var cfg := {
		"active": false, "bot": "kite", "cards": "default",
		"seed": 0, "fast": DEFAULT_FAST, "out": "telemetry/run", "maxtime": 0.0,
	}
	for raw in user_args:
		var a := String(raw)
		if a == "--bot" or a.begins_with("--bot="):
			cfg["active"] = true
			if "=" in a:
				cfg["bot"] = a.split("=")[1]
		elif a.begins_with("--cards="):
			cfg["cards"] = a.split("=")[1]
		elif a.begins_with("--seed="):
			cfg["seed"] = int(a.split("=")[1])
		elif a.begins_with("--fast="):
			cfg["fast"] = float(a.split("=")[1])
		elif a.begins_with("--out="):
			cfg["out"] = a.split("=")[1]
		elif a.begins_with("--maxtime="):
			cfg["maxtime"] = float(a.split("=")[1])
	return cfg

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var cfg := parse_args(OS.get_cmdline_user_args())
	active = cfg["active"]
	if not active:
		return   # 真人模式:全惰性
	_bot_mode = cfg["bot"]
	_profile = PROFILES.get(cfg["cards"], DEFAULT_PROFILE)
	_out = cfg["out"]
	_maxtime = cfg["maxtime"]
	base_time_scale = cfg["fast"]
	seed(int(cfg["seed"]))                 # 早于任何 randi():首个 randi 在主场景 _ready 之后
	Engine.time_scale = base_time_scale
	GameManager.level_up_triggered.connect(_on_level_up)
	GameManager.victory_triggered.connect(func() -> void: _finish("victory"))
	GameManager.game_over_triggered.connect(func() -> void: _finish("death"))
	RunRecorder.begin(_out, DEFAULT_INTERVAL, {
		"bot": _bot_mode, "cards": cfg["cards"], "fast": base_time_scale,
		"seed": int(cfg["seed"]), "maxtime": _maxtime,
	})
	print("[RunHarness] bot=%s cards=%s seed=%d fast=%.1f out=%s maxtime=%.0f"
			% [_bot_mode, cfg["cards"], int(cfg["seed"]), base_time_scale, _out, _maxtime])

func _physics_process(_delta: float) -> void:
	if not active or _finished:
		return
	if GameManager.current_state != GameManager.State.PLAYING:
		return
	var p := _get_player()
	if p == null:
		return
	if _maxtime > 0.0 and DebugMetrics.get_elapsed() >= _maxtime:
		_finish("timeout")
		return
	p.bot_input = _compute_input(p)

func _compute_input(p: Player) -> Vector2:
	if _bot_mode == "still":
		return Vector2.ZERO
	var positions: Array = []
	for e in get_tree().get_nodes_in_group("enemies"):
		if e is Node2D:
			positions.append(e.global_position)
	return compute_kite_dir(p.global_position, positions, _arena_center, PERCEPTION_RADIUS)

# 升级:唯一一次 pick → 按 profile 选 → apply → 通知 recorder → resume。
func _on_level_up() -> void:
	var p := _get_player()
	if p == null:
		return
	var offered := CardPool.pick(p)
	var picked := choose_card(offered, _profile)
	if picked.is_empty():
		GameManager.resume_game()
		return
	var offered_ids: Array = []
	for c in offered:
		offered_ids.append(c.get("id", ""))
	CardPool.apply(picked, p)
	RunRecorder.log_levelup(p.level, String(picked.get("id", "")), offered_ids)
	GameManager.resume_game()

func _finish(outcome: String) -> void:
	if _finished:
		return
	_finished = true
	RunRecorder.finalize(outcome)
	print("[RunHarness] 终局=%s,退出。" % outcome)
	get_tree().quit()

func _get_player() -> Player:
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player") as Player
	return _player
```

- [ ] **Step 4: 跑测试确认通过**

Run: `& "C:\Dev\GAME\Godot\Godot_v4.6.3-stable_win64_console.exe" --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/test_run_harness.gd`
Expected: PASS —— 命令行解析 4 用例 + 之前全部用例全绿。

- [ ] **Step 5: 提交**

```bash
git add autoloads/run_harness.gd tests/test_run_harness.gd
git commit -m "feat(telemetry): RunHarness 接管命令行/bot 驱动/自动选卡/终局退出"
```

---

## Task 8: .gitignore 加 telemetry/

输出目录不入库。

**Files:**
- Modify: `.gitignore`

- [ ] **Step 1: 加忽略项**

在 `.gitignore` 的「工具 / 临时 / 可再生产物」段(`reports/` 行附近)加一行:

```
reports/
telemetry/
```

- [ ] **Step 2: 验证忽略生效**

Run: `git check-ignore telemetry/run.tick.csv`
Expected: 输出 `telemetry/run.tick.csv`(说明被忽略)。

- [ ] **Step 3: 提交**

```bash
git add .gitignore
git commit -m "chore(telemetry): gitignore telemetry/ 输出目录"
```

---

## Task 9: 端到端冒烟 + 确定性验收(CLI,非 gdUnit)

确定性需要跑完整一局,在 gdUnit 进程内做不可靠;改为 CLI 短跑验收。本任务无代码,是手动验证步骤 + 结果记录。

> **前置:** `addons/limboai/`(敌人 AI GDExtension v1.7.1)必须已装,否则项目无法加载(见 CLAUDE.md)。

- [ ] **Step 1: 短跑冒烟(headless + 快进 + maxtime 兜底)**

Run:
```
& "C:\Dev\GAME\Godot\Godot_v4.6.3-stable_win64_console.exe" --headless --path . -- --bot=kite --cards=default --seed=42 --fast=3 --maxtime=20 --out=telemetry/smoke_42
```
Expected: 进程在 ~数秒内自行退出(打印 `[RunHarness] 终局=...,退出。`),不崩、不挂。

- [ ] **Step 2: 验证三类产物非空**

Run:
```bash
ls -l telemetry/smoke_42.tick.csv telemetry/smoke_42.events.jsonl telemetry/smoke_42.summary.json
```
Expected: 三个文件都存在且大小 > 0。用 Read 打开 `telemetry/smoke_42.summary.json`,确认含 `outcome / survived_s / kills / dmg_taken_total / hp_pct_min / danger_total_s / build / seed` 字段(验收 #2、#4)。打开 `.tick.csv` 确认表头 13 列且同时有进攻列(`kills_ps,dmg_dealt_ps`)与威胁列(`dmg_taken_ps,hp_pct,danger_ps,enemies_near`)(验收 #4)。

- [ ] **Step 3: 确定性:同种子跑两遍 diff summary**

Run:
```
& "C:\Dev\GAME\Godot\Godot_v4.6.3-stable_win64_console.exe" --headless --path . -- --bot=kite --cards=default --seed=7 --fast=3 --maxtime=60 --out=telemetry/det_a
& "C:\Dev\GAME\Godot\Godot_v4.6.3-stable_win64_console.exe" --headless --path . -- --bot=kite --cards=default --seed=7 --fast=3 --maxtime=60 --out=telemetry/det_b
```
然后比较:
```bash
diff telemetry/det_a.summary.json telemetry/det_b.summary.json
```
Expected: 两份 summary 关键字段相等(`survived_s / final_level / kills / dmg_taken_total / build`)。`out`/`config.out` 路径不同属预期,可忽略。若发散:先确认无 hitstop 漏跳(Task 3),再把 `--fast` 调低(如 2)重试——这是 spec §7 的"旋钮非魔法"取舍。**把实测稳定的 fast 档记到 memory。**

- [ ] **Step 4: 验证真人模式零回归(无 --bot)**

Run:
```
& "C:\Dev\GAME\Godot\Godot_v4.6.3-stable_win64_console.exe" --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests
```
Expected: 全套 gdUnit 测试通过(验收 #1 的代理:无 `--bot` 时 `active=false`,钩子惰性、UI 正常;且不产生 telemetry 文件)。另可在编辑器手动开一局确认能正常游玩、选卡、震动。

- [ ] **Step 5: 清理冒烟产物并记录结论**

冒烟产物已 gitignore,不必提交。把"稳定 fast 档 + 一次基线 summary 关键值"写入 memory(项目类),供后续 A/B 对照。本任务无 commit。

---

## 批量 A/B 用法(交付后参考,不在本计划实现范围)

改一个数值前后各跑一批,收 summary 对比威胁轴/存活差异。shell 循环示例(交付后 agent 自行起):

```bash
GODOT='C:\Dev\GAME\Godot\Godot_v4.6.3-stable_win64_console.exe'
for s in 1 2 3 4 5; do
  "$GODOT" --headless --path . -- --bot=kite --cards=default --seed=$s --fast=3 --maxtime=600 --out=telemetry/baseline_$s
done
```
逐个 Read `telemetry/baseline_*.summary.json`,对比 `survived_s / hp_pct_min / danger_total_s / dmg_taken_total`。

---

## 验收标准回执(对照 spec §11)

1. **无 `--bot` 真人零回归** → Task 2(钩子默认 INF)、Task 4(UI 守卫仅 active 触发)、Task 9 Step 4。
2. **`--bot=kite --seed=N --fast=3` 跑完自动退出,产出非空 CSV+events+summary** → Task 7(`_finish`→`quit`)、Task 6(三类文件)、Task 9 Step 1-2。
3. **同种子两跑 summary 关键字段相等(确定性)** → Task 1(seed)、Task 3(hitstop 跳过)、Task 4(单点 pick)、Task 9 Step 3。
4. **CSV 同含进攻轴 + 威胁轴** → Task 5(两轴累计)、Task 6(13 列)、Task 9 Step 2。
5. **boss 击杀后快进 time_scale 不被冲掉** → Task 3(bot 模式跳过 hitstop;人类模式恢复到 base)。
```

