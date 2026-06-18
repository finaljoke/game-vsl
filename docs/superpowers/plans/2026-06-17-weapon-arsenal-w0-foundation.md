# 武器军械库重做 W0：共享机制原语（底座）Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 建立武器重做依赖的三个跨武器共享原语——状态系统（燃烧/减速/冻结/硬直）、真击退（external_velocity）、暴击口径——并接入敌人 AI 移动原子与伤害管线，全部带 gdUnit 单测。

**Architecture:** 状态逻辑抽成独立纯类 `StatusComponent`（RefCounted，零节点依赖，可裸实例单测）；`Enemy` 持有一个实例并对外暴露 `apply_status / move_speed_mult / is_stunned / has_status`，每物理帧 `tick` 驱动燃烧 DoT 与外力衰减。BT 的 4 个移动原子写 velocity 时统一经 `Enemy.resolve_velocity()`（纯静态 `compose_velocity` 合成「期望速度×减速 + 外力」，硬直时归零自身只留外力）。暴击集中在 `WeaponBase.damage_for` 的可选重载 + 纯静态 `crit_multiplier`，`Player` 新增 `crit_chance/crit_mult`。

**Tech Stack:** Godot 4.6.3 · GDScript · gdUnit4 · LimboAI v1.7.1（GDExtension，敌人 BT）· PhantomCamera/GameFeel（既有打击感层，本轮不改）。

## Global Constraints

逐条来自设计 spec（`docs/superpowers/specs/2026-06-17-weapon-arsenal-redesign-design.md`）§4、§6.4、§8、§11，每个任务都隐含遵守：

- **引擎 Godot 4.6.3**；测试经 gdUnit4 headless 运行，**必须** `--ignoreHeadlessMode`（否则 abort 退出码 103）。
- **确定性靠引擎参数 `--fixed-fps 60`**（不是 `--fast`）；所有随时间结算的逻辑（燃烧 tick、外力衰减）走 `_physics_process(delta)` 而非 `_process`，与物理帧对齐。
- **状态语义（spec §4.1，不可偏离）**：`&"burn"` magnitude=每秒 DoT，每 0.25s 结算一拍，**可刷新不可叠加（取最强 = 更高 dps）**；`&"slow"` magnitude=速度乘子 0..1，**取最强 = 更小乘子**；`&"freeze"` = 速度乘子 0 且 `is_stunned()=true`；`&"stun"` = `is_stunned()=true` 但不改速度乘子。
- **真击退（spec §4.2）**：与 BT 的单次 `move_and_slide` **共用同一 velocity 通道**——`velocity = 期望速度*move_speed_mult() + external_velocity`，仍只调一次 `move_and_slide`；GameFeel 的 sprite 抖动保留作纯视觉（不动）。
- **暴击默认值（spec §4.4）**：`Player.crit_chance = 0.0`、`Player.crit_mult = 2.0`（默认不暴击，**保持现有手感**）；`damage_for` 向后兼容——默认 `can_crit=false` 时等价旧 `damage_for(base)`。
- **测试约定（仓库现状）**：测试 `extends GdUnitTestSuite`，**用 `const X := preload("res://…")` 引用脚本**（而非 class_name 全局标识，避免类缓存重建依赖）；纯函数用 `auto_free(Script.new())`，场景用 `load(...).instantiate()` + `add_child` + `await get_tree().process_frame`。
- **LimboAI 必装**：敌人场景含 `BTPlayer`；headless 测试进程会加载该 GDExtension（见 `tests/test_enemy_ai.gd` 头注）。
- **反射注入校验既有约定**：`.tres` 含脚本未声明字段时 `push_warning` 不静默（本轮新增字段都在脚本声明，但不在 W0 触碰武器 `.tres`）。

**headless 测试命令**（PowerShell；下文每个任务的 Run 步骤都用它，仅换 `-a` 的目标文件）：

```powershell
& "C:\Dev\GAME\Godot\Godot_v4.6.3-stable_win64_console.exe" --headless --path "D:\Workspace\GAME\game_0_vsl" -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/<TEST_FILE>.gd
```

> **执行前置（不阻塞计划，执行时处理）**：当前分支 `balance/heal-threat-pacing` 有未提交的遥测改动。W0 应在**专用分支**（建议 `feat/weapon-arsenal-w0`，从 `main` 切出）上执行；如用 worktree，由 `superpowers:using-git-worktrees` 在执行期建立。

---

## 范围说明：为何 W0 不含「召唤基类（4.3）」

spec §10.1 把召唤基类（OrbitGuardian / RoamingMinion）列入 W0。**本计划有意将其推迟**到各自的消费波次，理由：

- OrbitGuardian 仅被「缚灵 Spectral Wisps」（W1，由 orb 泛化）消费；RoamingMinion 仅被「亡者召唤 Reanimate」（W3 冲刺项，spec 标为实现成本最高、可延后）消费。
- 二者都**不是跨武器共享原语**（不像状态/击退/暴击被 6+ 把武器复用）；把它们和唯一消费者放同一波次，符合「同改同在」与「不提前造最贵的东西」。
- W0 因此聚焦三个真正跨武器、且**全部可纯函数单测**的底座，交付面更小、评审更快。

> 评审若坚持 4.3 进 W0，告知即可，会补两个任务（OrbitGuardian 由 `orb_shield.gd` 泛化 + RoamingMinion `CharacterBody2D` 索敌）。

---

## File Structure

**新建**

- `scenes/enemies/status_component.gd` — `StatusComponent`：燃烧/减速/冻结/硬直的纯逻辑底座（RefCounted）。唯一职责：持有当前状态、按 delta 推进、回答「速度乘子 / 是否硬直 / 本帧燃烧伤害」。
- `tests/test_status_component.gd` — StatusComponent 纯逻辑单测（无场景）。
- `tests/test_enemy_status.gd` — Enemy 接入状态/击退的集成验证（实例化 `enemy.tscn`）。
- `tests/test_enemy_velocity.gd` — `Enemy.compose_velocity` 纯静态单测（无场景）。
- `tests/test_weapon_crit.gd` — `crit_multiplier` 纯函数 + `damage_for` 实例集成。

**修改**

- `scenes/enemies/enemy.gd` — 持有 `StatusComponent`；新增 `apply_status/move_speed_mult/is_stunned/has_status`、`external_velocity/apply_impulse`、静态 `compose_velocity` + `resolve_velocity`；新增 `_physics_process` 驱动燃烧 DoT 与外力衰减。
- `scenes/enemies/ai/atoms/bt_chase_target.gd`、`bt_kite_target.gd`、`bt_bomber_attack.gd`、`bt_move_to_target.gd` — 写 velocity 处改经 `agent.resolve_velocity(...)`；kite 开火、bomber 引信加 `is_stunned` 门控。
- `scenes/player/player.gd` — 新增 `crit_chance/crit_mult`；`_check_contact_damage` 抽出纯静态 `sum_contact_damage`（硬直敌人不结算接触）。
- `scenes/weapons/weapon_base.gd` — `damage_for` 加暴击重载；新增纯静态 `crit_multiplier`。
- `tests/test_player.gd` — 追加 crit 默认值 + `sum_contact_damage` 单测。

## Interfaces（后续 W1–W3 依赖的对外契约）

供后续波次按名消费——名字与签名以本节为准：

```gdscript
# Enemy（状态/击退）
func apply_status(kind: StringName, magnitude: float, duration: float) -> void
func move_speed_mult() -> float          # 1.0=无影响, 0.0=冻结；取最强减速
func is_stunned() -> bool                # stun/freeze 期间 true
func has_status(kind: StringName) -> bool
func apply_impulse(dir: Vector2, strength: float) -> void
var external_velocity: Vector2           # 随物理帧 *0.85 衰减
func resolve_velocity(desired: Vector2) -> Vector2
static func compose_velocity(desired: Vector2, speed_mult: float, stunned: bool, external: Vector2) -> Vector2

# 状态 kind 取值：&"burn"(magnitude=dps) / &"slow"(magnitude=0..1 乘子) / &"freeze"(magnitude 忽略) / &"stun"(magnitude 忽略)

# WeaponBase（暴击）
func damage_for(base: float, can_crit := false, crit_bonus := 0.0) -> float
static func crit_multiplier(roll: float, chance: float, crit_bonus: float, crit_mult: float) -> float

# Player（暴击口径）
var crit_chance: float = 0.0
var crit_mult: float = 2.0
static func sum_contact_damage(entries: Array, delta: float, max_sources: int) -> float
```

---

### Task 1: StatusComponent（状态底座，纯逻辑）

**Files:**
- Create: `scenes/enemies/status_component.gd`
- Test: `tests/test_status_component.gd`

**Interfaces:**
- Consumes: 无（纯 RefCounted）。
- Produces: `apply(kind, magnitude, duration)`、`tick(delta) -> float`（返回本帧燃烧伤害）、`move_speed_mult() -> float`、`is_stunned() -> bool`、`has(kind) -> bool`、常量 `BURN_INTERVAL = 0.25`。`Enemy`（Task 2/3）按这些方法委托。

- [x] **Step 1: 写失败测试 `tests/test_status_component.gd`**

```gdscript
extends GdUnitTestSuite
# 状态底座纯逻辑单测(RefCounted，无需场景)。preload 引用脚本，避免类缓存重建依赖。

const StatusComponentScript := preload("res://scenes/enemies/status_component.gd")

func _sc():
	return StatusComponentScript.new()

func test_no_status_speed_mult_is_one() -> void:
	assert_float(_sc().move_speed_mult()).is_equal(1.0)

func test_no_status_not_stunned() -> void:
	assert_bool(_sc().is_stunned()).is_false()

func test_slow_sets_speed_mult() -> void:
	var s = _sc()
	s.apply(&"slow", 0.5, 1.0)
	assert_float(s.move_speed_mult()).is_equal_approx(0.5, 0.001)

func test_slow_takes_strongest_lower_mult() -> void:
	var s = _sc()
	s.apply(&"slow", 0.5, 1.0)
	s.apply(&"slow", 0.7, 1.0)   # 较弱(更快) → 不取代
	assert_float(s.move_speed_mult()).is_equal_approx(0.5, 0.001)
	s.apply(&"slow", 0.3, 1.0)   # 更强(更慢) → 取代
	assert_float(s.move_speed_mult()).is_equal_approx(0.3, 0.001)

func test_freeze_zeroes_speed_and_stuns() -> void:
	var s = _sc()
	s.apply(&"freeze", 0.0, 1.0)
	assert_float(s.move_speed_mult()).is_equal(0.0)
	assert_bool(s.is_stunned()).is_true()

func test_stun_sets_stunned_without_slowing() -> void:
	var s = _sc()
	s.apply(&"stun", 0.0, 1.0)
	assert_bool(s.is_stunned()).is_true()
	assert_float(s.move_speed_mult()).is_equal(1.0)

func test_burn_returns_damage_in_quarter_second_chunks() -> void:
	var s = _sc()
	s.apply(&"burn", 8.0, 2.0)   # 8 dps
	assert_float(s.tick(0.25)).is_equal_approx(2.0, 0.001)   # 一拍 = 8×0.25
	assert_float(s.tick(0.25)).is_equal_approx(2.0, 0.001)

func test_burn_accumulates_partial_deltas() -> void:
	var s = _sc()
	s.apply(&"burn", 8.0, 2.0)
	assert_float(s.tick(0.1)).is_equal(0.0)                  # 0.1 < 0.25 未满一拍
	assert_float(s.tick(0.1)).is_equal(0.0)                  # 累计 0.2，仍未满
	assert_float(s.tick(0.1)).is_equal_approx(2.0, 0.001)    # 累计 0.3 → 结算一拍

func test_burn_refresh_takes_strongest_dps() -> void:
	var s = _sc()
	s.apply(&"burn", 4.0, 2.0)
	s.apply(&"burn", 8.0, 2.0)   # 更高 dps → 取代
	assert_float(s.tick(0.25)).is_equal_approx(2.0, 0.001)   # 8×0.25

func test_no_burn_tick_returns_zero() -> void:
	assert_float(_sc().tick(1.0)).is_equal(0.0)

func test_status_expires_after_duration() -> void:
	var s = _sc()
	s.apply(&"slow", 0.5, 0.5)
	s.tick(0.6)   # 超过时长 → 过期
	assert_float(s.move_speed_mult()).is_equal(1.0)
	assert_bool(s.has(&"slow")).is_false()

func test_has_reports_active_status() -> void:
	var s = _sc()
	s.apply(&"slow", 0.5, 1.0)
	assert_bool(s.has(&"slow")).is_true()
	assert_bool(s.has(&"freeze")).is_false()

func test_apply_zero_duration_is_noop() -> void:
	var s = _sc()
	s.apply(&"slow", 0.5, 0.0)
	assert_bool(s.has(&"slow")).is_false()

func test_freeze_overrides_slow_for_speed() -> void:
	var s = _sc()
	s.apply(&"slow", 0.5, 1.0)
	s.apply(&"freeze", 0.0, 1.0)
	assert_float(s.move_speed_mult()).is_equal(0.0)
```

- [x] **Step 2: 运行，确认失败**

Run: 上方命令，`<TEST_FILE>` = `test_status_component`
Expected: 套件加载失败（红）——`Could not preload resource "res://scenes/enemies/status_component.gd"`（文件尚不存在）。

- [x] **Step 3: 创建实现 `scenes/enemies/status_component.gd`**

```gdscript
# scenes/enemies/status_component.gd
# 敌人状态底座：燃烧 DoT / 减速 / 冻结 / 硬直。纯逻辑(RefCounted)，不持节点引用，便于单测。
# Enemy 每物理帧调 tick(delta) 推进，并据返回值结算燃烧伤害。
class_name StatusComponent
extends RefCounted

# 燃烧 DoT 结算节拍(秒)：每满一拍结算一次 dps*INTERVAL 的伤害。
const BURN_INTERVAL: float = 0.25

# kind(StringName) -> 剩余秒数；过期即 erase。
var _durations: Dictionary = {}
# kind(StringName) -> magnitude(燃烧=dps / 减速=速度乘子 / 冻结|硬直=忽略)。
var _magnitudes: Dictionary = {}
# 燃烧累加器：跨帧累计 delta，满 BURN_INTERVAL 结算一拍。
var _burn_accum: float = 0.0

# 统一入口：施加/刷新一个状态。可刷新不可叠加——magnitude 取最强、duration 取更久者。
func apply(kind: StringName, magnitude: float, duration: float) -> void:
	if duration <= 0.0:
		return
	if not _magnitudes.has(kind) or _is_stronger(kind, magnitude, _magnitudes[kind]):
		_magnitudes[kind] = magnitude
	_durations[kind] = maxf(_durations.get(kind, 0.0), duration)

# 减速取"更慢"(乘子更小)为强；其余(燃烧 dps)取更大为强。
static func _is_stronger(kind: StringName, new_mag: float, old_mag: float) -> bool:
	if kind == &"slow":
		return new_mag < old_mag
	return new_mag > old_mag

# 每物理帧驱动：递减所有时长、清过期，返回本帧应结算的燃烧伤害(无燃烧时为 0)。
func tick(delta: float) -> float:
	for kind in _durations.keys():   # keys() 返回拷贝，循环内 erase 安全
		_durations[kind] -= delta
		if _durations[kind] <= 0.0:
			_durations.erase(kind)
			_magnitudes.erase(kind)
	var burn_damage := 0.0
	if _durations.has(&"burn"):
		_burn_accum += delta
		while _burn_accum >= BURN_INTERVAL:
			_burn_accum -= BURN_INTERVAL
			burn_damage += _magnitudes[&"burn"] * BURN_INTERVAL
	else:
		_burn_accum = 0.0
	return burn_damage

# 速度乘子：冻结=0；否则取最强减速；无减速=1.0。供 BT move atom 读取。
func move_speed_mult() -> float:
	if _durations.has(&"freeze"):
		return 0.0
	if _durations.has(&"slow"):
		return _magnitudes[&"slow"]
	return 1.0

# 硬直：冻结或硬直期间为 true → atom 输出零速、跳过攻击/接触结算。
func is_stunned() -> bool:
	return _durations.has(&"stun") or _durations.has(&"freeze")

# 查询某状态是否生效(霜噬"已减速则升级冻结"等机制循环需要)。
func has(kind: StringName) -> bool:
	return _durations.has(kind)
```

- [x] **Step 4: 运行，确认通过**

Run: 同 Step 2
Expected: PASS（14 个测试全绿）。

- [x] **Step 5: 提交**

```bash
git add scenes/enemies/status_component.gd tests/test_status_component.gd
git commit -m "feat(combat): StatusComponent 状态底座(燃烧/减速/冻结/硬直,纯逻辑+单测)"
```

---

### Task 2: Enemy 接入状态系统

**Files:**
- Modify: `scenes/enemies/enemy.gd`
- Test: `tests/test_enemy_status.gd`

**Interfaces:**
- Consumes: `StatusComponent`（Task 1）的 `apply / tick / move_speed_mult / is_stunned / has`。
- Produces: `Enemy.apply_status(kind, magnitude, duration)`、`Enemy.move_speed_mult()`、`Enemy.is_stunned()`、`Enemy.has_status(kind)`；`_physics_process` 驱动燃烧 DoT（武器/玩家/atom 在 Task 3/4 消费）。

- [x] **Step 1: 写失败测试 `tests/test_enemy_status.gd`**

```gdscript
extends GdUnitTestSuite
# Enemy 接入状态/击退的集成验证(实例化 enemy.tscn → 依赖 LimboAI；headless 测试进程会加载)。
# 后续 Task 3/4 会向本文件追加击退与移动门控的测试。

const EnemyScene := preload("res://scenes/enemies/enemy.tscn")

# 建一只敌人并入树(触发 _enter_tree 建 BT + _ready)。无玩家时 chase atom 直接 FAILURE 不移动，
# 适合隔离验证状态/外力本身。
func _make_enemy(behavior: String = "chase") -> Enemy:
	var e: Enemy = EnemyScene.instantiate()
	e.behavior = behavior
	add_child(e)
	e.add_to_group("enemies")
	return auto_free(e)

func test_apply_burn_damages_over_physics_frames() -> void:
	var e := _make_enemy()
	e.MAX_HP = 100.0
	e.hp = 100.0
	e.apply_status(&"burn", 8.0, 1.0)   # 8 dps, 1s
	for i in range(60):                  # ~1 秒 @60fps
		await get_tree().physics_frame
	# 8 dps × ~1s ≈ 8 伤害(4 拍 × 2.0)；给 ±2 容差吸收帧边界
	assert_float(e.hp).is_less(100.0)
	assert_float(e.hp).is_equal_approx(92.0, 2.0)

func test_freeze_stuns_and_zeroes_speed_mult() -> void:
	var e := _make_enemy()
	e.apply_status(&"freeze", 0.0, 1.0)
	assert_bool(e.is_stunned()).is_true()
	assert_float(e.move_speed_mult()).is_equal(0.0)

func test_slow_reduces_speed_mult_without_stun() -> void:
	var e := _make_enemy()
	e.apply_status(&"slow", 0.5, 1.0)
	assert_float(e.move_speed_mult()).is_equal_approx(0.5, 0.001)
	assert_bool(e.is_stunned()).is_false()

func test_stun_sets_stunned() -> void:
	var e := _make_enemy()
	e.apply_status(&"stun", 0.0, 1.0)
	assert_bool(e.is_stunned()).is_true()

func test_has_status_reports_active() -> void:
	var e := _make_enemy()
	e.apply_status(&"slow", 0.5, 1.0)
	assert_bool(e.has_status(&"slow")).is_true()
	assert_bool(e.has_status(&"freeze")).is_false()
```

- [x] **Step 2: 运行，确认失败**

Run: `<TEST_FILE>` = `test_enemy_status`
Expected: 红——`Invalid call. Nonexistent function 'apply_status' in base 'Enemy'`（方法尚未声明，静态类型检查失败）。

- [x] **Step 3: 修改 `scenes/enemies/enemy.gd`**

在变量区，`_pulse_tween` 行（第 23 行）下方加状态实例：

```gdscript
var status: StatusComponent = StatusComponent.new()   # 燃烧/减速/冻结/硬直底座(4.1)
```

在 `_process`（第 44–46 行的 sprite 翻转）之后、`take_damage` 之前，新增物理帧驱动与对外接口：

```gdscript
# 物理帧驱动状态底座：结算燃烧 DoT。(external_velocity 衰减在 Task3 追加到本函数。)
func _physics_process(delta: float) -> void:
	var burn := status.tick(delta)
	if burn > 0.0:
		take_damage(burn)

# ── 状态底座对外接口 ───────────────────────────────────────────────────────
# 武器命中调 apply_status；BT move atom / 玩家接触结算读 move_speed_mult / is_stunned。
func apply_status(kind: StringName, magnitude: float, duration: float) -> void:
	status.apply(kind, magnitude, duration)

func move_speed_mult() -> float:
	return status.move_speed_mult()

func is_stunned() -> bool:
	return status.is_stunned()

func has_status(kind: StringName) -> bool:
	return status.has(kind)
```

- [x] **Step 4: 运行，确认通过**

Run: 同 Step 2
Expected: PASS（5 个测试全绿）。燃烧经 `take_damage` 会触发 GameFeel 命中反馈（headless 下伤害数字/音效有 null 守卫，不崩）。

- [x] **Step 5: 提交**

```bash
git add scenes/enemies/enemy.gd tests/test_enemy_status.gd
git commit -m "feat(enemy): Enemy 接入 StatusComponent(apply_status/move_speed_mult/is_stunned + 燃烧 DoT)"
```

---

### Task 3: 真击退 external_velocity + 速度合成 compose_velocity

**Files:**
- Modify: `scenes/enemies/enemy.gd`
- Test: `tests/test_enemy_velocity.gd`（新建，纯静态）、`tests/test_enemy_status.gd`（追加击退集成）

**Interfaces:**
- Consumes: `move_speed_mult() / is_stunned()`（Task 2）。
- Produces: `Enemy.external_velocity`、`Enemy.apply_impulse(dir, strength)`、静态 `Enemy.compose_velocity(desired, speed_mult, stunned, external)`、`Enemy.resolve_velocity(desired)`；BT 原子（Task 4）调用 `resolve_velocity`，变幻/双手武器（W2/W3）调用 `apply_impulse`。

- [x] **Step 1: 写失败测试 `tests/test_enemy_velocity.gd`（纯静态合成）**

```gdscript
extends GdUnitTestSuite
# Enemy.compose_velocity 纯静态合成单测(无需实例化场景)。
const EnemyScript := preload("res://scenes/enemies/enemy.gd")

func test_compose_full_speed_no_status_no_external() -> void:
	var v: Vector2 = EnemyScript.compose_velocity(Vector2(80, 0), 1.0, false, Vector2.ZERO)
	assert_vector(v).is_equal(Vector2(80, 0))

func test_compose_slow_scales_desired() -> void:
	var v: Vector2 = EnemyScript.compose_velocity(Vector2(80, 0), 0.5, false, Vector2.ZERO)
	assert_vector(v).is_equal(Vector2(40, 0))

func test_compose_adds_external_velocity() -> void:
	var v: Vector2 = EnemyScript.compose_velocity(Vector2(80, 0), 1.0, false, Vector2(0, 100))
	assert_vector(v).is_equal(Vector2(80, 100))

func test_compose_stunned_drops_self_motion_keeps_external() -> void:
	# 硬直：自身期望速度归零，但仍受外力(击退/拉拽)推动
	var v: Vector2 = EnemyScript.compose_velocity(Vector2(80, 0), 1.0, true, Vector2(0, 100))
	assert_vector(v).is_equal(Vector2(0, 100))

func test_compose_frozen_zero_mult_still_takes_external() -> void:
	# 冻结时调用方传 speed_mult=0 且 stunned=true → 只剩外力
	var v: Vector2 = EnemyScript.compose_velocity(Vector2(80, 0), 0.0, true, Vector2(50, 0))
	assert_vector(v).is_equal(Vector2(50, 0))
```

- [x] **Step 2: 运行，确认失败**

Run: `<TEST_FILE>` = `test_enemy_velocity`
Expected: 红——`Static function "compose_velocity()" not found in base "GDScript"`（静态方法未声明）。

- [x] **Step 3: 修改 `scenes/enemies/enemy.gd`（外力 + 合成）**

在常量区（`ICON_TO_TILE` 第 9 行下方）加：

```gdscript
const EXTERNAL_VELOCITY_DECAY: float = 0.85   # 每物理帧外力衰减(真击退,4.2)
const EXTERNAL_VELOCITY_CUTOFF: float = 1.0   # 低于此速度归零，防长尾抖动
```

在 `status` 变量（Task 2 新增）下方加：

```gdscript
var external_velocity: Vector2 = Vector2.ZERO   # 随物理帧衰减的外力速度(击退/拉拽)
```

把 Task 2 新增的 `_physics_process` 扩成（追加外力衰减两行）：

```gdscript
# 物理帧驱动状态底座：结算燃烧 DoT；衰减外力速度。
func _physics_process(delta: float) -> void:
	var burn := status.tick(delta)
	if burn > 0.0:
		take_damage(burn)
	external_velocity *= EXTERNAL_VELOCITY_DECAY
	if external_velocity.length() < EXTERNAL_VELOCITY_CUTOFF:
		external_velocity = Vector2.ZERO
```

在对外接口区（`has_status` 之后）加击退与速度合成：

```gdscript
# 真击退/拉拽：把方向冲量累加到随帧衰减的外力速度(被 BT move atom 并入移动)。
func apply_impulse(dir: Vector2, strength: float) -> void:
	external_velocity += dir * strength

# 纯函数(便于单测)：把 atom 的期望速度按状态+外力合成最终速度。
# 硬直时自身不动但仍受外力推动。
static func compose_velocity(desired: Vector2, speed_mult: float, stunned: bool, external: Vector2) -> Vector2:
	if stunned:
		return external
	return desired * speed_mult + external

# BT move atom 调用：传入期望速度，返回应写入 velocity 的合成速度(仍只调一次 move_and_slide)。
func resolve_velocity(desired: Vector2) -> Vector2:
	return compose_velocity(desired, move_speed_mult(), is_stunned(), external_velocity)
```

- [x] **Step 4: 向 `tests/test_enemy_status.gd` 追加击退集成测试**

在文件末尾追加（沿用同文件的 `_make_enemy()`）：

```gdscript
func test_apply_impulse_sets_external_velocity() -> void:
	var e := _make_enemy()
	e.apply_impulse(Vector2.RIGHT, 200.0)
	assert_vector(e.external_velocity).is_equal(Vector2(200.0, 0.0))

func test_external_velocity_decays_over_physics_frames() -> void:
	var e := _make_enemy()   # 无玩家 → chase atom FAILURE 不写 velocity，隔离衰减
	e.apply_impulse(Vector2.RIGHT, 200.0)
	var before := e.external_velocity.length()
	await get_tree().physics_frame
	await get_tree().physics_frame
	assert_float(e.external_velocity.length()).is_less(before)

func test_resolve_velocity_uses_status_and_external() -> void:
	var e := _make_enemy()
	e.apply_status(&"slow", 0.5, 1.0)
	e.apply_impulse(Vector2(0, 100), 1.0)   # external = (0,100)
	var v := e.resolve_velocity(Vector2(80, 0))
	assert_vector(v).is_equal(Vector2(40, 100))   # 80*0.5 + (0,100)
```

- [x] **Step 5: 运行两个文件，确认通过**

Run: `<TEST_FILE>` = `test_enemy_velocity`，再 `<TEST_FILE>` = `test_enemy_status`
Expected: 均 PASS。

- [x] **Step 6: 提交**

```bash
git add scenes/enemies/enemy.gd tests/test_enemy_velocity.gd tests/test_enemy_status.gd
git commit -m "feat(enemy): 真击退 external_velocity/apply_impulse + compose_velocity 速度合成"
```

---

### Task 4: BT 移动原子接入 + 玩家接触伤害跳过硬直

**Files:**
- Modify: `scenes/enemies/ai/atoms/bt_chase_target.gd`、`bt_move_to_target.gd`、`bt_kite_target.gd`、`bt_bomber_attack.gd`
- Modify: `scenes/player/player.gd`
- Test: `tests/test_player.gd`（追加 `sum_contact_damage` 纯函数）、`tests/test_enemy_status.gd`（追加移动门控集成）

**Interfaces:**
- Consumes: `Enemy.resolve_velocity`、`Enemy.is_stunned`（Task 3/2）。
- Produces: `Player.sum_contact_damage(entries, delta, max_sources)`（纯静态）；4 个移动原子的移动统一经状态/外力通道。

- [x] **Step 1: 向 `tests/test_player.gd` 追加 `sum_contact_damage` 失败测试**

在文件末尾追加：

```gdscript
# ── 接触伤害结算(W0)：硬直敌人不结算、最多累计 CONTACT_MAX_SOURCES 个来源 ──────
func test_sum_contact_damage_skips_stunned() -> void:
	var entries := [
		{"damage": 8.0, "stunned": false},
		{"damage": 8.0, "stunned": true},   # 硬直 → 跳过
		{"damage": 8.0, "stunned": false},
	]
	# 0.5s：两个非硬直 × 8 × 0.5 = 8.0
	assert_float(Player.sum_contact_damage(entries, 0.5, 6)).is_equal_approx(8.0, 0.001)

func test_sum_contact_damage_caps_at_max_sources() -> void:
	var entries: Array = []
	for i in range(10):
		entries.append({"damage": 10.0, "stunned": false})
	# 上限 6 个来源 × 10 × 1.0s = 60
	assert_float(Player.sum_contact_damage(entries, 1.0, 6)).is_equal_approx(60.0, 0.001)

func test_sum_contact_damage_all_stunned_is_zero() -> void:
	var entries := [{"damage": 8.0, "stunned": true}, {"damage": 8.0, "stunned": true}]
	assert_float(Player.sum_contact_damage(entries, 1.0, 6)).is_equal(0.0)
```

- [x] **Step 2: 运行，确认失败**

Run: `<TEST_FILE>` = `test_player`
Expected: 红——`Static function "sum_contact_damage()" not found in base "Player"`。

- [x] **Step 3: 修改 `scenes/player/player.gd`（抽纯函数 + 跳过硬直）**

把 `_check_contact_damage`（第 113–123 行）整体替换为：

```gdscript
func _check_contact_damage(delta: float) -> void:
	var entries: Array = []
	for body in hurt_box.get_overlapping_bodies():
		if body.is_in_group("enemies"):
			var stunned: bool = body.has_method("is_stunned") and body.is_stunned()
			entries.append({"damage": body.CONTACT_DAMAGE, "stunned": stunned})
	var total := sum_contact_damage(entries, delta, CONTACT_MAX_SOURCES)
	if total > 0.0:
		take_damage(total)

# 纯函数(便于单测)：累计接触伤害；硬直敌人不结算且不占来源上限；最多累计 max_sources 个。
static func sum_contact_damage(entries: Array, delta: float, max_sources: int) -> float:
	var total := 0.0
	var n := 0
	for e in entries:
		if e["stunned"]:
			continue
		total += float(e["damage"]) * delta
		n += 1
		if n >= max_sources:
			break
	return total
```

- [x] **Step 4: 修改 4 个 BT 移动原子**

`scenes/enemies/ai/atoms/bt_chase_target.gd` —— `_tick` 内的两行移动改为：

```gdscript
	agent.velocity = agent.resolve_velocity(_dir_to_player(target) * agent.SPEED)
	agent.move_and_slide()
	return RUNNING
```

`scenes/enemies/ai/atoms/bt_move_to_target.gd` —— `_tick` 的停留分支与追击分支都经 `resolve_velocity`（停留时传 `Vector2.ZERO`，仍保留外力）：

```gdscript
func _tick(_delta: float) -> Status:
	var target := _player()
	if target == null:
		return FAILURE
	var dist := _dist_to_player(target)
	if dist <= desired_dist:
		agent.velocity = agent.resolve_velocity(Vector2.ZERO)
		agent.move_and_slide()
		return SUCCESS
	agent.velocity = agent.resolve_velocity(_dir_to_player(target) * agent.SPEED)
	agent.move_and_slide()
	return RUNNING
```

`scenes/enemies/ai/atoms/bt_kite_target.gd` —— `_tick` 改为经 `resolve_velocity`，且硬直时不开火：

```gdscript
func _tick(delta: float) -> Status:
	var target := _player()
	if target == null:
		return FAILURE
	var dist := _dist_to_player(target)
	var dir := _dir_to_player(target)
	var move := kite_move(dist, preferred, band)
	agent.velocity = agent.resolve_velocity(dir * agent.SPEED * float(move))
	agent.move_and_slide()
	_cd -= delta
	if move == 0 and _cd <= 0.0 and not agent.is_stunned():
		_cd = shoot_cooldown
		_shoot(dir)
	return RUNNING
```

`scenes/enemies/ai/atoms/bt_bomber_attack.gd` —— 追击阶段经 `resolve_velocity`；引信阶段改用外力速度、硬直时暂停引信：

```gdscript
func _tick(delta: float) -> Status:
	var target := _player()
	if target == null:
		return FAILURE
	var dist := _dist_to_player(target)
	if _fuse < 0.0:
		# 阶段一：追击直到进入引信范围
		agent.velocity = agent.resolve_velocity(_dir_to_player(target) * agent.SPEED)
		agent.move_and_slide()
		if dist <= fuse_range:
			_fuse = fuse_time
		return RUNNING
	# 阶段二：停下倒计时(硬直会暂停引信；仍受击退外力推动)
	agent.velocity = agent.resolve_velocity(Vector2.ZERO)
	agent.move_and_slide()
	if not agent.is_stunned():
		_fuse -= delta
	if _fuse <= 0.0:
		_detonate(target)
		return SUCCESS
	return RUNNING
```

- [x] **Step 5: 向 `tests/test_enemy_status.gd` 追加移动门控集成测试**

在文件顶部 `const EnemyScene` 下方加玩家场景常量：

```gdscript
const PlayerScene := preload("res://scenes/player/player.tscn")
```

在文件末尾追加（冻结敌人不追击 / 正常敌人追击的对照）：

```gdscript
# 在 (px,0) 放一名玩家(入 "player" 组供 BT 索敌)，返回玩家。
func _make_player(px: float) -> Player:
	var p: Player = PlayerScene.instantiate()
	add_child(p)
	p.add_to_group("player")
	p.global_position = Vector2(px, 0)
	return auto_free(p)

func test_frozen_enemy_does_not_chase_player() -> void:
	_make_player(400.0)
	await get_tree().process_frame
	var e := _make_enemy("chase")
	e.global_position = Vector2.ZERO
	await get_tree().process_frame
	e.apply_status(&"freeze", 0.0, 5.0)
	var start_x := e.global_position.x
	for i in range(20):
		await get_tree().physics_frame
	# 冻结期间 resolve_velocity → 仅外力(=0) → 不应朝玩家(+x)移动
	assert_float(e.global_position.x).is_equal_approx(start_x, 2.0)

func test_unimpeded_enemy_chases_player() -> void:
	_make_player(400.0)
	await get_tree().process_frame
	var e := _make_enemy("chase")
	e.global_position = Vector2.ZERO
	var start_x := e.global_position.x
	for i in range(20):
		await get_tree().physics_frame
	assert_float(e.global_position.x).is_greater(start_x + 5.0)
```

- [x] **Step 6: 运行两个文件，确认通过**

Run: `<TEST_FILE>` = `test_player`，再 `<TEST_FILE>` = `test_enemy_status`
Expected: 均 PASS（含既有 Player 测试不回归）。

- [x] **Step 7: 提交**

```bash
git add scenes/enemies/ai/atoms/bt_chase_target.gd scenes/enemies/ai/atoms/bt_move_to_target.gd scenes/enemies/ai/atoms/bt_kite_target.gd scenes/enemies/ai/atoms/bt_bomber_attack.gd scenes/player/player.gd tests/test_player.gd tests/test_enemy_status.gd
git commit -m "feat(enemy-ai): BT move atom 经 resolve_velocity 接入状态/击退 + 玩家接触伤害跳过硬直"
```

---

### Task 5: 暴击口径（damage_for 重载 + Player crit 字段）

**Files:**
- Modify: `scenes/weapons/weapon_base.gd`
- Modify: `scenes/player/player.gd`
- Test: `tests/test_weapon_crit.gd`（新建）、`tests/test_player.gd`（追加默认值）

**Interfaces:**
- Consumes: `Player.damage_mult`（既有）。
- Produces: `WeaponBase.damage_for(base, can_crit:=false, crit_bonus:=0.0)`、静态 `WeaponBase.crit_multiplier(roll, chance, crit_bonus, crit_mult)`、`Player.crit_chance/crit_mult`；长弓（W1）用 `crit_bonus` 表达「距离/满血加成」。

- [x] **Step 1: 写失败测试 `tests/test_weapon_crit.gd`**

```gdscript
extends GdUnitTestSuite
# 暴击口径：crit_multiplier 纯函数 + damage_for 实例(在玩家下)集成。
# 概率中段用纯函数显式 roll 覆盖；damage_for 用确定性极值(chance 0/1)避免依赖 randf。

const WeaponBaseScript := preload("res://scenes/weapons/weapon_base.gd")

var _player: Player

func before_test() -> void:
	var scene := load("res://scenes/player/player.tscn") as PackedScene
	_player = auto_free(scene.instantiate() as Player)
	add_child(_player)
	await get_tree().process_frame

# ── crit_multiplier 纯函数 ──
func test_crit_below_threshold_crits() -> void:
	assert_float(WeaponBaseScript.crit_multiplier(0.10, 0.25, 0.0, 2.0)).is_equal(2.0)

func test_crit_above_threshold_no_crit() -> void:
	assert_float(WeaponBaseScript.crit_multiplier(0.50, 0.25, 0.0, 2.0)).is_equal(1.0)

func test_crit_bonus_raises_threshold() -> void:
	# 0.40 < 0.25+0.30=0.55 → 暴击
	assert_float(WeaponBaseScript.crit_multiplier(0.40, 0.25, 0.30, 2.0)).is_equal(2.0)

func test_crit_threshold_clamped_to_one() -> void:
	# 0.8+0.5=1.3 clamp 1.0；roll 0.99 < 1.0 → 必暴
	assert_float(WeaponBaseScript.crit_multiplier(0.99, 0.8, 0.5, 2.0)).is_equal(2.0)

func test_crit_zero_chance_never_crits() -> void:
	assert_float(WeaponBaseScript.crit_multiplier(0.0, 0.0, 0.0, 2.0)).is_equal(1.0)

# ── damage_for 实例(确定性极值)──
func test_damage_for_no_crit_is_base_times_mult() -> void:
	var w = auto_free(WeaponBaseScript.new())
	_player.add_child(w)
	await get_tree().process_frame
	_player.damage_mult = 2.0
	assert_float(w.damage_for(10.0)).is_equal_approx(20.0, 0.001)

func test_damage_for_guaranteed_crit() -> void:
	var w = auto_free(WeaponBaseScript.new())
	_player.add_child(w)
	await get_tree().process_frame
	_player.damage_mult = 1.0
	_player.crit_chance = 1.0   # 必暴
	_player.crit_mult = 2.0
	assert_float(w.damage_for(10.0, true)).is_equal_approx(20.0, 0.001)

func test_damage_for_can_crit_false_ignores_crit() -> void:
	var w = auto_free(WeaponBaseScript.new())
	_player.add_child(w)
	await get_tree().process_frame
	_player.damage_mult = 1.0
	_player.crit_chance = 1.0
	assert_float(w.damage_for(10.0, false)).is_equal_approx(10.0, 0.001)
```

- [x] **Step 2: 运行，确认失败**

Run: `<TEST_FILE>` = `test_weapon_crit`
Expected: 红——`Static function "crit_multiplier()" not found`（且 `_player.crit_chance` 字段不存在 → 解析错误）。

- [x] **Step 3: 修改 `scenes/player/player.gd`（新增 crit 字段）**

在 `damage_mult`（第 36 行）下方加：

```gdscript
var crit_chance: float = 0.0   # 暴击率(武器/构筑叠加)；默认 0 保持现有手感
var crit_mult: float = 2.0     # 暴击伤害倍率
```

- [x] **Step 4: 修改 `scenes/weapons/weapon_base.gd`（damage_for 重载 + crit_multiplier）**

把 `damage_for`（第 66–68 行）替换为：

```gdscript
# 伤害 = 基础 × 玩家全局伤害加成；可选暴击(弓等)：按 (crit_chance+crit_bonus) 概率 ×crit_mult。
# 改平衡只动一处口径。向后兼容：默认 can_crit=false 时等价旧 damage_for(base)。
func damage_for(base: float, can_crit: bool = false, crit_bonus: float = 0.0) -> float:
	var dmg := base * (_player as Player).damage_mult
	if can_crit:
		var p := _player as Player
		dmg *= crit_multiplier(randf(), p.crit_chance, crit_bonus, p.crit_mult)
	return dmg

# 纯函数(便于单测)：roll∈[0,1) 落在 (chance+crit_bonus，clamp 到[0,1]) 内则暴击。
static func crit_multiplier(roll: float, chance: float, crit_bonus: float, crit_mult: float) -> float:
	if roll < clampf(chance + crit_bonus, 0.0, 1.0):
		return crit_mult
	return 1.0
```

- [x] **Step 5: 向 `tests/test_player.gd` 追加 crit 默认值测试**

在「质变 modifier(E3)」区之后追加：

```gdscript
# ── 暴击口径默认值(W0)──────────────────────────────────────────────────────
func test_crit_chance_default_zero() -> void:
	assert_float(_player.crit_chance).is_equal(0.0)

func test_crit_mult_default_two() -> void:
	assert_float(_player.crit_mult).is_equal(2.0)
```

- [x] **Step 6: 运行两个文件，确认通过**

Run: `<TEST_FILE>` = `test_weapon_crit`，再 `<TEST_FILE>` = `test_player`
Expected: 均 PASS。

- [x] **Step 7: 提交**

```bash
git add scenes/weapons/weapon_base.gd scenes/player/player.gd tests/test_weapon_crit.gd tests/test_player.gd
git commit -m "feat(combat): WeaponBase.damage_for 暴击重载 + Player crit_chance/crit_mult"
```

---

### Task 6: W0 全量回归 + headless 烟雾

**Files:** 无新增（验证关）。

- [x] **Step 1: 跑全测试套件**

Run:
```powershell
& "C:\Dev\GAME\Godot\Godot_v4.6.3-stable_win64_console.exe" --headless --path "D:\Workspace\GAME\game_0_vsl" -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests
```
Expected: 全绿，含既有 `test_player / test_enemy_ai / test_weapons_new / test_game_formulas / test_spawn_director …` 无回归。

- [x] **Step 2: 资源导入 + 解析检查（确认新脚本无导入/解析错误）**

Run:
```powershell
& "C:\Dev\GAME\Godot\Godot_v4.6.3-stable_win64_console.exe" --headless --path "D:\Workspace\GAME\game_0_vsl" --import
```
Expected: 无 `SCRIPT ERROR` / 无 `Parse Error`。

- [x] **Step 3: 一局确定性烟雾（敌人移动/状态在真运行下不崩）**

Run:
```powershell
& "C:\Dev\GAME\Godot\Godot_v4.6.3-stable_win64_console.exe" --headless --fixed-fps 60 --path "D:\Workspace\GAME\game_0_vsl" --quit-after 900
```
Expected: 正常退出，DebugMetrics 打印聚合行；日志无 `Invalid call` / `Nonexistent function` / 关于 `resolve_velocity` / `is_stunned` 的报错。（注：无输入下玩家会被接触伤害打死属预期。）

- [x] **Step 4: 不提交（纯验证）。** 若任一步红，回到对应 Task 修复并重跑。

---

## Self-Review（对照 spec 复核）

**1. Spec 覆盖（W0 范围）**
- §4.1 状态系统（burn/slow/freeze/stun、取最强、move_speed_mult/is_stunned）→ Task 1（纯逻辑）+ Task 2（Enemy 接口）+ Task 4（BT atom 零速、玩家接触跳过）。✓
- §4.2 真击退（external_velocity / apply_impulse / 共用 velocity 通道 / 单次 move_and_slide）→ Task 3 + Task 4。✓
- §4.4 暴击（damage_for 重载、crit_chance/crit_mult 默认值、crit_bonus 口径）→ Task 5。✓
- §4.3 召唤基类 → **有意推迟**到 W1（OrbitGuardian）/ W3（RoamingMinion），见顶部「范围说明」。⚠（已显式记录，待评审确认）
- §10.1 配套 gdUnit 单测（状态取最强 / 速度乘子 / 暴击判定）→ Task 1/3/5 的纯函数测试覆盖全部三项。✓

**2. 占位符扫描**：无 TODO/TBD；每个代码步骤含完整可运行代码与确切命令、预期输出。✓

**3. 类型/命名一致性**：`apply_status / move_speed_mult / is_stunned / has_status / apply_impulse / external_velocity / resolve_velocity / compose_velocity / damage_for / crit_multiplier / crit_chance / crit_mult / sum_contact_damage / BURN_INTERVAL` 在「Interfaces」与各 Task 间一致；状态 kind 统一 `&"burn"/&"slow"/&"freeze"/&"stun"`。✓

**已知风险/注记**
- ~~**燃烧经 take_damage**：每 0.25s 触发一次 GameFeel 命中反馈（闪白/伤害数字/音效）。功能正确；视觉上可能偏吵，后续若需「持续灼烧用独立 DoT 视觉」再优化（spec §4.1 视觉列只是建议）。~~ **已解决**：新增 `Enemy.DamageChannel { DIRECT, DOT }` 通道；`take_damage(amount, channel)` 对 DOT 抑制白闪/击退/音效，仅留 per-enemy 节流（~0.5s）的橙色跳字；伤害与遥测照常计入。燃烧 + 重力井周期 tick 均归 DOT。
- **Enemy 集成测试依赖 LimboAI 在 headless 加载**（与既有 `test_enemy_ai.gd` 同前提）。核心数学已被纯函数测试（Task 1/3/5）独立保证；若集成测试因扩展未加载而 error，先排查 LimboAI 安装（见 CLAUDE.md），核心逻辑不受影响。
- **bomber 引信硬直暂停 / 接触上限不计硬直来源**：均为合理增强，已在代码注释说明，非 spec 明文但与 stun 语义自洽。

---

## Execution Handoff

**Plan complete and saved to `docs/superpowers/plans/2026-06-17-weapon-arsenal-w0-foundation.md`. Two execution options:**

**1. Subagent-Driven (recommended)** - I dispatch a fresh subagent per task, review between tasks, fast iteration

**2. Inline Execution** - Execute tasks in this session using executing-plans, batch execution with checkpoints

**Which approach?**
