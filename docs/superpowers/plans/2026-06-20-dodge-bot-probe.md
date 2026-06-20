# Dodge 探针(late-game bot probe)实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 给 bot 加躲飞弹能力,使其跑到游戏后期,为 P2 平衡提供真·后期 A/B 遥测基线;harness-only,零游戏平衡改动,保 C5 确定性。

**Architecture:** 延续 `run_harness.gd` "纯静态决策函数 + `_compute_input` 编排" 模式。新增纯函数 `compute_dodge_dir`(垂直弹道侧移)与 `blend_move`(kite+dodge 加权合成),与现有 `compute_kite_dir` 平级、无场景依赖、可单测。唯一游戏侧改动:`enemy_projectile` 加入组 `enemy_projectiles`(对真人游玩惰性)。两个方向函数求和前 `sort_custom` 定序以保 C5。

**Tech Stack:** Godot 4.7-stable / GDScript / gdUnit4(headless)。

## Global Constraints

- **回复用简体中文。**
- **分支 `feat/dodge-bot-probe`**(已建,spec 已提交 `2b2d547`);实现不在 master 直接做。
- **每任务独立提交,独立绿测。** 提交信息结尾加 `Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>`。
- **不要 `git add -A`**:repo 有 ~2600 预先存在未追踪文件(收录是用户决策);每次只 `git add` 本任务明确涉及的文件。工作区另有预先存在的 4.7 重导入 churn(`.tscn`/`project.godot`/`.import`/`data/arenas`),**不属本范围,不要 add**。
- **C5 遥测确定性**:bot 遥测同种子两跑须逐字节一致;命令行须带引擎参数 `--fixed-fps 60`(放 `--` 之前),新增逻辑用确定性排序保序。
- **C6 测试契约**:gdUnit4 headless 中失败/报错断言会**静默截断其后用例发现**;只在 GREEN 态核对预期用例数,风险用例排最后;别只看"全绿"要核对数目。
- **Windows 双实例铁律**:跑 headless(测试/bot)前**必须先关 Godot 编辑器**,否则 LimboAI DLL 复制撞名→headless 实例加载失败。
- **武器/敌人/平衡数值一律不碰**(回血令牌桶/威胁缩放/spawn 节拍是 P2 工作,明确 Out)。

测试运行命令(全量):
```
& "C:\Dev\GAME\Godot\Godot_v4.7-stable_win64_console.exe" --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests
```
单套件:把 `-a res://tests` 换成 `-a res://tests/test_run_harness.gd`(或对应文件)。

---

### Task 0: 前置确认

**Files:** 无改动。

- [ ] **Step 1: 确认在分支上**

Run:
```
cd "D:\Workspace\GAME\game_0_vsl"; git branch --show-current
```
Expected: `feat/dodge-bot-probe`

- [ ] **Step 2: 确认编辑器已关(headless 前置)**

Run:
```
Get-Process | Where-Object { $_.ProcessName -like '*odot*' } | Select-Object Id, ProcessName
```
Expected: 无输出(无 Godot 进程)。若有,先 `editor_manage quit` 或关编辑器再继续。

---

### Task 1: enemy_projectile 入组 `enemy_projectiles`

让 bot 能感知飞弹。这是唯一的游戏侧改动,对真人游玩惰性(无人读该组)。

**Files:**
- Modify: `scenes/enemies/enemy_projectile.gd`(加 `_ready`)
- Test: `tests/test_enemy_projectile.gd`(新建)

**Interfaces:**
- Produces: 运行时所有 `enemy_projectile` 实例 `_ready` 后 `is_in_group("enemy_projectiles")` 为真;实例暴露 `direction: Vector2`(单位向量)与 `const SPEED: float = 220.0`,故速度 = `direction * SPEED`。

- [ ] **Step 1: 写失败测试**

新建 `tests/test_enemy_projectile.gd`:
```gdscript
# tests/test_enemy_projectile.gd
# 弹体入组 enemy_projectiles,供 bot 躲弹感知(harness 读该组)。
extends GdUnitTestSuite

func test_enemy_projectile_joins_group_on_ready() -> void:
	var scene := load("res://scenes/enemies/enemy_projectile.tscn") as PackedScene
	var proj: Node = auto_free(scene.instantiate())
	add_child(proj)
	await get_tree().process_frame
	assert_bool(proj.is_in_group("enemy_projectiles")).is_true()
```

- [ ] **Step 2: 跑测试确认失败**

Run: `… -a res://tests/test_enemy_projectile.gd`
Expected: FAIL —— 弹体未入组,`is_in_group` 返回 false。

- [ ] **Step 3: 实现最小改动**

在 `scenes/enemies/enemy_projectile.gd` 的 `var _age: float = 0.0` 之后、`_physics_process` 之前加:
```gdscript
func _ready() -> void:
	add_to_group("enemy_projectiles")
```

- [ ] **Step 4: 跑测试确认通过**

Run: `… -a res://tests/test_enemy_projectile.gd`
Expected: PASS（1 个用例）。

- [ ] **Step 5: 提交**

```
git add scenes/enemies/enemy_projectile.gd tests/test_enemy_projectile.gd
git commit -m "feat(bot): enemy_projectile 入组 enemy_projectiles(供躲弹感知)"
```
（提交信息记得带 Co-Authored-By 行。）

---

### Task 2: `compute_dodge_dir` 纯函数(垂直弹道侧移)

**Files:**
- Modify: `autoloads/run_harness.gd`（加常量 + `compute_dodge_dir`）
- Test: `tests/test_run_harness.gd`（追加用例,排在文件末尾——风险用例靠后,守 C6 截断）

**Interfaces:**
- Consumes: 弹体速度由调用方算为 `direction * SPEED`。
- Produces: `static func compute_dodge_dir(player_pos: Vector2, projectiles: Array, dodge_radius: float) -> Vector2`,`projectiles` 为 `Array[{ "pos": Vector2, "vel": Vector2 }]`;返回归一化躲避方向,无则 `Vector2.ZERO`。常量 `DODGE_RADIUS=200.0`、`W_KITE=1.0`、`W_DODGE=1.5`。

- [ ] **Step 1: 写失败测试(追加到 `tests/test_run_harness.gd` 末尾)**

```gdscript
# ── 躲弹方向(compute_dodge_dir) ──────────────────────────────────────────
func test_dodge_no_projectiles_is_zero() -> void:
	assert_vector(Harness.compute_dodge_dir(Vector2(640, 360), [], 200.0)).is_equal(Vector2.ZERO)

func test_dodge_sidesteps_perpendicular_to_incoming() -> void:
	# 弹在玩家左下、向右飞,玩家在弹道线上方 → 垂直侧移(向上=负 y),且垂直于弹速
	var dir := Harness.compute_dodge_dir(Vector2(640, 360), [{"pos": Vector2(540, 380), "vel": Vector2(220, 0)}], 200.0)
	assert_float(dir.y).is_less(0.0)
	assert_float(dir.dot(Vector2(1, 0))).is_equal_approx(0.0, 0.001)
	assert_float(dir.length()).is_equal_approx(1.0, 0.001)

func test_dodge_ignores_receding_projectile() -> void:
	# 弹向左飞(远离右侧玩家)→ vel·to_player<0 → 不躲
	var dir := Harness.compute_dodge_dir(Vector2(640, 360), [{"pos": Vector2(540, 360), "vel": Vector2(-220, 0)}], 200.0)
	assert_vector(dir).is_equal(Vector2.ZERO)

func test_dodge_ignores_projectile_beyond_radius() -> void:
	# 弹距离 340 > 半径 200 → 忽略
	var dir := Harness.compute_dodge_dir(Vector2(640, 360), [{"pos": Vector2(300, 360), "vel": Vector2(220, 0)}], 200.0)
	assert_vector(dir).is_equal(Vector2.ZERO)

func test_dodge_head_on_uses_deterministic_perpendicular() -> void:
	# 玩家恰在弹道延长线上 → lateral≈0 → 兜底 (-vdir.y, vdir.x) = (0,1)
	var dir := Harness.compute_dodge_dir(Vector2(640, 360), [{"pos": Vector2(540, 360), "vel": Vector2(220, 0)}], 200.0)
	assert_vector(dir).is_equal(Vector2(0, 1))

func test_dodge_order_independent() -> void:
	# 内部排序 → 同一组弹乱序输入两次结果逐位一致(C5 单元锁)
	var p := Vector2(640, 360)
	var a := {"pos": Vector2(540, 340), "vel": Vector2(220, 0)}
	var b := {"pos": Vector2(560, 380), "vel": Vector2(0, -220)}
	var r1 := Harness.compute_dodge_dir(p, [a, b], 200.0)
	var r2 := Harness.compute_dodge_dir(p, [b, a], 200.0)
	assert_vector(r1).is_equal(r2)
```

- [ ] **Step 2: 跑测试确认失败**

Run: `… -a res://tests/test_run_harness.gd`
Expected: FAIL/报错 —— `Harness` 无 `compute_dodge_dir`。⚠ C6:此报错会截断其后用例发现,属预期;实现后在 GREEN 态核对数目。

- [ ] **Step 3: 实现 `compute_dodge_dir` + 常量**

在 `autoloads/run_harness.gd` 现有 kite 常量后(`const NEAR_RADIUS: float = 140.0` 之后)加:
```gdscript
const DODGE_RADIUS: float = 200.0        # 躲弹感知半径(px):此半径内、正接近的弹触发侧移
const W_KITE: float = 1.0                 # _compute_input 合成:避敌权重
const W_DODGE: float = 1.5                # 合成:躲弹权重(占优——正面斥力对快弹无效)
```

在现有 `compute_kite_dir` 函数之后加:
```gdscript
# 躲弹方向:对半径内"正朝玩家飞来"的弹,沿垂直其弹道方向把玩家推离弹道线。
# projectiles: Array[{ "pos": Vector2, "vel": Vector2 }]。归一化;无净向量返回 ZERO。
# 求和前按位置 (x→y) 定序(C5:消除 get_nodes_in_group 顺序抖动 × 浮点加法非结合)。
static func compute_dodge_dir(player_pos: Vector2, projectiles: Array, dodge_radius: float) -> Vector2:
	var sorted_proj := projectiles.duplicate()
	sorted_proj.sort_custom(func(a, b):
		var pa: Vector2 = a["pos"]
		var pb: Vector2 = b["pos"]
		return pa.x < pb.x if pa.x != pb.x else pa.y < pb.y
	)
	var steer := Vector2.ZERO
	for pr in sorted_proj:
		var pos: Vector2 = pr["pos"]
		var vel: Vector2 = pr["vel"]
		var to_player := player_pos - pos
		var d := to_player.length()
		if d > dodge_radius or d <= 0.001:
			continue
		if vel.dot(to_player) <= 0.0:
			continue   # 远离或已掠过,不躲
		var vdir := vel.normalized()
		var lateral := to_player - vdir * to_player.dot(vdir)   # 玩家相对弹道线的横向偏移
		var side := lateral
		if side.length() < 0.001:
			side = Vector2(-vdir.y, vdir.x)   # 正中:确定性取一侧垂直
		steer += side.normalized() * (1.0 - d / dodge_radius)
	if steer.length() < 0.001:
		return Vector2.ZERO
	return steer.normalized()
```

- [ ] **Step 4: 跑测试确认通过**

Run: `… -a res://tests/test_run_harness.gd`
Expected: PASS。核对本套件用例数 = 原 16 + 6 = **22**(无截断)。

- [ ] **Step 5: 提交**

```
git add autoloads/run_harness.gd tests/test_run_harness.gd
git commit -m "feat(bot): compute_dodge_dir 纯函数(垂直弹道侧移,定序保C5)"
```

---

### Task 3: `compute_kite_dir` 求和前定序(C5)

后期密集战 `get_nodes_in_group` 顺序不稳 + 浮点向量加法非结合 → 同种子分叉。给 kite 也补定序(当前 kite bot 174s 就死、没进密集终幕,故此分叉此前未暴露)。

**Files:**
- Modify: `autoloads/run_harness.gd`（`compute_kite_dir` 加排序）
- Test: `tests/test_run_harness.gd`（追加 1 用例,文件末尾)

**Interfaces:**
- Produces: `compute_kite_dir` 行为对 `enemy_positions` 输入顺序不变(结果逐位稳定)。签名不变。

- [ ] **Step 1: 写测试(追加末尾)**

```gdscript
func test_kite_order_independent() -> void:
	# 排序后:同一组敌人乱序输入两次结果逐位一致(C5 单元锁;后期大输入下顺序真会变)
	var p := Vector2(640, 360)
	var e1 := Vector2(600, 340)
	var e2 := Vector2(680, 380)
	var e3 := Vector2(620, 400)
	var r1 := Harness.compute_kite_dir(p, [e1, e2, e3], Vector2(640, 360), 220.0)
	var r2 := Harness.compute_kite_dir(p, [e3, e1, e2], Vector2(640, 360), 220.0)
	assert_vector(r1).is_equal(r2)
```
注:小输入下浮点加法可能恰好稳定 → 此测可能在实现前就 GREEN(非严格 RED)。它是**契约/回归锁**;后期大输入的权威确定性证明在 Task 5 的 seed7 逐字节 C5 跑。

- [ ] **Step 2: 跑测试**

Run: `… -a res://tests/test_run_harness.gd`
Expected: PASS 或 FAIL 均可(见上注)。无论如何记录当前结果。

- [ ] **Step 3: 给 `compute_kite_dir` 加排序**

把 `compute_kite_dir` 开头改为(在 `var repulse := Vector2.ZERO` 之前插入排序,循环改遍历 `sorted_enemies`):
```gdscript
static func compute_kite_dir(player_pos: Vector2, enemy_positions: Array, arena_center: Vector2, perception_radius: float) -> Vector2:
	var sorted_enemies := enemy_positions.duplicate()
	sorted_enemies.sort_custom(func(a, b): return a.x < b.x if a.x != b.x else a.y < b.y)
	var repulse := Vector2.ZERO
	for ep in sorted_enemies:
		var to_player: Vector2 = player_pos - ep
		var d := to_player.length()
		if d > perception_radius or d <= 0.001:
			continue
		repulse += to_player.normalized() * (1.0 - d / perception_radius)
	var center_pull := (arena_center - player_pos) * CENTER_PULL_GAIN
	var dir := repulse + center_pull
	if dir.length() < 0.001:
		return Vector2.ZERO
	return dir.normalized()
```

- [ ] **Step 4: 跑测试确认通过**

Run: `… -a res://tests/test_run_harness.gd`
Expected: PASS。核对用例数 = **23**(22 + 1)。

- [ ] **Step 5: 提交**

```
git add autoloads/run_harness.gd tests/test_run_harness.gd
git commit -m "feat(bot): compute_kite_dir 求和前定序(后期密集战保C5)"
```

---

### Task 4: `blend_move` 合成 + `_compute_input` 接线

**Files:**
- Modify: `autoloads/run_harness.gd`（加 `blend_move` + 改 `_compute_input`）
- Test: `tests/test_run_harness.gd`（追加 2 用例,文件末尾)

**Interfaces:**
- Consumes: `compute_kite_dir`、`compute_dodge_dir`、常量 `W_KITE`/`W_DODGE`/`DODGE_RADIUS`/`PERCEPTION_RADIUS`;弹体实例 `b.global_position`、`b.direction`、`b.SPEED`。
- Produces: `static func blend_move(kite: Vector2, dodge: Vector2, w_kite: float, w_dodge: float) -> Vector2`(加权归一,均零返回 ZERO);`_compute_input` 在 `kite`/默认模式返回 kite+dodge 合成。

- [ ] **Step 1: 写失败测试(追加末尾)**

```gdscript
# ── kite + dodge 合成(blend_move) ────────────────────────────────────────
func test_blend_dodge_dominates_opposing_kite() -> void:
	# kite 推右(+x)、dodge 推上(-y),dodge 权重更高 → 合成更偏 dodge 轴
	var v := Harness.blend_move(Vector2(1, 0), Vector2(0, -1), 1.0, 1.5)
	assert_float(absf(v.y)).is_greater(absf(v.x))
	assert_float(v.length()).is_equal_approx(1.0, 0.001)

func test_blend_zero_when_both_zero() -> void:
	assert_vector(Harness.blend_move(Vector2.ZERO, Vector2.ZERO, 1.0, 1.5)).is_equal(Vector2.ZERO)
```

- [ ] **Step 2: 跑测试确认失败**

Run: `… -a res://tests/test_run_harness.gd`
Expected: FAIL/报错 —— `Harness` 无 `blend_move`(截断属预期)。

- [ ] **Step 3: 实现 `blend_move`,并改 `_compute_input`**

在 `compute_dodge_dir` 之后加:
```gdscript
# kite + dodge 加权合成,归一化;两者皆零返回 ZERO。
static func blend_move(kite: Vector2, dodge: Vector2, w_kite: float, w_dodge: float) -> Vector2:
	var v := kite * w_kite + dodge * w_dodge
	if v.length() < 0.001:
		return Vector2.ZERO
	return v.normalized()
```

把现有 `_compute_input` 改为(新增收集 `enemy_projectiles` 组 + 合成):
```gdscript
func _compute_input(p: Player) -> Vector2:
	if _bot_mode == "still":
		return Vector2.ZERO
	var positions: Array = []
	for e in get_tree().get_nodes_in_group("enemies"):
		if e is Node2D:
			positions.append(e.global_position)
	var projectiles: Array = []
	for b in get_tree().get_nodes_in_group("enemy_projectiles"):
		if b is Node2D:
			projectiles.append({"pos": b.global_position, "vel": b.direction * b.SPEED})
	var kite := compute_kite_dir(p.global_position, positions, _arena_center, PERCEPTION_RADIUS)
	var dodge := compute_dodge_dir(p.global_position, projectiles, DODGE_RADIUS)
	return blend_move(kite, dodge, W_KITE, W_DODGE)
```

- [ ] **Step 4: 跑测试确认通过**

Run: `… -a res://tests/test_run_harness.gd`
Expected: PASS。核对用例数 = **25**(23 + 2)。

- [ ] **Step 5: 提交**

```
git add autoloads/run_harness.gd tests/test_run_harness.gd
git commit -m "feat(bot): _compute_input 合成 kite+dodge,kite bot 升级为后期探针"
```

---

### Task 5: 全量回归 + C5 确定性重验

**Files:** 无代码改动(验证任务)。

- [ ] **Step 1: 跑全量 gdUnit**

Run:
```
& "C:\Dev\GAME\Godot\Godot_v4.7-stable_win64_console.exe" --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests
```
Expected: 全绿。核对总用例数 = 旧 486 + 新 10 = **496**(新 = test_run_harness +9〔Task2:6 + Task3:1 + Task4:2〕+ test_enemy_projectile +1)。⚠ C6:GREEN 态核对数目防截断。

- [ ] **Step 2: 确认编辑器关闭**

Run: `Get-Process | Where-Object { $_.ProcessName -like '*odot*' }`
Expected: 无输出。

- [ ] **Step 3: seed 7 跑两次(C5 逐字节)**

Run(两条,out 分别 `probe47_7`、`probe47_7b`):
```
& "C:\Dev\GAME\Godot\Godot_v4.7-stable_win64_console.exe" --headless --fixed-fps 60 --path . -- --bot=kite --cards=default --seed=7 --fast=3 --maxtime=600 --out=telemetry/probe47_7
& "C:\Dev\GAME\Godot\Godot_v4.7-stable_win64_console.exe" --headless --fixed-fps 60 --path . -- --bot=kite --cards=default --seed=7 --fast=3 --maxtime=600 --out=telemetry/probe47_7b
```

- [ ] **Step 4: SHA256 比对**

Run:
```
foreach ($s in @("summary.json","events.jsonl","tick.csv")) {
  $a=(Get-FileHash "telemetry/probe47_7.$s" -Algorithm SHA256).Hash
  $b=(Get-FileHash "telemetry/probe47_7b.$s" -Algorithm SHA256).Hash
  Write-Output "$s : $(if($a -eq $b){'IDENTICAL'}else{'DIFFER'})"
}
```
Expected: 三项 IDENTICAL(至少到 bot 实际触及点;若 DIFFER,读 tick.csv 找首个分叉 t——可接受仅"极密终幕 t≳560s 引擎级微抖",其余分叉须排查 `get_nodes_in_group` 之外的逐帧 RNG 消费者)。

---

### Task 6: 重采 probe47 后期基线 + 功能验收 + 记忆记录

**Files:**
- Modify: 记忆 `project_vsl_bot_telemetry.md`、`MEMORY.md` 索引行。

- [ ] **Step 1: 跑 seed 42 / 101**

Run:
```
& "C:\Dev\GAME\Godot\Godot_v4.7-stable_win64_console.exe" --headless --fixed-fps 60 --path . -- --bot=kite --cards=default --seed=42  --fast=3 --maxtime=600 --out=telemetry/probe47_42
& "C:\Dev\GAME\Godot\Godot_v4.7-stable_win64_console.exe" --headless --fixed-fps 60 --path . -- --bot=kite --cards=default --seed=101 --fast=3 --maxtime=600 --out=telemetry/probe47_101
```

- [ ] **Step 2: 读三份 summary,功能验收**

读 `telemetry/probe47_{7,42,101}.summary.json`。
Expected(验收):至少 1–2 个种子跑到**深后期**(`final_level` ≥ ~20 / build 含进化 / `survived_s` 显著 > 旧基线的 ≤175s)。对比旧 `base47_*`(全 ≤Lv10)确认探针生效。若**全部**仍早死,停下排查(dodge 权重/半径,或 bot 死因非飞弹)。

- [ ] **Step 3: 把 probe47 基线数值 + 探针生效结论写入记忆**

更新 `project_vsl_bot_telemetry.md`:追加 probe47 三种子数值(结局/存活/Lv/kills/dmg/danger/build)、C5 结论、"dodge 探针已实现并接通 kite bot"。同步 `MEMORY.md` 该行。

- [ ] **Step 4: 提交记忆不在 git**(记忆在 `~/.claude/...`,非本 repo,无需 git。)跳过。

- [ ] **Step 5: 完成开发分支**

**REQUIRED SUB-SKILL:** 用 superpowers:finishing-a-development-branch:先核验全量测试绿(Task5 Step1 已跑,如已开编辑器则以该结果为准)、检测环境、呈 4 选项、执行所选(预期 FF 合并 master + 删分支,与 Phase0/P1 一致)。

---

## Self-Review

**1. Spec coverage:**
- 弹体入组 → Task 1 ✓
- `compute_dodge_dir` 纯函数(含 ②③④⑤⑥⑦ 用例)→ Task 2 ✓(⑦ 归一化在 `test_dodge_sidesteps...` 内断言)
- `_compute_input` 合成 + bot 模式折叠进 kite → Task 4 ✓
- 全程排序定序(kite+dodge)→ Task 2(dodge)+ Task 3(kite)✓
- C5 逐字节重验 → Task 5 ✓
- 功能验收(探针到后期)→ Task 6 Step 2 ✓
- 重采 probe47 基线 + 记忆 → Task 6 ✓

**2. Placeholder scan:** 无 TBD/TODO;每改码步骤含完整代码;命令含预期输出。✓

**3. Type consistency:** `compute_dodge_dir(player_pos, projectiles, dodge_radius)`、`blend_move(kite, dodge, w_kite, w_dodge)`、`compute_kite_dir(...)` 签名跨任务一致;常量名 `DODGE_RADIUS`/`W_KITE`/`W_DODGE` 在 Task2 定义、Task4 消费,一致。弹体字段 `direction`/`SPEED` 与 `enemy_projectile.gd` 实际一致。✓

**4. 用例计数链**:run_harness 16→22(+6)→23(+1)→25(+2);enemy_projectile +1;全量 486→**496**。
