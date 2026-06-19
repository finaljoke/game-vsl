# 状态协同系统（C2 State Synergy）实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在伤害收口 `Enemy.take_damage` 一处插入纯数值的状态协同乘区（碎裂/处决/引力增幅/燃尽），使全体武器零改动即获得"控住→收割""聚怪→增伤""点燃→引爆"的可感知连携。

**Architecture:** 单点接管——所有伤害都过 `Enemy.take_damage(amount, channel)`，在此读取扣血前的状态快照、经纯静态 `Enemy.synergy_multiplier()` 算出乘区、放大伤害；DIRECT 打击型协同放复用 Vfx 爆发；死时带 burn 触发一次性燃尽 AoE（模块级重入守卫保证单波）。引力井在已有的半径循环里多打一行 `amp` 状态。武器/法术 `.tres` 与脚本零改动。

**Tech Stack:** Godot 4.6.3 / GDScript / gdUnit4（headless）。状态底座 `StatusComponent`（RefCounted 纯逻辑）、`Vfx` autoload（`BURST_PRESETS` 已含 `ice_shard`/`crit_spark`/`fire_burst`）、`GameFeel` autoload（`enemy_hit` 信号驱动跳字）。

## Global Constraints

- **设计来源**：`docs/superpowers/specs/2026-06-19-state-synergy-design.md`（四规则数值、防级联细节、验收标准的唯一权威）。
- **分支**：`feat/state-synergy`（已存在，off 含 A1/A4 修复的 `fix/charger-control-evolution-regressions`）。每个 Task 末尾提交。
- **TDD 强制**：每个 Task 先写测试 → 看红（失败原因正确）→ 最小实现 → 看绿。无失败测试不写产品代码。
- **确定性不变量**：零 RNG。`Vfx.spawn_burst` 用实时 timer + CPUParticles，纯视觉、不碰 gameplay 状态，确定性安全。规则全套零随机 → `--fixed-fps 60` 下字节一致。
- **武器零改动**：除 `gravity_well.gd` 加一行 `apply_status(&"amp", …)` 外，不动任何武器脚本或 `.tres`。
- **常量集中**：所有协同常量定义在 `Enemy`（`SHATTER_MULT=1.5`、`EXECUTE_BASE=0.2`、`EXECUTE_SCALE=0.8`、`GRAVITY_AMP=0.25`、`AMP_DUR=0.25`、`CONFLAG_RADIUS=60.0`、`CONFLAG_DAMAGE=10.0`），便于后续遥测调参。
- **gdUnit 截断陷阱**：某测试解析/脚本错误会静默截断其后测试的发现。每次跑完核对**测试总数**，不能只看"全绿"。
- **测试运行命令**（CLI 必须用 `_console.exe` + `--ignoreHeadlessMode`）：
  - 全量：`& "C:\Dev\GAME\Godot\Godot_v4.6.3-stable_win64_console.exe" --headless --path "D:\Workspace\GAME\game_0_vsl" -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests`
  - 单套件：把 `-a res://tests` 换成 `-a res://tests/<file>.gd`
- **当前基线**：414/414 绿，33 套件，0 错误/失败。

---

## 文件结构

| 文件 | 职责 | 改动 |
|---|---|---|
| `scenes/enemies/status_component.gd` | 状态底座纯逻辑 | 新增 `magnitude(kind)` getter；`amp` 走现有泛型 apply/tick（零特判） |
| `scenes/enemies/enemy.gd` | 伤害收口 + 协同核心 | 新增协同常量 + `_conflagrating` 静态守卫 + 纯静态 `synergy_multiplier` + `_trigger_conflagration` helper；改 `take_damage` 插入乘区/反馈/燃尽 |
| `scenes/weapons/gravity_well/gravity_well.gd` | 引力井场 | 半径循环里加一行 `apply_status(&"amp", …)` |
| `tests/test_status_component.gd` | StatusComponent 纯逻辑单测 | 追加 `magnitude` + `amp` 泛型守卫 |
| `tests/test_enemy_synergy.gd` | **新建**：`synergy_multiplier` 纯函数单测 | 12 例 |
| `tests/test_enemy_status.gd` | Enemy 状态/伤害集成 | 追加碎裂/处决/燃尽集成 |
| `tests/test_weapons_w2.gd` | 引力井集成 | 追加 amp 打标守卫 |

---

## Task 1: StatusComponent.magnitude() getter + amp 泛型守卫

**Files:**
- Modify: `scenes/enemies/status_component.gd`
- Test: `tests/test_status_component.gd`

**Interfaces:**
- Consumes: 现有 `StatusComponent.apply(kind, magnitude, duration)`、`tick(delta)`、`has(kind)`、`move_speed_mult()`、`is_stunned()`、静态 `_is_stronger`（非 slow 取"更大更强"——`amp` 自动适用）。
- Produces: `StatusComponent.magnitude(kind: StringName) -> float`（缺省 0.0）。被 Task 3（`status.magnitude(&"amp")`）与 Task 4 测试依赖。

- [ ] **Step 1: 写失败测试（magnitude getter）**

追加到 `tests/test_status_component.gd` 末尾：

```gdscript
func test_magnitude_returns_stored_value() -> void:
	var s = _sc()
	s.apply(&"burn", 8.0, 1.0)
	assert_float(s.magnitude(&"burn")).is_equal_approx(8.0, 0.001)

func test_magnitude_missing_returns_zero() -> void:
	assert_float(_sc().magnitude(&"amp")).is_equal(0.0)
```

- [ ] **Step 2: 跑测试确认失败**

Run: `& "C:\Dev\GAME\Godot\Godot_v4.6.3-stable_win64_console.exe" --headless --path "D:\Workspace\GAME\game_0_vsl" -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/test_status_component.gd`
Expected: FAIL —「Invalid call. Nonexistent function 'magnitude' in base 'RefCounted (StatusComponent)'」。

- [ ] **Step 3: 实现 magnitude getter**

在 `scenes/enemies/status_component.gd` 的 `has()` 方法之后追加：

```gdscript
# 查询某状态的 magnitude(燃烧 dps / 引力增幅 amp 等数值项)；缺省返回 0.0。
func magnitude(kind: StringName) -> float:
	return _magnitudes.get(kind, 0.0)
```

- [ ] **Step 4: 跑测试确认通过**

Run: `& "...console.exe" --headless --path "D:\Workspace\GAME\game_0_vsl" -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/test_status_component.gd`
Expected: PASS（含两条新测试）。

- [ ] **Step 5: 加 amp 泛型守卫测试（amp 借现有泛型路径，无新产品代码）**

这四条守卫钉住"amp 是纯伤害读取项"的设计不变量：apply/查询正常、"更大更强"、到期 erase，且**不**影响速度/硬直。其中 `test_amp_does_not_affect_speed_or_stun` 在现有泛型实现下即绿（`move_speed_mult`/`is_stunned` 本就只看 freeze/slow/stun），作为防回归守卫保留。追加到 `tests/test_status_component.gd`：

```gdscript
func test_amp_rides_generic_apply_and_query() -> void:
	var s = _sc()
	s.apply(&"amp", 0.25, 0.25)
	assert_bool(s.has(&"amp")).is_true()
	assert_float(s.magnitude(&"amp")).is_equal_approx(0.25, 0.001)

func test_amp_takes_larger_as_stronger() -> void:
	var s = _sc()
	s.apply(&"amp", 0.25, 1.0)
	s.apply(&"amp", 0.10, 1.0)   # 更小 → 不取代
	assert_float(s.magnitude(&"amp")).is_equal_approx(0.25, 0.001)
	s.apply(&"amp", 0.40, 1.0)   # 更大 → 取代
	assert_float(s.magnitude(&"amp")).is_equal_approx(0.40, 0.001)

func test_amp_does_not_affect_speed_or_stun() -> void:
	var s = _sc()
	s.apply(&"amp", 0.25, 1.0)
	assert_float(s.move_speed_mult()).is_equal(1.0)
	assert_bool(s.is_stunned()).is_false()

func test_amp_expires_after_duration() -> void:
	var s = _sc()
	s.apply(&"amp", 0.25, 0.25)
	s.tick(0.3)
	assert_bool(s.has(&"amp")).is_false()
	assert_float(s.magnitude(&"amp")).is_equal(0.0)
```

- [ ] **Step 6: 跑测试确认全绿**

Run: `& "...console.exe" --headless --path "D:\Workspace\GAME\game_0_vsl" -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/test_status_component.gd`
Expected: PASS（新增 6 条测试全绿）。

- [ ] **Step 7: 提交**

```bash
git add scenes/enemies/status_component.gd tests/test_status_component.gd
git commit -m "feat(synergy): StatusComponent.magnitude() getter + amp 泛型守卫"
```

---

## Task 2: Enemy 协同常量 + synergy_multiplier 纯函数

**Files:**
- Modify: `scenes/enemies/enemy.gd`
- Test: `tests/test_enemy_synergy.gd`（新建）

**Interfaces:**
- Consumes: `Enemy.DamageChannel { DIRECT, DOT }`（已存在，`enemy.gd:14`）。
- Produces:
  - 常量 `Enemy.SHATTER_MULT/EXECUTE_BASE/EXECUTE_SCALE/GRAVITY_AMP/AMP_DUR/CONFLAG_RADIUS/CONFLAG_DAMAGE`、静态 `Enemy._conflagrating: bool`。
  - 纯静态 `Enemy.synergy_multiplier(channel: DamageChannel, frozen: bool, stun: bool, hp_frac: float, amp_frac: float) -> float`。被 Task 3（`take_damage`）、Task 4（gravity_well 用到 `GRAVITY_AMP`/`AMP_DUR`）、Task 5（`_conflagrating`/`CONFLAG_*`）依赖。

- [ ] **Step 1: 写失败测试（新建文件）**

创建 `tests/test_enemy_synergy.gd`：

```gdscript
extends GdUnitTestSuite
# Enemy.synergy_multiplier 纯静态乘区单测(无场景)。
# 状态键互斥(冻结只走碎裂、硬直只走处决)、引力增幅吃双通道、其余通道隔离。

func test_no_status_is_identity() -> void:
	assert_float(Enemy.synergy_multiplier(Enemy.DamageChannel.DIRECT, false, false, 1.0, 0.0)).is_equal_approx(1.0, 0.0001)

func test_frozen_direct_shatters() -> void:
	assert_float(Enemy.synergy_multiplier(Enemy.DamageChannel.DIRECT, true, false, 1.0, 0.0)).is_equal_approx(1.5, 0.0001)

func test_frozen_dot_does_not_shatter() -> void:
	assert_float(Enemy.synergy_multiplier(Enemy.DamageChannel.DOT, true, false, 1.0, 0.0)).is_equal_approx(1.0, 0.0001)

func test_stun_direct_full_hp_execute_base() -> void:
	# 满血 hp_frac=1.0 → 1 + 0.2 + 0.8*0 = 1.2
	assert_float(Enemy.synergy_multiplier(Enemy.DamageChannel.DIRECT, false, true, 1.0, 0.0)).is_equal_approx(1.2, 0.0001)

func test_stun_direct_near_death_execute_max() -> void:
	# 濒死 hp_frac=0.0 → 1 + 0.2 + 0.8*1 = 2.0
	assert_float(Enemy.synergy_multiplier(Enemy.DamageChannel.DIRECT, false, true, 0.0, 0.0)).is_equal_approx(2.0, 0.0001)

func test_stun_dot_does_not_execute() -> void:
	assert_float(Enemy.synergy_multiplier(Enemy.DamageChannel.DOT, false, true, 0.0, 0.0)).is_equal_approx(1.0, 0.0001)

func test_amp_applies_to_direct() -> void:
	assert_float(Enemy.synergy_multiplier(Enemy.DamageChannel.DIRECT, false, false, 1.0, 0.25)).is_equal_approx(1.25, 0.0001)

func test_amp_applies_to_dot() -> void:
	assert_float(Enemy.synergy_multiplier(Enemy.DamageChannel.DOT, false, false, 1.0, 0.25)).is_equal_approx(1.25, 0.0001)

func test_frozen_plus_amp_direct_stacks_multiplicatively() -> void:
	# 1.5 * 1.25 = 1.875
	assert_float(Enemy.synergy_multiplier(Enemy.DamageChannel.DIRECT, true, false, 1.0, 0.25)).is_equal_approx(1.875, 0.0001)

func test_near_death_stun_plus_amp_direct_stacks() -> void:
	# 2.0 * 1.25 = 2.5
	assert_float(Enemy.synergy_multiplier(Enemy.DamageChannel.DIRECT, false, true, 0.0, 0.25)).is_equal_approx(2.5, 0.0001)

func test_frozen_only_excludes_execute() -> void:
	# 仅冻结(非硬直)即便残血,只 ×1.5,不含处决项
	assert_float(Enemy.synergy_multiplier(Enemy.DamageChannel.DIRECT, true, false, 0.0, 0.0)).is_equal_approx(1.5, 0.0001)

func test_stun_only_excludes_shatter() -> void:
	# 仅硬直(非冻结)满血,只 ×1.2,不含碎裂项
	assert_float(Enemy.synergy_multiplier(Enemy.DamageChannel.DIRECT, false, true, 1.0, 0.0)).is_equal_approx(1.2, 0.0001)
```

- [ ] **Step 2: 跑测试确认失败**

Run: `& "...console.exe" --headless --path "D:\Workspace\GAME\game_0_vsl" -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/test_enemy_synergy.gd`
Expected: FAIL —「Invalid call. Nonexistent function 'synergy_multiplier' in base 'Enemy'」（12 条全红）。

- [ ] **Step 3: 加常量 + 静态守卫**

在 `scenes/enemies/enemy.gd` 的 `enum DamageChannel { DIRECT, DOT }`（第 14 行）之后追加：

```gdscript
# ── 状态协同(C2)常量 ──────────────────────────────────────────────────────────
const SHATTER_MULT: float = 1.5      # 冻结目标受直击的脆性增伤(碎裂,不消耗冻结)
const EXECUTE_BASE: float = 0.2      # 硬直处决基础加成(满血)
const EXECUTE_SCALE: float = 0.8     # 硬直处决随缺失血量的额外加成
const GRAVITY_AMP: float = 0.25      # 引力井内受到的全通道增伤
const AMP_DUR: float = 0.25          # amp 状态时长(井每帧刷新,离场约 3 帧自然衰减)
const CONFLAG_RADIUS: float = 60.0   # 燃尽 AoE 半径
const CONFLAG_DAMAGE: float = 10.0   # 燃尽 AoE 一次性火伤(DOT 通道)

# 燃尽重入守卫(模块级):燃尽 AoE 击杀带 burn 邻怪时跳过其再触发,保证单波(见设计 §6)。
static var _conflagrating: bool = false
```

- [ ] **Step 4: 实现 synergy_multiplier**

在 `scenes/enemies/enemy.gd` 的静态 `compose_velocity`（约第 121 行）之前追加：

```gdscript
# 纯函数(便于单测)：状态协同乘区。冻结→碎裂(仅DIRECT,不消耗)；硬直→处决(随缺失血量递增,仅DIRECT)；
# 引力增幅 amp→双通道。状态键互斥(冻结只走碎裂、硬直只走处决),跨来源乘算叠加。
static func synergy_multiplier(channel: DamageChannel, frozen: bool, stun: bool, hp_frac: float, amp_frac: float) -> float:
	var m := 1.0
	if amp_frac > 0.0:                       # 引力增幅：两个通道都吃
		m *= (1.0 + amp_frac)
	if channel == DamageChannel.DIRECT:      # 打击型协同：仅直击
		if frozen:
			m *= SHATTER_MULT
		if stun:                             # key 在 stun,不含 freeze → 与碎裂互斥
			m *= (1.0 + EXECUTE_BASE + EXECUTE_SCALE * (1.0 - hp_frac))
	return m
```

- [ ] **Step 5: 跑测试确认通过**

Run: `& "...console.exe" --headless --path "D:\Workspace\GAME\game_0_vsl" -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/test_enemy_synergy.gd`
Expected: PASS（12 条全绿）。

- [ ] **Step 6: 提交**

```bash
git add scenes/enemies/enemy.gd tests/test_enemy_synergy.gd
git commit -m "feat(synergy): Enemy 协同常量 + synergy_multiplier 纯函数"
```

---

## Task 3: take_damage 接入乘区 + DIRECT 反馈 + 放大跳字

**Files:**
- Modify: `scenes/enemies/enemy.gd:130-150`（`take_damage` 函数体）
- Test: `tests/test_enemy_status.gd`

**Interfaces:**
- Consumes: `Enemy.synergy_multiplier`（Task 2）、`StatusComponent.magnitude`（Task 1）、`Vfx.spawn_burst(pos, preset)`（已存在，`ice_shard`/`crit_spark` 预设在库）、`GameFeel.enemy_hit`（已存在）。
- Produces: `take_damage` 现按状态快照放大伤害；`GameFeel.enemy_hit.emit` 传出**放大后**的 `final`（跳字自然变大）。死亡分支本步**不**变（燃尽在 Task 5）。

- [ ] **Step 1: 写失败测试**

追加到 `tests/test_enemy_status.gd` 末尾：

```gdscript
func test_take_damage_shatters_frozen_enemy_on_direct() -> void:
	var e := _make_enemy()
	e.MAX_HP = 100.0
	e.hp = 100.0
	e.apply_status(&"freeze", 0.0, 1.0)
	e.take_damage(10.0, Enemy.DamageChannel.DIRECT)
	# 10 × 1.5 = 15 → hp 85
	assert_float(e.hp).is_equal_approx(85.0, 0.001)

func test_take_damage_dot_does_not_shatter_frozen() -> void:
	var e := _make_enemy()
	e.MAX_HP = 100.0
	e.hp = 100.0
	e.apply_status(&"freeze", 0.0, 1.0)
	e.take_damage(10.0, Enemy.DamageChannel.DOT)
	# 碎裂不沾 DoT → 10 × 1.0 = 10 → hp 90
	assert_float(e.hp).is_equal_approx(90.0, 0.001)

func test_take_damage_executes_full_hp_stun() -> void:
	var e := _make_enemy()
	e.MAX_HP = 100.0
	e.hp = 100.0
	e.apply_status(&"stun", 0.0, 1.0)
	e.take_damage(10.0, Enemy.DamageChannel.DIRECT)
	# 满血处决 ×1.2 → 12 → hp 88
	assert_float(e.hp).is_equal_approx(88.0, 0.001)

func test_take_damage_execute_scales_with_missing_hp() -> void:
	# 同样 10 直击,残血硬直怪掉血显著多于满血硬直怪。
	var full := _make_enemy()
	full.MAX_HP = 100.0
	full.hp = 100.0
	full.apply_status(&"stun", 0.0, 1.0)
	full.take_damage(10.0, Enemy.DamageChannel.DIRECT)
	var full_loss := 100.0 - full.hp

	var low := _make_enemy()
	low.MAX_HP = 100.0
	low.hp = 20.0   # hp_frac 0.2 → ×(1+0.2+0.8*0.8)=×1.84
	low.apply_status(&"stun", 0.0, 1.0)
	var before := low.hp
	low.take_damage(10.0, Enemy.DamageChannel.DIRECT)
	var low_loss := before - low.hp
	assert_float(low_loss).is_greater(full_loss)
```

- [ ] **Step 2: 跑测试确认失败**

Run: `& "...console.exe" --headless --path "D:\Workspace\GAME\game_0_vsl" -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/test_enemy_status.gd`
Expected: FAIL — 冻结/硬直怪扣血仍为基础值（如 frozen 测试 hp=90 而非期望 85），断言不满足。

- [ ] **Step 3: 改写 take_damage 插入乘区与反馈**

把 `scenes/enemies/enemy.gd` 现有 `take_damage` 整段（第 130–150 行）替换为（**注意死亡分支保持原样，燃尽在 Task 5 加**）：

```gdscript
func take_damage(amount: float, channel: DamageChannel = DamageChannel.DIRECT) -> void:
	# 扣血前快照协同输入(乘区用)。
	var frozen := has_status(&"freeze")
	var stun := has_status(&"stun")
	var hp_frac := (hp / MAX_HP) if MAX_HP > 0.0 else 0.0
	var amp := status.magnitude(&"amp")
	var final := amount * synergy_multiplier(channel, frozen, stun, hp_frac, amp)
	hp -= final
	# DIRECT 打击型协同反馈(复用预设,纯 cosmetic,确定性安全)。
	if channel == DamageChannel.DIRECT:
		if frozen:
			Vfx.spawn_burst(global_position, &"ice_shard")
		if stun:
			Vfx.spawn_burst(global_position, &"crit_spark")
	# Boss 受击：先 kill 脉冲并复位 _sprite.modulate，否则白闪 (enemy.modulate) 被脉冲色乘穿。
	# 仅 DIRECT 复位脉冲——DOT 每秒 4 跳，不能把 boss 红脉冲冲掉。
	if channel == DamageChannel.DIRECT and _pulse_tween != null:
		_pulse_tween.kill()
		_pulse_tween = null
		_sprite.modulate = Color.WHITE
	GameFeel.enemy_hit.emit(final, global_position, self, channel)
	if hp <= 0.0:
		if split_count > 0:
			_spawn_split()
		GameFeel.enemy_died.emit(global_position, self)
		died.emit(global_position)
		queue_free()
		return
	# 0.15s 白闪结束后稍微 buffer 一下再重启脉冲；ignore_time_scale 防 hitstop 拖死。
	if channel == DamageChannel.DIRECT and behavior == "boss":
		var t := get_tree().create_timer(0.2, false, true, true)
		t.timeout.connect(_restart_pulse_if_alive)
```

- [ ] **Step 4: 跑测试确认通过**

Run: `& "...console.exe" --headless --path "D:\Workspace\GAME\game_0_vsl" -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/test_enemy_status.gd`
Expected: PASS（新增 4 条 + 原有集成测试全绿；无状态时 `final==amount`，`test_apply_burn_damages_over_physics_frames` 等不受影响）。

- [ ] **Step 5: 提交**

```bash
git add scenes/enemies/enemy.gd tests/test_enemy_status.gd
git commit -m "feat(synergy): take_damage 接入协同乘区+DIRECT反馈+放大跳字"
```

---

## Task 4: 引力井打标 amp（井内增伤）

**Files:**
- Modify: `scenes/weapons/gravity_well/gravity_well.gd:31-36`（半径循环）
- Test: `tests/test_weapons_w2.gd`

**Interfaces:**
- Consumes: `Enemy.GRAVITY_AMP`、`Enemy.AMP_DUR`（Task 2 常量）、`Enemy.apply_status`（已存在）。
- Produces: 井内每只敌人每帧被刷新 `amp` 状态（magnitude=`GRAVITY_AMP`）；经 Task 3 乘区使其受到的全通道伤害 ×1.25。奇点（singularity）复用同脚本自动继承。

- [ ] **Step 1: 写失败测试**

追加到 `tests/test_weapons_w2.gd` 末尾（该文件已有 `_tough_enemy_at` 与 `GravityWellScript`）：

```gdscript
func test_gravity_well_stamps_amp_on_enemy_in_radius() -> void:
	var well: GravityWell = auto_free(GravityWellScript.new()) as GravityWell
	well.radius = 140.0
	well.pull_strength = 120.0
	well.field_dur = 5.0
	well.tick_damage = 0.0
	add_child(well)
	well.global_position = Vector2.ZERO
	var e := _tough_enemy_at(Vector2(50, 0))   # 半径内
	await get_tree().process_frame
	well._physics_process(0.1)
	assert_bool(e.has_status(&"amp")).is_true()
	assert_float(e.status.magnitude(&"amp")).is_equal_approx(Enemy.GRAVITY_AMP, 0.001)

func test_gravity_well_does_not_stamp_amp_outside_radius() -> void:
	var well: GravityWell = auto_free(GravityWellScript.new()) as GravityWell
	well.radius = 140.0
	well.pull_strength = 120.0
	well.field_dur = 5.0
	well.tick_damage = 0.0
	add_child(well)
	well.global_position = Vector2.ZERO
	var e := _tough_enemy_at(Vector2(300, 0))   # 半径外
	await get_tree().process_frame
	well._physics_process(0.1)
	assert_bool(e.has_status(&"amp")).is_false()
```

- [ ] **Step 2: 跑测试确认失败**

Run: `& "...console.exe" --headless --path "D:\Workspace\GAME\game_0_vsl" -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/test_weapons_w2.gd`
Expected: FAIL —「`test_gravity_well_stamps_amp_on_enemy_in_radius`：expected has_status(&"amp") true，实得 false」。

- [ ] **Step 3: 在半径循环里打标 amp**

把 `scenes/weapons/gravity_well/gravity_well.gd` 现有半径循环（第 31–36 行）替换为：

```gdscript
		for e in get_tree().get_nodes_in_group("enemies"):
			if not is_instance_valid(e):
				continue
			var to_center: Vector2 = global_position - (e as Node2D).global_position
			if to_center.length() <= radius and e.has_method("apply_impulse"):
				e.apply_impulse(to_center.normalized(), pull_strength * delta)
				# 引力增幅(C2)：井内每帧刷新 amp,使受到的全通道伤害 ×(1+amp)。奇点复用同脚本自动继承。
				e.apply_status(&"amp", Enemy.GRAVITY_AMP, Enemy.AMP_DUR)
```

> 注：缩进与 `_physics_process` 内现有循环一致（一层 tab）。仅在 `apply_impulse` 之后多一行 `apply_status`。

- [ ] **Step 4: 跑测试确认通过**

Run: `& "...console.exe" --headless --path "D:\Workspace\GAME\game_0_vsl" -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/test_weapons_w2.gd`
Expected: PASS（新增 2 条 + 原有引力井测试全绿；`test_gravity_well_ticks_damage` 断言仍是 `hp < 500`，amp 放大 DOT 后更小，仍满足）。

- [ ] **Step 5: 提交**

```bash
git add scenes/weapons/gravity_well/gravity_well.gd tests/test_weapons_w2.gd
git commit -m "feat(synergy): 引力井打标 amp(井内全通道增伤),奇点自动继承"
```

---

## Task 5: 燃尽（带 burn 死亡的一次性 AoE + 单波守卫）

**Files:**
- Modify: `scenes/enemies/enemy.gd`（`take_damage` 快照加 `had_burn`、死亡分支加燃尽触发；新增 `_trigger_conflagration` helper）
- Test: `tests/test_enemy_status.gd`

**Interfaces:**
- Consumes: `Enemy._conflagrating`、`Enemy.CONFLAG_RADIUS`、`Enemy.CONFLAG_DAMAGE`（Task 2）、`Vfx.spawn_burst`（`fire_burst` 预设在库）、`take_damage(amount, DOT)`（Task 3）。
- Produces: 带 burn 死亡 → 半径内邻怪各吃一次 `CONFLAG_DAMAGE` 的 DOT 火伤；**不**施 burn（不蔓延）；模块级重入守卫保证**单波**（邻怪被本波炸死不再触发第二波）。

- [ ] **Step 1: 写失败测试**

追加到 `tests/test_enemy_status.gd` 末尾：

```gdscript
func test_burning_enemy_death_conflagrates_neighbor() -> void:
	var dying := _make_enemy()
	dying.MAX_HP = 100.0
	dying.hp = 100.0
	dying.global_position = Vector2.ZERO
	dying.apply_status(&"burn", 1.0, 5.0)   # 死时带 burn
	var neighbor := _make_enemy()
	neighbor.MAX_HP = 100.0
	neighbor.hp = 100.0
	neighbor.global_position = Vector2(30, 0)   # < CONFLAG_RADIUS(60)
	await get_tree().process_frame
	dying.take_damage(999.0, Enemy.DamageChannel.DIRECT)   # 致死
	# 邻怪吃一次燃尽 DOT 10 → hp 90
	assert_float(neighbor.hp).is_equal_approx(90.0, 0.001)

func test_non_burning_enemy_death_does_not_conflagrate() -> void:
	var dying := _make_enemy()
	dying.MAX_HP = 100.0
	dying.hp = 100.0
	dying.global_position = Vector2.ZERO
	# 不带 burn
	var neighbor := _make_enemy()
	neighbor.MAX_HP = 100.0
	neighbor.hp = 100.0
	neighbor.global_position = Vector2(30, 0)
	await get_tree().process_frame
	dying.take_damage(999.0, Enemy.DamageChannel.DIRECT)
	assert_float(neighbor.hp).is_equal_approx(100.0, 0.001)

func test_conflagration_is_single_wave() -> void:
	# A、B 相邻且都带 burn。杀 A 触发一次燃尽,该 AoE 把脆皮 B 也炸死;
	# B 死亡分支因重入守卫不再触发第二波。用更远的 C 验证只被炸一次(90 而非 80)。
	var a := _make_enemy()
	a.MAX_HP = 100.0; a.hp = 100.0
	a.global_position = Vector2.ZERO
	a.apply_status(&"burn", 1.0, 5.0)
	var b := _make_enemy()
	b.MAX_HP = 5.0; b.hp = 5.0           # 脆,被 10 燃尽一击毙
	b.global_position = Vector2(20, 0)    # 距 A 20 < 60
	b.apply_status(&"burn", 1.0, 5.0)     # B 也带 burn
	var c := _make_enemy()
	c.MAX_HP = 100.0; c.hp = 100.0
	c.global_position = Vector2(50, 0)    # 距 A 50<60(吃 A 波); 距 B 30<60(若 B 二次触发会被再炸)
	await get_tree().process_frame
	a.take_damage(999.0, Enemy.DamageChannel.DIRECT)
	# 单波：C 仅被 A 的燃尽炸一次 → 90。若 B 二次触发会变 80。
	assert_float(c.hp).is_equal_approx(90.0, 0.001)
```

- [ ] **Step 2: 跑测试确认失败**

Run: `& "...console.exe" --headless --path "D:\Workspace\GAME\game_0_vsl" -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/test_enemy_status.gd`
Expected: FAIL —「`test_burning_enemy_death_conflagrates_neighbor`：expected hp≈90，实得 100」（燃尽未实现，邻怪不掉血）。

- [ ] **Step 3: 快照加 had_burn**

在 `scenes/enemies/enemy.gd` 的 `take_damage` 快照块里，`var stun := has_status(&"stun")` 之后加一行：

```gdscript
	var had_burn := has_status(&"burn")
```

- [ ] **Step 4: 死亡分支加燃尽触发**

在 `take_damage` 死亡分支 `if hp <= 0.0:` 内、`if split_count > 0:` **之前**插入：

```gdscript
		# 燃尽(C2)：死时带 burn → 半径内一次性 DOT 火伤。经模块级重入守卫保证单波(见设计 §6)。
		if had_burn and not Enemy._conflagrating:
			Enemy._conflagrating = true
			Vfx.spawn_burst(global_position, &"fire_burst")
			_trigger_conflagration()
			Enemy._conflagrating = false
```

- [ ] **Step 5: 新增 _trigger_conflagration helper**

在 `scenes/enemies/enemy.gd` 的 `_spawn_split()` 之前（或任意方法间）追加：

```gdscript
# 燃尽(C2)：带 burn 死亡时,对半径内存活邻怪各打一次性 DOT 火伤。不施 burn(不蔓延);
# 走 DOT 通道(抑制白闪/击退/音效,避免一次群伤炸出 N 份完整命中反馈)。
# 单波由调用处的 _conflagrating 守卫保证(邻怪被本波炸死的死亡分支会跳过再触发)。
func _trigger_conflagration() -> void:
	for e in get_tree().get_nodes_in_group("enemies"):
		if e == self or not is_instance_valid(e):
			continue
		if global_position.distance_to((e as Node2D).global_position) <= CONFLAG_RADIUS:
			e.take_damage(CONFLAG_DAMAGE, DamageChannel.DOT)
```

- [ ] **Step 6: 跑测试确认通过**

Run: `& "...console.exe" --headless --path "D:\Workspace\GAME\game_0_vsl" -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/test_enemy_status.gd`
Expected: PASS（新增 3 条燃尽测试全绿，含单波守卫）。

- [ ] **Step 7: 提交**

```bash
git add scenes/enemies/enemy.gd tests/test_enemy_status.gd
git commit -m "feat(synergy): 燃尽(带burn死亡一次性AoE)+单波重入守卫"
```

---

## Task 6: 全量回归 + 确定性核验

**Files:**
- 无产品代码改动（仅验证）。

**Interfaces:**
- Consumes: 全部前序 Task 的成果。
- Produces: 绿色全量套件 + 确认测试**总数**符合预期（防 gdUnit 截断）。

- [ ] **Step 1: 跑全量套件**

Run: `& "C:\Dev\GAME\Godot\Godot_v4.6.3-stable_win64_console.exe" --headless --path "D:\Workspace\GAME\game_0_vsl" -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests`
Expected: 0 失败 / 0 错误。测试总数 ≈ **441**（414 基线 + 新增：Task1 6 条 + Task2 12 条 + Task3 4 条 + Task4 2 条 + Task5 3 条 = 27）。

- [ ] **Step 2: 核对测试总数（gdUnit 截断守卫）**

确认报告底部「Test Suites / Tests」计数 = 34 套件（新增 `test_enemy_synergy.gd`）、约 441 测试。**若总数低于预期但显示全绿**，说明某测试解析错误静默截断了后续发现——逐套件排查（先单独跑 `test_enemy_synergy.gd`、`test_enemy_status.gd`）。

- [ ] **Step 3: 确认确定性不变量**

人工核查：本期新增逻辑零 `randf`/`randi`/`Math.random` 类调用；`Vfx.spawn_burst` 仅视觉（实时 timer + CPUParticles，不碰 gameplay 状态）。`grep` 验证：

Run: `& "C:\Dev\GAME\Godot\Godot_v4.6.3-stable_win64_console.exe" --headless --path "D:\Workspace\GAME\game_0_vsl" --import`
Expected: 导入无解析错误（确认全部脚本编译通过）。

- [ ] **Step 4: 收尾提交（若 Step 2/3 有微调）**

若前几步无需改动，本步跳过。否则：

```bash
git add -A
git commit -m "test(synergy): 全量回归核验 + 测试计数守卫"
```

---

## 验收对照（spec §10）

- [x] 四规则按 §4 数值实现，集中在 `take_damage`（Task 3/5）+ `synergy_multiplier`（Task 2）+ `gravity_well`（Task 4）三处。
- [x] 全部新逻辑有单测，且按 TDD 先红后绿（Task 1–5 每个都先看红）。
- [x] 全量套件绿、确定性保持（Task 6）。
- [x] 武器/法术 `.tres` 与各武器脚本零改动（仅 `gravity_well.gd` 加一行 `apply_status`）。
- [x] 反馈复用现有预设（`ice_shard`/`crit_spark`/`fire_burst`），无新美术资源。

## 已知遥测缺口（非本期阻塞，spec §9）

W4 solo bot 是单武器档，测不到跨元素协同。真正的协同平衡需要"配对/多元素" bot 场景（如 frostbite + 一把直击武器、或引力井 + 火球），列为后续工作项。本期以有原则 + 单测覆盖的数值出货，遥测校准随后。
